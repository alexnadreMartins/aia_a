import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'widgets/full_screen_viewer.dart';
import 'widgets/browser_full_screen_viewer.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'widgets/flip_book_viewer.dart';
import '../logic/auto_diagramming_service.dart';
import 'widgets/diagram_progress_overlay.dart';
import '../logic/standard_template_initializer.dart';
import '../logic/rapid_diagramming_service.dart';
import 'dialogs/rapid_diagramming_dialog.dart';
import 'package:aia_album/ui/dialogs/time_shift_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'; // For PointerScrollEvent
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../models/project_model.dart';
import '../models/asset_model.dart';
import '../state/project_state.dart';
import '../state/asset_state.dart';
import '../logic/layout_engine.dart';
import '../logic/template_system.dart';
import '../logic/export_helper.dart';
import '../logic/image_loader.dart';
import 'editor/image_editor_view.dart';
import '../../logic/cache_provider.dart';
import 'widgets/photo_manipulator.dart';
import 'widgets/smart_image.dart';
import 'widgets/properties_panel.dart';
import 'widgets/resizable_pane.dart';
import 'widgets/dock_panel.dart';
import 'docks/browser_dock.dart';
import 'batch_editor/batch_editor_view.dart';
import '../logic/project_packager.dart';

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
  final FocusNode _canvasFocusNode = FocusNode();
  
  // Dock State
  double _leftPanelWidth = 300.0;
  double _rightPanelWidth = 300.0;
  double _bottomPanelHeight = 160.0;
  
  int _leftDockIndex = 0; // 0 = Fotos, 1 = Assets
  String? _lastSelectedBrowserPath;

  // Floating Dock State (ValueNotifiers for Performance)
  late ValueNotifier<bool> _isLeftDockFloating;
  late ValueNotifier<Offset> _leftDockPos;
  late ValueNotifier<bool> _showLeftSnap;

  late ValueNotifier<bool> _isRightDockFloating;
  late ValueNotifier<Offset> _rightDockPos;
  late ValueNotifier<bool> _showRightSnap;

  late ValueNotifier<bool> _isBottomDockFloating;
  late ValueNotifier<Offset> _bottomDockPos;
  late ValueNotifier<bool> _showBottomSnap;

 // 0 = Fotos, 1 = Assets

  @override
  void initState() {
    super.initState();
    // Dock State initialized
    
    // Dock State initialized
    _isLeftDockFloating = ValueNotifier(false);
    _leftDockPos = ValueNotifier(const Offset(50, 100)); // Default floating pos
    _showLeftSnap = ValueNotifier(false);

    _isRightDockFloating = ValueNotifier(false);
    _rightDockPos = ValueNotifier(const Offset(800, 100));
    _showRightSnap = ValueNotifier(false);

    _isBottomDockFloating = ValueNotifier(false);
    _bottomDockPos = ValueNotifier(const Offset(300, 500));
    _showBottomSnap = ValueNotifier(false);

    _transformationController.addListener(() {
      final zoom = _transformationController.value.getMaxScaleOnAxis();
      ref.read(projectProvider.notifier).setCanvasScale(zoom);
    });
    
    // Show new project dialog on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _initializeStandardTemplates(ref);
       _showNewProjectDialog(context, ref);
    });
  }

  Future<void> _initializeStandardTemplates(WidgetRef ref) async {
     final paths = await StandardTemplateInitializer.initializeStandardTemplates();
     // Always refresh so the collection appears, even if empty (so user can drop files there if needed, or see it exists)
     ref.read(assetProvider.notifier).refreshStandardCollection("Templates Padrão", paths);
  }

  // Scroll Controllers for Scrollbars
  final ScrollController _browserScrollCtrl = ScrollController();
  final ScrollController _galleryScrollCtrl = ScrollController();

  // Toolbar State
  Offset _toolbarPos = const Offset(100, 100);

  @override
  void dispose() {
    _thumbScrollController.dispose();
    _transformationController.dispose();
    
    _isLeftDockFloating.dispose();
    _leftDockPos.dispose();
    _showLeftSnap.dispose();
    _isRightDockFloating.dispose();
    _rightDockPos.dispose();
    _showRightSnap.dispose();
    _isBottomDockFloating.dispose();
    _bottomDockPos.dispose();
    _showBottomSnap.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index) {
     if (!_thumbScrollController.hasClients) return;
     
     // Estimated width per item + padding
     // Assuming average width ~ 180.0 (Width depends on aspect ratio, but auto-scroll is approximate)
     const double estimatedItemWidth = 180.0;
     
     final double targetOffset = index * estimatedItemWidth;
     final double currentOffset = _thumbScrollController.offset;
     final double viewport = _thumbScrollController.position.viewportDimension;
     
     // Scroll if out of view or close to edge
     if (targetOffset < currentOffset + 50 || targetOffset > currentOffset + viewport - estimatedItemWidth - 50) {
        // Center the target
        double finalOffset = targetOffset - (viewport / 2) + (estimatedItemWidth / 2);
        
        // Clamp to bounds (Max extent might be dynamic, but clamp helps safety)
        if (finalOffset < 0) finalOffset = 0;
        try {
           if (finalOffset > _thumbScrollController.position.maxScrollExtent) finalOffset = _thumbScrollController.position.maxScrollExtent;
        } catch (_) {}

        _thumbScrollController.animateTo(
          finalOffset, 
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
     }
  }

  // --- Shortcuts & Dialogs ---

  void _showNewProjectDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _NewProjectDialog(
        onCreate: (width, height, dpi) {
           // We can use DPI here if needed, e.g. store in project state
           // Currently initializeProject takes (w, h, count)
           // TODO: Add DPI to project model if required later
           ref.read(projectProvider.notifier).initializeProject(width, height, 1);
           Navigator.pop(context);
        },
      ),
    );
  }
  
  void _handleNewInstance() {
     try {
       Process.start(Platform.resolvedExecutable, [], mode: ProcessStartMode.detached);
     } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao abrir nova instância: $e")));
     }
  }

  void _handleDelete(WidgetRef ref, PhotoBookState state) {
     if (state.selectedPhotoId != null) {
       ref.read(projectProvider.notifier).removePhoto(state.selectedPhotoId!);
     } else if (state.project.pages.isNotEmpty) {
        if (state.multiSelectedPages.isNotEmpty) {
            ref.read(projectProvider.notifier).removeSelectedPages();
        } else {
            // Delete current page if valid
            ref.read(projectProvider.notifier).removePage(state.project.currentPageIndex);
        }
     }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectProvider);
    final isProcessing = state.isProcessing;

    // Auto-fit when Page Index changes
    ref.listen<int>(
      projectProvider.select((s) => s.project.currentPageIndex),
      (prev, next) {
        if (prev != next) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateCanvasView(context, ref, ref.read(projectProvider));
              _scrollToIndex(next);
           });
        }
      }
    );

    // Auto-fit on Project Load / Creation (Pages added)
    ref.listen<int>(
      projectProvider.select((s) => s.project.pages.length),
      (prev, next) {
        if (prev == 0 && next > 0) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateCanvasView(context, ref, ref.read(projectProvider));
           });
        }
      }
    );



    return CallbackShortcuts(
      bindings: {
         const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _handleSave(context, ref),
         const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => _handleSaveAs(context, ref),
         const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _showNewProjectDialog(context, ref),
         const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): _handleNewInstance,
         const SingleActivator(LogicalKeyboardKey.delete): () => ref.read(projectProvider.notifier).deleteSelectedPhoto(),
         const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => ref.read(projectProvider.notifier).copySelectedPhoto(),
         const SingleActivator(LogicalKeyboardKey.keyX, control: true): () => ref.read(projectProvider.notifier).cutSelectedPhoto(),
         const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => ref.read(projectProvider.notifier).pastePhoto(),
         
         // Navigation & Layout Shortcuts
         const SingleActivator(LogicalKeyboardKey.arrowRight): () => ref.read(projectProvider.notifier).nextPage(),
         const SingleActivator(LogicalKeyboardKey.arrowLeft): () => ref.read(projectProvider.notifier).previousPage(),
         const SingleActivator(LogicalKeyboardKey.arrowUp): () => ref.read(projectProvider.notifier).cycleAutoLayout(),
         const SingleActivator(LogicalKeyboardKey.arrowDown): () => ref.read(projectProvider.notifier).cycleAutoLayout(),

         // Advanced Editing Shortcuts
         const SingleActivator(LogicalKeyboardKey.comma, control: true): () => ref.read(projectProvider.notifier).sendToBack(ref.read(projectProvider).selectedPhotoId ?? ''),
         const SingleActivator(LogicalKeyboardKey.period, control: true): () => ref.read(projectProvider.notifier).bringToFront(ref.read(projectProvider).selectedPhotoId ?? ''),
         
         const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => ref.read(projectProvider.notifier).undo(),
         const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => ref.read(projectProvider.notifier).redo(),
         
         const SingleActivator(LogicalKeyboardKey.enter, shift: true): () => ref.read(projectProvider.notifier).toggleEditMode(),
         const SingleActivator(LogicalKeyboardKey.keyE, shift: true): () => _openSelectedInEditor(context, ref), // Open Editor
         
         // Pan Content (Ctrl + Arrow)
         const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () => ref.read(projectProvider.notifier).panSelectedPhotoContent(0.1, 0),
         const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () => ref.read(projectProvider.notifier).panSelectedPhotoContent(-0.1, 0),
         const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () => ref.read(projectProvider.notifier).panSelectedPhotoContent(0, -0.1),
         const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () => ref.read(projectProvider.notifier).panSelectedPhotoContent(0, 0.1),

         // Select Adjacent (Ctrl + Shift + Arrow)
         const SingleActivator(LogicalKeyboardKey.arrowRight, control: true, shift: true): () => ref.read(projectProvider.notifier).selectAdjacentPhoto('right'),
         const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true, shift: true): () => ref.read(projectProvider.notifier).selectAdjacentPhoto('left'),
         const SingleActivator(LogicalKeyboardKey.arrowUp, control: true, shift: true): () => ref.read(projectProvider.notifier).selectAdjacentPhoto('up'),
         const SingleActivator(LogicalKeyboardKey.arrowDown, control: true, shift: true): () => ref.read(projectProvider.notifier).selectAdjacentPhoto('down'),
      },
      child: Focus(
        autofocus: true, 
        child: Scaffold(
          backgroundColor: const Color(0xFF1E1E1E),
          body: Stack(
             children: [
               Column(
                 children: [
                   // Top Bar
                   Container(
                     height: 48,
                     decoration: const BoxDecoration(
                       gradient: LinearGradient(
                         colors: [Color(0xFF2C2C2C), Color(0xFF1E1E1E)],
                         begin: Alignment.topCenter,
                         end: Alignment.bottomCenter,
                       ),
                       border: Border(bottom: BorderSide(color: Color(0xFF383838))),
                     ),
                     child: Consumer(builder: (context, ref, _) {
                        final canUndo = ref.watch(projectProvider.select((s) => s.canUndo));
                        final canRedo = ref.watch(projectProvider.select((s) => s.canRedo));
                        return _buildToolbar(context, ref, canUndo, canRedo);
                     }),
                   ),
                   
                   Expanded(
                     child: Row(
                       children: [
                          // Left Dock (Resizable)
                          ValueListenableBuilder<bool>(
                            valueListenable: _isLeftDockFloating,
                            builder: (context, isFloating, child) {
                               if (isFloating) return const SizedBox.shrink();
                               return ResizablePane(
                                 width: _leftPanelWidth,
                                 edge: ResizeEdge.right,
                                 onResize: (delta) => setState(() {
                                    _leftPanelWidth = (_leftPanelWidth + delta).clamp(200.0, 600.0);
                                 }),
                                 child: DockPanel(
                                    title: "Navegador",
                                    tabs: const ["Fotos", "Assets"],
                                    selectedTabIndex: _leftDockIndex,
                                    onTabSelected: (i) => setState(() => _leftDockIndex = i),
                                    onDetach: () => _isLeftDockFloating.value = true,
                                    child: _leftDockIndex == 0 ? const BrowserDock() : _buildAssetsDock(ref),
                                 ),
                               );
                            }
                          ),
                         
                         // Center Canvas
                         Expanded(
                           child: Container(
                             color: const Color(0xFF000000),
                             child: Center(
                               child: _buildCanvas(context, ref, state),
                             ),
                           ),
                         ),
                         
                         // Right Dock (Resizable)
                          ValueListenableBuilder<bool>(
                            valueListenable: _isRightDockFloating,
                            builder: (context, isFloating, child) {
                               if (isFloating) return const SizedBox.shrink();
                               return ResizablePane(
                               width: _rightPanelWidth,
                               edge: ResizeEdge.left,
                               onResize: (delta) => setState(() {
                                  _rightPanelWidth = (_rightPanelWidth + delta).clamp(250.0, 500.0);
                               }),
                               child: DockPanel(
                                  title: "Propriedades",
                                  tabs: const [], // Single Tab for now
                                  onTabSelected: (_) {},
                                  selectedTabIndex: 0,
                                  onDetach: () => _isRightDockFloating.value = true,
                                  child: _buildRightDock(context, ref, state),
                               ),
                             );
                            }
                          ),
                       ],
                     ),
                   ),
                   
                   // Bottom Dock (Timeline) - Resizable Top Edge
                    ValueListenableBuilder<bool>(
                        valueListenable: _isBottomDockFloating,
                        builder: (context, isFloating, child) {
                           if (isFloating) return const SizedBox.shrink();
                           return ResizablePane(
                              width: _bottomPanelHeight, // reused as height
                              edge: ResizeEdge.top,
                              onResize: (delta) => setState(() {
                                 // Dragging UP (negative Y) -> Positive Delta (implemented in ResizablePane logic for Top Edge: -dy)
                                 _bottomPanelHeight = (_bottomPanelHeight + delta).clamp(100.0, 500.0);
                              }),
                              child: DockPanel(
                                 title: "Linha do Tempo  •  ${state.project.pages.length} Páginas",
                                 onTabSelected: (_) {},
                                 onDetach: () => _isBottomDockFloating.value = true,
                                 child: _buildThumbnails(ref, state),
                              ),
                           );
                        }
                    ),
                 ],
               ),
               
               // Touch Controls Overlay (Draggable)
               Positioned(
                 left: _toolbarPos.dx,
                 top: _toolbarPos.dy,
                 child: _buildTouchControls(context, ref, state),
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
                 
                  const DiagramProgressOverlay(),

               // --- Floating Docks (Optimized with ValueListenableBuilder) ---

               // Left Floating Dock
               ValueListenableBuilder<bool>(
                  valueListenable: _isLeftDockFloating,
                  builder: (ctx, isFloating, _) {
                     if (!isFloating) return const SizedBox.shrink();
                     return ValueListenableBuilder<Offset>(
                        valueListenable: _leftDockPos,
                        builder: (ctx, pos, _) {
                           return Positioned(
                              left: pos.dx, top: pos.dy,
                              child: SizedBox(
                                 width: 320, height: 600,
                                 child: DockPanel(
                                     title: "Navegador (Flutuante)",
                                     tabs: const ["Fotos", "Assets"],
                                     selectedTabIndex: _leftDockIndex,
                                     onTabSelected: (i) => setState(() => _leftDockIndex = i),
                                     onDetach: () {}, // Already detached
                                     onDragStart: (_) {},
                                     onDragUpdate: (d) {
                                         _leftDockPos.value += d.delta;
                                         // Check Snap
                                         _showLeftSnap.value = _leftDockPos.value.dx < 50;
                                     },
                                     onDragEnd: (_) {
                                         if (_showLeftSnap.value) {
                                            _isLeftDockFloating.value = false;
                                            _showLeftSnap.value = false;
                                            _leftDockPos.value = const Offset(50, 100); // Reset
                                         }
                                     },
                                     child: _leftDockIndex == 0 ? const BrowserDock() : _buildAssetsDock(ref),
                                 ),
                              ),
                           );
                        }
                     );
                  }
               ),

               // Right Floating Dock
               ValueListenableBuilder<bool>(
                  valueListenable: _isRightDockFloating,
                  builder: (ctx, isFloating, _) {
                     if (!isFloating) return const SizedBox.shrink();
                     return ValueListenableBuilder<Offset>(
                        valueListenable: _rightDockPos,
                        builder: (ctx, pos, _) {
                           return Positioned(
                              left: pos.dx, top: pos.dy,
                              child: SizedBox(
                                 width: 320, height: 600,
                                 child: DockPanel(
                                     title: "Propriedades (Flutuante)",
                                     onTabSelected: (_) {},
                                     onDetach: () {},
                                     onDragStart: (_) {},
                                     onDragUpdate: (d) {
                                         _rightDockPos.value += d.delta;
                                         final screenW = MediaQuery.of(context).size.width;
                                          _showRightSnap.value = _rightDockPos.value.dx > screenW - 350;
                                     },
                                     onDragEnd: (_) {
                                         if (_showRightSnap.value) {
                                            _isRightDockFloating.value = false;
                                            _showRightSnap.value = false;
                                            _rightDockPos.value = const Offset(800, 100);
                                         }
                                     },
                                     child: _buildRightDock(context, ref, state),
                                 ),
                              ),
                           );
                        }
                     );
                  }
               ),

               // Bottom Floating Dock
               ValueListenableBuilder<bool>(
                  valueListenable: _isBottomDockFloating,
                  builder: (ctx, isFloating, _) {
                     if (!isFloating) return const SizedBox.shrink();
                     return ValueListenableBuilder<Offset>(
                        valueListenable: _bottomDockPos,
                        builder: (ctx, pos, _) {
                           return Positioned(
                              left: pos.dx, top: pos.dy,
                              child: SizedBox(
                                 width: 800, height: 250,
                                 child: DockPanel(
                                     title: "Linha do Tempo (Flutuante)",
                                     onTabSelected: (_) {},
                                      onDetach: () {},
                                     onDragStart: (_) {},
                                     onDragUpdate: (d) {
                                         _bottomDockPos.value += d.delta;
                                         final screenH = MediaQuery.of(context).size.height;
                                         _showBottomSnap.value = _bottomDockPos.value.dy > screenH - 300;
                                     },
                                     onDragEnd: (_) {
                                         if (_showBottomSnap.value) {
                                            _isBottomDockFloating.value = false;
                                            _showBottomSnap.value = false;
                                            _bottomDockPos.value = const Offset(300, 500);
                                         }
                                     },
                                     child: _buildThumbnails(ref, state),
                                 ),
                              ),
                           );
                        }
                     );
                  }
               ),

                // --- Snap Highlights ---
                ValueListenableBuilder<bool>(
                   valueListenable: _showLeftSnap,
                   builder: (ctx, show, _) => show ? Positioned(
                      left: 0, top: 0, bottom: 0, width: 50,
                      child: Container(color: Colors.blueAccent.withOpacity(0.3))
                   ) : const SizedBox.shrink(),
                ),
                ValueListenableBuilder<bool>(
                   valueListenable: _showRightSnap,
                   builder: (ctx, show, _) => show ? Positioned(
                      right: 0, top: 0, bottom: 0, width: 50,
                      child: Container(color: Colors.blueAccent.withOpacity(0.3))
                   ) : const SizedBox.shrink(),
                ),
                ValueListenableBuilder<bool>(
                   valueListenable: _showBottomSnap,
                   builder: (ctx, show, _) => show ? Positioned(
                      left: 0, right: 0, bottom: 0, height: 50,
                      child: Container(color: Colors.blueAccent.withOpacity(0.3))
                   ) : const SizedBox.shrink(),
                ),
             ],
          ),
        ),
      ),
    );
  }



  // --- Rapid Diagramming ---

  void _showRapidDiagrammingDialog(BuildContext context) async {
      final result = await showDialog(
         context: context,
         builder: (ctx) => RapidDiagrammingDialog(onStart: (m, b) {}) 
      );
      
      if (result != null && result is Map) {
         final mode = result['mode'];
         final batchPath = result['batchPath'];
         final templatePath = result['templatePath'];
         final useAutoSelect = result['useAutoSelect'] ?? true;
         final contractNumber = result['contractNumber'];
         
         if (mode == 'individual') {
            _startRapidDiagramming(context, templatePath: templatePath, useAutoSelect: useAutoSelect, contractNumber: contractNumber);
         } else if (mode == 'batch' && batchPath != null) {
            _runBatchRapidDiagramming(batchPath, templatePath: templatePath, useAutoSelect: useAutoSelect, contractNumber: contractNumber);
         }
      }
  }
  
  void _startRapidDiagramming(BuildContext context, {String? templatePath, bool useAutoSelect = true, String? contractNumber}) async {
     final state = ref.read(projectProvider);
     if (state.project?.allImagePaths.isEmpty ?? true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("O projeto atual não possui fotos!")));
        return;
     }
     
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Iniciando Diagramação Rápida...")));
     
     try {
        final newProject = await RapidDiagrammingService.generateProject(
           currentProject: state.project!, 
           allPhotoPaths: state.project!.allImagePaths, 
           projectName: state.project!.name,
           customTemplateDir: templatePath,
           useAutoSelect: useAutoSelect,
           contractNumber: contractNumber
        );
        
        ref.read(projectProvider.notifier).setProject(newProject);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Diagramação Concluída!")));
        
     } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
     }
  }

  Future<void> _runBatchRapidDiagramming(String rootPath, {String? templatePath, bool useAutoSelect = true, String? contractNumber}) async {
      final state = ref.read(projectProvider);
      final modelProject = state.project;
      
      // Inherit dimensions from current open project
      double targetW = 300.0;
      double targetH = 300.0;
      if (modelProject.pages.isNotEmpty) {
         targetW = modelProject.pages[0].widthMm;
         targetH = modelProject.pages[0].heightMm;
      }

      // 1. Scan Subfolders
      final rootDir = Directory(rootPath);
      // Sort alphabetic for consistency
      final entries = rootDir.listSync().whereType<Directory>().toList()..sort((a,b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      
      if (entries.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nenhuma subpasta encontrada!")));
          return;
      }
      
      // Progress State
      ValueNotifier<int> processedCount = ValueNotifier(0);
      ValueNotifier<String> currentStatus = ValueNotifier("Preparando...");
      ValueNotifier<String> etaStatus = ValueNotifier("--:--");
      
      // Show Progress Dialog
      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false, // Prevent closing
          child: AlertDialog(
           backgroundColor: const Color(0xFF2C2C2C),
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
           content: SizedBox(
             height: 220, // Increased height for ETA
             width: 300,
             child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const SizedBox(height: 10),
                   const CircularProgressIndicator(color: Colors.amberAccent),
                   const SizedBox(height: 16),
                   ValueListenableBuilder<String>(
                      valueListenable: currentStatus,
                      builder: (c, val, _) => Text(
                         val, 
                         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500), 
                         textAlign: TextAlign.center,
                         maxLines: 2,
                         overflow: TextOverflow.ellipsis,
                      )
                   ),
                   const SizedBox(height: 8),
                   ValueListenableBuilder<int>(
                      valueListenable: processedCount,
                      builder: (c, val, _) => LinearProgressIndicator(
                         value: entries.isNotEmpty ? val / entries.length : 0,
                         backgroundColor: Colors.white10,
                         valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      )
                   ),
                   const SizedBox(height: 8),
                   Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         ValueListenableBuilder<int>(
                            valueListenable: processedCount,
                            builder: (c, val, _) => Text(
                              "$val / ${entries.length}", 
                              style: const TextStyle(color: Colors.white54, fontSize: 12)
                            )
                         ),
                         ValueListenableBuilder<String>(
                            valueListenable: etaStatus,
                            builder: (c, val, _) => Text(
                              "Previsão: $val", 
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)
                            )
                         ),
                      ],
                   )
                ],
             ),
           ),
        ),
       )
      );
      
      int successCount = 0;
      final startTime = DateTime.now();
      
      for (int i=0; i<entries.length; i++) {
           final dir = entries[i];
           final studentName = p.basename(dir.path);
           
           // Update Status
           currentStatus.value = "Processando: $studentName";
           await Future.delayed(const Duration(milliseconds: 50)); // Allow UI paint
           
           // Scan photos
           final photos = dir.listSync(recursive: true)
             .whereType<File>()
             .where((f) => ['.jpg', '.jpeg', '.png'].contains(p.extension(f.path).toLowerCase()))
             .map((f) => f.path)
             .toList();
             
           if (photos.isEmpty) {
              processedCount.value = i + 1;
              continue;
           }
           
           // Generate Project
           try {
              // Create seed project with CORRECT DIMENSIONS
              // We add a dummy page so generateProject picks up the size
              Project base = Project(
                  id: Uuid().v4(),
                  name: studentName,
                  contractNumber: studentName,
                  pages: [
                     AlbumPage(id: Uuid().v4(), photos: [], widthMm: targetW, heightMm: targetH)
                  ],
                  allImagePaths: photos
              );
              
              final newProject = await RapidDiagrammingService.generateProject(
                 currentProject: base,
                 allPhotoPaths: photos,
                 projectName: studentName,
                 customTemplateDir: templatePath,
                 useAutoSelect: useAutoSelect,
                 contractNumber: contractNumber
              );
              
              // Save as packaged .alem
              final saveFile = p.join(dir.path, "$studentName.alem");
              
              // Use ProjectPackager to create Smart Preview
              currentStatus.value = "Empacotando: $studentName";
              
              await ProjectPackager.packProject(newProject, saveFile, onProgress: (cur, tot, status) {
                  // Only update text, don't flood progress bar to avoid jitter
                  currentStatus.value = "Empacotando [$studentName]: $cur/$tot";
              });
                
              successCount++;
               
           } catch (e) {
              debugPrint("Error processing $studentName: $e");
           }
           
           processedCount.value = i + 1;
           
           // Calculate ETA
           if (i < entries.length - 1) { // If not last
              final now = DateTime.now();
              final elapsed = now.difference(startTime);
              final avgMs = elapsed.inMilliseconds / (i + 1);
              final remaining = entries.length - (i + 1);
              final etaMs = avgMs * remaining;
              
              final etaDuration = Duration(milliseconds: etaMs.toInt());
              final min = etaDuration.inMinutes;
              final sec = etaDuration.inSeconds % 60;
              etaStatus.value = "${min}m ${sec}s";
           } else {
              etaStatus.value = "Concluído";
           }
      }
      
      final endTime = DateTime.now();
      final totalDuration = endTime.difference(startTime);
      final avgMillis = (entries.isNotEmpty) ? totalDuration.inMilliseconds ~/ entries.length : 0;
      final avgDuration = Duration(milliseconds: avgMillis);

      String _printDuration(Duration d) {
         final m = d.inMinutes;
         final s = d.inSeconds % 60;
         return "${m}m ${s}s";
      }

      if (mounted) {
         Navigator.pop(context); // Close Progress Dialog
         
         showDialog(
           context: context,
           builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF2C2C2C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text("Relatório de Processamento", style: TextStyle(color: Colors.white)),
              content: Column(
                 mainAxisSize: MainAxisSize.min,
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Text("Total Processado: ${entries.length} pastas", style: const TextStyle(color: Colors.white70)),
                    Text("Sucessos: $successCount", style: const TextStyle(color: Colors.greenAccent)),
                    const Divider(color: Colors.grey),
                    const SizedBox(height: 8),
                    Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                          const Text("Tempo Total:", style: TextStyle(color: Colors.white)),
                          Text(_printDuration(totalDuration), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                       ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                       children: [
                          const Text("Média por Projeto:", style: TextStyle(color: Colors.white)),
                          Text(_printDuration(avgDuration), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                       ],
                    ),
                 ],
              ),
              actions: [
                 TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Fechar", style: TextStyle(color: Colors.lightBlueAccent)),
                 )
              ],
           )
         );
      }
  }

  void _handlePackProject(BuildContext context, WidgetRef ref) async {
       final state = ref.read(projectProvider);
       if (state.project.pages.isEmpty && state.project.allImagePaths.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Projeto vazio!")));
          return;
       }
       
       String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Salvar Pacote Smart Preview',
          fileName: '${state.project.name}.alem',
          allowedExtensions: ['alem'],
          type: FileType.custom,
       );
       
       if (outputFile == null) return;
       if (!outputFile.toLowerCase().endsWith('.alem')) {
          outputFile += '.alem';
       }
       
       // Show Progress
       ValueNotifier<double> progress = ValueNotifier(0);
       ValueNotifier<String> status = ValueNotifier("Iniciando...");
       
       showDialog(
         context: context, 
         barrierDismissible: false,
         builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2C),
            content: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                  const CircularProgressIndicator(color: Colors.amberAccent),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<String>(
                     valueListenable: status, 
                     builder: (c, val, _) => Text(val, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<double>(
                     valueListenable: progress,
                     builder: (c, val, _) => LinearProgressIndicator(value: val, backgroundColor: Colors.white10),
                  )
               ],
            ),
         )
       );
       
       try {
          await ProjectPackager.packProject(state.project, outputFile, onProgress: (cur, tot, msg) {
              if (tot > 0) progress.value = cur / tot;
              status.value = msg;
          });
          
          if (mounted) {
             Navigator.pop(context);
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Projeto empacotado com sucesso em $outputFile")));
          }
       } catch (e) {
          if (mounted) {
             Navigator.pop(context);
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao empacotar: $e")));
          }
       }
  }

  void _showBatchEditor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => BatchEditorView())
    );
  }

  Widget _buildToolbar(BuildContext context, WidgetRef ref, bool canUndo, bool canRedo) {
    return Container(
      height: 50,
      decoration: const BoxDecoration(
        color: Color(0xFF000000), 
        border: Border(bottom: BorderSide(color: Color(0xFF262626))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 0), // MenuBar has its own padding
      child: Row( // Use a Row to combine MenuBar and IconButtons
        children: [
          MenuBar(
              style: MenuStyle(
                 backgroundColor: MaterialStateProperty.all(Colors.transparent),
                 elevation: MaterialStateProperty.all(0),
                 padding: MaterialStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)),
              ),
              children: [
                 SubmenuButton(
                   menuChildren: [
                     MenuItemButton(
                        onPressed: () => _showNewProjectDialog(context, ref),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: true),
                        child: const MenuAcceleratorLabel("&Novo Projeto..."),
                     ),
                     MenuItemButton(
                        onPressed: () => _handleLoad(context, ref), // Corrected method name
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true),
                        child: const MenuAcceleratorLabel("&Abrir..."),
                     ),
                     MenuItemButton(
                        onPressed: () => _handleSave(context, ref),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
                        child: const MenuAcceleratorLabel("&Salvar"),
                     ),
                     MenuItemButton(
                        onPressed: () => _handleSaveAs(context, ref),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
                        child: const MenuAcceleratorLabel("Sa&lvar Como..."),
                     ),
                     const Divider(),
                     MenuItemButton(
                        onPressed: () => _handlePackProject(context, ref),
                        child: const MenuAcceleratorLabel("&Empacotar Projeto (Smart Preview)..."),
                     ),
                     const Divider(),
                     SubmenuButton( // Nested submenu for Exports
                        menuChildren: [
                           MenuItemButton(
                              onPressed: () => _handleExportJpg(context, ref),
                              child: const MenuAcceleratorLabel("&JPG (Todas as Páginas)"),
                           ),
                           MenuItemButton(
                              onPressed: () => _handleExportPdf(context, ref),
                              child: const MenuAcceleratorLabel("&PDF (Álbum Completo)"),
                           ),
                        ],
                        child: const MenuAcceleratorLabel("&Exportar"),
                     ),
                     const Divider(),
                     MenuItemButton(
                        onPressed: () => _handleNewInstance(),
                        shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true),
                        child: const MenuAcceleratorLabel("Nova &Janela"),
                     ),
                     MenuItemButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: const MenuAcceleratorLabel("Sai&r"),
                     ),
                   ],
                   child: const MenuAcceleratorLabel("&Arquivo"),
                 ),
                 // We can accept other menus here (Edit, View, etc.)
              ],
          ),
          // The rest of the toolbar buttons
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
             icon: const Icon(Icons.vertical_split, color: Colors.indigoAccent), 
             tooltip: "Curingar Verticais (Agrupar Pares)",
             onPressed: () {
                ref.read(projectProvider.notifier).groupConsecutiveVerticals();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fotos verticais agrupadas!")));
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
                print("DEBUG: Smart Flow Button Pressed. Selected: ${state.selectedBrowserPaths.length}");
                ref.read(projectProvider.notifier).applyAutoLayout(state.selectedBrowserPaths.toList());
             }
          ),
          const VerticalDivider(indent: 8, endIndent: 8, color: Colors.white24),
          PopupMenuButton<String>(
            icon: const Icon(Icons.construction, color: Colors.white70),
            tooltip: "Ferramentas",
            onSelected: (value) async {
                  if (value == 'batch_export') {
                     _showBatchExportDialog(context);
                  } else if (value == 'batch_editor') {
                     _showBatchEditor(context);
                  } else if (value == 'auto_diagram') {
                  _showAutoDiagrammingDialog(context);
               } else if (value == 'rapid_diagram') {
                  _showRapidDiagrammingDialog(context);
               } else if (value == 'generate_labels_endpoints') {
                  if (await _promptAndSetContractNumber(context, ref)) {
                      ref.read(projectProvider.notifier).generateLabels(allPages: false);
                  }
               } else if (value == 'generate_labels_all') {
                  if (await _promptAndSetContractNumber(context, ref)) {
                      ref.read(projectProvider.notifier).generateLabels(allPages: true);
                  }
               } else if (value == 'generate_labels_kit') {
                  if (await _promptAndSetContractNumber(context, ref)) {
                      ref.read(projectProvider.notifier).generateKitLabels();
                  }
               } else if (value == 'sort_pages') {
                  ref.read(projectProvider.notifier).sortPages();
               }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
               const PopupMenuItem<String>(
                value: 'batch_export',
                child: Row(
                   children: [
                      Icon(Icons.drive_folder_upload, color: Colors.black54),
                      SizedBox(width: 8),
                      Flexible(child: Text('Exportação em Lote (Auto)')),
                   ],
                ),
               ),
               const PopupMenuItem<String>(
                value: 'batch_editor',
                child: Row(
                   children: [
                      Icon(Icons.grid_view, color: Colors.pinkAccent),
                      SizedBox(width: 8),
                      Flexible(child: Text('Editor em Lote (40k+)')),
                   ],
                ),
               ),
               const PopupMenuItem<String>(
                value: 'auto_diagram',
                child: Row(
                   children: [
                      Icon(Icons.auto_stories, color: Colors.deepPurpleAccent),
                      SizedBox(width: 8),
                      Flexible(child: Text('Diagramação Automática (Smart Flow)')),
                   ],
                ),
               ),
               const PopupMenuItem<String>(
                value: 'rapid_diagram',
                child: Row(
                   children: [
                      Icon(Icons.flash_on, color: Colors.amberAccent),
                      SizedBox(width: 8),
                      Flexible(child: Text('Diagramação Rápida (Prefixos e Lote)')),
                   ],
                ),
               ),
               const PopupMenuDivider(),
               const PopupMenuItem<String>(
                 value: 'generate_labels_endpoints',
                 child: Row(
                   children: [
                     Icon(Icons.label_outline, color: Colors.blueGrey),
                     SizedBox(width: 8),
                     Flexible(child: Text('Gerar Etiquetas (Primeira/Última)')),
                   ],
                 ),
               ),
               const PopupMenuItem<String>(
                 value: 'sort_pages',
                 child: Row(
                   children: [
                     Icon(Icons.sort, color: Colors.orange),
                     SizedBox(width: 8),
                     Text('Ordenar Páginas (Dia > Câmera)'),
                   ],
                 ),
               ),
               const PopupMenuItem<String>(
                 value: 'generate_labels_all',
                 child: Row(
                   children: [
                     Icon(Icons.label, color: Colors.amber),
                     SizedBox(width: 8),
                     Text('Gerar Etiquetas (Todas)'),
                   ],
                 ),
               ),
               const PopupMenuItem<String>(
                 value: 'generate_labels_kit',
                 child: Row(
                   children: [
                     Icon(Icons.assignment_ind, color: Colors.green),
                     SizedBox(width: 8),
                     Text('Gerar Etiquetas de Kit'),
                   ],
                 ),
               ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
             icon: const Icon(Icons.menu_book, color: Colors.white70),
             tooltip: "Visualização Flip Book (ESC para sair)",
             onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const FlipBookViewer())
                );
             },
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





