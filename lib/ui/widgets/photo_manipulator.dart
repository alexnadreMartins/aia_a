import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/project_model.dart';
import '../../logic/image_loader.dart';

class PhotoManipulator extends StatefulWidget {
  final PhotoItem photo;
  final bool isSelected;
  final Function(PhotoItem) onUpdate;
  final VoidCallback onSelect;
  final VoidCallback onDragEnd;
  // Context Actions - REMOVED IN THIS UPDATE
  // final VoidCallback? onDelete;
  // final VoidCallback? onDuplicate;
  // final VoidCallback? onBringToFront;
  // final VoidCallback? onSendToBack;
  final bool isEditingContent;
  final VoidCallback? onDoubleTap;
  final int globalRotation;
  final Function(Offset)? onContextMenu;
  final bool isExporting; // NEW

  const PhotoManipulator({
    super.key,
    required this.photo,
    required this.isSelected,
    required this.onUpdate,
    required this.onSelect,
    required this.onDragEnd,
    this.isEditingContent = false,
    this.onDoubleTap,
    this.globalRotation = 0,
    this.onContextMenu,
    this.isExporting = false, // NEW
  });

  @override
  State<PhotoManipulator> createState() => _PhotoManipulatorState();
}

class _PhotoManipulatorState extends State<PhotoManipulator> {
  ui.Image? _uiImage;
  String? _lastPath;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(PhotoManipulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photo.path != _lastPath) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.photo.path.isEmpty) {
      if (mounted) setState(() => _uiImage = null);
      return;
    }
    try {
      final img = await ImageLoader.loadImage(widget.photo.path);
      if (mounted) {
        setState(() {
          _uiImage = img;
          _lastPath = widget.photo.path;
        });
      }
    } catch (e) {
      debugPrint("Error loading image: $e");
    }
  }

  // --- Interaction State ---
  Alignment? _activeHandle;
  bool _isMoving = false;

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final angle = photo.rotation * (math.pi / 180);

    return Positioned(
      left: photo.x,
      top: photo.y,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.topLeft,
        child: AnimatedScale(
          scale: _isMoving ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: GestureDetector(
          onTap: widget.onSelect,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapDown: (details) {
            if (widget.onContextMenu != null) {
              widget.onContextMenu!(details.localPosition);
            }
          },
            onPanStart: (details) {
              if (!widget.isSelected || widget.isEditingContent) return;
              // Hit test handles manually
              final localPos = details.localPosition;
              _activeHandle = _hitTestHandles(localPos, Size(photo.width, photo.height));
              if (_activeHandle == null) {
                setState(() => _isMoving = true);
              }
            },
          onPanUpdate: (details) {
            if (widget.isEditingContent) {
              // Pan Image Inside Frame
              final dAlignX = details.delta.dx / (photo.width / 2);
              final dAlignY = details.delta.dy / (photo.height / 2);
              widget.onUpdate(photo.copyWith(
                contentX: (photo.contentX - dAlignX).clamp(-5.0, 5.0),
                contentY: (photo.contentY - dAlignY).clamp(-5.0, 5.0),
              ));
            } else if (_activeHandle == const Alignment(0, -2)) {
              // Rotate Frame
              final center = Offset(photo.width / 2, photo.height / 2);
              final currentPos = details.localPosition;
              final angle = math.atan2(currentPos.dy - center.dy, currentPos.dx - center.dx);
              // convert to degrees and add 90 because handle is at top
              double deg = angle * (180 / math.pi) + 90;
              widget.onUpdate(photo.copyWith(rotation: deg % 360));
            } else if (_activeHandle != null) {
              // Resize Frame
              _handleResize(photo, details.delta, _activeHandle!, _isCorner(_activeHandle!));
            } else if (widget.isSelected) {
              // Move Frame
              // We need to rotate the local delta back to global page coordinates 
              // because the GestureDetector is inside Transform.rotate
              final globalDelta = _rotateVector(details.delta, angle);
              widget.onUpdate(photo.copyWith(
                x: photo.x + globalDelta.dx,
                y: photo.y + globalDelta.dy,
              ));
            }
          },
            onPanEnd: (_) {
              _activeHandle = null;
              if (_isMoving) {
                setState(() => _isMoving = false);
              }
              widget.onDragEnd();
            },
          child: CustomPaint(
            size: Size(photo.width, photo.height),
            painter: PhotoPainter(
              image: _uiImage,
              photo: photo,
              isSelected: widget.isSelected,
              isEditingContent: widget.isEditingContent,
              globalRotation: widget.globalRotation,
              isExporting: widget.isExporting, // NEW
            ),
          ),
          ),
        ),
      ),
    );
  }

  bool _isCorner(Alignment align) => align.x != 0 && align.y != 0;

  Alignment? _hitTestHandles(Offset pos, Size size) {
    const double threshold = 25.0; // Large grab area
    final handles = [
      const Alignment(-1, -1), const Alignment(1, -1),
      const Alignment(-1, 1), const Alignment(1, 1),
      const Alignment(0, -1), const Alignment(0, 1),
      const Alignment(-1, 0), const Alignment(1, 0),
    ];

    for (var align in handles) {
      final hPos = _getHandleOffset(align, size);
      if ((pos - hPos).distance < threshold) return align;
    }
    // Check rotation handle
    final rotPos = Offset(size.width / 2, -30);
    if ((pos - rotPos).distance < threshold) return const Alignment(0, -2); // Special value for rotation

    return null;
  }

  Offset _getHandleOffset(Alignment align, Size size) {
    return Offset(
      (align.x + 1) / 2 * size.width,
      (align.y + 1) / 2 * size.height,
    );
  }

  // Reuse the stable rotation-aware resize logic
  void _handleResize(PhotoItem photo, Offset globalDelta, Alignment alignment, bool keepAspect) {
    final angle = photo.rotation * (math.pi / 180);
    final localDelta = _rotateVector(globalDelta, -angle);

    double newX = photo.x;
    double newY = photo.y;
    double newW = photo.width;
    double newH = photo.height;

    double dW = 0, dH = 0, dX = 0, dY = 0;

    if (alignment.x == -1) { dW = -localDelta.dx; dX = localDelta.dx; }
    else if (alignment.x == 1) { dW = localDelta.dx; }

    if (alignment.y == -1) { dH = -localDelta.dy; dY = localDelta.dy; }
    else if (alignment.y == 1) { dH = localDelta.dy; }

    if (keepAspect && photo.height != 0) {
      final aspectRatio = photo.width / photo.height;
      if (dW.abs() > dH.abs()) {
        double targetH = (newW + dW) / aspectRatio;
        double hChange = targetH - newH;
        dH = hChange;
        if (alignment.y == -1) dY = -hChange;
      } else {
        double targetW = (newH + dH) * aspectRatio;
        double wChange = targetW - newW;
        dW = wChange;
        if (alignment.x == -1) dX = -wChange;
      }
    }

    newW += dW;
    newH += dH;
    if (newW < 20) newW = 20;
    if (newH < 20) newH = 20;

    if (newW >= 20 && newH >= 20) {
      final globalShift = _rotateVector(Offset(dX, dY), angle);
      newX += globalShift.dx;
      newY += globalShift.dy;
      widget.onUpdate(photo.copyWith(x: newX, y: newY, width: newW, height: newH));
    }
  }

  Offset _rotateVector(Offset vector, double angleRad) {
    return Offset(
      vector.dx * math.cos(angleRad) - vector.dy * math.sin(angleRad),
      vector.dx * math.sin(angleRad) + vector.dy * math.cos(angleRad),
    );
  }
}

