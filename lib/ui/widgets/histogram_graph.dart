
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../logic/editor/editor_state.dart';

class HistogramWidget extends StatefulWidget {
  final String imagePath;
  final double width;
  final double height;
  final ImageEditorState? editorState;

  const HistogramWidget({
    super.key,
    required this.imagePath,
    this.width = 150,
    this.height = 80,
    this.editorState,
  });

  @override
  State<HistogramWidget> createState() => _HistogramWidgetState();
}

class _HistogramWidgetState extends State<HistogramWidget> {
  List<int>? _reds;
  List<int>? _greens;
  List<int>? _blues;
  List<int>? _luminance;
  bool _loading = false;
  String? _lastPath;
  double _zoomLevel = 1.0; // Zoom functionality

  @override
  void didUpdateWidget(covariant HistogramWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath || oldWidget.editorState != widget.editorState) {
      _loadHistogram();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHistogram();
  }

  Future<void> _loadHistogram() async {
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
      final result = await compute(_computeHistogram, args);
      if (mounted) {
        setState(() {
          _reds = result['r'];
          _greens = result['g'];
          _blues = result['b'];
          _luminance = result['l'];
          _loading = false;
        });
      }
    } catch (e) {
      print("Histogram Error: $e");
    }
  }

  static Map<String, List<int>> _computeHistogram(Map<String, dynamic> args) {
    final path = args['path'] as String;
    final file = File(path);
    if (!file.existsSync()) return {};

    final bytes = file.readAsBytesSync();
    var image = img.decodeImage(bytes);
    if (image == null) return {};

    // 1. Resize for Performance
    image = img.copyResize(image, width: 256);

    // 2. APPLY EDITOR STATE (Simulate)
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

    final rList = List.filled(256, 0);
    final gList = List.filled(256, 0);
    final bList = List.filled(256, 0);
    final lList = List.filled(256, 0);

    for (final p in image) {
      rList[p.r.toInt().clamp(0, 255)]++;
      gList[p.g.toInt().clamp(0, 255)]++;
      bList[p.b.toInt().clamp(0, 255)]++;
      lList[p.luminanceNormalized.toInt().clamp(0, 255)]++;
    }

    return {'r': rList, 'g': gList, 'b': bList, 'l': lList};
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
        return const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)));
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Graph (Expanded)
        Expanded(
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: CustomPaint(
              size: Size.infinite,
              painter: _HistogramPainter(_reds, _greens, _blues, _luminance, _zoomLevel),
            ),
          ),
        ),
        
        // 2. Ruler (Precise 0..255)
        SizedBox(
          height: 20,
          child: CustomPaint(
            size: Size.infinite,
            painter: _HistogramRulerPainter(),
          ),
        ),

        // 3. Zoom Controls (Bottom Row)
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 0),
          color: Colors.black26,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               const Text("Zoom Vertical: ", style: TextStyle(color: Colors.white70, fontSize: 10)),
               IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.white),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() { if (_zoomLevel > 1) _zoomLevel -= 1; })
               ),
               Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 8.0),
                 child: Text("x${_zoomLevel.toInt()}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
               ),
               IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 16, color: Colors.white),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _zoomLevel += 1)
               ),
            ],
          ),
        )
      ],
    );
  }
}

class _HistogramRulerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    
    // Line
    final paintLine = Paint()..color = Colors.white30..strokeWidth = 1;
    canvas.drawLine(Offset(0, 0), Offset(w, 0), paintLine);
    
    // Markers to draw
    // Value, Color, Height, Label
    final markers = [
      (0, Colors.red, 1.0, "0"),
      (5, Colors.yellow, 0.8, "5"),
      (128, Colors.white54, 0.5, "128"),
      (250, Colors.yellow, 0.8, "250"),
      (252, Colors.yellow, 0.6, "252"),
      (255, Colors.red, 1.0, "255"),
    ];

    for (final m in markers) {
      final val = m.$1;
      final color = m.$2;
      final heightFactor = m.$3;
      final label = m.$4;
      
      final x = (val / 255.0) * w;
      
      // Tick
      final paintTick = Paint()..color = color..strokeWidth = 1.5;
      final tickH = h * 0.5 * heightFactor;
      canvas.drawLine(Offset(x, 0), Offset(x, tickH), paintTick);
      
      // Label
      if (label.isNotEmpty) {
        final textSpan = TextSpan(
          text: label,
          style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.bold),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        // Adjust text position to center on tick, ensure not out of bounds
        double dx = x - (textPainter.width / 2);
        if (dx < 0) dx = 0;
        if (dx + textPainter.width > w) dx = w - textPainter.width;
        
        textPainter.paint(canvas, Offset(dx, tickH + 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HistogramPainter extends CustomPainter {
  final List<int>? r, g, b, l;
  final double zoom;
  
  _HistogramPainter(this.r, this.g, this.b, this.l, this.zoom);

  @override
  void paint(Canvas canvas, Size size) {
    if (r == null) return;
    
    final maxCount = [
      ...(r ?? []), 
      ...(g ?? []), 
      ...(b ?? []),
    ].reduce((a, b) => a > b ? a : b);
    
    if (maxCount == 0) return;

    final double w = size.width;
    final double h = size.height;
    final double stepX = w / 255;

    // Helper to create path with Zoom
    Path createPath(List<int> data) {
       final path = Path();
       path.moveTo(0, h);
       for (int i = 0; i < 256; i++) {
          final x = i * stepX;
          // Apply Zoom to Height
          var valueHeight = (data[i] / maxCount * h) * zoom;
          // Clamp to avoid drawing way outside (although clips usually handle it)
          if (valueHeight > h) valueHeight = h;
          
          final y = h - valueHeight;
          path.lineTo(x, y);
       }
       path.lineTo(w, h);
       path.close();
       return path;
    }

    // Colors: Standard blending or srcOver for visibility
    // Using simple opacity to see overlaps
    final paintR = Paint()..color = Colors.red.withOpacity(0.6)..style = PaintingStyle.fill;
    final paintG = Paint()..color = Colors.green.withOpacity(0.6)..style = PaintingStyle.fill;
    final paintB = Paint()..color = Colors.blue.withOpacity(0.6)..style = PaintingStyle.fill;
    
    // Draw Filled Paths (Painter's algorithm: draw one over another)
    // To see all, we rely on opacity.
    canvas.drawPath(createPath(r!), paintR);
    canvas.drawPath(createPath(g!), paintG);
    canvas.drawPath(createPath(b!), paintB);
    
    // Luminance Line (Guide)
    final paintLLine = Paint()..color = Colors.white.withOpacity(0.9)..style = PaintingStyle.stroke..strokeWidth = 1.0;
    
    final pathL = Path();
    bool first = true;
    for (int i = 0; i < 256; i++) {
        final x = i * stepX;
        var valueHeight = (l![i] / maxCount * h) * zoom;
        if (valueHeight > h) valueHeight = h;
        final y = h - valueHeight;
        
        if (first) {
            pathL.moveTo(x,y); 
            first = false;
        } else {
            pathL.lineTo(x, y);
        }
    }
    canvas.drawPath(pathL, paintLLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
