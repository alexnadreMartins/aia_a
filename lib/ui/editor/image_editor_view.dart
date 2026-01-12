import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/editor/editor_state.dart';
import '../../logic/editor/color_matrix_helper.dart';
import '../../logic/editor/gemini_service.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import '../widgets/scope_widget.dart';
import '../widgets/histogram_graph.dart';
import '../widgets/vectorscope_scope.dart';
import '../../logic/cache_provider.dart';
import '../../state/task_queue_state.dart';

class ImageEditorView extends ConsumerStatefulWidget {
  final List<String> paths;
  final int initialIndex;

  const ImageEditorView({
    super.key, 
    required this.paths,
    required this.initialIndex,
  });

  @override
  ConsumerState<ImageEditorView> createState() => _ImageEditorViewState();
}

class _ImageEditorViewState extends ConsumerState<ImageEditorView> {
  late ScrollController _timelineController;
  late TransformationController _transformController;
  Offset _histogramOffset = const Offset(20, 20); // Default positions relative to canvas
  Offset _vectorscopeOffset = const Offset(20, 160);
  
  @override
  void initState() {
    super.initState();
    _timelineController = ScrollController();
    _transformController = TransformationController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(imageEditorProvider.notifier).reset();
      ref.read(imageEditorProvider.notifier).setImages(widget.paths, widget.initialIndex);
      // Initial Scroll
      _scrollToIndex(widget.initialIndex);
    });
  }

  @override
  void dispose() {
    _timelineController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
      if (!_timelineController.hasClients) return;
      if (index < 0) return;
      
      const itemWidth = 80.0 + 8.0; // Width + Separator
      final screenWidth = MediaQuery.of(context).size.width;
      
      // Center the item
      final offset = (index * itemWidth) - (screenWidth / 2) + (itemWidth / 2);
      
      // Clamp not strictly needed as animateTo handles alignment, but good practice
      _timelineController.animateTo(
         offset, 
         duration: const Duration(milliseconds: 300), 
         curve: Curves.easeOutQuart
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageEditorProvider);
    final notifier = ref.read(imageEditorProvider.notifier);
    
    // Auto-Scroll Listener
    ref.listen(imageEditorProvider.select((s) => s.currentIndex), (prev, next) {
       if (prev != next) {
          _scrollToIndex(next);
       }
    });

    void zoomIn() {
       final currentScale = _transformController.value.getMaxScaleOnAxis();
       if (currentScale < 5.0) {
           _transformController.value = Matrix4.identity()..scale(currentScale * 1.5);
       }
    }

    void zoomOut() {
       final currentScale = _transformController.value.getMaxScaleOnAxis();
       if (currentScale > 0.1) {
           _transformController.value = Matrix4.identity()..scale(currentScale / 1.5);
       }
    }
    
    final currentAdj = state.currentAdjustments;
    final currentPath = state.currentPath;

    // Calculate Matrix
    final matrix = ColorMatrixHelper.getMatrix(
       exposure: currentAdj.exposure,
       contrast: currentAdj.contrast,
       brightness: currentAdj.brightness,
       saturation: currentAdj.saturation,
       temperature: currentAdj.temperature,
       tint: currentAdj.tint
    );
    
    // Handle Compare Mode
    final effectiveMatrix = state.showOriginal 
        ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) // No filter
        : ColorFilter.matrix(matrix);

    return CallbackShortcuts(
      bindings: {
          SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () {
             notifier.syncAdjustments();
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes Sincronizados!")));
          },
          SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
             notifier.copyAdjustments();
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes Copiados!")));
          },
          SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
             notifier.pasteAdjustments();
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes Colados!")));
          },
          SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true): () => _triggerAutoEnhance(notifier, context, state.currentPath),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => notifier.selectImage(state.currentIndex + 1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => notifier.selectImage(state.currentIndex - 1),
          // Zoom Shortcuts
          const SingleActivator(LogicalKeyboardKey.add): zoomIn,
          const SingleActivator(LogicalKeyboardKey.equal): zoomIn,
          const SingleActivator(LogicalKeyboardKey.minus): zoomOut,
          const SingleActivator(LogicalKeyboardKey.numpadAdd): zoomIn,
          const SingleActivator(LogicalKeyboardKey.numpadSubtract): zoomOut,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            title: Text("Editor Inteligente (${state.currentIndex + 1}/${state.imagePaths.length})"),
            backgroundColor: const Color(0xFF1E1E1E),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
               if (state.selectedPaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.sync, color: Colors.orangeAccent),
                      label: Text("Sincronizar (${state.selectedPaths.length})", 
                        style: const TextStyle(color: Colors.orangeAccent)),
                      onPressed: () {
                         notifier.syncAdjustments();
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes Sincronizados!")));
                      },
                    ),
                  ),

              TextButton.icon(
                 icon: const Icon(Icons.save, color: Colors.blueAccent),
                 label: Text(state.selectedPaths.isNotEmpty ? "Salvar Seleção" : "Salvar Atual", style: const TextStyle(color: Colors.blueAccent)),
                  onPressed: () {
                     if (state.selectedPaths.isNotEmpty) {
                        _saveAllSelected(notifier, context, state);
                     } else {
                        _saveImage(notifier, context, state.currentPath, state.currentAdjustments);
                     }
                  },
               ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.zoom_out), onPressed: zoomOut, tooltip: "Zoom Out (-)"),
              IconButton(icon: const Icon(Icons.zoom_in), onPressed: zoomIn, tooltip: "Zoom In (+)"),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    // CANVA
                    Expanded(
                      child: Stack(
                        children: [
                             // Image
                             currentPath.isEmpty ? const Center(child: Text("Nenhuma imagem selecionada")) : InteractiveViewer(
                                transformationController: _transformController,
                                maxScale: 5.0,
                                minScale: 0.1,
                                child: Center(
                                  child: ColorFiltered(
                                      colorFilter: effectiveMatrix as ColorFilter,
                                      child: Image.file(
                                          File(currentPath), 
                                          key: ValueKey('${currentPath}_${ref.watch(imageVersionProvider(currentPath))}')
                                      ), // Force refresh
                                  ),
                                ),
                             ),

                             // SCOPES
                             if (currentPath.isNotEmpty) ...[
                               ScopeWidget(
                                  title: "Histograma",
                                  helpTitle: "Tutorial: Luz",
                                  helpContent: "Mantenha a 'montanha' entre 5 e 252.",
                                  initialOffset: _histogramOffset,
                                  onDragEnd: (pos) => setState(() => _histogramOffset = pos),
                                  child: HistogramWidget(
                                      imagePath: currentPath, 
                                      width: 250, 
                                      height: 120,
                                      editorState: state,
                                      key: ValueKey('${currentPath}_Hist_${ref.watch(imageVersionProvider(currentPath))}'),
                                  ),
                               ),
                               ScopeWidget(
                                  title: "Vectorscope",
                                  helpTitle: "Tutorial: Cor",
                                  helpContent: "Pele na linha entre Vermelho e Amarelo.",
                                  initialOffset: _vectorscopeOffset,
                                  onDragEnd: (pos) => setState(() => _vectorscopeOffset = pos),
                                  child: VectorscopeWidget(
                                      imagePath: currentPath, 
                                      size: 160,
                                      editorState: state,
                                      key: ValueKey('${currentPath}_Vect_${ref.watch(imageVersionProvider(currentPath))}'),
                                  ),
                               ),
                             ]
                        ],
                      ),
                    ),
                    
                    // SIDEBAR
                    Container(
                       width: 320,
                       color: const Color(0xFF1E1E1E),
                       padding: const EdgeInsets.all(16),
                       child: Column(
                         children: [
                           // Auto Magic
                           SizedBox(
                             width: double.infinity,
                             child: ElevatedButton.icon(
                               style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                               ),
                               icon: state.isProcessing 
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                                  : const Icon(Icons.auto_fix_high),
                               label: Text(state.isProcessing ? "Analisando..." : "Auto AI Enhance (Ctrl+Shift+A)"),
                               onPressed: (state.isProcessing || currentPath.isEmpty) ? null : () => _triggerAutoEnhance(notifier, context, currentPath),
                             ),
                           ),
                           
                           const Divider(height: 32, color: Colors.white24),
                           
                           Expanded(
                             child: ListView(
                               children: [
                                  _buildSectionHeader("Luz"),
                                  _buildSlider("Exposição", currentAdj.exposure, -1.0, 1.0, notifier.updateExposure),
                                  _buildSlider("Contraste", currentAdj.contrast, 0.5, 2.0, notifier.updateContrast),
                                  _buildSlider("Brilho (Offset)", currentAdj.brightness, 0.5, 1.5, notifier.updateBrightness),
                                  
                                  _buildSectionHeader("Cor"),
                                  _buildSlider("Saturação", currentAdj.saturation, 0.0, 2.0, notifier.updateSaturation),
                                  _buildSlider("Temperatura", currentAdj.temperature, -1.0, 1.0, notifier.updateTemperature, 
                                      colors: [Colors.blue, Colors.orange]),
                                  _buildSlider("Tint", currentAdj.tint, -1.0, 1.0, notifier.updateTint,
                                      colors: [Colors.green, Colors.purple]),

                                  _buildSectionHeader("Detalhe (Lento)"),
                                  _buildSlider("Nitidez", currentAdj.sharpness, 0.0, 1.0, notifier.updateSharpness),
                                  _buildSlider("Red. Ruído", currentAdj.noiseReduction, 0.0, 1.0, notifier.updateNoiseReduction),
                                  _buildSlider("Suavizar Pele", currentAdj.skinSmooth, 0.0, 1.0, notifier.updateSkinSmooth),
                               ],
                             ),
                           ),
                           
                           // Compare Button
                           GestureDetector(
                              onTapDown: (_) => notifier.toggleCompare(true),
                              onTapUp: (_) => notifier.toggleCompare(false),
                              onTapCancel: () => notifier.toggleCompare(false),
                              child: Container(
                                 padding: const EdgeInsets.all(12),
                                 decoration: BoxDecoration(
                                    color: const Color(0xFF333333),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white24),
                                 ),
                                 child: const Center(child: Text("Segure para Comparar", style: TextStyle(color: Colors.white70))),
                              ),
                           ),
                         ],
                       ),
                    ),
                  ],
                ),
              ),

              // TIMELINE
              Container(
                height: 120, // Increased for Scrollbar
                color: const Color(0xFF101010),
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Scrollbar(
                  controller: _timelineController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thickness: 8,
                  radius: const Radius.circular(4),
                  child: ListView.separated(
                    controller: _timelineController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: state.imagePaths.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                     final path = state.imagePaths[index];
                     final isSelected = index == state.currentIndex;
                     final isMultiSelected = state.selectedPaths.contains(path);
                     final hasAdjustments = state.allAdjustments.containsKey(path);
                     
                     return GestureDetector(
                        onTap: () {
                           final keys = HardwareKeyboard.instance.logicalKeysPressed;
                           final isShift = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
                           
                           if (isShift && state.currentIndex >= 0) {
                               // Range Selection
                               final start = state.currentIndex;
                               final end = index;
                               final low = start < end ? start : end;
                               final high = start < end ? end : start;
                               
                               for (int i = low; i <= high; i++) {
                                  notifier.toggleSelection(state.imagePaths[i], forceSelect: true);
                               }
                           } else {
                               notifier.selectImage(index);
                           }
                        },
                        onDoubleTap: () {
                           // Exclusive Selection
                           notifier.deselectAll();
                           notifier.selectImage(index);
                        },
                        onLongPress: () {
                           notifier.toggleSelection(path);
                        },
                        child: Container(
                           width: 80,
                           decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected ? Colors.amber : (isMultiSelected ? Colors.blueAccent : Colors.white12),
                                width: isSelected ? 2 : (isMultiSelected ? 2 : 1),
                              ),
                              borderRadius: BorderRadius.circular(4),
                           ),
                           child: Stack(
                             fit: StackFit.expand,
                             children: [
                               Image.file(File(path), fit: BoxFit.cover),
                               if (hasAdjustments)
                                  const Positioned(
                                    top: 4, right: 4,
                                    child: CircleAvatar(radius: 4, backgroundColor: Colors.greenAccent),
                                  ),
                               if (isMultiSelected)
                                  Container(color: Colors.blueAccent.withOpacity(0.3)),
                             ],
                           ),
                        ),
                     );
                  },
                ),
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _triggerAutoEnhance(ImageEditorNotifier notifier, BuildContext context, String path) async {
      final state = ref.read(imageEditorProvider);
      if (state.isProcessing) return;

      notifier.setProcessing(true);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AIA : analisando a imagem...")));
      
      try {
         final suggestions = await GeminiService.analyzeImage(path);
         if (context.mounted) {
             if (suggestions.isNotEmpty) {
                 notifier.applySuggestions(suggestions);
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes Inteligentes Aplicados!")));
             } else {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Falha na análise.")));
             }
         }
      } finally {
         notifier.setProcessing(false);
      }
  }

  Widget _buildSectionHeader(String title) {
     return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(title.toUpperCase(), style: const TextStyle(
           color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0
        )),
     );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged, {List<Color>? colors}) {
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(label, style: const TextStyle(fontSize: 12)),
             Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 11, color: Colors.white54)),
           ],
         ),
         SizedBox(
           height: 30,
           child: SliderTheme(
             data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: colors?.last ??Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
             ),
             child: Slider(
               value: value,
               min: min,
               max: max,
               onChanged: onChanged,
             ),
           ),
         ),
       ],
     );
  }
  // --- SAVE LOGIC ---
  Future<void> _saveImage(ImageEditorNotifier notifier, BuildContext context, String path, ImageAdjustments adj) async {
      await _saveInternal(context, path, adj);
      if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Salvamento iniciado em segundo plano...")));
      }
  }

  Future<void> _saveAllSelected(ImageEditorNotifier notifier, BuildContext context, ImageEditorState state) async {
       if (state.selectedPaths.isEmpty) return;
       
       // Do not block UI
       // notifier.setProcessing(true); 
       
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Iniciando salvamento de ${state.selectedPaths.length} imagens em segundo plano...")));
       
       try {
           for (final path in state.selectedPaths) {
               final adj = state.allAdjustments[path] ?? const ImageAdjustments();
               await _saveInternal(context, path, adj); // Returns immediately
           }
       } catch (e) {
           print("Error initiating save: $e");
       }
       // Process continues in background
  }

  Future<void> _saveInternal(BuildContext context, String path, ImageAdjustments adj) async {
       // Offload to background queue
       final notifier = ref.read(taskQueueProvider.notifier);
       
       // Prepare Params (Snapshot)
       final params = _SaveParams(
          path: path,
          adj: adj, // Adjustments are immutable
          matrix: ColorMatrixHelper.getMatrix(
             exposure: adj.exposure,
             contrast: adj.contrast,
             brightness: adj.brightness,
             saturation: adj.saturation,
             temperature: adj.temperature,
             tint: adj.tint
          )
       );

       // Enqueue Task
       // Capture notifier instance to ensure safe access even if widget disposes
       final taskNotifier = ref.read(taskQueueProvider.notifier);
       // We can also capture the editor notifier but accessing it after dispose is risky if it's autoDispose.
       // However, we can wrap its usage.
       
       taskNotifier.addTask(
          "Salvando ${path.split(Platform.pathSeparator).last}...",
          (id) => _processSaveTaskLogic(id, params, taskNotifier, ref) 
       );
  }

  // The logic that runs inside the Queue Execution
  // We pass 'taskNotifier' explicitly so we don't depend on 'ref' for it.
  // We still keep 'ref' for other providers, but we must use it safely.
  Future<void> _processSaveTaskLogic(String taskId, _SaveParams params, TaskQueueNotifier taskNotifier, WidgetRef ref) async {
       try {
           taskNotifier.updateTask(taskId, progress: 0.2);
           
           // Heavy lifting in Isolate
           await compute(_executeSaveTask, params);
           
           taskNotifier.updateTask(taskId, progress: 1.0, status: TaskStatus.success);
           
           // UI Updates in Main Thread
           await Future.delayed(Duration.zero); // Ensure next frame
           
           try {
             PaintingBinding.instance.imageCache.clear();
             PaintingBinding.instance.imageCache.clearLiveImages();
             CacheService.invalidate(ref, params.path);
             
             // Reset adjustments - verify if ref is still valid/mounted?
             // There is no easy 'ref.isMounted'. catch-all is safest.
             ref.read(imageEditorProvider.notifier).resetAdjustments(params.path);
           } catch (_) {
             // If widget disposed, we don't care about UI updates
           }
           
       } catch (e) {
           print("Error in Background Save: $e");
           // Ensure we report error to queue
           taskNotifier.updateTask(taskId, status: TaskStatus.error, error: e.toString());
       }
  }
}

class _SaveParams {
  final String path;
  final ImageAdjustments adj; 
  final List<double> matrix;
  
  _SaveParams({required this.path, required this.adj, required this.matrix});
}

Future<void> _executeSaveTask(_SaveParams params) async {
    final file = File(params.path);
    final bytes = await file.readAsBytes();
    var imgRaw = img.decodeImage(bytes);
    if (imgRaw == null) throw Exception("Failed to decode image");

    imgRaw = ColorMatrixHelper.applyColorMatrix(imgRaw, params.matrix);
    
    // Auto Levels (Background)
    imgRaw = ColorMatrixHelper.autoLevel(imgRaw);
    
    // Encode
    final jpg = img.encodeJpg(imgRaw, quality: 90);
    await file.writeAsBytes(jpg);
}
