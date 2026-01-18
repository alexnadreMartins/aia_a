import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../../models/project_model.dart';
import '../../state/project_state.dart';
import '../../logic/metadata_helper.dart';
import '../widgets/smart_image.dart';

class TimeShiftDialog extends ConsumerStatefulWidget {
  const TimeShiftDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<TimeShiftDialog> createState() => _TimeShiftDialogState();
}

class _TimeShiftDialogState extends ConsumerState<TimeShiftDialog> {
  // State
  Map<String, int> _tempOffsets = {}; // Key: "Model_Serial", Value: Seconds
  bool _isLoading = true;
  List<String> _sortedPaths = [];
  Map<String, PhotoMetadata> _metaCache = {};
  
  // Filtering
  String _selectedEventFilter = "Todos"; 
  final List<String> _eventOptions = ["Todos", ...List.generate(12, (i) => (i+1).toString())];

  // Auto-Scroll
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _gridKey = GlobalKey();
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    final project = ref.read(projectProvider).project;
    _tempOffsets = Map.from(project.cameraTimeOffsets);
    _loadMetadataAndSort();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadataAndSort() async {
    setState(() => _isLoading = true);
    
    final project = ref.read(projectProvider).project;
    final allPaths = project.allImagePaths;
    
    // 1. Fetch Metadata (Batch)
     final metas = await MetadataHelper.getMetadataBatch(allPaths);
     
     _metaCache.clear();
     for (int i=0; i<allPaths.length; i++) {
        _metaCache[allPaths[i]] = metas[i];
     }
     
     _applySort();
  }

  void _applySort() {
     final project = ref.read(projectProvider).project;
     List<String> paths = List.from(project.allImagePaths);

     // 1. Filter
     if (_selectedEventFilter != "Todos") {
        paths = paths.where((path) {
            final name = p.basename(path).toLowerCase();
            final parent = Directory(path).parent.path.split(Platform.pathSeparator).last.toLowerCase();
            final filter = _selectedEventFilter.toLowerCase();
            
            // Check Filename Prefix (e.g. "1_DSC...", "1-DSC...")
            bool matchName = name.startsWith("${filter}_") || name.startsWith("$filter-") || name.startsWith("$filter ") || name.startsWith(filter);
            
            // Check Parent Folder (e.g. "Event 1", "1_Wedding")
            bool matchParent = parent.startsWith("${filter}_") || parent.startsWith("$filter-") || parent.startsWith("$filter ") || parent == filter;
            
            return matchName || matchParent;
        }).toList();
     }

     // 2. Sort by Adjusted Time
     paths.sort((a, b) {
        final dateA = _getAdjustedDate(a);
        final dateB = _getAdjustedDate(b);
        return dateA.compareTo(dateB);
     });

     setState(() {
        _sortedPaths = paths;
        _isLoading = false;
     });
  }

  DateTime _getAdjustedDate(String path) {
      final meta = _metaCache[path];
      DateTime date = meta?.dateTaken ?? DateTime(1970);
      final offset = _tempOffsets[_getCameraKey(path)] ?? 0;
      if (offset != 0) {
         return date.add(Duration(seconds: offset));
      }
      return date;
  }
  
  DateTime _getOriginalDate(String path) {
      return _metaCache[path]?.dateTaken ?? DateTime(1970);
  }

  String _getCameraKey(String path) {
      final meta = _metaCache[path];
      if (meta == null) return "Unknown";
      
      // 1. Model + Serial (Best)
      final model = meta.cameraModel ?? "Unknown";
      if (meta.cameraSerial != null && meta.cameraSerial!.isNotEmpty) {
          return "${model}_${meta.cameraSerial}";
      }
      
      // 2. Model + Artist (Fallback if Serial missing)
      if (meta.artist != null && meta.artist!.isNotEmpty) {
          return "${model}_${meta.artist}";
      }
      
      // 3. Just Model (Worst)
      return model;
  }

  void _handleSmartReorder(String srcPath, String targetPath) {
      if (srcPath == targetPath) return;

      final srcCamera = _getCameraKey(srcPath);
      final targetCamera = _getCameraKey(targetPath);
      
      if (srcCamera == targetCamera) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reordene fotos de câmeras diferentes para sincronizar.")));
          return;
      }

      final targetDate = _getAdjustedDate(targetPath);
      final srcOriginal = _getOriginalDate(srcPath);
      final diff = targetDate.difference(srcOriginal).inSeconds;
      
