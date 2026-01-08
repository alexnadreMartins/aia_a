import 'package:flutter_riverpod/flutter_riverpod.dart';

class ImageAdjustments {
  // Light
  final double exposure; // -1.0 to 1.0 (Impacts matrix)
  final double contrast; // 0.5 to 2.0 (1.0 = normal)
  final double brightness; // 0.5 to 1.5 (1.0 = normal)
  final double saturation; // 0.0 to 2.0 (1.0 = normal)
  
  // Color
  final double temperature; // -1.0 (Blue) to 1.0 (Orange)
  final double tint; // -1.0 (Green) to 1.0 (Magenta)
  
  // Detail
  final double sharpness; // 0.0 to 1.0
  final double noiseReduction; // 0.0 to 1.0
  final double skinSmooth; // 0.0 to 1.0

  const ImageAdjustments({
    this.exposure = 0.0,
    this.contrast = 1.0,
    this.brightness = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.sharpness = 0.0,
    this.noiseReduction = 0.0,
    this.skinSmooth = 0.0,
  });

  ImageAdjustments copyWith({
    double? exposure,
    double? contrast,
    double? brightness,
    double? saturation,
    double? temperature,
    double? tint,
    double? sharpness,
    double? noiseReduction,
    double? skinSmooth,
  }) {
    return ImageAdjustments(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      brightness: brightness ?? this.brightness,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      sharpness: sharpness ?? this.sharpness,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      skinSmooth: skinSmooth ?? this.skinSmooth,
    );
  }
}

class ImageEditorState {
  // Navigation & Selection
  final List<String> imagePaths;
  final int currentIndex;
  final Set<String> selectedPaths; // For batch operations
  final ImageAdjustments? clipboard; // Copied adjustments

  // Adjustments Cache (Path -> Adjustments)
  final Map<String, ImageAdjustments> allAdjustments;
  
  // Current View Shortcuts (Computed from currentIndex)
  ImageAdjustments get currentAdjustments {
    if (currentIndex < 0 || currentIndex >= imagePaths.length) return const ImageAdjustments();
    return allAdjustments[imagePaths[currentIndex]] ?? const ImageAdjustments();
  }

  String get currentPath {
    if (currentIndex < 0 || currentIndex >= imagePaths.length) return '';
    return imagePaths[currentIndex];
  }

  // Meta
  final bool isProcessing;
  final bool showOriginal; // For "Compare" feature

  const ImageEditorState({
    this.imagePaths = const [],
    this.currentIndex = -1,
    this.selectedPaths = const {},
    this.allAdjustments = const {},
    this.clipboard,
    this.isProcessing = false,
    this.showOriginal = false,
  });

  ImageEditorState copyWith({
    List<String>? imagePaths,
    int? currentIndex,
    Set<String>? selectedPaths,
    Map<String, ImageAdjustments>? allAdjustments,
    ImageAdjustments? clipboard,
    bool? isProcessing,
    bool? showOriginal,
  }) {
    return ImageEditorState(
      imagePaths: imagePaths ?? this.imagePaths,
      currentIndex: currentIndex ?? this.currentIndex,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      allAdjustments: allAdjustments ?? this.allAdjustments,
      clipboard: clipboard ?? this.clipboard,
      isProcessing: isProcessing ?? this.isProcessing,
      showOriginal: showOriginal ?? this.showOriginal,
    );
  }
}

class ImageEditorNotifier extends StateNotifier<ImageEditorState> {
  ImageEditorNotifier() : super(const ImageEditorState());

  void setImages(List<String> paths, int initialIndex) {
    state = const ImageEditorState().copyWith(
      imagePaths: paths,
      currentIndex: initialIndex,
      // Initialize empty adjustments for all paths if needed, or lazy load
    );
  }

  void selectImage(int index) {
    if (index < 0 || index >= state.imagePaths.length) return;
    state = state.copyWith(currentIndex: index);
  }

  void toggleSelection(String path, {bool forceSelect = false}) {
    final newSelection = Set<String>.from(state.selectedPaths);
    if (forceSelect) {
       newSelection.add(path);
    } else {
       if (newSelection.contains(path)) {
         newSelection.remove(path);
       } else {
         newSelection.add(path);
       }
    }
    state = state.copyWith(selectedPaths: newSelection);
  }

