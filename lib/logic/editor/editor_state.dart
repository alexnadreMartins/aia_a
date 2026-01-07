import 'package:flutter_riverpod/flutter_riverpod.dart';

class ImageEditorState {
  // Light
  final double exposure; // -1.0 to 1.0 (Impacts matrix)
  final double contrast; // 0.5 to 2.0 (1.0 = normal)
  final double brightness; // 0.5 to 1.5 (1.0 = normal)
  final double saturation; // 0.0 to 2.0 (1.0 = normal)
  
  // Color
  final double temperature; // -1.0 (Blue) to 1.0 (Orange)
  final double tint; // -1.0 (Green) to 1.0 (Magenta)
  
  // Detail (Applied on Save/Preview, not real-time matrix usually)
  final double sharpness; // 0.0 to 1.0
  final double noiseReduction; // 0.0 to 1.0
  final double skinSmooth; // 0.0 to 1.0 (Smart Blur)
  
  // Meta
  final bool isProcessing;
  final String? originalPath;
  final bool showOriginal; // For "Compare" feature

  const ImageEditorState({
    this.exposure = 0.0,
    this.contrast = 1.0,
    this.brightness = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.sharpness = 0.0,
    this.noiseReduction = 0.0,
    this.skinSmooth = 0.0,
    this.isProcessing = false,
    this.originalPath,
    this.showOriginal = false,
  });

  ImageEditorState copyWith({
    double? exposure,
    double? contrast,
    double? brightness,
    double? saturation,
    double? temperature,
    double? tint,
    double? sharpness,
    double? noiseReduction,
    double? skinSmooth,
    bool? isProcessing,
    String? originalPath,
    bool? showOriginal,
  }) {
    return ImageEditorState(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      brightness: brightness ?? this.brightness,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      sharpness: sharpness ?? this.sharpness,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      skinSmooth: skinSmooth ?? this.skinSmooth,
      isProcessing: isProcessing ?? this.isProcessing,
      originalPath: originalPath ?? this.originalPath,
      showOriginal: showOriginal ?? this.showOriginal,
    );
  }
}

class ImageEditorNotifier extends StateNotifier<ImageEditorState> {
  ImageEditorNotifier() : super(const ImageEditorState());

  void setPath(String path) {
    state = state.copyWith(originalPath: path);
  }

  void updateExposure(double v) => state = state.copyWith(exposure: v);
  void updateContrast(double v) => state = state.copyWith(contrast: v);
  void updateBrightness(double v) => state = state.copyWith(brightness: v);
  void updateSaturation(double v) => state = state.copyWith(saturation: v);
  void updateTemperature(double v) => state = state.copyWith(temperature: v);
  void updateTint(double v) => state = state.copyWith(tint: v);
  void updateSharpness(double v) => state = state.copyWith(sharpness: v);
  void updateNoiseReduction(double v) => state = state.copyWith(noiseReduction: v);
  void updateSkinSmooth(double v) => state = state.copyWith(skinSmooth: v);

  void toggleCompare(bool down) {
    state = state.copyWith(showOriginal: down);
  }

  void reset() {
    state = const ImageEditorState();
  }
  
  void setProcessing(bool v) {
    state = state.copyWith(isProcessing: v);
  }
  
  // Apply AI Suggestions (to be called by Gemini Service)
  void applySuggestions(Map<String, double> values) {
    state = state.copyWith(
       exposure: values['exposure'] ?? state.exposure,
       contrast: values['contrast'] ?? state.contrast,
       brightness: values['brightness'] ?? state.brightness,
       saturation: values['saturation'] ?? state.saturation,
       sharpness: values['sharpness'] ?? state.sharpness,
       noiseReduction: values['noiseReduction'] ?? state.noiseReduction,
       skinSmooth: values['skinSmooth'] ?? state.skinSmooth,
       // Temp/Tint might be complex to map from generic prediction, keep 0 for now unless specific
    );
  }
}

final imageEditorProvider = StateNotifierProvider<ImageEditorNotifier, ImageEditorState>((ref) {
  return ImageEditorNotifier();
});
