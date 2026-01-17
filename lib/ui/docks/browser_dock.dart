import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../../state/project_state.dart';
import '../../models/project_model.dart';
import '../widgets/smart_image.dart';
import '../widgets/browser_full_screen_viewer.dart';
import '../dialogs/time_shift_dialog.dart';
import '../../logic/image_loader.dart';
import '../../logic/cache_provider.dart';

class BrowserDock extends ConsumerStatefulWidget {
  const BrowserDock({super.key});

  @override
  ConsumerState<BrowserDock> createState() => _BrowserDockState();
}

class _BrowserDockState extends ConsumerState<BrowserDock> {
  final ScrollController _browserScrollCtrl = ScrollController();
  String? _lastSelectedBrowserPath;

  @override
  void dispose() {
    _browserScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildFileBrowser(ref);
  }

  Widget _buildFileBrowser(WidgetRef ref) {
    final projectState = ref.watch(projectProvider);
    final notifier = ref.read(projectProvider.notifier);
    
    // Get Sorted/Filtered List computed by Notifier logic
    final displayedPaths = notifier.getSortedAndFilteredPaths();

    return Column(
      children: [
        _buildBrowserToolbar(ref, projectState),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => 
                  notifier.selectAllBrowserPhotos(),
              const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => 
                  notifier.deselectAllBrowserPhotos(),
            },
            child: Focus(
              autofocus: true,
              child: Scrollbar(
                controller: _browserScrollCtrl,
                thumbVisibility: true,
                thickness: 12,
                radius: const Radius.circular(6),
                interactive: true,
                child: GridView.builder(
                  controller: _browserScrollCtrl,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: displayedPaths.length,
                itemBuilder: (ctx, i) {
                  final path = displayedPaths[i];
                  final isSelected = projectState.selectedBrowserPaths.contains(path);
                  final rot = projectState.project.imageRotations[path] ?? 0;
                  final version = ref.watch(imageVersionProvider(path)); // Watch version

                  return Draggable<String>(
                    data: path,
                    feedback: Opacity(
                      opacity: 0.7,
                      child: SizedBox(
                        width: 60, height: 60,
                        child: RotatedBox(quarterTurns: rot ~/ 90, child: SmartImage(path: path, key: ValueKey('${path}_$version'), fit: BoxFit.contain)),
                      ),
                    ),
                    child: GestureDetector(
                      onTap: () {
                           final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed
                               .contains(LogicalKeyboardKey.shiftLeft) ||
                               HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                           
                           if (isShiftPressed && _lastSelectedBrowserPath != null) {
                               notifier.selectBrowserRange(_lastSelectedBrowserPath!, path, displayedPaths);
                           } else {
                               notifier.toggleBrowserPathSelection(path);
                               _lastSelectedBrowserPath = path;
                           }
                      },
                      onDoubleTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => BrowserFullScreenViewer(paths: displayedPaths, initialIndex: i)),
                        );
                      },
                      onSecondaryTapUp: (details) {
                          _showBrowserContextMenu(context, ref, path, details.globalPosition);
                      },
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.deepPurple.withOpacity(0.3) : const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? Colors.deepPurpleAccent : Colors.transparent,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Center(
                              child: RotatedBox(
                                quarterTurns: rot ~/ 90,
                                child: SmartImage(path: path, key: ValueKey('${path}_$version'), fit: BoxFit.contain),
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Positioned(
                              bottom: 4, right: 4,
                              child: Icon(Icons.check_circle, size: 14, color: Colors.deepPurpleAccent),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ), // Scrollbar
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrowserToolbar(WidgetRef ref, PhotoBookState state) {
      final notifier = ref.read(projectProvider.notifier);
      return Container(
        height: 100, // Increased height for two rows
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: const Color(0xFF1A1A1A),
        child: Column(
          children: [
             // Import and Sort Row
             SingleChildScrollView(
               scrollDirection: Axis.horizontal,
               child: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   // Import Button (Small)
                   ElevatedButton(
                       style: ElevatedButton.styleFrom(
                         backgroundColor: const Color(0xFF333333),
                         foregroundColor: Colors.white,
                         minimumSize: const Size(80, 28),
                         padding: const EdgeInsets.symmetric(horizontal: 8),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                       ),
                       onPressed: () async {
                         final result = await FilePicker.platform.pickFiles(
                           type: FileType.custom,
                           allowedExtensions: [
                             'jpg', 'jpeg', 'png', 'webp', 'bmp', 'tiff', 'tif',
                             'JPG', 'JPEG', 'PNG', 'WEBP', 'BMP', 'TIFF', 'TIF'
                           ],
                           allowMultiple: true,
                         );
                         if (result != null) {
                           notifier.addPhotos(result.paths.whereType<String>().toList());
                         }
                       },
                       child: const Text("Importar", style: TextStyle(fontSize: 11)),
                   ),
                   const SizedBox(width: 8),
                   // Sort Options
                   const Text("Sort:", style: TextStyle(color: Colors.white54, fontSize: 10)),
                   _buildToolIcon(Icons.sort_by_alpha, "Nome", 
                      state.browserSortType == BrowserSortType.name,
                      () => notifier.setBrowserSortType(BrowserSortType.name)),
                   _buildToolIcon(Icons.access_time, "Data", 
                      state.browserSortType == BrowserSortType.date,
                      () => notifier.setBrowserSortType(BrowserSortType.date)),
                   
                   const SizedBox(width: 8),
                   TextButton.icon(
                      icon: const Icon(Icons.auto_awesome, size: 14, color: Colors.amberAccent),
                      label: const Text("AutoSelect", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                      onPressed: () => _handleAutoSelect(context, notifier),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                   ),
                   TextButton.icon(
                      icon: const Icon(Icons.timer, size: 14, color: Colors.blueAccent),
                      label: const Text("TimeShift", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      onPressed: () => showDialog(context: context, builder: (c) => const TimeShiftDialog()),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                   ),
                 ],
               ),
             ),
             
             const Divider(height: 8, color: Colors.white12),
             
             // Filter Row
             Expanded(
               child: SingleChildScrollView(
                 scrollDirection: Axis.horizontal,
                 child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                       const Text("Filtros: ", style: TextStyle(color: Colors.white54, fontSize: 10)),
                       _buildToolIcon(Icons.grid_view, "Todos", 
                          state.browserFilterType == BrowserFilterType.all,
                          () => notifier.setBrowserFilterType(BrowserFilterType.all)),
                       _buildToolIcon(Icons.check_box, "Marcados", 
                          state.browserFilterType == BrowserFilterType.selected,
                          () => notifier.setBrowserFilterType(BrowserFilterType.selected)),
                       _buildToolIcon(Icons.check_box_outline_blank, "Desmarcados", 
                          state.browserFilterType == BrowserFilterType.unselected,
                          () => notifier.setBrowserFilterType(BrowserFilterType.unselected)),
                       const VerticalDivider(width: 8, color: Colors.white12, indent: 4, endIndent: 4),
                       _buildToolIcon(Icons.photo_album, "Usados", 
                          state.browserFilterType == BrowserFilterType.used,
                          () => notifier.setBrowserFilterType(BrowserFilterType.used)),
                       _buildToolIcon(Icons.visibility_off, "Não Usados", 
                          state.browserFilterType == BrowserFilterType.unused,
                          () => notifier.setBrowserFilterType(BrowserFilterType.unused)),
                    ],
                 ),
               ),
             ),
          ],
        ),
      );
   }

  Widget _buildToolIcon(IconData icon, String tooltip, bool active, VoidCallback onTap) {
      return IconButton(
        icon: Icon(icon, size: 16, color: active ? Colors.blueAccent : Colors.white54),
        tooltip: tooltip,
        onPressed: onTap,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        visualDensity: VisualDensity.compact,
      );
  }

  void _showBrowserContextMenu(BuildContext context, WidgetRef ref, String path, Offset globalPos) {
      final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (overlay == null) return;
      
      showMenu(
         context: context,
         position: RelativeRect.fromLTRB(
            globalPos.dx, globalPos.dy,
            overlay.size.width - globalPos.dx,
            overlay.size.height - globalPos.dy
         ),
         color: const Color(0xFF262626),
         items: [
             PopupMenuItem(
                child: const ListTile(
                    leading: Icon(Icons.timer, color: Colors.amberAccent),
                    title: Text("Ajustar Horário (Time Shift)", style: TextStyle(color: Colors.white))
                ),
                onTap: () {
                    // Slight delay to allow menu to close
                    Future.delayed(Duration(milliseconds: 100), () {
                        showDialog(
                           context: context,
                           builder: (ctx) => const TimeShiftDialog()
                        );
                    });
                },
             ),
             PopupMenuItem(
                child: const ListTile(
                    leading: Icon(Icons.rotate_right, color: Colors.white),
                    title: Text("Girar 90°", style: TextStyle(color: Colors.white))
                ),
                onTap: () => ref.read(projectProvider.notifier).rotateGalleryPhoto(path, 90),
             ),
         ]
      );
  }

  Future<void> _handleAutoSelect(BuildContext context, ProjectNotifier notifier) async {
     final progressMsg = ValueNotifier<String>("Iniciando...");
     
     // Show Dialog
     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (ctx) {
          return ValueListenableBuilder<String>(
             valueListenable: progressMsg,
             builder: (c, val, _) => AlertDialog(
                content: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                       const CircularProgressIndicator(),
                       const SizedBox(height: 16),
                       const Text("AutoSelect Inteligente", style: TextStyle(fontWeight: FontWeight.bold)),
                       const SizedBox(height: 8),
                       Text(val, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                   ],
                ),
             ),
          );
       },
     );
     
     await notifier.runAutoSelect(onProgress: (phase, proc, total, sel) {
         progressMsg.value = "$phase\nAnalizado: $proc / $total\nSelecionadas: $sel";
     });
     
     if (context.mounted) Navigator.pop(context);
  }
}
