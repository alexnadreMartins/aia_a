import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../models/project_model.dart';
import '../models/asset_model.dart';
import '../state/project_state.dart';
import '../state/asset_state.dart';
import '../logic/layout_engine.dart';
import '../logic/template_system.dart';
import '../logic/export_helper.dart';
import 'widgets/photo_manipulator.dart';
import 'widgets/properties_panel.dart';

class PhotoBookHome extends ConsumerStatefulWidget {
  const PhotoBookHome({super.key});

  @override
  ConsumerState<PhotoBookHome> createState() => _PhotoBookHomeState();
}

class _PhotoBookHomeState extends ConsumerState<PhotoBookHome> {
  final GlobalKey _pageKey = GlobalKey();
  final GlobalKey _canvasCaptureKey = GlobalKey();
  final ScrollController _thumbScrollController = ScrollController();
  final TransformationController _transformationController = TransformationController();
  int _leftDockIndex = 0; // 0 = Fotos, 1 = Assets

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(() {
      final zoom = _transformationController.value.getMaxScaleOnAxis();
      ref.read(projectProvider.notifier).setCanvasScale(zoom);
    });
  }

  @override
  void dispose() {
    _thumbScrollController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = ref.watch(projectProvider.select((s) => s.isProcessing));

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
            ref.read(projectProvider.notifier).selectAllBrowserPhotos();
          },
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
            ref.read(projectProvider.notifier).deselectAllBrowserPhotos();
          },
        },
        child: Stack(
          children: [
          Column(
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
                    // 2. Left Dock: Photos & Assets
                    _buildLeftDock(ref),
                    
                    // 3. Center: Canvas
                    Expanded(
                      child: Container(
                        color: const Color(0xFF000000), // App background
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
          if (isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.amberAccent),
                      const SizedBox(height: 16),
                      Text(
                        "IA Smart Flow: Analisando fotos...",
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Garantindo a melhor orientação e estilo",
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

  Widget _buildToolbar(BuildContext context, WidgetRef ref, bool canUndo, bool canRedo) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF000000), // Deep black toolbar
        border: Border(bottom: BorderSide(color: Color(0xFF262626))),
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
             onPressed: () => _handleLoad(context, ref)
          ),
          IconButton(
             icon: const Icon(Icons.save_outlined, color: Colors.white70), 
             tooltip: "Save",
             onPressed: () => _handleSave(context, ref)
          ),
          const VerticalDivider(indent: 8, endIndent: 8, color: Colors.white24),
          IconButton(
             icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
             tooltip: "Export PDF",
             onPressed: () => _handleExportPdf(context, ref),
          ),
          IconButton(
             icon: const Icon(Icons.image_outlined, color: Colors.blueAccent),
             tooltip: "Export JPG",
             onPressed: () => _handleExportJpg(context, ref),
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

                final templates = TemplateSystem.getTemplatesForCount(page.photos.length);
                if (templates.isEmpty) return;
                final random = math.Random();
                final templateId = templates[random.nextInt(templates.length)];
                
                final newLayout = TemplateSystem.applyTemplate(
                    templateId, 
                    page.photos, 
                    page.widthMm, 
                    page.heightMm
                );
                ref.read(projectProvider.notifier).updatePageLayout(newLayout);
             }
          ),
          IconButton(
             icon: const Icon(Icons.psychology_outlined, color: Colors.amberAccent), 
             tooltip: "AI Smart Flow (Layout Selection)",
             onPressed: () {
                final state = ref.read(projectProvider);
                if (state.selectedBrowserPaths.isEmpty) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select some images first!")));
                   return;
                }
                ref.read(projectProvider.notifier).applyAutoLayout(state.selectedBrowserPaths.toList());
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
    final contractCtrl = TextEditingController();
    final fichaCtrl = TextEditingController();

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
            const SizedBox(height: 16),
            TextField(
              controller: contractCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Contrato (opcional)",
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: fichaCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Ficha/Projeto (opcional)",
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
               
               // Set contract and ficha if provided
               if (contractCtrl.text.isNotEmpty) {
                 ref.read(projectProvider.notifier).setContractNumber(contractCtrl.text);
               }
               if (fichaCtrl.text.isNotEmpty) {
                 ref.read(projectProvider.notifier).state = ref.read(projectProvider).copyWith(
                   project: ref.read(projectProvider).project.copyWith(name: fichaCtrl.text),
                 );
               }
               
               Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLeftDock(WidgetRef ref) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: Border(
           right: BorderSide(color: Color(0xFF262626)),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF000000),
              border: Border(bottom: BorderSide(color: Color(0xFF262626))),
            ),
            child: Row(
              children: [
                _buildDockTab("Fotos", 0),
                _buildDockTab("Assets", 1),
              ],
            ),
          ),
          Expanded(
            child: _leftDockIndex == 0 
              ? _buildFileBrowser(ref) 
              : _buildAssetLibrary(ref),
          ),
        ],
      ),
    );
  }

  Widget _buildDockTab(String title, int index) {
    bool isSelected = _leftDockIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _leftDockIndex = index),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.amberAccent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssetLibrary(WidgetRef ref) {
    final assetState = ref.watch(assetProvider);
    if (assetState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A1A1A),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: const BorderSide(color: Color(0xFF262626)),
              ),
            ),
            onPressed: () => _showAddCollectionDialog(context, ref),
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: const Text("Nova Coleção", style: TextStyle(fontSize: 12)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: assetState.collections.length,
            itemBuilder: (ctx, idx) {
              final collection = assetState.collections[idx];
              return _buildAssetCollection(context, ref, collection);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAssetCollection(BuildContext context, WidgetRef ref, AssetCollection collection) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(collection.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      iconColor: Colors.white54,
      collapsedIconColor: Colors.white54,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18, color: Colors.white54),
            onPressed: () => _importAssetsToCollection(ref, collection.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
            onPressed: () => ref.read(assetProvider.notifier).removeCollection(collection.id),
          ),
        ],
      ),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: collection.assets.length,
          itemBuilder: (ctx, i) {
            final asset = collection.assets[i];
            return _buildLibraryAssetItem(ref, collection.id, asset);
          },
        ),
      ],
    );
  }

  Widget _buildLibraryAssetItem(WidgetRef ref, String collectionId, LibraryAsset asset) {
    return Draggable<LibraryAsset>(
      data: asset,
      feedback: Opacity(
        opacity: 0.7,
        child: SizedBox(
          width: 60, height: 60,
          child: Image.file(File(asset.path), fit: BoxFit.contain),
        ),
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: asset.type == AssetType.template ? Colors.amberAccent.withOpacity(0.3) : Colors.transparent,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(child: Image.file(File(asset.path), fit: BoxFit.contain)),
                const SizedBox(height: 2),
                Text(
                  asset.type == AssetType.template ? "Template" : "Elemento",
                  style: const TextStyle(fontSize: 7, color: Colors.white38),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0, right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 12, color: Colors.white54),
              onPressed: () => ref.read(assetProvider.notifier).removeAssetFromCollection(collectionId, asset.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCollectionDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("Nova Coleção", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Nome da Coleção",
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                ref.read(assetProvider.notifier).addCollection(ctrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text("Criar"),
          ),
        ],
      ),
    );
  }

  Future<void> _importAssetsToCollection(WidgetRef ref, String collectionId) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (result == null) return;

    final paths = result.paths.whereType<String>().toList();
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF333333),
          title: const Text("Tipo de Importação", style: TextStyle(color: Colors.white)),
          content: const Text(
            "Selecione como esses assets devem ser tratados:",
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
              onPressed: () {
                ref.read(assetProvider.notifier).addAssetsToCollection(collectionId, paths, AssetType.element);
                Navigator.pop(ctx);
              },
              child: const Text("Elementos (Decoração)"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[800]),
              onPressed: () {
                ref.read(assetProvider.notifier).addAssetsToCollection(collectionId, paths, AssetType.template);
                Navigator.pop(ctx);
              },
              child: const Text("Templates (Molduras)"),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDock(String title, double width, Widget child) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A), // Next.js deep black
        border: Border(
           right: BorderSide(color: Color(0xFF262626)),
           left: BorderSide(color: Color(0xFF262626)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF000000), // Slightly lighter header
            child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13, letterSpacing: -0.2)),
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
            backgroundColor: const Color(0xFF1A1A1A), // Subtle gray/black
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Color(0xFF262626))),
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
              final paths = result.paths.whereType<String>().toList();
              ref.read(projectProvider.notifier).addPhotos(paths);
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text("Import Images", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    children: [
                      Text(
                        "Total: ${state.project.allImagePaths.length}",
                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Selected: ${state.selectedBrowserPaths.length}",
                        style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                      ),
                      const Spacer(),
                      // Rotation Buttons
                      IconButton(
                        icon: const Icon(Icons.rotate_left, size: 16, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: "Girar 90° Esquerda",
                        onPressed: () => ref.read(projectProvider.notifier).rotateSelectedGalleryPhotos(270),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.rotate_90_degrees_ccw, size: 16, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: "Girar 180°",
                        onPressed: () => ref.read(projectProvider.notifier).rotateSelectedGalleryPhotos(180),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.rotate_right, size: 16, color: Colors.white70),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: "Girar 90° Direita",
                        onPressed: () => ref.read(projectProvider.notifier).rotateSelectedGalleryPhotos(90),
                      ),
                    ],
                  ),
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
                      final isSelected = state.selectedBrowserPaths.contains(path);
                      final rotation = state.project.imageRotations[path] ?? 0;
                      final usageCount = state.photoUsage[path] ?? 0;

                      return Draggable<String>(
                        data: path,
                        feedback: Opacity(
                          opacity: 0.7,
                          child: SizedBox(
                            width: 80, height: 80,
                            child: Transform.rotate(
                              angle: (math.pi / 180) * rotation,
                              child: Image.file(File(path), fit: BoxFit.cover),
                            ),
                          ),
                        ),
                        child: GestureDetector(
                          onTap: () => ref.read(projectProvider.notifier).toggleBrowserPathSelection(path),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: isSelected ? Colors.blueAccent : Colors.transparent, width: 2),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Transform.rotate(
                                    angle: (math.pi / 180) * rotation,
                                    child: Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      color: usageCount > 0 ? Colors.black.withOpacity(0.5) : null,
                                      colorBlendMode: usageCount > 0 ? BlendMode.darken : null,
                                      errorBuilder: (_,__,___) => Container(color: Colors.red),
                                    ),
                                  ),
                                ),
                                if (usageCount > 0)
                                  Positioned(
                                    top: 4, right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white24, width: 0.5),
                                      ),
                                      child: Text(
                                        "$usageCount",
                                        style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                if (isSelected)
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.blueAccent.withOpacity(0.2),
                                      child: const Center(
                                        child: Icon(Icons.check_circle, color: Colors.blueAccent, size: 24),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
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
      color: const Color(0xFF000000),
      child: Stack(
        children: [
          // 0. Background Tap Handler (moved here to catch ALL taps on background)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                 ref.read(projectProvider.notifier).selectPhoto(null);
                 ref.read(projectProvider.notifier).setEditingContent(false);
              },
              behavior: HitTestBehavior.opaque, // Catch everything not caught by children
              child: Container(color: Colors.transparent),
            ),
          ),
          
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.1,
              maxScale: 10.0,
              scaleEnabled: true,
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(200),
                  child: DropTarget(
                    onDragDone: (details) {
                       _handleDrop(ref, details.localPosition, details.files.map((f) => f.path).toList(), currentPage);
                    },
                    child: DragTarget<Object>(
                      onAcceptWithDetails: (details) {
                        final RenderBox? box = _pageKey.currentContext?.findRenderObject() as RenderBox?;
                        if (box != null) {
                          final localPos = box.globalToLocal(details.offset);
                          final data = details.data;
                          if (data is String) {
                            _handleDrop(ref, localPos, [data], currentPage);
                          } else if (data is LibraryAsset) {
                            _handleAssetDrop(ref, localPos, data, currentPage);
                          }
                        }
                      },
                      builder: (ctx, candidates, rejected) {
                        return GestureDetector(
                          onSecondaryTapDown: (details) {
                            _showPageContextMenu(context, ref, details.localPosition);
                          },
                          child: RepaintBoundary(
                            key: _canvasCaptureKey,
                            child: Container(
                              key: _pageKey,
                              width: currentPage.widthMm,
                              height: currentPage.heightMm,
                              decoration: BoxDecoration(
                                color: Color(currentPage.backgroundColor),
                                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ...currentPage.photos.map((photo) => _buildPhotoWidget(ref, photo, state.selectedPhotoId == photo.id, key: ValueKey(photo.id))),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // 2. Zoom Controls Overlay
          Positioned(
            bottom: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white),
                    onPressed: () {
                      final current = _transformationController.value;
                      final zoom = current.getMaxScaleOnAxis();
                      final newScale = (zoom - 0.1).clamp(0.1, 5.0);
                      _transformationController.value = Matrix4.identity()..scale(newScale);
                    },
                    tooltip: "Zoom Out",
                  ),
                  Text(
                    "${(state.canvasScale * 100).toInt()}%",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: () {
                      final current = _transformationController.value;
                      final zoom = current.getMaxScaleOnAxis();
                      final newScale = (zoom + 0.1).clamp(0.1, 5.0);
                      _transformationController.value = Matrix4.identity()..scale(newScale);
                    },
                    tooltip: "Zoom In",
                  ),
                  const VerticalDivider(color: Colors.white24, width: 20, indent: 10, endIndent: 10),
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong, color: Colors.white70),
                    onPressed: () {
                       _fitToScreen(context, ref, state);
                    },
                    tooltip: "Fit to Screen",
                  ),
                ],
              ),
            ),
          ),
        ],
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
      isExporting: ref.watch(projectProvider).isExporting, // Pass global export flag
      globalRotation: ref.watch(projectProvider).project.imageRotations[photo.path] ?? 0,
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
      onContextMenu: (localPos) {
         _showPhotoContextMenu(context, ref, photo, localPos);
      },
    );
  }

  void _showPhotoContextMenu(BuildContext context, WidgetRef ref, PhotoItem photo, Offset localPos) {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // Convert local to global for showMenu
    final RenderBox? photoBox = context.findRenderObject() as RenderBox?; // Actually we need the photo widget's box
    // To simplify, we'll use the global offset from the event if possible or just show at mouse
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        localPos.dx + 300, // Offset for dock/center
        localPos.dy + 100, 
        overlay.size.width - localPos.dx, 
        overlay.size.height - localPos.dy
      ),
      color: const Color(0xFF262626),
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.content_cut, color: Colors.white, size: 18), title: Text("Cortar", style: TextStyle(color: Colors.white))),
          onTap: () => ref.read(projectProvider.notifier).cutPhoto(photo.id),
        ),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.content_copy, color: Colors.white, size: 18), title: Text("Copiar", style: TextStyle(color: Colors.white))),
          onTap: () => ref.read(projectProvider.notifier).copyPhoto(photo.id),
        ),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.delete_outline, color: Colors.redAccent, size: 18), title: Text("Excluir", style: TextStyle(color: Colors.redAccent))),
          onTap: () => ref.read(projectProvider.notifier).removePhoto(photo.id),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.vertical_align_top, color: Colors.white, size: 18), title: Text("Trazer para Frente", style: TextStyle(color: Colors.white))),
          onTap: () => ref.read(projectProvider.notifier).bringToFront(photo.id),
        ),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.vertical_align_bottom, color: Colors.white, size: 18), title: Text("Enviar para Trás", style: TextStyle(color: Colors.white))),
          onTap: () => ref.read(projectProvider.notifier).sendToBack(photo.id),
        ),
      ],
    );
  }

  void _showPageContextMenu(BuildContext context, WidgetRef ref, Offset localPos) {
    final state = ref.read(projectProvider);

    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        localPos.dx + 300, 
        localPos.dy + 100, 
        overlay.size.width - localPos.dx, 
        overlay.size.height - localPos.dy
      ),
      color: const Color(0xFF262626),
      items: <PopupMenuEntry<dynamic>>[
        if (state.clipboardPhoto != null)
          PopupMenuItem(
            child: const ListTile(leading: Icon(Icons.content_paste, color: Colors.white, size: 18), title: Text("Colar Aqui", style: TextStyle(color: Colors.white))),
            onTap: () => ref.read(projectProvider.notifier).pastePhoto(localPos.dx, localPos.dy),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.label, color: Colors.white, size: 18), title: Text("Gerar Etiquetas (Primeira/Última)", style: TextStyle(color: Colors.white, fontSize: 13))),
          onTap: () {
            _showContractDialog(context, ref, allPages: false);
          },
        ),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.label, color: Colors.amber, size: 18), title: Text("Gerar Etiquetas (Todas)", style: TextStyle(color: Colors.white, fontSize: 13))),
          onTap: () {
            _showContractDialog(context, ref, allPages: true);
          },
        ),
      ],
    );
  }

  void _showContractDialog(BuildContext context, WidgetRef ref, {required bool allPages}) {
    final labelCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("Texto da Etiqueta", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: labelCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Texto da Etiqueta",
            hintText: "Ex: 340_2234",
            labelStyle: TextStyle(color: Colors.white54),
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancelar"),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            child: const Text("Gerar Etiquetas"),
            onPressed: () {
              if (labelCtrl.text.isNotEmpty) {
                // Store the label text temporarily for generation
                ref.read(projectProvider.notifier).state = ref.read(projectProvider).copyWith(
                  project: ref.read(projectProvider).project.copyWith(
                    contractNumber: labelCtrl.text,
                  ),
                );
              }
              ref.read(projectProvider.notifier).generateLabels(allPages: allPages);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnails(WidgetRef ref, PhotoBookState state) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Scrollbar(
        controller: _thumbScrollController,
        thumbVisibility: true,
      child: ReorderableListView.builder(
          scrollController: _thumbScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          itemCount: state.project.pages.length,
          buildDefaultDragHandles: false, // We will provide our own drag listener
          onReorder: (oldIndex, newIndex) {
            ref.read(projectProvider.notifier).reorderPage(oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final page = state.project.pages[index];
            final isCurrent = state.project.currentPageIndex == index;
            final double pageAspectRatio = page.widthMm / page.heightMm;
            final double thumbHeight = 110.0;
            final double thumbWidth = thumbHeight * pageAspectRatio;

            return ReorderableDragStartListener(
              index: index,
              key: ValueKey(page.id),
              child: GestureDetector(
                onTap: () => ref.read(projectProvider.notifier).setPageIndex(index),
                child: Container(
                  width: thumbWidth,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Color(page.backgroundColor),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isCurrent ? Colors.amberAccent : Colors.white12,
                    width: isCurrent ? 2 : 1,
                  ),
                  boxShadow: [
                    if (isCurrent)
                      BoxShadow(color: Colors.amberAccent.withOpacity(0.4), blurRadius: 8),
                  ],
                ),
                child: Stack(
                  children: [
                    // Page Content Preview (Actual Photos)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: _buildMiniPagePreview(page),
                      ),
                    ),
                    
                    // Page Number Badge
                    Positioned(
                      top: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCurrent ? Colors.amberAccent : Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${index + 1}", 
                          style: TextStyle(
                            color: isCurrent ? Colors.black : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    
                    if (page.photos.isNotEmpty)
                      Positioned(
                        bottom: 4, right: 4,
                        child: Text(
                          "${page.photos.length} fotos",
                          style: TextStyle(fontSize: 8, color: Colors.grey[500]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildMiniPagePreview(AlbumPage page) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double scaleX = constraints.maxWidth / page.widthMm;
        final double scaleY = constraints.maxHeight / page.heightMm;

        return Stack(
          children: page.photos.map((photo) {
            return Positioned(
              left: photo.x * scaleX,
              top: photo.y * scaleY,
              width: photo.width * scaleX,
              height: photo.height * scaleY,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(1),
                ),
                child: photo.path.isNotEmpty 
                  ? Image.file(File(photo.path), fit: BoxFit.cover, errorBuilder: (_,__,___) => const SizedBox())
                  : const SizedBox(),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _fitToScreen(BuildContext context, WidgetRef ref, PhotoBookState state) {
    if (state.project.pages.isEmpty) return;
    
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    
    final Size viewportSize = box.size;
    final page = state.project.pages[state.project.currentPageIndex];
    
    // Available space for the page (viewport minus some padding)
    final double availWidth = viewportSize.width - 200; // Account for 100 padding on each side
    final double availHeight = viewportSize.height - 250; // Account for padding + bottom dock
    
    if (availWidth <= 0 || availHeight <= 0) return;

    final double scaleX = availWidth / page.widthMm;
    final double scaleY = availHeight / page.heightMm;
    
    final double finalScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 5.0);
    
    _transformationController.value = Matrix4.identity()..scale(finalScale);
    ref.read(projectProvider.notifier).setCanvasScale(finalScale);
  }

  // --- Handlers ---

  Future<void> _handleSave(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: "Save Project",
      fileName: "album_project.alem",
      allowedExtensions: ['alem'],
    );
    if (result != null) {
      await ref.read(projectProvider.notifier).saveProject(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Projeto salvo com sucesso!")));
      }
    }
  }

  Future<void> _handleLoad(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['alem'],
    );
    if (result != null && result.files.single.path != null) {
      await ref.read(projectProvider.notifier).loadProject(result.files.single.path!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Projeto carregado!")));
      }
    }
  }

  Future<void> _handleExportPdf(BuildContext context, WidgetRef ref) async {
    final state = ref.read(projectProvider);
    String defaultName = "meu_album.pdf";
    if (state.currentProjectPath != null) {
      final base = p.basenameWithoutExtension(state.currentProjectPath!);
      defaultName = "$base.pdf";
    }

    final result = await FilePicker.platform.saveFile(
      dialogTitle: "Export PDF",
      fileName: defaultName,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      _showExportingDialog(context);
      
      final state = ref.read(projectProvider);
      final List<GlobalKey> keys = [];
      
      // PPI Scale calculation: 1 unit = 1mm, target ppi is from project
      // Standard screen resolution is roughly 96 DPI, but Flutter units are logical pixels.
      // If we assume 1 unit = 1mm, then target_dpi / 25.4 gives the pixelRatio.
      final double exportPixelRatio = state.project.ppi / 25.4;

      _showExportingDialog(context);
      
      final originalIndex = state.project.currentPageIndex;
      final capturedBytes = <List<int>>[];

      // Enable Export Mode: Hides all UI handles
      ref.read(projectProvider.notifier).setIsExporting(true);
      await Future.delayed(const Duration(milliseconds: 300)); // Short wait for rebuild
      
      for (int i = 0; i < state.project.pages.length; i++) {
         ref.read(projectProvider.notifier).setPageIndex(i);
         // Deselect not strictly needed anymore given the flag, but good practice
         ref.read(projectProvider.notifier).selectPhoto(null);
         ref.read(projectProvider.notifier).setEditingContent(false);
         // Wait for UI to update (especially image loading for the new page)
         await Future.delayed(const Duration(milliseconds: 1500));
         final bytes = await ExportHelper.captureKeyToBytes(_canvasCaptureKey, pixelRatio: exportPixelRatio);
         if (bytes != null) capturedBytes.add(bytes);
      }
      
      // Disable Export Mode
      ref.read(projectProvider.notifier).setIsExporting(false);

      // Restore index
      ref.read(projectProvider.notifier).setPageIndex(originalIndex);
      
      // Now use ExportHelper to build PDF from captured bytes
      await _buildPdfFromBytes(capturedBytes, state.project, result);
      
      if (mounted) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PDF Exportado com sucesso!")));
      }
    }
  }

  Future<void> _handleExportJpg(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "Selecione a pasta para as imagens",
    );
    if (result != null) {
        final state = ref.read(projectProvider);
        final double exportPixelRatio = state.project.ppi / 25.4;

        // Derive prefix from project path if available
        String prefix = "pagina";
        if (state.currentProjectPath != null) {
          prefix = p.basenameWithoutExtension(state.currentProjectPath!);
        }

        _showExportingDialog(context);
        final originalIndex = state.project.currentPageIndex;

        // Enable Export Mode
        ref.read(projectProvider.notifier).setIsExporting(true);
        await Future.delayed(const Duration(milliseconds: 300));

        for (int i = 0; i < state.project.pages.length; i++) {
          ref.read(projectProvider.notifier).setPageIndex(i);
          ref.read(projectProvider.notifier).selectPhoto(null);
          ref.read(projectProvider.notifier).setEditingContent(false);
          await Future.delayed(const Duration(milliseconds: 1500));
          final bytes = await ExportHelper.captureKeyToBytes(_canvasCaptureKey, pixelRatio: exportPixelRatio);
          if (bytes != null) {
             final pageNum = (i + 1).toString().padLeft(2, '0');
             final fileName = "${prefix}_$pageNum.jpg";
             final filePath = p.join(result, fileName);
             await ExportHelper.saveAsHighResJpg(
               pngBytes: bytes, 
               path: filePath, 
               dpi: state.project.ppi.toInt()
             );
          }
        }

        // Disable Export Mode
        ref.read(projectProvider.notifier).setIsExporting(false);

        // Restore index

        
        ref.read(projectProvider.notifier).setPageIndex(originalIndex);
       
       if (mounted) {
         Navigator.pop(context);
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imagens exportadas!")));
       }
    }
  }

  void _showExportingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Exportando projeto..."),
            Text("Aguarde, processando todas as páginas.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // Extra helper because I can't easily pass the keys of unrendered pages
  static Future<void> _buildPdfFromBytes(List<List<int>> bytesList, Project project, String path) async {
    final pdf = pw.Document();
    final dpi = project.ppi.toInt();
    for (int i = 0; i < bytesList.length; i++) {
      final image = pw.MemoryImage(Uint8List.fromList(bytesList[i]), dpi: dpi.toDouble());
      final pageData = project.pages[i];
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            pageData.widthMm * PdfPageFormat.mm,
            pageData.heightMm * PdfPageFormat.mm,
            marginAll: 0,
          ),
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }
    await File(path).writeAsBytes(await pdf.save());
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
    if (path.isEmpty) return false;
    final p = path.toLowerCase();
    return p.endsWith('.jpg') || 
           p.endsWith('.jpeg') || 
           p.endsWith('.png') || 
           p.endsWith('.webp') || 
           p.endsWith('.bmp') || 
           p.endsWith('.tiff') || 
           p.endsWith('.tif');
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

  void _handleAssetDrop(WidgetRef ref, Offset dropPos, LibraryAsset asset, AlbumPage currentPage) {
    if (asset.type == AssetType.element) {
      // Elements are just placed as decorative items
      final item = PhotoItem(
        path: asset.path,
        x: dropPos.dx - 50,
        y: dropPos.dy - 50,
        width: 100,
        height: 100,
        zIndex: 10, // Higher default for elements
      );
      ref.read(projectProvider.notifier).addPhotoToCurrentPage(item);
    } else {
      // Template logic: Frames with holes
      final double width = currentPage.widthMm;
      final double height = currentPage.heightMm;
      
      // 1. Add Template Frame (Top Level)
      final templateItem = PhotoItem(
        path: asset.path,
        x: 0, 
        y: 0,
        width: width,
        height: height,
        zIndex: 5, // Frame usually on top of photos
      );
      
      PhotoItem contentItem;
      bool isExisting = false;
      
      // Determine what goes inside the hole
      final firstPhoto = currentPage.photos.where((p) => p.path.isNotEmpty).toList();
      if (firstPhoto.isNotEmpty) {
        // Reuse first existing photo
        contentItem = firstPhoto.last.copyWith(); // Use the top-most photo
        isExisting = true;
      } else {
        // Create Placeholder
        contentItem = PhotoItem(path: "");
      }

      // Position content inside the detected hole
      if (asset.holeX != null) {
        // Add a small "bleeding" (1% extra) to ensure no gaps at edges
        final double bleedW = asset.holeW! * 0.01;
        final double bleedH = asset.holeH! * 0.01;
        
        contentItem = contentItem.copyWith(
          x: (asset.holeX! - bleedW) * width,
          y: (asset.holeY! - bleedH) * height,
          width: (asset.holeW! + 2 * bleedW) * width,
          height: (asset.holeH! + 2 * bleedH) * height,
          zIndex: 1, // Photos behind frame
          contentScale: 1.0, // Reset transformations for new hole
          contentX: 0.0,
          contentY: 0.0,
        );
      } else {
        // Default to center if no hole detected
        contentItem = contentItem.copyWith(
          x: width * 0.1,
          y: height * 0.1,
          width: width * 0.8,
          height: height * 0.8,
          zIndex: 1,
          contentScale: 1.0,
          contentX: 0.0,
          contentY: 0.0,
        );
      }

      if (isExisting) {
        // We modify the existing photo AND add the template
        // To keep it atomic, we can use updatePageLayout or manually combine
        final List<PhotoItem> newPhotos = currentPage.photos.map((p) {
          if (p.id == contentItem.id) return contentItem;
          return p;
        }).toList();
        
        if (!newPhotos.any((p) => p.path == asset.path)) {
           newPhotos.add(templateItem);
        }
        
        ref.read(projectProvider.notifier).updatePageLayout(newPhotos);
      } else {
        // Add both as new items
        ref.read(projectProvider.notifier).addPhotosToCurrentPage([contentItem, templateItem]);
      }
    }
  }
}
