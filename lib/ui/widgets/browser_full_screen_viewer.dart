import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/project_state.dart';
import '../../logic/editor/editor_state.dart';
import '../../logic/editor/color_matrix_helper.dart';
import '../../logic/editor/gemini_service.dart';
import '../../logic/editor/native_auto_enhance.dart';
import '../../logic/cache_provider.dart';
import 'histogram_graph.dart';
import 'waveform_scope.dart';
import 'vectorscope_scope.dart';
import 'scope_widget.dart';
import '../editor/image_editor_view.dart';

import 'dart:ui' as ui;

// --- WORKER TASKS ---
class _SaveTaskArgs {
  final String path;
  final double exposure;
  final double contrast;
  final double brightness;
  final double saturation;
  final double sharpness;
  final double noiseReduction;
  final double temperature;
  final double tint;

  _SaveTaskArgs({
    required this.path,
    required this.exposure,
    required this.contrast,
    required this.brightness,
    required this.saturation, 
    required this.sharpness,
    required this.noiseReduction,
    required this.temperature,
    required this.tint,
  });
}

Future<void> _applyAndSaveTask(_SaveTaskArgs args) async {
  try {
     final file = File(args.path);
     final bytes = await file.readAsBytes();
     final image = img.decodeImage(bytes);
     if (image == null) throw Exception("Failed to decode image");
     
     var processed = image;
     
     // Apply Adjustments (Basic)
     // NOTE: Removed 'brightness' from here to apply it manually for guaranteed effect
     processed = img.adjustColor(
        processed, 
        // brightness: args.brightness, // Moved to manual loop
        contrast: args.contrast,
        saturation: args.saturation,
        exposure: args.exposure, 
     );
     
     // Apply Temperature, Tint AND BRIGHTNESS (Manual Pixel Loop)
     // This is expensive but necessary as 'image' package lacks these filters natively in this version
     if (args.temperature != 0.0 || args.tint != 0.0 || args.brightness != 1.0) {
        for (final pixel in processed) {
           var r = pixel.r;
           var b = pixel.b;
           var g = pixel.g;
           
           // 1. Brightness (Multiplier)
           if (args.brightness != 1.0) {
              r = r * args.brightness;
              g = g * args.brightness;
              b = b * args.brightness;
           }

           // 2. Temperature
           if (args.temperature > 0) {
              r += args.temperature * 50; 
              b -= args.temperature * 50; 
           } else {
              r += args.temperature * 50; 
              b -= args.temperature * 50; 
           }
           
           // 3. Tint
           if (args.tint > 0) {
              g -= args.tint * 50; 
           } else {
              g -= args.tint * 50; 
           }
           
           pixel.r = r.clamp(0, 255);
           pixel.g = g.clamp(0, 255);
           pixel.b = b.clamp(0, 255);
        }
     }

     // Apply Noise Reduction (Smart Blur)
     if (args.noiseReduction > 0) {
        // Radius 0 to 10
        final radius = (args.noiseReduction * 10).toInt();
        if (radius > 0) {
           processed = img.gaussianBlur(processed, radius: radius);
        }
     }

     // Apply Sharpness (Simple Convolution)
     if (args.sharpness > 0) {
        // A simple sharpen kernel
        const kernel = [
          0, -1, 0,
          -1, 5, -1,
          0, -1, 0
        ];
        processed = img.convolution(processed, filter: kernel, div: 1, offset: 0);
     }
     
     // 300 DPI Injection
     if (processed.exif.imageIfd.xResolution == null) {
        processed.exif.imageIfd.xResolution = [300, 1];
        processed.exif.imageIfd.yResolution = [300, 1];
        processed.exif.imageIfd.resolutionUnit = 2; 
     } else {
        // Update existing
        processed.exif.imageIfd.xResolution = [300, 1];
        processed.exif.imageIfd.yResolution = [300, 1];
     }
     
     final jpg = img.encodeJpg(processed, quality: 95);
     
     print("Worker: Writing ${jpg.length} bytes to ${args.path}...");
     final f = File(args.path);
     print("Worker: File exists before? ${f.existsSync()} Size: ${f.existsSync() ? f.lengthSync() : 0}");
     
     await f.writeAsBytes(jpg, flush: true);
     
     print("Worker: Write Done. New Size: ${f.lengthSync()}");
      
   } catch (e) {
     print("Worker Error: $e");
     rethrow;
  }
}
// --------------------

