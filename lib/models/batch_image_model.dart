import '../logic/editor/editor_state.dart';

class BatchImage {
  final String path;
  final DateTime? dateCaptured;
  final String? cameraModel;
  final double? brightness; // 0.0 to 1.0 (Approximate)
  final ImageAdjustments? adjustments;

  BatchImage({
    required this.path,
    this.dateCaptured,
    this.cameraModel,
    this.brightness,
    this.adjustments,
  });

  BatchImage copyWith({
    String? path,
    DateTime? dateCaptured,
    String? cameraModel,
    double? brightness,
    ImageAdjustments? adjustments,
  }) {
    return BatchImage(
      path: path ?? this.path,
      dateCaptured: dateCaptured ?? this.dateCaptured,
      cameraModel: cameraModel ?? this.cameraModel,
      brightness: brightness ?? this.brightness,
      adjustments: adjustments ?? this.adjustments,
    );
  }
}
