
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../logic/editor/editor_state.dart';

class WaveformWidget extends StatefulWidget {
  final String imagePath;
  final double width;
  final double height;
  final ImageEditorState? editorState;

  const WaveformWidget({
    super.key,
    required this.imagePath,
    this.width = 260,
    this.height = 140,
    this.editorState,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget> {
  // Store points: List of offsets and their alpha
  Float32List? _points; 
  bool _loading = false;
  String? _lastPath;

  @override
  void didUpdateWidget(covariant WaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath || oldWidget.editorState != widget.editorState) {
      _loadWaveform();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  Future<void> _loadWaveform() async {
    bool newFile = _lastPath != widget.imagePath;
    _lastPath = widget.imagePath;

    if (newFile) setState(() => _loading = true);

    final args = {
       'path': widget.imagePath,
       'exposure': widget.editorState?.currentAdjustments.exposure ?? 0.0,
       'contrast': widget.editorState?.currentAdjustments.contrast ?? 1.0,
       'brightness': widget.editorState?.currentAdjustments.brightness ?? 1.0, 
       'saturation': widget.editorState?.currentAdjustments.saturation ?? 1.0,
       'temperature': widget.editorState?.currentAdjustments.temperature ?? 0.0,
       'tint': widget.editorState?.currentAdjustments.tint ?? 0.0,
    };

    try {
      final points = await compute(_computeWaveform, args);
      if (mounted) {
        setState(() {
          _points = points;
          _loading = false;
        });
      }
    } catch (e) {
      print("Waveform Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  static Float32List _computeWaveform(Map<String, dynamic> args) {
    final path = args['path'] as String;
    final file = File(path);
    if (!file.existsSync()) return Float32List(0);

    final bytes = file.readAsBytesSync();
    var image = img.decodeImage(bytes);
    if (image == null) return Float32List(0);

    // Resize for Scope Width
    image = img.copyResize(image, width: 256, height: 256);
    
    // APPLY EDITOR STATE (Simulate)
    final double exposure = (args['exposure'] as num).toDouble();
    final double contrast = (args['contrast'] as num).toDouble();
    final double brightness = (args['brightness'] as num).toDouble();
    final double saturation = (args['saturation'] as num).toDouble();
    final double temperature = (args['temperature'] as num).toDouble();
    final double tint = (args['tint'] as num).toDouble();
    
    final expMult = pow(2, exposure).toDouble();
    
    for (final p in image) {
       double r = p.r.toDouble();
       double g = p.g.toDouble();
       double b = p.b.toDouble();
       
       if (brightness != 1.0) { r *= brightness; g *= brightness; b *= brightness; }
       if (exposure != 0.0) { r *= expMult; g *= expMult; b *= expMult; }
       if (contrast != 1.0) {
          r = (r - 128.0) * contrast + 128.0;
          g = (g - 128.0) * contrast + 128.0;
          b = (b - 128.0) * contrast + 128.0;
       }
       if (saturation != 1.0) {
          final gray = 0.299 * r + 0.587 * g + 0.114 * b;
          r = gray + saturation * (r - gray);
          g = gray + saturation * (g - gray);
          b = gray + saturation * (b - gray);
       }
       if (temperature != 0.0) {
           if (temperature > 0) { r += temperature * 50; b -= temperature * 50; } 
           else { r += temperature * 50; b -= temperature * 50; }
       }
       if (tint != 0.0) {
           if (tint > 0) g -= tint * 50; else g -= tint * 50;
       }
       
       p.r = r.clamp(0, 255);
       p.g = g.clamp(0, 255);
       p.b = b.clamp(0, 255);
    }
    
    // Grid: [x][luminance]
    final grid = List.generate(256, (_) => List.filled(256, 0));
    
    for (final p in image) {
       final x = p.x; 
       final l = p.luminanceNormalized.toInt(); 
       if (x < 256 && l < 256) {
          grid[x][l]++;
       }
    }
    
    final pointsList = <double>[];
    
    // Density limit for display optimization
    // Only plot points that have meaningful density
    for (int x = 0; x < 256; x++) {
       for (int y = 0; y < 256; y++) {
          final count = grid[x][y];
          if (count > 0) {
             final drawY = 255.0 - y.toDouble();
             
             // Visual Density Trick:
             // If count is high, draw it multiple times slightly offset? 
             // Or just let opacity handle it.
             pointsList.add(x.toDouble());
             pointsList.add(drawY);
             
             // Extra points for thickness if high count
             if (count > 5) {
                pointsList.add(x.toDouble());
                pointsList.add(drawY - 0.5);
             }
          }
       }
    }
    
    return Float32List.fromList(pointsList);
  }

  @override
  Widget build(BuildContext context) {
    return _loading && _points == null
        ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)))
        : CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _WaveformPainter(_points),
          );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List? points;
  _WaveformPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points == null || points!.isEmpty) return;

    final scaleX = size.width / 256.0;
    final scaleY = size.height / 256.0; 
    
    canvas.save();
    canvas.scale(scaleX, scaleY);

    // Thicker, Brighter Green (Davinci)
    final paint = Paint()
      ..color = const Color(0xFF00FF00).withOpacity(0.15) // Brighter Green
      ..strokeWidth = 1.5 // Thicker points
      ..strokeCap = StrokeCap.round;
      
    canvas.drawRawPoints(PointMode.points, points!, paint);
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
