
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../logic/editor/editor_state.dart';

class VectorscopeWidget extends StatefulWidget {
  final String imagePath;
  final double size; // Square format
  final ImageEditorState? editorState;

  const VectorscopeWidget({
    super.key,
    required this.imagePath,
    this.size = 200,
    this.editorState,
  });

  @override
  State<VectorscopeWidget> createState() => _VectorscopeWidgetState();
}

class _VectorscopeWidgetState extends State<VectorscopeWidget> {
  Float32List? _points; 
  bool _loading = false;
  String? _lastPath;

  @override
  void didUpdateWidget(covariant VectorscopeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath || oldWidget.editorState != widget.editorState) {
      _loadVectorscope();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadVectorscope();
  }

  Future<void> _loadVectorscope() async {
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
      final points = await compute(_computeVectorscope, args);
      if (mounted) {
        setState(() {
          _points = points;
          _loading = false;
        });
      }
    } catch (e) {
      print("Vectorscope Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  static Float32List _computeVectorscope(Map<String, dynamic> args) {
    final path = args['path'] as String;
    final file = File(path);
    if (!file.existsSync()) return Float32List(0);

    final bytes = file.readAsBytesSync();
    var image = img.decodeImage(bytes);
    if (image == null) return Float32List(0);

    // Resize
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
    
    final pointsList = <double>[];
    const cx = 128.0;
    const cy = 128.0;
    
    for (final p in image) {
       final r = p.rNormalized.toDouble();
       final g = p.gNormalized.toDouble();
       final b = p.bNormalized.toDouble();
       
       final maxC = max(r, max(g, b));
       final minC = min(r, min(g, b));
       final delta = maxC - minC;
       
       double h = 0;
       double s = 0;
       
       if (delta != 0) {
          s = (maxC + minC) > 1 ? delta / (2 - maxC - minC) : delta / (maxC + minC);
          if (maxC == r) {
             h = (g - b) / delta + (g < b ? 6 : 0);
          } else if (maxC == g) {
             h = (b - r) / delta + 2;
          } else {
             h = (r - g) / delta + 4;
          }
          h /= 6;
       }
       
       if (s < 0.05) continue; 
       
       final angle = h * 2 * pi;
       final radius = s * 110.0; // Scaled to fit 
       
       // Correct rotation for standard vectorscope (Red at top/marker?)
       // Our helper draws Red at 0 deg (Right). 
       // Color wheel math: 0 is Right. 
       // So no rotation needed if markers follow math.
       
       final x = cx + radius * cos(angle);
       final y = cy + radius * sin(angle);
       
       pointsList.add(x);
       pointsList.add(y);
    }
    
    return Float32List.fromList(pointsList);
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)))
        : CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _VectorscopePainter(_points),
          );
  }
}

class _VectorscopePainter extends CustomPainter {
  final Float32List? points;
  _VectorscopePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Calculate safe square area
    final side = min(size.width, size.height);
    
    // 2. Center of the widget
    final cx = size.width / 2;
    final cy = size.height / 2;
    
    // 3. Grid Radius (Fit to side)
    // side is diameter, so radius is side/2. 
    // Add padding? 
    final radius = (side / 2) * 0.9; 

    // Draw Reticule (Grid)
    _drawReticule(canvas, cx, cy, radius);

    if (points == null || points!.isEmpty) return;
    
    // 4. Transform Logic for Points
    // Points are generated in 256x256 logic (Center 128,128).
    // We need to map [0..256] -> [DrawArea]
    // The "radius" in the 256 logic was ~110-128.
    // If logic radius is ~127 (max), and visual radius is 'radius',
    // Scale factor = radius / 127.0 ?
    // In _computeVectorscope, max radius is ~110. (s * 110). 
    // And center is 128.
    
    // Let's rely on mapping the 256 box to the visual box.
    // Visual Box is centered at cx,cy with size 'side'.
    // Scale = side / 256.0.
    final scale = side / 256.0;

    canvas.save();
    
    // Translate to center first? 
    // The points are in 0..256. 
    // We want 128,128 (center of points) to land on cx,cy.
    // So shift by (cx - 128*scale, cy - 128*scale).
    final tx = cx - (128.0 * scale);
    final ty = cy - (128.0 * scale);
    
    canvas.translate(tx, ty);
    canvas.scale(scale, scale);

    // Draw content points
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15) // White density cloud
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
      
    canvas.drawRawPoints(PointMode.points, points!, paint);
    
    canvas.restore();
  }
  
  void _drawReticule(Canvas canvas, double cx, double cy, double radius) {
     final paintRing = Paint()..color = Colors.white24..style = PaintingStyle.stroke;
     final paintLine = Paint()..color = Colors.white12..style = PaintingStyle.stroke;
     
     canvas.drawCircle(Offset(cx, cy), radius, paintRing);
     canvas.drawCircle(Offset(cx, cy), radius * 0.75, paintLine); // 75% Saturation
     canvas.drawCircle(Offset(cx, cy), radius * 0.50, paintLine); // 50%
     
     // Color Makers
     _drawColorMarker(canvas, cx, cy, radius, 0, Colors.red);
     _drawColorMarker(canvas, cx, cy, radius, 120, Colors.green);
     _drawColorMarker(canvas, cx, cy, radius, 240, Colors.blue);
     _drawColorMarker(canvas, cx, cy, radius, 60, Colors.yellow);
     _drawColorMarker(canvas, cx, cy, radius, 180, Colors.cyan);
     _drawColorMarker(canvas, cx, cy, radius, 300, const Color(0xFFFF00FF));
  }
  
  void _drawColorMarker(Canvas canvas, double cx, double cy, double radius, double hue, Color color) {
      final angle = (hue * (pi / 180.0)) - (pi / 2);
      final x = cx + (radius * 0.8) * cos(angle);
      final y = cy + (radius * 0.8) * sin(angle);
      
      final paint = Paint()..color = color.withOpacity(0.8)..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 4, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