class BrowserFullScreenViewer extends ConsumerStatefulWidget {
  final List<String> paths;
  final int initialIndex;

  const BrowserFullScreenViewer({
    super.key,
    required this.paths,
    required this.initialIndex,
  });

  @override
  ConsumerState<BrowserFullScreenViewer> createState() => _BrowserFullScreenViewerState();
}

class _BrowserFullScreenViewerState extends ConsumerState<BrowserFullScreenViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();
  Offset _histogramOffset = const Offset(20, 20); // Bottom Left
  Offset _waveformOffset = const Offset(300, 20); // Bottom Center
  Offset _vectorscopeOffset = const Offset(600, 20); // Bottom Right

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < widget.paths.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleSelection() {
    final path = widget.paths[_currentIndex];
    ref.read(projectProvider.notifier).toggleBrowserPathSelection(path);
  }

  void _rotate(bool clockwise) {
    // Rotates ONLY the current photo being viewed
     final degrees = clockwise ? 90 : -90;
     final currentPath = widget.paths[_currentIndex];
    ref.read(projectProvider.notifier).rotateGalleryPhoto(currentPath, degrees);
    setState(() {}); 
  }


  bool _showEditor = false;

  void _toggleEditor() {
    setState(() {
      _showEditor = !_showEditor;
    });
    // Set initial path
    if (_showEditor) {
      ref.read(imageEditorProvider.notifier).setImages([widget.paths[_currentIndex]], 0);
    }
  }

  Future<void> _saveAdjustments(String path) async {
    final editorState = ref.read(imageEditorProvider);
    final notifier = ref.read(imageEditorProvider.notifier);
    final projectNotifier = ref.read(projectProvider.notifier); // To trigger refreshes if needed
    
    // Capture current values
    print("Save Debug: Capturing values for $path");
    print("Save Debug: Exposure: ${editorState.currentAdjustments.exposure}");
    print("Save Debug: Contrast: ${editorState.currentAdjustments.contrast}");
    print("Save Debug: Brightness: ${editorState.currentAdjustments.brightness}");
    print("Save Debug: Saturation: ${editorState.currentAdjustments.saturation}");
    print("Save Debug: Sharpness: ${editorState.currentAdjustments.sharpness}");
    
    if (editorState.isProcessing) return;
    notifier.setProcessing(true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Salvando imagem (Alta Resolução 300 DPI)...")));

    try {
       await compute(_applyAndSaveTask, _SaveTaskArgs(
          path: path,
          exposure: editorState.currentAdjustments.exposure,
          contrast: editorState.currentAdjustments.contrast,
          brightness: editorState.currentAdjustments.brightness,
          saturation: editorState.currentAdjustments.saturation,
          sharpness: editorState.currentAdjustments.sharpness,
          noiseReduction: editorState.currentAdjustments.noiseReduction,
          temperature: editorState.currentAdjustments.temperature,
          tint: editorState.currentAdjustments.tint,
       ));
       
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Imagem salva e sobrescrita!")));
          await FileImage(File(path)).evict(); // Specific File Cache
          CacheService.invalidate(ref, path); // Global specific invalidation
          
          // Reset editor sliders to 0, because the file now contains the changes "baked in"
          // If we don't reset, the visualizer would apply the sliders ON TOP of the already edited file (Double Effect)
          notifier.reset(); 
          // Re-set path to keep context (reset clears path too?)
          // ImageEditorNotifier.reset() does `state = const ImageEditorState()`, which clears originalPath.
          notifier.setImages([path], 0);
          
          setState(() {}); // Refresh UI
       }
    } catch (e) {
       print("Save Error: $e");
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao salvar: $e")));
    } finally {
       notifier.setProcessing(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(projectProvider);
    final editorState = ref.watch(imageEditorProvider);
    final notifier = ref.read(imageEditorProvider.notifier);
    
    final currentPath = widget.paths[_currentIndex];
    final isSelected = projectState.selectedBrowserPaths.contains(currentPath);
    final name = currentPath.split(Platform.pathSeparator).last;
    final rotation = projectState.project.imageRotations[currentPath] ?? 0;

    // Calculate Matrix for Editor
    final matrix = ColorMatrixHelper.getMatrix(
       exposure: editorState.currentAdjustments.exposure,
       contrast: editorState.currentAdjustments.contrast,
       brightness: editorState.currentAdjustments.brightness,
       saturation: editorState.currentAdjustments.saturation,
       temperature: editorState.currentAdjustments.temperature,
       tint: editorState.currentAdjustments.tint
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // Main Content (Expanded)
          Expanded(
            child: Stack(
              children: [
                // Keyboard & PageView
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowRight): _nextPage,
                    const SingleActivator(LogicalKeyboardKey.arrowLeft): _previousPage,
                    const SingleActivator(LogicalKeyboardKey.space): _toggleSelection,
                    const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
                  },
                  child: Focus(
                    focusNode: _focusNode,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.paths.length,
                      physics: _showEditor ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(), // Disable swipe if editing to avoid accidents
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                        // Reset Editor when changing photos
                        if (_showEditor) {
                          notifier.reset();
                          notifier.setImages([widget.paths[index]], 0);
                        }
                      },
                      itemBuilder: (context, index) {
                        final path = widget.paths[index];
                        final isPageSelected = projectState.selectedBrowserPaths.contains(path);
                        final pageRotation = projectState.project.imageRotations[path] ?? 0;
                        final version = ref.watch(imageVersionProvider(path)); // Watch version

                        // If this is the current page AND editor is open, apply filter
                        final applyFilter = _showEditor && index == _currentIndex;

                        final transformationController = TransformationController();
                        
                        return Stack(
                          children: [
                            GestureDetector(
                              onTap: _toggleSelection,
                              onDoubleTap: _toggleEditor,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 150),
                                opacity: isPageSelected ? 0.3 : 1.0,
                                child: Center(
                                  child: RotatedBox(
                                    quarterTurns: pageRotation ~/ 90,
                                    child: CallbackShortcuts(
                                      bindings: {
                                         const SingleActivator(LogicalKeyboardKey.add): () {
                                            final updated = transformationController.value.clone();
                                            updated.scale(1.2);
                                            transformationController.value = updated;
                                         },
                                         const SingleActivator(LogicalKeyboardKey.numpadAdd): () {
                                            final updated = transformationController.value.clone();
                                            updated.scale(1.2);
                                            transformationController.value = updated;
                                         },
                                         const SingleActivator(LogicalKeyboardKey.minus): () {
                                            final updated = transformationController.value.clone();
                                            updated.scale(0.8);
                                            transformationController.value = updated;
                                         },
                                         const SingleActivator(LogicalKeyboardKey.numpadSubtract): () {
                                            final updated = transformationController.value.clone();
                                            updated.scale(0.8);
                                            transformationController.value = updated;
                                         },
                                      },
                                      child: Focus( // Focus required for local shortcuts
                                        autofocus: true,
                                        child: InteractiveViewer(
                                          transformationController: transformationController,
                                          minScale: 0.1,
                                          maxScale: 5.0,
                                          boundaryMargin: const EdgeInsets.all(double.infinity),
                                          child: applyFilter 
                                            ? ImageFiltered(
                                                imageFilter: ui.ImageFilter.blur(
                                                   sigmaX: (editorState.currentAdjustments.noiseReduction * 5) + (editorState.currentAdjustments.skinSmooth * 3),
                                                   sigmaY: (editorState.currentAdjustments.noiseReduction * 5) + (editorState.currentAdjustments.skinSmooth * 3),
                                                ),
                                                child: ColorFiltered(
                                                    colorFilter: ColorFilter.matrix(matrix),
                                                    child: Image.file(File(path), key: ValueKey('${path}_$version'), fit: BoxFit.contain, filterQuality: FilterQuality.high)
                                                )
                                              )
                                            : Image.file(File(path), key: ValueKey('${path}_$version'), fit: BoxFit.contain, filterQuality: FilterQuality.high),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            
                            // Zoom Hints
                            if (_showEditor)
                              Positioned(
                                bottom: 160, right: 20,
                                child: Column(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                         final updated = transformationController.value.clone();
                                         updated.scale(1.2);
                                         transformationController.value = updated;
                                      },
                                      icon: const Icon(Icons.add, color: Colors.white),
                                      tooltip: "Zoom In (+)",
                                      style: IconButton.styleFrom(backgroundColor: Colors.black26),
                                    ),
                                    const SizedBox(height: 8),
                                    IconButton(
                                      onPressed: () {
                                         final updated = transformationController.value.clone();
                                         updated.scale(0.8);
                                         transformationController.value = updated;
                                      },
                                      icon: const Icon(Icons.remove, color: Colors.white),
                                      tooltip: "Zoom Out (-)",
                                      style: IconButton.styleFrom(backgroundColor: Colors.black26),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                // HUD (Top Name)
                Positioned(
                  top: 40, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        "$name  •  ${_currentIndex + 1}/${widget.paths.length}",
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

                // Checkmark
                if (isSelected)
                  const Positioned(
                    top: 50, right: 80,
                    child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 48),
                  ),

                // Arrows
                if (_currentIndex > 0)
                   Positioned(left: 20, top: 0, bottom: 0, child: Center(child: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white54, size: 40), onPressed: _previousPage))),
                if (_currentIndex < widget.paths.length - 1)
                   Positioned(right: 20, top: 0, bottom: 0, child: Center(child: IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 40), onPressed: _nextPage))),

                // Close Button
                Positioned(
                  top: 40, right: 20,
                  child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
                ),

                // Bottom Toolbar (Rotation + Editor Toggle)
                Positioned(
                  bottom: 40, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.rotate_left, color: Colors.white), onPressed: () => _rotate(false)),
                          const SizedBox(width: 16),
                          IconButton(icon: const Icon(Icons.rotate_right, color: Colors.white), onPressed: () => _rotate(true)),
                          Container(height: 24, width: 1, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 16)),
                          IconButton(
                             icon: const Icon(Icons.tune, color: Colors.white),
                             onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ImageEditorView(
                                    paths: widget.paths,
                                    initialIndex: _currentIndex,
                                  ))
                                ).then((_) => setState(() {})); // Refresh on return
                             },
                             tooltip: "Abrir Editor Completo",
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                   // --- SCOPES LAYER ---
                   


                   // ... (Rest of children like HUD)
                 ],
               ),
             ),
 
             // EDITOR SIDEBAR (Conditioned)
             if (_showEditor)
               Container(
                width: 300,
                color: const Color(0xFF1E1E1E),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         const Text("Editor Inteligente", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                         IconButton(icon: const Icon(Icons.close, size: 16), onPressed: _toggleEditor),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Auto Magic
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.deepPurple,
                           foregroundColor: Colors.white,
                           padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: editorState.isProcessing 
                           ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                           : const Icon(Icons.auto_fix_high),
                        label: Text(editorState.isProcessing ? "..." : "Auto Ajuste"),
                        onPressed: editorState.isProcessing ? null : () async {
                           notifier.setProcessing(true);
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gemini: Analisando imagem...")));
                           try {
                              // 1. Native Auto-Enhance (Fast First)
                              final nativeSuggestions = await NativeAutoEnhance.analyze(currentPath);
                              if (nativeSuggestions.isNotEmpty) {
                                notification("Aplicando Ajuste Nativo...");
                                notifier.applySuggestions(nativeSuggestions);
                                
                                // Native Log
                                print("\n--- NATIVE AUTO ADJUSTMENTS ---");
                                nativeSuggestions.forEach((k, v) => print("$k: ${v.toStringAsFixed(3)}"));
                                print("-------------------------------\n");
                              }
 
                              // 2. Gemini Hybrid (Refinement)
                              final suggestions = await GeminiService.analyzeImage(currentPath);
                              if (suggestions.isNotEmpty && context.mounted) {
                                 // Merge or Overwrite? Usually AI is smarter, so overwrite some.
                                 // Or apply delta?
                                 // For now, let Gemini overwrite Native if Gemini succeeds.
                                 notifier.applySuggestions(suggestions);
                                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes Refinados por AI!")));
                                 
                                 // Gemini Log
                                 print("\n--- GEMINI AI ADJUSTMENTS ---");
                                 suggestions.forEach((k, v) => print("$k: ${v.toStringAsFixed(3)}"));
                                 print("-----------------------------\n");
                                 
                              }
                           } finally {
                              notifier.setProcessing(false);
                           }
                        },
                      ),
                    ),
                    
                    const Divider(height: 24, color: Colors.white24),
                    
                    Expanded(
                       child: ListView(
                        children: [
                           _buildSectionHeader("Luz"),
                           _buildSlider("Exposição", editorState.currentAdjustments.exposure, -1.0, 1.0, notifier.updateExposure),
                           _buildSlider("Contraste", editorState.currentAdjustments.contrast, 0.5, 2.0, notifier.updateContrast),
                           _buildSlider("Brilho", editorState.currentAdjustments.brightness, 0.5, 1.5, notifier.updateBrightness),
                           
                           _buildSectionHeader("Cor"),
                           _buildSlider("Saturação", editorState.currentAdjustments.saturation, 0.0, 2.0, notifier.updateSaturation),
                           _buildSlider("Temperatura", editorState.currentAdjustments.temperature, -1.0, 1.0, notifier.updateTemperature, 
                               colors: [Colors.blue, Colors.orange]),
                           _buildSlider("Tint", editorState.currentAdjustments.tint, -1.0, 1.0, notifier.updateTint,
                               colors: [Colors.green, Colors.purple]),
 
                           _buildSectionHeader("Detalhe"),
                           _buildSlider("Nitidez", editorState.currentAdjustments.sharpness, 0.0, 1.0, notifier.updateSharpness),
                           _buildSlider("Red. Ruído", editorState.currentAdjustments.noiseReduction, 0.0, 1.0, notifier.updateNoiseReduction),
                           _buildSlider("Suavizar Pele", editorState.currentAdjustments.skinSmooth, 0.0, 1.0, notifier.updateSkinSmooth),
                        ],
                      ),
                    ),
                    
                    // Save Button Stub
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: editorState.isProcessing ? null : () {
                           // Log Final User Changes before Save
                           print("\n--- FINAL USER/MANUAL ADJUSTMENTS ---");
                           print("Exposure: ${editorState.currentAdjustments.exposure}");
                           print("Contrast: ${editorState.currentAdjustments.contrast}");
                           print("Brightness: ${editorState.currentAdjustments.brightness}");
                           print("Saturation: ${editorState.currentAdjustments.saturation}");
                           print("Temperature: ${editorState.currentAdjustments.temperature}");
                           print("Tint: ${editorState.currentAdjustments.tint}");
                           print("-------------------------------------\n");
                           
                           _saveAdjustments(currentPath);
                        },
                        child: const Text("Salvar Alterações"),
                      )
                    ),
                  ],
                ),
             ),
             
          ],
        ),
      );
   }

   // Helper for snackbar
   void notification(String msg) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
   }

  Widget _buildSectionHeader(String title) {
     return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(title.toUpperCase(), style: const TextStyle(
           color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0
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
             Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
             Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 10, color: Colors.white30)),
           ],
         ),
         SizedBox(
           height: 24,
           child: SliderTheme(
             data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: colors?.last ?? Colors.white,
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
}