      setState(() {
          _tempOffsets[srcCamera] = diff;
      });
      _applySort();
      
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
         content: Text("Câmera $srcCamera sincronizada para ${DateFormat("HH:mm:ss").format(targetDate)}"),
         duration: const Duration(seconds: 2),
      ));
  }

  // --- Auto Scroll Logic ---

  void _onDragUpdate(DragUpdateDetails details) {
      if (_gridKey.currentContext == null) return;
      
      final RenderBox box = _gridKey.currentContext!.findRenderObject() as RenderBox;
      final localPos = box.globalToLocal(details.globalPosition);
      
      final double threshold = 60.0;
      final double height = box.size.height;
      
      double newVelocity = 0.0;
      
      if (localPos.dy < threshold) {
          // Scroll Up: Closer to 0 = Faster
          // Ratio 0..1 (0 at edge, 1 at threshold)
          final ratio = (threshold - localPos.dy) / threshold; 
          newVelocity = -5.0 - (15.0 * ratio); // Min -5, Max -20
      } else if (localPos.dy > height - threshold) {
          // Scroll Down: Closer to height = Faster
          final ratio = (localPos.dy - (height - threshold)) / threshold;
          newVelocity = 5.0 + (15.0 * ratio); // Min 5, Max 20
      }
      
      if (newVelocity != 0) {
          _startAutoScroll(newVelocity);
      } else {
          _stopAutoScroll();
      }
  }

  void _startAutoScroll(double velocity) {
      // If timer exists, just update velocity if needed? 
      // Current implementation restarts timer which is fine but maybe jerky.
      // Let's keep a _currentVelocity
      _currentVelocity = velocity;
      
      if (_scrollTimer != null) return;
      
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
          if (!_scrollController.hasClients) {
             _stopAutoScroll();
             return;
          }
          
          final newOffset = _scrollController.offset + _currentVelocity;
          if (newOffset >= _scrollController.position.minScrollExtent && 
              newOffset <= _scrollController.position.maxScrollExtent) {
              _scrollController.jumpTo(newOffset);
          } else {
              // Hit boundary
              _stopAutoScroll();
          }
      });
  }
  
  double _currentVelocity = 0;

  void _stopAutoScroll() {
      _scrollTimer?.cancel();
      _scrollTimer = null;
      _currentVelocity = 0;
  }

  @override
  Widget build(BuildContext context) {
    final cameras = <String>{};
    for (var p in _sortedPaths) {
       cameras.add(_getCameraKey(p));
    }
    final sortedCameras = cameras.toList()..sort();

    return Dialog(
       backgroundColor: const Color(0xFF1E1E1E),
       insetPadding: const EdgeInsets.all(24),
       child: Column(
         children: [
            // Header
            Padding(
               padding: const EdgeInsets.all(16),
               child: Row(
                 children: [
                    const Icon(Icons.timer, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    const Text("Time Shift", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    const Text("Arraste uma foto para sincronizar sua câmera com as outras.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const Spacer(),
                    const Text("Evento:", style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                       value: _selectedEventFilter,
                       dropdownColor: Colors.grey[800],
                       style: const TextStyle(color: Colors.white),
                       items: _eventOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                       onChanged: (val) {
                          if (val != null) {
                             setState(() => _selectedEventFilter = val);
                             _applySort(); 
                          }
                       }
                    ),
                 ],
               ),
            ),
            const Divider(color: Colors.white24, height: 1),
            
            Expanded(
               child: Row(
                 children: [
                    // Left: Controls
                    Container(
                       width: 320,
                       color: Colors.black26,
                       child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                             const Text("Ajuste Manual", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                             const SizedBox(height: 16),
                             if (_isLoading)
                               const Center(child: CircularProgressIndicator())
                             else if (sortedCameras.isEmpty)
                               const Text("Sem dados.", style: TextStyle(color: Colors.white30))
                             else
                               ...sortedCameras.map((camKey) {
                                  final currentOffset = _tempOffsets[camKey] ?? 0;
                                  final duration = Duration(seconds: currentOffset.abs());
                                  final sign = currentOffset >= 0 ? "+" : "-";
                                  final formatted = "$sign${duration.inDays}d ${duration.inHours % 24}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s";

                                  return Card(
                                    color: Colors.white10,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                         crossAxisAlignment: CrossAxisAlignment.start,
                                         children: [
                                            Text(camKey, style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 4),
                                            Text("Offset: $formatted", style: const TextStyle(color: Colors.white, fontSize: 11)),
                                            const SizedBox(height: 8),
                                            Row(
                                               children: [
                                                  _buildIconButton(Icons.fast_rewind, () => _shift(camKey, -3600)),
                                                  _buildIconButton(Icons.remove, () => _shift(camKey, -1)),
                                                  Expanded(
                                                     child: Slider(
                                                        value: currentOffset.remainder(3600).toDouble().clamp(-3600.0, 3600.0), 
                                                        min: -3600,
                                                        max: 3600,
                                                        divisions: 7200, 
                                                        label: "${currentOffset.remainder(3600)}s",
                                                        onChanged: (val) {
                                                           final base = (currentOffset ~/ 3600) * 3600;
                                                           setState(() {
                                                              _tempOffsets[camKey] = base + val.toInt();
                                                           });
                                                           _applySort(); 
                                                        },
                                                     ),
                                                  ),
                                                  _buildIconButton(Icons.add, () => _shift(camKey, 1)),
                                                  _buildIconButton(Icons.fast_forward, () => _shift(camKey, 3600)),
                                               ],
                                            ),
                                         ],
                                      ),
                                    ),
                                  );
                               }).toList()
                          ],
                       ),
                    ),
                    const VerticalDivider(color: Colors.white24, width: 1),
                    // Right: Preview Grid with Drag Target
                    Expanded(
                       key: _gridKey,
                       child: _isLoading 
                         ? const Center(child: CircularProgressIndicator())
                         : GridView.builder(
                             controller: _scrollController,
                             padding: const EdgeInsets.all(8),
                             gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 4,
                                childAspectRatio: 1.0,
                             ),
                             itemCount: _sortedPaths.length,
                             itemBuilder: (ctx, i) {
                                final path = _sortedPaths[i];
                                final date = _getAdjustedDate(path);
                                final cam = _getCameraKey(path);
                                final offset = _tempOffsets[cam] ?? 0;
                                final isShifted = offset != 0;
                                
                                return DragTarget<String>(
                                   onWillAccept: (src) => src != null && src != path,
                                   onAccept: (src) => _handleSmartReorder(src, path),
                                   builder: (context, candidates, rejects) {
                                       final isHovering = candidates.isNotEmpty;
                                       
                                       return Draggable<String>(
                                          data: path,
                                          onDragUpdate: _onDragUpdate,
                                          onDragEnd: (_) => _stopAutoScroll(),
                                          onDraggableCanceled: (_,__) => _stopAutoScroll(),
                                          feedback: Material(
                                            color: Colors.transparent,
                                            child: Opacity(opacity: 0.8, child: SizedBox(width: 100, height: 100, child: SmartImage(path: path, fit: BoxFit.cover))),
                                          ),
                                          childWhenDragging: Opacity(opacity: 0.5, child: SmartImage(path: path)),
                                          child: Container(
                                             decoration: BoxDecoration(
                                                border: Border.all(
                                                   color: isHovering ? Colors.greenAccent : (isShifted ? Colors.amberAccent : Colors.transparent),
                                                   width: isHovering ? 3 : 2
                                                ),
                                             ),
                                             child: Stack(
                                                children: [
                                                   Positioned.fill(child: SmartImage(path: path, fit: BoxFit.cover)),
                                                   Positioned(
                                                      bottom: 0, left: 0, right: 0,
                                                      child: Container(
                                                         color: Colors.black87,
                                                         padding: const EdgeInsets.all(2),
                                                         child: Column(
                                                            children: [
                                                               Text(DateFormat("HH:mm:ss").format(date), style: const TextStyle(color: Colors.white, fontSize: 10)),
                                                               Text(cam, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[400], fontSize: 8)),
                                                            ],
                                                         ),
                                                      ),
                                                   ),
                                                   if (isHovering)
                                                      const Center(child: Icon(Icons.sync_alt, color: Colors.greenAccent, size: 32))
                                                ],
                                             ),
                                          ),
                                       );
                                   },
                                );
                             },
                         ),
                    ),
                 ],
               ),
            ),
            
            const Divider(color: Colors.white24, height: 1),
            // Actions
            Padding(
               padding: const EdgeInsets.all(16),
               child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                     TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
                     const SizedBox(width: 16),
                     ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text("Aplicar Correção"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                        onPressed: () {
                           ref.read(projectProvider.notifier).updateCameraTimeOffsets(_tempOffsets);
                           Navigator.pop(context);
                        },
                     )
                  ],
               ),
            )
         ],
       ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
     return IconButton(
        icon: Icon(icon, color: Colors.white70, size: 16),
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(4),
        onPressed: () {
           setState(onTap);
           _applySort();
        },
     );
  }

  void _shift(String cam, int delta) {
      final current = _tempOffsets[cam] ?? 0;
      _tempOffsets[cam] = current + delta;
  }
}
