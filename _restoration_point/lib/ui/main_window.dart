import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/project_model.dart';
import '../state/project_state.dart';
import '../logic/layout_engine.dart';
import '../logic/template_system.dart';
import 'package:file_picker/file_picker.dart';
import 'widgets/photo_manipulator.dart';
import 'widgets/properties_panel.dart';

class PhotoBookHome extends ConsumerStatefulWidget {
  const PhotoBookHome({super.key});

  @override
  ConsumerState<PhotoBookHome> createState() => _PhotoBookHomeState();
}

class _PhotoBookHomeState extends ConsumerState<PhotoBookHome> {
  final GlobalKey _pageKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(projectProvider);
    return Scaffold(
      body: Column(
        children: [
          // 1. Toolbar area (Only rebuilds on undo/redo status)
          Consumer(builder: (context, ref, _) {
            final canUndo = ref.watch(projectProvider.select((s) => s.canUndo));
            final canRedo = ref.watch(projectProvider.select((s) => s.canRedo));
            return _buildToolbar(context, ref, canUndo, canRedo);
          }),
          
          Expanded(
            child: Row(
              children: [
                // 2. Left Dock: File Browser
                _buildDock("File Browser", 250, _buildFileBrowser(ref)),
                
                // 3. Center: Canvas (Only rebuilds when photos/page/selection change)
                Expanded(
                  child: Container(
                    color: Colors.grey[800],
                    child: Center(
                      child: Consumer(builder: (context, ref, _) {
                         final state = ref.watch(projectProvider);
                         return _buildCanvas(context, ref, state);
                      }),
                    ),
                  ),
                ),
                
                // 4. Right Dock: Timeline / Photos / Properties
                Consumer(builder: (context, ref, _) {
                   final state = ref.watch(projectProvider);
                   return _buildDock("Properties & Photos", 300, _buildRightDock(context, ref, state));
                }),
              ],
            ),
          ),
          
          // 5. Bottom Dock: Thumbnails (Only rebuilds when pages/index change)
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border(top: BorderSide(color: Colors.grey[400]!)),
            ),
            child: Consumer(builder: (context, ref, _) {
               final state = ref.watch(projectProvider);
               return _buildThumbnails(ref, state);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, WidgetRef ref, bool canUndo, bool canRedo) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D), // Dark Toolbar
        border: Border(bottom: BorderSide(color: Colors.black)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
             icon: const Icon(Icons.note_add_outlined, color: Colors.white70), 
             tooltip: "New Project",
             onPressed: () => _showNewProjectDialog(context, ref),
          ),
          IconButton(
             icon: const Icon(Icons.file_open_outlined, color: Colors.white70), 
             tooltip: "Open",
             onPressed: () {} 
          ),
          IconButton(
             icon: const Icon(Icons.save_outlined, color: Colors.white70), 
             tooltip: "Save",
             onPressed: () {} 
          ),
          const VerticalDivider(indent: 8, endIndent: 8, color: Colors.white24),
          IconButton(
             icon: const Icon(Icons.check_box_outline_blank, color: Colors.white70), 
             tooltip: "Add Placeholder Box",
             onPressed: () {
                 final item = PhotoItem(
                    path: "", // Empty path = Placeholder
                    x: 20, y: 20, 
                    width: 100, height: 100
                 );
                 ref.read(projectProvider.notifier).addPhotoToCurrentPage(item);
             }
          ),
          IconButton(
             icon: const Icon(Icons.add_box_outlined, color: Colors.white70), 
             tooltip: "Add Page",
             onPressed: () => ref.read(projectProvider.notifier).addPage()
          ),
          IconButton(
             icon: const Icon(Icons.auto_awesome_mosaic, color: Colors.tealAccent), 
             tooltip: "Auto Layout (Cycle Options)",
             onPressed: () {
                final state = ref.read(projectProvider);
                if (state.project.pages.isEmpty) return;
                
                final page = state.project.pages[state.project.currentPageIndex];
                if (page.photos.isEmpty) return;

                // 1. Get All Templates for Count
                final templates = TemplateSystem.getTemplatesForCount(page.photos.length);
                if (templates.isEmpty) return;

                // 2. Cycle or Randomize
                // To cycle, we need to know the 'current' one. Since we don't store it, 
                // we'll pick Randomly for now to ensure variety as requested.
                // A better approach would be to store 'lastTemplateIndex' in the ProjectState.
                // For now:
                final random = math.Random();
                final templateId = templates[random.nextInt(templates.length)];
                
                // 3. Apply Template
                final newLayout = TemplateSystem.applyTemplate(
                    templateId, 
                    page.photos, 
                    page.widthMm, 
                    page.heightMm
                );
                
                // 4. Update State
                ref.read(projectProvider.notifier).updatePageLayout(newLayout);
             }
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white70), 
            onPressed: canUndo ? () => ref.read(projectProvider.notifier).undo() : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, color: Colors.white70), 
            onPressed: canRedo ? () => ref.read(projectProvider.notifier).redo() : null,
          ),
        ],
      ),
    );
  }

  void _showNewProjectDialog(BuildContext context, WidgetRef ref) {
    final widthCtrl = TextEditingController(text: "21.0");
    final heightCtrl = TextEditingController(text: "29.7");
    final dpiCtrl = TextEditingController(text: "300");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("New Project Setup", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Define Page Size", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widthCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Width (cm)",
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: heightCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Height (cm)",
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dpiCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "DPI (Resolution)",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            child: const Text("Create Project"),
            onPressed: () {
               final w = double.tryParse(widthCtrl.text) ?? 21.0;
               final h = double.tryParse(heightCtrl.text) ?? 29.7;
               final dpi = int.tryParse(dpiCtrl.text) ?? 300;
               
               // Convert CM to MM
               final widthMm = w * 10;
               final heightMm = h * 10;

               // Initialize
               ref.read(projectProvider.notifier).initializeProject(widthMm, heightMm, 1);
               // TODO: Store DPI in project state/model if needed, currently passed implicitly via context or future updates
               
               Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDock(String title, double width, Widget child) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Dark Dock Background
        border: Border(
           right: BorderSide(color: Colors.black),
           left: BorderSide(color: Colors.black),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF252526), // Slightly lighter header
            child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white70)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildFileBrowser(WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3E3E42),
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              allowMultiple: true,
            );
            if (result != null) {
              final paths = result.paths.whereType<String>().toList();
              ref.read(projectProvider.notifier).addPhotos(paths);
            }
          },
          icon: const Icon(Icons.folder_open),
          label: const Text("Import Photos"),
        ),
        const SizedBox(height: 10),
        const Text("Drag & Drop supported", style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildRightDock(BuildContext context, WidgetRef ref, PhotoBookState state) {
    PhotoItem? selectedPhoto;
    if (state.selectedPhotoId != null && state.project.currentPageIndex >= 0) {
       final page = state.project.pages[state.project.currentPageIndex];
       try {
         selectedPhoto = page.photos.firstWhere((p) => p.id == state.selectedPhotoId);
       } catch (_) {}
    }

    return Column(
      children: [
        // Properties Section
        if (selectedPhoto != null) ...[
        Expanded(
          flex: 0,
          child: PropertiesPanel(
            photo: selectedPhoto!,
            isEditingContent: state.isEditingContent,
          ),
        ),
          const Divider(height: 1, color: Colors.black),
        ],

        // Photo List (Timeline)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
               const Padding(
                 padding: EdgeInsets.all(8.0),
                 child: Text("Project Photos", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
               ),
               Expanded(
                 child: GridView.builder(
                   padding: const EdgeInsets.all(8),
                   gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                     crossAxisCount: 3, 
                     crossAxisSpacing: 4, 
                     mainAxisSpacing: 4
                   ),
                   itemCount: state.project.allImagePaths.length,
                   itemBuilder: (ctx, i) {
                     final path = state.project.allImagePaths[i];
                     return Draggable<String>(
                       data: path,
                       feedback: Opacity(
                         opacity: 0.7,
                         child: SizedBox(
                           width: 80, height: 80,
                           child: Image.file(File(path), fit: BoxFit.cover),
                         ),
                       ),
                       child: Image.file(
                         File(path),
                         fit: BoxFit.cover,
                         errorBuilder: (_,__,___) => Container(color: Colors.red),
                       ),
                     );
                   },
                 ),
               )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildCanvas(BuildContext context, WidgetRef ref, PhotoBookState state) {
    if (state.project.pages.isEmpty) return const SizedBox();

    final currentPage = state.project.pages[state.project.currentPageIndex];

    return Container(
      color: Colors.grey[800],
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          // Use FittedBox to ensure the "MM" sized container fits in the view
          return Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: DropTarget(
                onDragDone: (details) {
                   _handleDrop(ref, details.localPosition, details.files.map((f) => f.path).toList(), currentPage);
                },
                child: DragTarget<String>(
                  onAcceptWithDetails: (details) {
                    final RenderBox? box = _pageKey.currentContext?.findRenderObject() as RenderBox?;
                    if (box != null) {
                      final localPos = box.globalToLocal(details.offset);
                      _handleDrop(ref, localPos, [details.data], currentPage);
                    }
                  },
                  builder: (ctx, candidates, rejected) {
                    return GestureDetector(
                      onTap: () {
                         ref.read(projectProvider.notifier).selectPhoto(null);
                         ref.read(projectProvider.notifier).setEditingContent(false);
                      },
                      child: Container(
                        key: _pageKey,
                        width: currentPage.widthMm,
                        height: currentPage.heightMm,
                        decoration: BoxDecoration(
                          color: Color(currentPage.backgroundColor),
                          // Visual page border/shadow
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ...currentPage.photos.map((photo) => _buildPhotoWidget(ref, photo, state.selectedPhotoId == photo.id, key: ValueKey(photo.id))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        }
      ),
    );
  }



  Widget _buildPhotoWidget(WidgetRef ref, PhotoItem photo, bool isSelected, {Key? key}) {
    // Determine if we are editing THIS photo's content
    final isEditingContent = isSelected && ref.watch(projectProvider).isEditingContent;

    return PhotoManipulator(
      key: key,
      photo: photo,
      isSelected: isSelected,
      isEditingContent: isEditingContent,
      onSelect: () {
         ref.read(projectProvider.notifier).selectPhoto(photo.id);
         // If we select a different photo, we probably should exit content edit mode?
         // The notifier handles state, but let's ensure:
         if (!isSelected) {
            ref.read(projectProvider.notifier).setEditingContent(false);
         }
      },
      onDoubleTap: () {
         ref.read(projectProvider.notifier).selectPhoto(photo.id);
         // Toggle Mode
         ref.read(projectProvider.notifier).setEditingContent(!isEditingContent);
      },
      onUpdate: (newPhoto) {
         ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => newPhoto); 
      },
      onDragEnd: () {
         ref.read(projectProvider.notifier).saveHistorySnapshot();
      },
    );
  }

  Widget _buildThumbnails(WidgetRef ref, PhotoBookState state) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(10),
      itemCount: state.project.pages.length,
      itemBuilder: (ctx, i) {
        final isSelected = i == state.project.currentPageIndex;
        return GestureDetector(
          onTap: () => ref.read(projectProvider.notifier).setPageIndex(i),
          child: Container(
            width: 100,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: isSelected ? Border.all(color: Colors.blue, width: 3) : Border.all(color: Colors.grey),
            ),
            child: Center(child: Text("Page ${i+1}")),
          ),
        );
      },
    );
  }
  Widget _buildSlider(BuildContext context, String label, double value, double min, double max, Function(double) onChanged) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
               thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
               overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(width: 35, child: Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.white54, fontSize: 10))),
      ],
    );
  }
  bool _isImage(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png') || p.endsWith('.webp');
  }

  void _handleDrop(WidgetRef ref, Offset dropPos, List<String> paths, AlbumPage currentPage) {
    bool handled = false;
    for (final photo in currentPage.photos.reversed) {
      final rect = Rect.fromLTWH(photo.x, photo.y, photo.width, photo.height);
      if (rect.contains(dropPos)) {
        if (paths.isNotEmpty && _isImage(paths.first)) {
           ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(path: paths.first));
           handled = true;
        }
        break;
      }
    }
    if (!handled) {
      for (final path in paths) {
        if(_isImage(path)) {
           final item = PhotoItem(
              path: path, 
              x: dropPos.dx - 50, 
              y: dropPos.dy - 50, 
              width: 100, 
              height: 100
           );
           ref.read(projectProvider.notifier).addPhotoToCurrentPage(item);
        }
      }
    }
  }
}