class PhotoPainter extends CustomPainter {
  final ui.Image? image;
  final PhotoItem photo;
  final bool isSelected;
  final bool isEditingContent;
  final int globalRotation;
  final bool isExporting; // NEW

  PhotoPainter({
    required this.image,
    required this.photo,
    required this.isSelected,
    required this.isEditingContent,
    this.globalRotation = 0,
    this.isExporting = false, // NEW
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    // Check if this is a text label
    if (photo.isText) {
      // Draw white background
      paint.color = Colors.white;
      canvas.drawRect(Offset.zero & size, paint);
      
      // Draw text
      if (photo.text != null && photo.text!.isNotEmpty) {
        // Auto-adjust font size to fit within label bounds (single line)
        double fontSize = 10.0;
        TextPainter? textPainter;
        
        // Try decreasing font sizes until text fits in one line
        while (fontSize >= 4.0) {
          textPainter = TextPainter(
            text: TextSpan(
              text: photo.text,
              style: TextStyle(
                color: Colors.black,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            maxLines: 1, // Force single line
          );
          textPainter.layout(maxWidth: size.width - 4);
          
          // Check if text fits within both width and height
          if (textPainter.width <= size.width - 4 && textPainter.height <= size.height - 4) {
            break;
          }
          fontSize -= 0.5;
        }
        
        if (textPainter != null) {
          textPainter.paint(
            canvas,
            Offset((size.width - textPainter.width) / 2, (size.height - textPainter.height) / 2),
          );
        }
      }
      
      // Border for label - ONLY IF NOT EXPORTING
      if (isSelected && !isExporting) {
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 1.5;
        paint.color = Colors.blue;
        canvas.drawRect(Offset.zero & size, paint);
      }
      return;
    }

    // Regular photo rendering
    if (image == null) {
      paint.color = Colors.grey[300]!;
      canvas.drawRect(Offset.zero & size, paint);
      _drawPlaceholderIcons(canvas, size);
    } else {
      _drawImage(canvas, size, paint);
    }

    if (isSelected && !isExporting) { // CHECK EXPORT FLAG
      // Frame Border
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = isEditingContent ? 3 : 1.5;
      paint.color = isEditingContent ? Colors.orange : Colors.blue;
      canvas.drawRect(Offset.zero & size, paint);

      // Handles
      if (!isEditingContent) {
        _drawHandles(canvas, size);
      }
    } else {
       // Placeholder border always visible when NOT selected if empty
       if (image == null) {
          paint.style = PaintingStyle.stroke;
          paint.strokeWidth = 1;
          paint.color = Colors.grey[400]!;
          canvas.drawRect(Offset.zero & size, paint);
       }
    }
  }

  void _drawImage(Canvas canvas, Size size, Paint paint) {
    // 1. Calculate Base "Cover" scale
    double imgW = image!.width.toDouble();
    double imgH = image!.height.toDouble();
    
    // EXIF Orientation check
    final int orient = photo.exifOrientation;
    final int manualRot = globalRotation;
    
    // Total logical rotation = EXIF + Manual
    // We handle them by rotating the canvas, but we need correct un-rotated dimensions for scale
    
    final bool isExifRotated = orient == 6 || orient == 8 || orient == 5 || orient == 7;
    final bool isManualRotated = manualRot == 90 || manualRot == 270;
    
    // If only one is rotated, we swap. If both or neither, we don't.
    if (isExifRotated ^ isManualRotated) {
      // Swap dimensions for scale calculation
      final temp = imgW;
      imgW = imgH;
      imgH = temp;
    }

    final double scale0 = math.max(size.width / imgW, size.height / imgH);
    final double finalScale = scale0 * photo.contentScale;

    // 2. Draw Ghosting (Full image dimmed) if editing
    if (isEditingContent) {
       canvas.save();
       canvas.translate(size.width/2, size.height/2);
       canvas.translate(-photo.contentX * (imgW * finalScale / 2), -photo.contentY * (imgH * finalScale / 2));
       
        // Apply EXIF Rotation
        if (orient == 6) canvas.rotate(math.pi / 2);
        else if (orient == 3) canvas.rotate(math.pi);
        else if (orient == 8) canvas.rotate(-math.pi / 2);

        // Apply Manual Rotation
        if (manualRot != 0) {
          canvas.rotate((math.pi / 180) * manualRot);
        }

       canvas.scale(finalScale);
       paint.color = Colors.black.withOpacity(0.3);
       // Note: imgW/imgH here are native (unswapped) for drawing
       canvas.drawImage(image!, Offset(-image!.width / 2, -image!.height / 2), paint);
       canvas.restore();
    }

    // 3. Draw Scaled & Panned Image clipped inside frame
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width/2, size.height/2);
    canvas.translate(-photo.contentX * (imgW * finalScale / 2), -photo.contentY * (imgH * finalScale / 2));
    
    // Apply EXIF Rotation
    if (orient == 6) canvas.rotate(math.pi / 2);
    else if (orient == 3) canvas.rotate(math.pi);
    else if (orient == 8) canvas.rotate(-math.pi / 2);

    // Apply Manual Rotation
    if (manualRot != 0) {
      canvas.rotate((math.pi / 180) * manualRot);
    }

    canvas.scale(finalScale);
    paint.color = Colors.white;
    canvas.drawImage(image!, Offset(-image!.width / 2, -image!.height / 2), paint);
    canvas.restore();
  }

  void _drawPlaceholderIcons(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.add_photo_alternate_outlined.codePoint),
        style: TextStyle(
          fontSize: 40,
          fontFamily: Icons.add_photo_alternate_outlined.fontFamily,
          color: Colors.grey[500],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2 - 10));
  }