// ... existing code ...

  Widget _buildAssetLibrary(WidgetRef ref) {
    final assetState = ref.watch(assetProvider);
    if (assetState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Keyboard Listener for Gallery Shortcuts
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => 
            ref.read(assetProvider.notifier).selectAll(),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => 
            ref.read(assetProvider.notifier).deselectAll(),
      },
      child: Focus(
        autofocus: true, 
        child: Column(
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
        ),
      ),
    );
  }

  Widget _buildBackgroundLibrary(WidgetRef ref) {
    // Similar to AssetLibrary but focuses on 'Background' type assets
    // Use a specific collection named "Fundos" or create it if missing
    final assetState = ref.watch(assetProvider);
    if (assetState.isLoading) return const Center(child: CircularProgressIndicator());

    // Find or Create "Fundos" collection
    // For now we just filter view to show collections. Ideally we have a single "Fundos" collection.
    // Let's filter collections that contain "fundo" in name, or just show specific one?
    // User wants "Import as I import templates". 
    // So let's show all collections but maybe default to "Fundos".
    
    // Better: Show a dedicated view for "Fundos".
    // If "Fundos" collection exists, show it expanded. If not, button to create.
    
    final fundosCollection = assetState.collections.firstWhere(
       (c) => c.name.toLowerCase() == "fundos", 
       orElse: () => AssetCollection(id: "", name: "") // Empty marker
    );
    
    final hasFundos = fundosCollection.id.isNotEmpty;

    return Column(
      children: [
         if (!hasFundos)
           Padding(
             padding: const EdgeInsets.all(8.0),
             child: ElevatedButton.icon(
               style: ElevatedButton.styleFrom(
                 backgroundColor: const Color(0xFF1A1A1A),
                 foregroundColor: Colors.white,
               ),
               onPressed: () {
                  ref.read(assetProvider.notifier).addCollection("Fundos");
               },
               icon: const Icon(Icons.add),
               label: const Text("Criar Coleção 'Fundos'"),
             ),
           )
         else ...[
             // Show Import Button specifically for Fundos
             Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton.icon(
                   style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 36),
                   ),
                   onPressed: () => _importAssetsToCollection(ref, fundosCollection.id, type: AssetType.background), // FORCE TYPE BACKGROUND
                   icon: const Icon(Icons.add_photo_alternate),
                   label: const Text("Importar Fundos"),
                ),
             ),
             Expanded(
               child: SingleChildScrollView(
                 child: _buildAssetCollection(context, ref, fundosCollection),
               ),
             ),
         ]
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
    final assetState = ref.watch(assetProvider);
    final isSelected = assetState.selectedAssetIds.contains(asset.id);

    return Draggable<LibraryAsset>(
      data: asset,
      feedback: Opacity(
        opacity: 0.7,
        child: SizedBox(
          width: 60, height: 60,
          child: SmartImage(path: asset.path, fit: BoxFit.contain),
        ),
      ),
      child: GestureDetector(
        onTap: () {
          final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed
              .contains(LogicalKeyboardKey.shiftLeft) ||
              HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
          
          if (isShiftPressed && assetState.selectedAssetIds.isNotEmpty) {
             // Range logic: simplistic for now, ideally needs ordered list info
             // Using last selected roughly if available, or just keeping shift behavior simple
             ref.read(assetProvider.notifier).toggleSelection(asset.id);
          } else {
             ref.read(assetProvider.notifier).toggleSelection(asset.id);
          }
        },
        onDoubleTap: () {
          // Flatten all assets to pass to viewer
          final allAssets = assetState.collections.expand((c) => c.assets).toList();
          final index = allAssets.indexWhere((a) => a.id == asset.id);
          if (index != -1) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FullScreenViewer(assets: allAssets, initialIndex: index)),
            );
          }
        },
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: isSelected ? Colors.deepPurple.withOpacity(0.3) : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected 
                      ? Colors.deepPurpleAccent 
                      : (asset.type == AssetType.template ? Colors.amberAccent.withOpacity(0.3) : Colors.transparent),
                  width: isSelected ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.all(4),
              child: Column(
                children: [
                  Expanded(child: SmartImage(path: asset.path, fit: BoxFit.contain)),
                  const SizedBox(height: 2),
                  Text(
                    asset.type == AssetType.template ? "Template" : "Elemento",
                    style: const TextStyle(fontSize: 7, color: Colors.white38),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Positioned(
                bottom: 4, right: 4,
                child: Icon(Icons.check_circle, size: 14, color: Colors.deepPurpleAccent),
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

  Future<void> _importAssetsToCollection(WidgetRef ref, String collectionId, {AssetType? type}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (result == null) return;

    final paths = result.paths.whereType<String>().toList();

    if (type != null) {
       await ref.read(assetProvider.notifier).addAssetsToCollection(collectionId, paths, type);
       return;
    }
    
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
             ElevatedButton(
               style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800]),
               onPressed: () {
                 ref.read(assetProvider.notifier).addAssetsToCollection(collectionId, paths, AssetType.background);
                 Navigator.pop(ctx);
               },
               child: const Text("Fundos"),
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

  Widget _buildLeftDock(WidgetRef ref) {
    return _buildFileBrowser(ref);
  }

  Widget _buildAssetsDock(WidgetRef ref) {
     final projectState = ref.watch(projectProvider);
     // If index is 1 (Assets) or 2 (Backgrounds) - wait, DockPanel handles tabs differently
     // "Fotos", "Assets" -> 0, 1.
     // Old logic had "Fundos" as 2.
     // For now, let's just return AssetLibrary.
    return _buildAssetLibrary(ref);
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
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        splashRadius: 20,
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
                  child: Scrollbar(
                    controller: _galleryScrollCtrl,
                    thumbVisibility: true,
                    thickness: 12,
                    radius: const Radius.circular(6),
                    interactive: true,
                    child: GridView.builder(
                      controller: _galleryScrollCtrl,
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
                              child: SmartImage(path: path, fit: BoxFit.cover),
                            ),
                          ),
                        ),
                        child: GestureDetector(
                          onSecondaryTapDown: (details) {
                               _showBrowserContextMenu(context, ref, path, details.globalPosition);
                          },
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
                                    child: SmartImage(
                                      path: path,
                                      fit: BoxFit.cover,
                                      // Note: complex blending logic left out to simplify, or can be passed if needed
                                      // For now, simpler SmartImage usage
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
                  ), // Scrollbar
                )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildTouchControls(BuildContext context, WidgetRef ref, PhotoBookState state) {
      if (state.project.pages.isEmpty) return const SizedBox.shrink();

      final hasSelection = state.selectedPhotoId != null;
      final copyAvailable = hasSelection;
      final pasteAvailable = state.clipboardPhoto != null;

      return GestureDetector(
         onPanUpdate: (details) {
            setState(() {
               _toolbarPos += details.delta;
            });
         },
         child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
               color: const Color(0xFF2C2C2C).withOpacity(0.9),
               borderRadius: BorderRadius.circular(30),
               boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))
               ],
               border: Border.all(color: Colors.white10),
            ),
            child: Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                   // Precision Mode
                   IconButton(
                      icon: Icon(
                         Icons.gps_fixed, // Target / Precision
                         color: state.isPrecisionMode ? Colors.orangeAccent : Colors.white70
                      ),
                      tooltip: "Modo Precisão (Movimento Lento)",
                      onPressed: () => ref.read(projectProvider.notifier).togglePrecisionMode(),
                   ),
                   const SizedBox(width: 8),
                   Container(width: 1, height: 24, color: Colors.white24),
                   const SizedBox(width: 8),

                   // Multi-Select Toggle
                   IconButton(
                      icon: Icon(
                         state.isTouchMultiSelectMode ? Icons.check_circle : Icons.check_circle_outline,
                         color: state.isTouchMultiSelectMode ? Colors.greenAccent : Colors.white70
                      ),
                      tooltip: "Modo Seleção (Toque Múltiplo)",
                      onPressed: () => ref.read(projectProvider.notifier).toggleTouchMultiSelect(),
                   ),
                   
                   // Paste (Always visible if available, or if nothing selected)
                   if (!hasSelection || pasteAvailable) ...[
                       const SizedBox(width: 8),
                       IconButton(
                          icon: const Icon(Icons.paste, color: Colors.white70),
                          tooltip: "Colar",
                          onPressed: pasteAvailable ? () => ref.read(projectProvider.notifier).pastePhoto() : null, // Disabled if empty
                       ),
                   ],

                   // Context Aware Tools (Only if Selection)
                   if (hasSelection) ...[
                       const SizedBox(width: 8),
                       Container(width: 1, height: 24, color: Colors.white24),
                       const SizedBox(width: 8),
                       
                       // Copy
                       IconButton(
                          icon: const Icon(Icons.copy, color: Colors.white70),
                          tooltip: "Copiar",
                          onPressed: () => ref.read(projectProvider.notifier).copySelectedPhoto(),
                       ),
                       
                       // Front / Back
                       IconButton(
                          icon: const Icon(Icons.flip_to_front, color: Colors.white70),
                          tooltip: "Trazer p/ Frente",
                          onPressed: () => ref.read(projectProvider.notifier).bringToFront(state.selectedPhotoId!),
                       ),
                        IconButton(
                          icon: const Icon(Icons.flip_to_back, color: Colors.white70),
                          tooltip: "Enviar p/ Trás",
                          onPressed: () => ref.read(projectProvider.notifier).sendToBack(state.selectedPhotoId!),
                       ),
                       
                       const SizedBox(width: 8),
                       Container(width: 1, height: 24, color: Colors.white24),
                       const SizedBox(width: 8),
                       
                       // Delete
                       IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          tooltip: "Excluir Seleção",
                          onPressed: () => _handleDelete(ref, state),
                       ),
                   ]
               ],
            ),
         ),
      );
  }

  Widget _buildCanvas(BuildContext context, WidgetRef ref, PhotoBookState state) {
    if (state.project.pages.isEmpty) return const SizedBox();

    final currentPage = state.project.pages[state.project.currentPageIndex];
    if (state.isExporting) {
       print("DEBUG: _buildCanvas - Page Size: ${currentPage.widthMm} x ${currentPage.heightMm} | isExporting: true");
    }

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
                 _canvasFocusNode.requestFocus();
              },
              behavior: HitTestBehavior.opaque, // Catch everything not caught by children
              child: Container(color: Colors.transparent),
            ),
          ),
          
          Positioned.fill(
            child: Focus(
                focusNode: _canvasFocusNode,
                autofocus: true,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.01,
                  maxScale: 10.0,
                  scaleEnabled: true,
                  panEnabled: true,
                  // Reduced boundary margin to strictly 10% as requested
                  boundaryMargin: EdgeInsets.all(currentPage.widthMm * 0.1), 
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
                          // Reverting to Center/Padding structure for visual "correctness"
                          // Changed Center to Align(topLeft) to match user preference for origin.
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(20), // Visual margin reduced to 20
                              child: RepaintBoundary(
                                key: _canvasCaptureKey,
                                child: Container(
                                  key: _pageKey,
                                  width: currentPage.widthMm,
                                  height: currentPage.heightMm,
                                  decoration: BoxDecoration(
                                color: Color(currentPage.backgroundColor),
                                boxShadow: state.isExporting 
                                   ? null 
                                   : const [BoxShadow(color: Colors.black45, blurRadius: 20)],
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  if (currentPage.backgroundPath != null && currentPage.backgroundPath!.isNotEmpty)
                                     Positioned.fill(
                                        child: Image.file(
                                           File(currentPage.backgroundPath!),
                                           fit: BoxFit.cover,
                                        )
                                     ),
                                  ...currentPage.photos.map((photo) => _buildPhotoWidget(ref, photo, state.selectedPhotoId == photo.id, key: ValueKey(photo.id))),
                                  
                                  // Cut Line Guide (Stroke)
                                  Positioned.fill(
                                     child: IgnorePointer(
                                       child: Container(
                                         decoration: BoxDecoration(
                                            border: Border.all(color: Colors.black12, width: 0.5),
                                         ),
                                       ),
                                     ),
                                  ),
                                ],
                              ),
                                    ),
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
                      _updateCanvasView(context, ref, state, overrideScale: newScale);
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
                      _updateCanvasView(context, ref, state, overrideScale: newScale);
                    },
                    tooltip: "Zoom In",
                  ),
                  const VerticalDivider(color: Colors.white24, width: 20, indent: 10, endIndent: 10),
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong, color: Colors.white70),
                    onPressed: () {
                       _updateCanvasView(context, ref, state);
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

      isExporting: ref.watch(projectProvider).isExporting, 
      canvasScale: ref.watch(projectProvider).canvasScale, // Pass Scale for Sensitive Drag
      isPrecisionMode: ref.watch(projectProvider).isPrecisionMode, // Pass Precision
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
          child: const ListTile(leading: Icon(Icons.edit, color: Colors.blueAccent, size: 18), title: Text("Abrir no Editor (Shift+E)", style: TextStyle(color: Colors.white))),
          onTap: () => _openSelectedInEditor(context, ref, photo),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.rotate_left, color: Colors.white, size: 18), title: Text("Rotacionar", style: TextStyle(color: Colors.white))),
          onTap: () => ref.read(projectProvider.notifier).rotatePagePhoto(photo.id, -90),
        ),
        PopupMenuItem(
          child: const ListTile(leading: Icon(Icons.rotate_right, color: Colors.white, size: 18), title: Text("Rotacionar", style: TextStyle(color: Colors.white))),
          onTap: () => ref.read(projectProvider.notifier).rotatePagePhoto(photo.id, 90),
        ),
        const PopupMenuDivider(),
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
          child: const ListTile(leading: Icon(Icons.wallpaper, color: Colors.white, size: 18), title: Text("Definir como Fundo", style: TextStyle(color: Colors.white))),
          onTap: () {
             Future.delayed(Duration.zero, () async {
                 final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
                    title: const Text("Definir Fundo"),
                    content: const Text("Deseja aplicar este fundo apenas nesta página ou em todas do projeto?"),
                    actions: [
                       TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("Cancelar")),
                       TextButton(onPressed: () => Navigator.pop(ctx, 'single'), child: const Text("Apenas Nesta")),
                       ElevatedButton(onPressed: () => Navigator.pop(ctx, 'all'), child: const Text("Em Todas")),
                    ],
                 ));
                 
                 if (result != null) {
                    await ref.read(projectProvider.notifier).setBackground(photo.path, applyToAll: result == 'all');
                 }
             });
          },
        ),
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

  void _openSelectedInEditor(BuildContext context, WidgetRef ref, [PhotoItem? photo]) {
     PhotoItem? targetPhoto = photo;
     
     // If not provided (e.g. shortcut), try to find selected
     if (targetPhoto == null) {
        final state = ref.read(projectProvider);
        if (state.selectedPhotoId != null && state.project.currentPageIndex >= 0) {
           final page = state.project.pages[state.project.currentPageIndex];
           try {
             targetPhoto = page.photos.firstWhere((p) => p.id == state.selectedPhotoId);
           } catch (_) {}
        }
     }

     if (targetPhoto == null || targetPhoto.path.isEmpty) return;

     // Block Templates (No Editor for Templates)
     final lowerPath = targetPhoto.path.toLowerCase();
     if (lowerPath.contains("templates") || lowerPath.contains("molduras") || lowerPath.endsWith(".png")) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
           content: Text("Templates e PNGs não podem ser editados no Editor de Imagem (Iluminação Fixa)."),
           backgroundColor: Colors.orangeAccent,
        ));
        return;
     }

     // Navigate logic reuse
     final paths = ref.read(projectProvider).project.pages
         .expand((p) => p.photos)
         .where((p) => !p.isText && p.path.isNotEmpty)
         .map((p) => p.path)
         .toSet()
         .toList();
     
     final initialIndex = paths.indexOf(targetPhoto.path);
     
     if (initialIndex != -1) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImageEditorView(
              paths: paths, 
              initialIndex: initialIndex
            )
          )
        );
     }
  }

  void _showPageContextMenu(BuildContext context, WidgetRef ref, Offset localPos) {
    final state = ref.read(projectProvider);

    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // Prevent empty menu crash
    if (state.clipboardPhoto == null) return;

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
      ],
    );
  }



  Widget _buildThumbnails(WidgetRef ref, PhotoBookState state) {
  return Container(
    color: const Color(0xFF1E1E1E),
    child: Column(
      children: [
        // Timeline Header (Sort & Info)
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: Colors.black26,
          child: Row(
            children: [
               const Icon(Icons.view_timeline, size: 16, color: Colors.white54),
               const SizedBox(width: 8),
               Text(
                 "Páginas (${state.project.pages.length})", 
                 style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)
               ),
               const Spacer(),
               // Sort Buttons
               TextButton.icon(
                 icon: const Icon(Icons.calendar_month, size: 14, color: Colors.white60),
                 label: const Text("Ordenar Data", style: TextStyle(fontSize: 11, color: Colors.white60)),
                 style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                 onPressed: () => ref.read(projectProvider.notifier).sortPagesByDate(),
               ),
               TextButton.icon(
                 icon: const Icon(Icons.sort_by_alpha, size: 14, color: Colors.white60),
                 label: const Text("Ordenar Nome", style: TextStyle(fontSize: 11, color: Colors.white60)),
                 style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                 onPressed: () => ref.read(projectProvider.notifier).sortPagesByName(),
               ),
            ],
          ),
        ),
        
        Expanded(
          child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete, shift: true): () {
            if (state.multiSelectedPages.isNotEmpty) {
                ref.read(projectProvider.notifier).removeSelectedPages();
            } else {
                ref.read(projectProvider.notifier).removePage(state.project.currentPageIndex);
            }
        },
      },
      child: Focus(
        autofocus: false,
        child: Builder(
          builder: (context) {
            return Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                // If vertical scroll (dy) is detected but no horizontal scroll (dx),
                // map it to horizontal scroll for the timeline.
                if (event.scrollDelta.dy != 0 && event.scrollDelta.dx == 0) {
                   final double newOffset = _thumbScrollController.offset + event.scrollDelta.dy;
                   if (newOffset >= _thumbScrollController.position.minScrollExtent &&
                       newOffset <= _thumbScrollController.position.maxScrollExtent) {
                       _thumbScrollController.jumpTo(newOffset);
                   }
                }
              }
            },
            child: Scrollbar(
              controller: _thumbScrollController,
              thumbVisibility: true,
              thickness: 12, // Thicker for touch
              radius: const Radius.circular(6),
              interactive: true,
              child: ReorderableListView.builder(
              scrollController: _thumbScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              itemCount: state.project.pages.length,
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) => ref.read(projectProvider.notifier).reorderPage(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final page = state.project.pages[index];
                final isCurrent = state.project.currentPageIndex == index;
                final isMultiSelected = state.multiSelectedPages.contains(index);
                final isSelected = isCurrent || isMultiSelected;
                
                final double pageAspectRatio = page.widthMm / page.heightMm;
                final double thumbHeight = 110.0;
                final double thumbWidth = thumbHeight * pageAspectRatio;

                return ReorderableDelayedDragStartListener(
                  index: index,
                  key: ValueKey(page.id),
                  child: GestureDetector(
                    onTap: () {
                       // Request focus for Delete shortcut
                       Focus.of(context).requestFocus();

                       final Set<LogicalKeyboardKey> pressed = HardwareKeyboard.instance.logicalKeysPressed;
                       final isShift = pressed.contains(LogicalKeyboardKey.shiftLeft) || pressed.contains(LogicalKeyboardKey.shiftRight);
                       final isCtrl = pressed.contains(LogicalKeyboardKey.controlLeft) || pressed.contains(LogicalKeyboardKey.controlRight);
                       
                       if (isShift) {
                           ref.read(projectProvider.notifier).selectPageRange(state.project.currentPageIndex, index);
                       } else if (isCtrl) {
                           // If starting multi-selection from a single selection, implicitly include the current page first
                           if (state.multiSelectedPages.isEmpty) {
                              ref.read(projectProvider.notifier).togglePageSelection(state.project.currentPageIndex);
                           }
                           ref.read(projectProvider.notifier).togglePageSelection(index);
                           ref.read(projectProvider.notifier).setPageIndex(index);
                       } else {
                           // Standard click clears selection and sets current
                           ref.read(projectProvider.notifier).clearPageSelection();
                           ref.read(projectProvider.notifier).setPageIndex(index);
                       }
                    },
                    onSecondaryTapUp: (details) {
                         Focus.of(context).requestFocus();
                         // Right click context menu
                         if (!isSelected) {
                             ref.read(projectProvider.notifier).setPageIndex(index);
                             ref.read(projectProvider.notifier).clearPageSelection();
                         }
                         
                         final multiCount = state.multiSelectedPages.length;
                         final deleteLabel = multiCount > 1 ? "Excluir $multiCount Páginas" : "Excluir Página";
                         
                         showMenu(
                           context: context,
                           position: RelativeRect.fromLTRB(
                             details.globalPosition.dx, 
                             details.globalPosition.dy, 
                             details.globalPosition.dx + 1, 
                             details.globalPosition.dy + 1
                           ),
                           color: const Color(0xFF262626),
                           items: [
                             if (multiCount > 0)
                               PopupMenuItem(
                                 child: const ListTile(
                                    leading: Icon(Icons.drive_file_move, color: Colors.blueAccent, size: 18), 
                                    title: Text("Mover Selecionados p/ Cá", style: TextStyle(color: Colors.white))
                                 ),
                                 onTap: () {
                                   ref.read(projectProvider.notifier).moveSelectedPages(index);
                                 },
                               ),
                             if (multiCount > 1) 
                               PopupMenuItem(
                                 child: const ListTile(
                                   leading: Icon(Icons.merge_type, color: Colors.blueAccent, size: 18), 
                                   title: Text("Fundir Páginas", style: TextStyle(color: Colors.white))
                                 ),
                                 onTap: () {
                                   ref.read(projectProvider.notifier).mergeSelectedPages();
                                 },
                               ),
                             PopupMenuItem(
                               child: ListTile(leading: const Icon(Icons.delete, color: Colors.red, size: 18), title: Text(deleteLabel, style: const TextStyle(color: Colors.white))),
                               onTap: () {
                                  if (multiCount > 1) {
                                      ref.read(projectProvider.notifier).removeSelectedPages();
                                  } else {
                                      ref.read(projectProvider.notifier).removePage(index);
                                  }
                               },
                             ),
                           ]
                         );
                    },
              child: Container(
                width: thumbWidth,
                margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Color(page.backgroundColor),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isCurrent ? Colors.amberAccent : (isMultiSelected ? Colors.blueAccent : Colors.white12),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  if (isSelected)
                    BoxShadow(color: (isCurrent ? Colors.amberAccent : Colors.blueAccent).withOpacity(0.4), blurRadius: 8),
                ],
              ),
              child: Stack(
                children: [
                  // Page Content Preview (Actual Photos)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(0), // Remove padding to fix aspect ratio
                      child: _buildMiniPagePreview(page),
                    ),
                  ),
                  
                  // Page Number Badge
                  Positioned(
                    top: 2, left: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isCurrent ? Colors.amberAccent : (isMultiSelected ? Colors.blueAccent : Colors.black54),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "${index + 1}", 
                        style: TextStyle(
                          color: isCurrent ? Colors.black : Colors.white,
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
              )
             )
            );
            },
          ),
        ),
      ),
    ),
      ],
    ),
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
             // We can add "Rotate" here too if we want
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
                  ? SmartImage(path: photo.path)
                  : const SizedBox(),
              ),
            );
          }).toList(),
        );
      },
    );
  }



  void _updateCanvasView(BuildContext context, WidgetRef ref, PhotoBookState state, {double? overrideScale}) {
    if (state.project.pages.isEmpty) return;
    
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    
    final Size viewportSize = box.size;
    final page = state.project.pages[state.project.currentPageIndex];
    
    // Estimate Canvas Dimensions (Window - Dock/Bars)
    // Relaxed margins slightly based on user feedback "extremely large"
    final double availWidth = viewportSize.width - 400; 
    final double availHeight = viewportSize.height - 220; 
    
    if (availWidth <= 0 || availHeight <= 0) return;

    // 1. Determine Scale
    double finalScale;
    if (overrideScale != null) {
      finalScale = overrideScale.clamp(0.1, 5.0);
    } else {
      // Calculate scale to fit page + padding (20+20=40)
      final double contentWidth = page.widthMm + 40;
      final double contentHeight = page.heightMm + 40;
      
      final double scaleX = availWidth / contentWidth;
      final double scaleY = availHeight / contentHeight;
      
      finalScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 5.0);
    }
    
    // 2. Align Top-Left (0,0)
    // User requested Top 0, Left 0.
    // The internal padding (50->20) will provide the visual margin.
    final double dx = 0.0;
    final double dy = 0.0;
    
    // 3. Apply Matrix (Translate then Scale)
    // Note: InteractiveViewer applies the matrix to the child.
    // We want the child to appear at (dx, dy).
    // Matrix4.identity()..translate(dx, dy)..scale(finalScale);
    // However, InteractiveViewer content coordinates usually start at 0,0.
    // If we translate, we move the content. 
    
    _transformationController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(finalScale);
      
    ref.read(projectProvider.notifier).setCanvasScale(finalScale);
  }


  // --- Handlers ---

  Future<void> _handleSave(BuildContext context, WidgetRef ref) async {
    final state = ref.read(projectProvider);
    if (state.currentProjectPath != null && state.currentProjectPath!.isNotEmpty) {
      // Overwrite existing file
      await ref.read(projectProvider.notifier).saveProject(state.currentProjectPath!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Projeto salvo!")));
      }
    } else {
      // If no file path, behave like Save As
      await _handleSaveAs(context, ref);
    }
  }

  Future<void> _handleSaveAs(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: "Salvar Como",
      fileName: "album_smart_preview.alem",
      allowedExtensions: ['alem', 'json'],
      type: FileType.custom,
    );
    if (result != null) {
      await ref.read(projectProvider.notifier).saveProject(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Projeto salvo com sucesso!")));
      }
    }
  }

  Future<bool> _promptAndSetContractNumber(BuildContext context, WidgetRef ref) async {
      final state = ref.read(projectProvider);
      final textCtrl = TextEditingController(text: state.project.contractNumber);
      
      final result = await showDialog<String>(
         context: context,
         builder: (ctx) => AlertDialog(
            title: const Text("Número do Contrato"),
            content: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                  const Text("Informe o Contrato para as etiquetas:"),
                  TextField(controller: textCtrl, autofocus: true, decoration: const InputDecoration(labelText: "Contrato (ex: 602)")),
               ],
            ),
            actions: [
               TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
               ElevatedButton(onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()), child: const Text("Confirmar")),
            ],
         )
      );
      
      if (result != null && result.isNotEmpty) {
         ref.read(projectProvider.notifier).setContractNumber(result);
         return true;
      }
      // If user clears it or cancels? Return false if null.
      // If result is empty string but confirmed, maybe they want to clear?
      // User said "preciso do numero". If they clear, labels might be empty.
      return result != null;
  }

  Future<void> _handleLoad(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['alem', 'json'],
    );
    if (result != null && result.files.single.path != null) {
      final success = await ref.read(projectProvider.notifier).loadProject(result.files.single.path!);
      if (mounted) {
        if (success) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Projeto carregado com sucesso!")));
        } else {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: const Text("Erro ao carregar projeto! Verifique o arquivo."), 
               backgroundColor: Colors.redAccent.shade700
             )
           );
        }
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
    // Prompt for Contract Number
    final contractCtrl = TextEditingController();
    // Default contract if available in project?
    contractCtrl.text = ref.read(projectProvider).project.contractNumber; // Pre-fill if stored?

    final proceed = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
          title: const Text("Exportar JPG - Opções"),
          content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
                TextField(
                   controller: contractCtrl,
                   decoration: const InputDecoration(labelText: "Número do Contrato (Prefixo)", hintText: "Ex: 602"),
                ),
                const SizedBox(height: 10),
                const Text("Exemplo: 602_NomeProjeto_01.jpg", style: TextStyle(fontSize: 12, color: Colors.grey)),
             ],
          ),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
             ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("EXPORTAR")),
          ],
       )
    );

    if (proceed != true) return;
    
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: "Selecione a pasta para as imagens",
    );
    if (result != null) {
        final state = ref.read(projectProvider);
        final double exportPixelRatio = state.project.ppi / 25.4;

        // Derive prefix
        String prefix = "pagina";
        if (state.currentProjectPath != null) {
          prefix = p.basenameWithoutExtension(state.currentProjectPath!);
        }
        
        // Add Contract Prefix
        if (contractCtrl.text.trim().isNotEmpty) {
           prefix = "${contractCtrl.text.trim()}_$prefix";
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
          
          bool success = false;
          int retries = 0;
          
          while (!success && retries < 3) {
              // Wait logic: longer on first try, shorter on retries? Or longer on retries?
              // User said: "guarde essa pagina que deve acontecer uma nova tentativa porque a imagem pode ainda nao estar carregada"
              // So wait longer on retries.
              await Future.delayed(Duration(milliseconds: retries == 0 ? 2000 : 4000));
              
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
                 
                 // Size Check
                 final file = File(filePath);
                 if (file.existsSync() && file.lengthSync() > 500 * 1024) {
                    success = true;
                 } else {
                    print("Page $i export too small (${file.existsSync() ? file.lengthSync() : 0} bytes). Retrying...");
                    retries++;
                    // Force refresh/cleanup?
                    PaintingBinding.instance.imageCache.clear();
                 }
              } else {
                 retries++;
              }
          }
          if (!success) {
             print("Failed to export page $i with valid size after retries.");
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

  void _showExportingDialog(BuildContext context, {String message = "Exportando para JPG..."}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
            if (message == "Exportando para JPG...") ...[
               const Text("Aguarde, processando todas as páginas.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]
          ],
        ),
      ),
    );
  }

  // --- Auto Diagramming Logic ---

  Future<void> _showAutoDiagrammingDialog(BuildContext context) async {
      // 1. Select Model Project
      FilePickerResult? modelResult = await FilePicker.platform.pickFiles(
         dialogTitle: "Selecione o PROJETO MODELO (.alem)",
         type: FileType.custom,
         allowedExtensions: ['alem'],
      );
      if (modelResult == null) return;
      final modelPath = modelResult.files.single.path!;

      // 2. Select Root Folder
      String? rootPath = await FilePicker.platform.getDirectoryPath(
         dialogTitle: "Selecione a PASTA PAI dos Alunos",
      );
      if (rootPath == null) return;

      // 3. Input Contract Number
      final contractCtrl = TextEditingController();
      final confirm = await showDialog<bool>(
         context: context,
         builder: (ctx) => AlertDialog(
            title: const Text("Diagramação Automática"),
            content: Column(
               mainAxisSize: MainAxisSize.min,
               children: [
                  const Text("Modelo selecionado e Pasta Pai definida.\nInsira o número de contrato padrão:"),
                  const SizedBox(height: 16),
                  TextField(
                     controller: contractCtrl,
                     decoration: const InputDecoration(labelText: "Contrato (ex: 1234)"),
                  )
               ],
            ),
            actions: [
               TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
               ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("INICIAR")),
            ],
         )
      );

      if (confirm == true) {
         try {
            AutoDiagrammingService().startDiagramming(
               modelProjectPath: modelPath,
               rootFolderPath: rootPath,
               contractNumber: contractCtrl.text.trim(),
            );
         } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao iniciar: $e")));
         }
      }
  }

  // --- Batch Export Logic ---

  Future<void> _showBatchExportDialog(BuildContext context) async {
      // 1. Select Input Folder
      String? inputPath = await FilePicker.platform.getDirectoryPath(
         dialogTitle: "Selecione a PASTA PAI (onde estão os projetos)",
      );
      if (inputPath == null) return;

      // 2. Select Output Folder
      String? outputPath = await FilePicker.platform.getDirectoryPath(
         dialogTitle: "Selecione a PASTA DE SAÍDA (onde criar as JPGs)",
      );
      if (outputPath == null) return;

      // Confirmation & Contract Input
      final contractCtrl = TextEditingController();
      final confirm = await showDialog<bool>(
         context: context,
         builder: (ctx) => AlertDialog(
            title: const Text("Iniciar Exportação em Lote?"),
            content: SizedBox(
               width: 300,
               child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     const Text("Insira o número de contrato para prefixar\nas pastas (ex: 602_004020)."),
                     const SizedBox(height: 16),
                     TextField(
                        controller: contractCtrl,
                        decoration: const InputDecoration(
                           labelText: "Número do Contrato",
                           hintText: "Ex: 602"
                        ),
                     ),
                     const SizedBox(height: 16),
                     Text("Origem: $inputPath\nDestino: $outputPath"),
                  ],
               ),
            ),
            actions: [
               TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
               ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("INICIAR")),
            ],
         )
      );

      if (confirm == true) {
         _runBatchExport(inputPath, outputPath, contractNumber: contractCtrl.text.trim());
      }
  }

  Future<void> _runBatchExport(String inputRoot, String outputRoot, {String contractNumber = ""}) async {
     try {
        _showExportingDialog(context, message: "Iniciando processo em lote...");
        
        // 1. Find Projects
        final dir = Directory(inputRoot);
        final projectFiles = dir.listSync(recursive: true).where((f) => f.path.toLowerCase().endsWith('.alem')).toList();
        
        if (projectFiles.isEmpty) {
           Navigator.pop(context); // Close loading
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nenhum projeto (.alem) encontrado!")));
           return;
        }

        int total = projectFiles.length;
        for (int i=0; i<total; i++) {
           final pFile = projectFiles[i];
           final pPath = pFile.path;
           final pName = p.basenameWithoutExtension(pPath);
           
           // Apply Contract Prefix logic
           String folderName = pName;
           if (contractNumber.isNotEmpty) {
              folderName = "${contractNumber}_$pName";
           }

           // Update Progress UI (Close previous dialog, open new one)
           if (mounted) {
              Navigator.pop(context); 
              _showExportingDialog(context, message: "Projeto ${i+1}/$total: $folderName");
           }
           
           // Load Project
           await ref.read(projectProvider.notifier).loadProject(pPath);
           
           // Wait for load settle
           await Future.delayed(const Duration(seconds: 2));
           
           final state = ref.read(projectProvider);
           final double exportPixelRatio = state.project.ppi / 25.4;

           // Create Output Subfolder
           final projOutputDir = Directory(p.join(outputRoot, folderName));
           if (!projOutputDir.existsSync()) {
              projOutputDir.createSync(recursive: true);
           }
           
           // Enable Export Mode
           ref.read(projectProvider.notifier).setIsExporting(true);
           await Future.delayed(const Duration(milliseconds: 300));
           
           // Iterate Pages
           for (int pageIdx = 0; pageIdx < state.project.pages.length; pageIdx++) {
              final page = state.project.pages[pageIdx];
              
              // PRE-LOAD IMAGES - CRITICAL FIX
              // Explicitly load all images into memory cache before showing the page
              await Future.wait(page.photos.map((p) async {
                 if (p.path.isNotEmpty) {
                    try {
                        await ImageLoader.loadImage(p.path);
                    } catch (e) {
                        print("Error pre-loading ${p.path}: $e");
                    }
                 }
              }));

              ref.read(projectProvider.notifier).setPageIndex(pageIdx);
              ref.read(projectProvider.notifier).selectPhoto(null);
              ref.read(projectProvider.notifier).setEditingContent(false);
              
              // Wait for render - Reduced to 2s as images are pre-loaded
              await Future.delayed(const Duration(milliseconds: 2000));
              
              final bytes = await ExportHelper.captureKeyToBytes(_canvasCaptureKey, pixelRatio: exportPixelRatio);
              if (bytes != null) {
                 final pageNum = (pageIdx + 1).toString().padLeft(2, '0');
                 final fileName = "${pName}_$pageNum.jpg";
                 final filePath = p.join(projOutputDir.path, fileName);
                 
                 // Use Helper with DPI
                 await ExportHelper.saveAsHighResJpg(
                    pngBytes: bytes, 
                    path: filePath, 
                    dpi: state.project.ppi.toInt()
                 );
              }
           }
           
           // Disable Export Mode
           ref.read(projectProvider.notifier).setIsExporting(false);
        }
        
        // Close last loading
        if (mounted) Navigator.pop(context); 
        
        if (mounted) {
           await showDialog(
              context: context, 
              builder: (ctx) => AlertDialog(
                 title: const Text("Concluído"),
                 content: Text("Processados $total projetos com sucesso!"),
                 actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
              )
           );
        }

     } catch (e) {
        if (mounted) Navigator.pop(context); // Close loading
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro no lote: $e")));
     }
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
     
     // Pop Config
     if (context.mounted) Navigator.pop(context);
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
       // Ignore Locked Items for Drop Target (unless they are placeholders/empty?)
       // If locked and not empty, we shouldn't replace it.
       if (photo.isLocked && photo.path.isNotEmpty) continue;
       
       // Optimization: Prioritize "Empty" placeholders if we have overlap
       // But 'reversed' suggests z-order check (top first).
       // If we have a Template Frame (Z=5, Locked) and a Photo (Z=1), 
       // the loop hits Frame first. We continue (skip).
       // Then hits Photo. Logic works.
       
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
       // Filter valid images
       final validPaths = paths.where((p) => _isImage(p)).toList();
       if (validPaths.isEmpty) return;

       // Directly Add as Photos (User Request: No Dialog)
       for (final path in validPaths) {
          final item = PhotoItem(
             id: Uuid().v4(),
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

  void _promptForBackgroundScope(WidgetRef ref, String path) {
     showDialog(
       context: context,
       builder: (ctx) => AlertDialog(
          title: const Text("Definir Fundo"),
          content: const Text("Deseja aplicar este fundo apenas nesta página ou em todas do projeto?"),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
             TextButton(
               onPressed: () async {
                  Navigator.pop(ctx);
                  await ref.read(projectProvider.notifier).setBackground(path, applyToAll: false);
               }, 
               child: const Text("Apenas Nesta")
             ),
             ElevatedButton(
               onPressed: () async {
                  Navigator.pop(ctx);
                  await ref.read(projectProvider.notifier).setBackground(path, applyToAll: true);
               },
               child: const Text("Em Todas")
             ),
          ],
       )
     );
  }

  void _handleAssetDrop(WidgetRef ref, Offset dropPos, LibraryAsset asset, AlbumPage currentPage) {
    if (asset.type == AssetType.element) {
       // Check for Background Tag or Filename
       // If tagged as "fundo", ask if apply to all pages
       final isBackground = asset.path.toLowerCase().contains("fundo") || asset.tags.contains("fundo");
       
       if (isBackground) {
           showDialog(
             context: context,
             builder: (ctx) => AlertDialog(
               title: const Text("Adicionar Fundo"),
               content: const Text("Deseja aplicar este fundo em TODAS as páginas do projeto ou somente nesta?"),
               actions: [
                 TextButton(
                   onPressed: () {
                     Navigator.pop(ctx);
                     // Single Page (Default) - Z-Index 0 (Bottom)
                     _addBackgroundToPage(ref, asset, dropPos, singlePage: true);
                   }, 
                   child: const Text("Somente Nesta")
                 ),
                 ElevatedButton(
                   onPressed: () {
                     Navigator.pop(ctx);
                     // All Pages
                     _addBackgroundToPage(ref, asset, dropPos, singlePage: false);
                   },
                   child: const Text("Todas as Páginas"),
                 )
               ],
             )
           );
       } else {
          // Standard Element Drop
          final item = PhotoItem(
            id: Uuid().v4(),
            path: asset.path,
            x: dropPos.dx - 50,
            y: dropPos.dy - 50,
            width: 100,
            height: 100,
            zIndex: 10,
          );
          ref.read(projectProvider.notifier).addPhotoToCurrentPage(item);
       }
    } else {
      // Template logic: Frames with holes
      final double pageWidth = currentPage.widthMm;
      final double pageHeight = currentPage.heightMm;
      
      // 1. Template Frame (Top Level)
      final templateItem = PhotoItem(
        id: Uuid().v4(), // Fix: Ensure ID is generated
        path: asset.path,
        // Full page frame
        x: 0, 
        y: 0,
        width: pageWidth,
        height: pageHeight,
        zIndex: 5, // Frame usually on top of photos
        isTemplate: true,
        isLocked: true, // Lock the template frame
      );
      
      // 2. Identify Holes
      List<Rect> holes = [];
      if (asset.holes.isNotEmpty) {
         holes = asset.holes;
      } else if (asset.holeX != null) {
         // Legacy single hole
         holes.add(Rect.fromLTWH(asset.holeX!, asset.holeY!, asset.holeW!, asset.holeH!));
      } else {
         // Default center hole if none defined
         holes.add(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8));
      }

      // 3. Map Photos to Holes
      // We prioritize existing photos with content.
      final existingPhotos = currentPage.photos.where((p) => p.path.isNotEmpty).toList();
      List<PhotoItem> newPhotos = [];
      
      for (int i = 0; i < holes.length; i++) {
        final hole = holes[i];
        
        // Bleeding calculation (1%)
        final double bleedW = hole.width * 0.01;
        final double bleedH = hole.height * 0.01;
        // Fix: Use correct hole coordinates without scaling if asset defines logical 0-1
        // The asset.holes should already be 0-1 if they are "logical". 
        // Assuming asset holes are normalized 0-1.
        
        final double finalX = (hole.left - bleedW) * pageWidth;
        final double finalY = (hole.top - bleedH) * pageHeight;
        final double finalW = (hole.width + 2 * bleedW) * pageWidth;
        final double finalH = (hole.height + 2 * bleedH) * pageHeight;

        if (i < existingPhotos.length) {
           // Reuse existing photo, update its geometry
           final p = existingPhotos[i].copyWith(
             x: finalX, y: finalY, width: finalW, height: finalH,
             zIndex: 1, // Photos behind frame
             contentScale: 1.0, 
             contentX: 0.0, 
             contentY: 0.0,
           );
           newPhotos.add(p);
        } else {
           // Create Placeholder for empty hole
           final p = PhotoItem(
             id: Uuid().v4(),
             path: "",
             x: finalX, y: finalY, width: finalW, height: finalH,
             zIndex: 1,
           );
           newPhotos.add(p);
        }
      }

      // 4. Handle extra existing photos (if any)
      // Keep them in the list so they don't disappear, but they might be obscured or floating
      if (existingPhotos.length > holes.length) {
         newPhotos.addAll(existingPhotos.sublist(holes.length));
      }
      
      // Add the template frame last (or handled by zIndex)
      // We want to ensure we don't duplicate if for some reason we drag the same template?
      // But here we are replacing layout fundamentally.
      newPhotos.add(templateItem);

      // Replace page content
      ref.read(projectProvider.notifier).updatePageLayout(newPhotos);
    }
  }

  void _addBackgroundToPage(WidgetRef ref, LibraryAsset asset, Offset dropPos, {required bool singlePage}) {
      // Background logic: specific geometry or just image?
      // Usually background fills the page (width/height of page).
      // Assuming 100x100 for now if drag-dropped as element, OR full page?
      // "Background" usually implies Full Page.
      // Let's assume full page if it's a "background" asset.
      
      final state = ref.read(projectProvider);
      
      if (singlePage) {
         final page = state.project.pages[state.project.currentPageIndex];
         final bgItem = PhotoItem(
            id: Uuid().v4(),
            path: asset.path,
            x: 0, 
            y: 0, 
            width: page.widthMm, 
            height: page.heightMm,
            zIndex: 0, // Bottom
         );
         ref.read(projectProvider.notifier).addPhotoToCurrentPage(bgItem);
      } else {
         // Apply to ALL pages
         final updatedPages = <AlbumPage>[];
         for (var page in state.project.pages) {
            final bgItem = PhotoItem(
               id: Uuid().v4(),
               path: asset.path,
               x: 0, 
               y: 0, 
               width: page.widthMm, 
               height: page.heightMm,
               zIndex: 0, // Bottom
            );
            // Add to start of list (bottom z-order visually if zIndex handled correctly, or verify zIndex sorting)
            // Existing logic uses zIndex property.
            updatedPages.add(page.copyWith(photos: [bgItem, ...page.photos]));
         }
         
         ref.read(projectProvider.notifier).replaceAllPages(updatedPages);
       }
   }
}