  void selectAll() {
    state = state.copyWith(selectedPaths: state.imagePaths.toSet());
  }
  
  void deselectAll() {
    state = state.copyWith(selectedPaths: {});
  }

  void resetAdjustments(String path) {
    final newMap = Map<String, ImageAdjustments>.from(state.allAdjustments);
    newMap.remove(path);
    state = state.copyWith(allAdjustments: newMap);
  }

  void _updateCurrent(ImageAdjustments newAdj) {
    final path = state.currentPath;
    if (path.isEmpty) return;
    
    final newMap = Map<String, ImageAdjustments>.from(state.allAdjustments);
    newMap[path] = newAdj;
    
    state = state.copyWith(allAdjustments: newMap);
  }

  void updateExposure(double v) => _updateCurrent(state.currentAdjustments.copyWith(exposure: v));
  void updateContrast(double v) => _updateCurrent(state.currentAdjustments.copyWith(contrast: v));
  void updateBrightness(double v) => _updateCurrent(state.currentAdjustments.copyWith(brightness: v));
  void updateSaturation(double v) => _updateCurrent(state.currentAdjustments.copyWith(saturation: v));
  void updateTemperature(double v) => _updateCurrent(state.currentAdjustments.copyWith(temperature: v));
  void updateTint(double v) => _updateCurrent(state.currentAdjustments.copyWith(tint: v));
  void updateSharpness(double v) => _updateCurrent(state.currentAdjustments.copyWith(sharpness: v));
  void updateNoiseReduction(double v) => _updateCurrent(state.currentAdjustments.copyWith(noiseReduction: v));
  void updateSkinSmooth(double v) => _updateCurrent(state.currentAdjustments.copyWith(skinSmooth: v));

  void toggleCompare(bool down) {
    state = state.copyWith(showOriginal: down);
  }

  void reset() {
    state = const ImageEditorState();
  }
  
  void setProcessing(bool v) {
    state = state.copyWith(isProcessing: v);
  }
  
  void syncAdjustments() {
     final source = state.currentAdjustments;
     final newMap = Map<String, ImageAdjustments>.from(state.allAdjustments);
     
     // Ensure current image is also updated in map if not already
     newMap[state.currentPath] = source;

     for (final path in state.selectedPaths) {
        newMap[path] = source;
     }
     state = state.copyWith(allAdjustments: newMap);
  }

  void copyAdjustments() {
    state = state.copyWith(clipboard: state.currentAdjustments);
  }

  void pasteAdjustments() {
    if (state.clipboard == null) return;
    final source = state.clipboard!;
    
    final newMap = Map<String, ImageAdjustments>.from(state.allAdjustments);
    
    // Valid targets: Selected paths OR current path if no selection
    final targets = state.selectedPaths.isNotEmpty ? state.selectedPaths : {state.currentPath};
    
    for (final path in targets) {
       newMap[path] = source;
    }
    
    state = state.copyWith(allAdjustments: newMap);
  }
  
  // Apply AI Suggestions (to be called by Gemini Service)
  void applySuggestions(Map<String, double> values) {
    // Mapping Gemini keys to our state keys
    var adj = state.currentAdjustments;
    
    if (values.containsKey('exposure')) adj = adj.copyWith(exposure: values['exposure']);
    if (values.containsKey('contrast')) adj = adj.copyWith(contrast: values['contrast']);
    if (values.containsKey('saturation')) adj = adj.copyWith(saturation: values['saturation']);
    if (values.containsKey('sharpness')) adj = adj.copyWith(sharpness: values['sharpness']);
    if (values.containsKey('brightness')) adj = adj.copyWith(brightness: values['brightness']);
    if (values.containsKey('temperature')) adj = adj.copyWith(temperature: values['temperature']);
    if (values.containsKey('tint')) adj = adj.copyWith(tint: values['tint']);
    if (values.containsKey('noiseReduction')) adj = adj.copyWith(noiseReduction: values['noiseReduction']);

    _updateCurrent(adj);
  }
}


final imageEditorProvider = StateNotifierProvider<ImageEditorNotifier, ImageEditorState>((ref) {
  return ImageEditorNotifier();
});