  void _drawHandles(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final handles = [
      const Alignment(-1, -1), const Alignment(1, -1),
      const Alignment(-1, 1), const Alignment(1, 1),
      const Alignment(0, -1), const Alignment(0, 1),
      const Alignment(-1, 0), const Alignment(1, 0),
    ];

    for (var align in handles) {
      final pos = Offset(
        (align.x + 1) / 2 * size.width,
        (align.y + 1) / 2 * size.height,
      );
      canvas.drawRect(Rect.fromCenter(center: pos, width: 8, height: 8), paint);
      canvas.drawRect(Rect.fromCenter(center: pos, width: 8, height: 8), borderPaint);
    }

    // Rotation Handle
    final rotPos = Offset(size.width / 2, -30);
    canvas.drawLine(Offset(size.width / 2, 0), rotPos, Paint()..color = (isEditingContent ? Colors.orange : Colors.blue).withOpacity(0.3)..strokeWidth = 1);
    canvas.drawCircle(rotPos, 7, paint);
    canvas.drawCircle(rotPos, 7, borderPaint);
    
    // Icon inside rotation handle
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.rotate_right.codePoint),
        style: TextStyle(
          fontSize: 10,
          fontFamily: Icons.rotate_right.fontFamily,
          color: Colors.blue,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, rotPos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant PhotoPainter oldDelegate) => true;
}