class _NewProjectDialog extends StatefulWidget {
  final Function(double width, double height, int dpi) onCreate;
  const _NewProjectDialog({required this.onCreate});

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  // Presets in CM
  final List<Map<String, dynamic>> presets = [
    {"label": "Padrão (30.5 x 21.5)", "w": 30.5, "h": 21.5},
    {"label": "Quadrado (30 x 30)", "w": 30.0, "h": 30.0},
    {"label": "Quadrado Grande (35 x 35)", "w": 35.0, "h": 35.0},
    {"label": "Retrato/Paisagem (30 x 40)", "w": 30.0, "h": 40.0},
    {"label": "Pequeno (20 x 25)", "w": 20.0, "h": 25.0},
  ];

  int _selectedIndex = 0;
  bool _isHorizontal = true;
  final TextEditingController _dpiCtrl = TextEditingController(text: "300");

  @override
  Widget build(BuildContext context) {
    // Current base dimensions
    double baseW = presets[_selectedIndex]["w"];
    double baseH = presets[_selectedIndex]["h"];
    
    // Apply orientation logic
    double finalW = _isHorizontal ? (baseW > baseH ? baseW : baseH) : (baseW < baseH ? baseW : baseH);
    double finalH = _isHorizontal ? (baseW > baseH ? baseH : baseW) : (baseW < baseH ? baseH : baseW);
    // Square check
    if ((baseW - baseH).abs() < 0.1) {
       finalW = baseW; finalH = baseH;
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: const Text("Novo Projeto", style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             const Text("Tamanho e Orientação:", style: TextStyle(color: Colors.white70)),
             const SizedBox(height: 10),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12),
               decoration: BoxDecoration(
                 color: Colors.white10,
                 borderRadius: BorderRadius.circular(4),
               ),
               child: DropdownButtonHideUnderline(
                 child: DropdownButton<int>(
                   value: _selectedIndex,
                   isExpanded: true,
                   dropdownColor: const Color(0xFF333333),
                   style: const TextStyle(color: Colors.white),
                   icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                   items: List.generate(presets.length, (i) {
                      return DropdownMenuItem(
                        value: i,
                        child: Text(presets[i]["label"]),
                      );
                   }),
                   onChanged: (val) {
                     if (val != null) setState(() => _selectedIndex = val);
                   },
                 ),
               ),
             ),
             const SizedBox(height: 16),
             Row(
               children: [
                 Expanded(
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       const Text("Orientação:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                       const SizedBox(height: 4),
                       ToggleButtons(
                         isSelected: [_isHorizontal, !_isHorizontal],
                         onPressed: (idx) {
                            setState(() => _isHorizontal = idx == 0);
                         },
                         borderRadius: BorderRadius.circular(4),
                         fillColor: Colors.blueAccent,
                         selectedColor: Colors.white,
                         color: Colors.white54,
                         constraints: const BoxConstraints(minWidth: 60, minHeight: 36),
                         children: const [
                           Icon(Icons.landscape, size: 20),
                           Icon(Icons.portrait, size: 20),
                         ]
                       ),
                     ],
                   ),
                 ),
                 const SizedBox(width: 16),
                 Expanded(
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       const Text("DPI:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                       const SizedBox(height: 4),
                       SizedBox(
                         height: 36,
                         child: TextField(
                           controller: _dpiCtrl,
                           style: const TextStyle(color: Colors.white),
                           keyboardType: TextInputType.number,
                           decoration: const InputDecoration(
                             contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                             filled: true,
                             fillColor: Colors.white10,
                             border: OutlineInputBorder(borderSide: BorderSide.none),
                           ),
                         ),
                       ),
                     ],
                   ),
                 ),
               ],
             ),
             const SizedBox(height: 16),
             Text(
               "Dimensões Finais: ${finalW.toStringAsFixed(1)} cm x ${finalH.toStringAsFixed(1)} cm",
               style: const TextStyle(color: Colors.white54, fontSize: 13),
             ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: const Text("Cancelar", style: TextStyle(color: Colors.white54))
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          onPressed: () {
             final dpi = int.tryParse(_dpiCtrl.text) ?? 300;
             // Convert CM to MM
             widget.onCreate(finalW * 10, finalH * 10, dpi);
          },
          child: const Text("Criar Projeto"),
        ),
      ],
    );
  }
}


