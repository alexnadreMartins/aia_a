import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/editor/editor_state.dart';
import '../../logic/editor/color_matrix_helper.dart';
import '../../logic/editor/gemini_service.dart';

class ImageEditorView extends ConsumerStatefulWidget {
  final String imagePath;
  const ImageEditorView({super.key, required this.imagePath});

  @override
  ConsumerState<ImageEditorView> createState() => _ImageEditorViewState();
}

class _ImageEditorViewState extends ConsumerState<ImageEditorView> {
  
  @override
  void initState() {
    super.initState();
    // Reset state and set path on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(imageEditorProvider.notifier).reset();
      ref.read(imageEditorProvider.notifier).setPath(widget.imagePath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageEditorProvider);
    final notifier = ref.read(imageEditorProvider.notifier);
    
    // Calculate Matrix
    final matrix = ColorMatrixHelper.getMatrix(
       exposure: state.exposure,
       contrast: state.contrast,
       brightness: state.brightness,
       saturation: state.saturation,
       temperature: state.temperature,
       tint: state.tint
    );

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Editor Inteligente"),
        backgroundColor: const Color(0xFF1E1E1E),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
             icon: const Icon(Icons.save, color: Colors.blueAccent),
             label: const Text("Salvar", style: TextStyle(color: Colors.blueAccent)),
             onPressed: () {
                // TODO: Save Logic
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Salvando (Demo)...")));
                Navigator.pop(context);
             },
          ),
        ],
      ),
      body: Row(
        children: [
          // CANVA
          Expanded(
            child: InteractiveViewer(
               maxScale: 5.0,
               minScale: 0.1,
               child: Center(
                 child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(matrix),
                    child: Image.file(File(widget.imagePath)),
                 ),
               ),
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
                     label: Text(state.isProcessing ? "Analisando..." : "Auto AI Enhance"),


                     onPressed: state.isProcessing ? null : () async {
                        notifier.setProcessing(true);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gemini: Analisando imagem...")));
                        
                        try {
                           final suggestions = await GeminiService.analyzeImage(widget.imagePath);
                           if (suggestions.isNotEmpty && context.mounted) {
                              notifier.applySuggestions(suggestions);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajustes Inteligentes Aplicados!")));
                           } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Falha na análise.")));
                           }
                        } finally {
                           notifier.setProcessing(false);
                        }
                     },
                   ),
                 ),
                 
                 const Divider(height: 32, color: Colors.white24),
                 
                 Expanded(
                   child: ListView(
                     children: [
                        _buildSectionHeader("Luz"),
                        _buildSlider("Exposição", state.exposure, -1.0, 1.0, notifier.updateExposure),
                        _buildSlider("Contraste", state.contrast, 0.5, 2.0, notifier.updateContrast),
                        _buildSlider("Brilho (Offset)", state.brightness, 0.5, 1.5, notifier.updateBrightness),
                        
                        _buildSectionHeader("Cor"),
                        _buildSlider("Saturação", state.saturation, 0.0, 2.0, notifier.updateSaturation),
                        _buildSlider("Temperatura", state.temperature, -1.0, 1.0, notifier.updateTemperature, 
                            colors: [Colors.blue, Colors.orange]),
                        _buildSlider("Tint", state.tint, -1.0, 1.0, notifier.updateTint,
                            colors: [Colors.green, Colors.purple]),

                        _buildSectionHeader("Detalhe (Lento)"),
                        _buildSlider("Nitidez", state.sharpness, 0.0, 1.0, notifier.updateSharpness),
                        _buildSlider("Red. Ruído", state.noiseReduction, 0.0, 1.0, notifier.updateNoiseReduction),
                        _buildSlider("Suavizar Pele", state.skinSmooth, 0.0, 1.0, notifier.updateSkinSmooth),
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
    );
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
}
