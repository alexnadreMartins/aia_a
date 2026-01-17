import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/project_model.dart';
import '../../logic/image_loader.dart';
import '../../logic/cache_provider.dart';
import '../../state/project_state.dart';

class PhotoManipulator extends ConsumerStatefulWidget {
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
  final bool isExporting;
  final double canvasScale;
  final bool isPrecisionMode; // NEW

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
    this.isExporting = false,
    required this.canvasScale,
    this.isPrecisionMode = false, // NEW
  });

  @override
  ConsumerState<PhotoManipulator> createState() => _PhotoManipulatorState();
}

class _PhotoManipulatorState extends ConsumerState<PhotoManipulator> {
  ui.Image? _uiImage;
  String? _lastPath;
  bool _isProxy = false; // NEW

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
    
    String loadPath = widget.photo.path;
    bool usingProxy = false;
    
    // Check Existence / Offline Mode Logic
    final file = File(loadPath);
    if (!await file.exists()) {
        // Try Proxy
        final projectState = ref.read(projectProvider);
        if (projectState.proxyRoot != null) {
            final filename = loadPath.split(Platform.pathSeparator).last;
            final proxyPath = '${projectState.proxyRoot}${Platform.pathSeparator}$filename';
            if (await File(proxyPath).exists()) {
                debugPrint("Using Proxy for $filename");
                loadPath = proxyPath;
                usingProxy = true;
            }
        }
    }

    try {
      final img = await ImageLoader.loadImage(loadPath);
      if (mounted) {
        setState(() {
          _uiImage = img;
          _lastPath = widget.photo.path;
          _isProxy = usingProxy;
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
    // Listen for external updates
    ref.listen(imageVersionProvider(widget.photo.path), (prev, next) {
       _loadImage();
    });

    final photo = widget.photo;
    final angle = photo.rotation * (math.pi / 180);

    // Draggable / Swap Logic
    return Positioned(
      left: photo.x,
      top: photo.y,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.topLeft,
        child: DragTarget<String>(
          onWillAccept: (data) => data != null && data != photo.id && !photo.isLocked,
          onAccept: (receivedId) {
             ref.read(projectProvider.notifier).swapPhotos(receivedId, photo.id);
          },
          builder: (context, candidateData, rejectedData) {
            final isHovered = candidateData.isNotEmpty && !photo.isLocked;
            final content = _buildContent(photo, angle, isHovered);

            if (photo.isLocked) {
              return content;
            }

            return LongPressDraggable<String>(
              data: photo.id,
              delay: const Duration(milliseconds: 2000), 
              feedback: Material(
                 elevation: 8,
                 color: Colors.transparent,
                 child: Opacity(
                   opacity: 0.8,
                   child: SizedBox(
                      width: 150, 
                      height: 150, 
                      child: _uiImage == null 
                         ? const Icon(Icons.photo, size: 50, color: Colors.white)
                         : RawImage(image: _uiImage, fit: BoxFit.cover),
                   ),
                 ),
              ),
              childWhenDragging: Opacity(opacity: 0.5, child: content),
              child: content,
            );
          }
        ),
      ),
    );
  }

  Widget _buildContent(PhotoItem photo, double angle, bool isHovered) {
    return AnimatedScale(
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
          if (!widget.isSelected || widget.isEditingContent || photo.isLocked) return; // Prevent move if locked
          final localPos = details.localPosition;
          _activeHandle = _hitTestHandles(localPos, Size(photo.width, photo.height));
          if (_activeHandle == null) {
            setState(() => _isMoving = true);
          }
        },
        onPanUpdate: (details) {
            // Apply Scale Correction: Divide delta by canvasScale
            double dx = details.delta.dx / widget.canvasScale;
            double dy = details.delta.dy / widget.canvasScale;
            
            // Precision Mode Damping
            if (widget.isPrecisionMode) {
               dx *= 0.1; // 10x Slower
               dy *= 0.1;
            }

            if (widget.isEditingContent) {
              // Pan Image Inside Frame - Content pan is also scaled?
              // YES, because if I move mouse 100px, I expect content to move 100px relative to frame?
              // Actually, contentX is normalized (-1 to 1?). No, logic is `dAlignX = dx / (width/2)`.
              // width inside here is logical width. `dx` should be scaled to match logical width.
              // So yes, dx must be divided by scale.
              
              final dAlignX = dx / (photo.width / 2);
              final dAlignY = dy / (photo.height / 2);
              widget.onUpdate(photo.copyWith(
                contentX: (photo.contentX - dAlignX).clamp(-5.0, 5.0),
                contentY: (photo.contentY - dAlignY).clamp(-5.0, 5.0),
              ));
            } else if (_activeHandle == const Alignment(0, -2)) {
               // Rotation logic... mostly based on position, not delta, but we use `localPosition`.
               // `localPosition` is ALREADY scaled by Flutter's Transform? No.
               // Verify: InteractiveViewer scales the canvas.
               // GestureDetector receives coordinates in local system?
               // If InteractiveViewer scales, the coordinates provided by GestureDetector ARE local to the widget size?
               // IF GestureDetector sees "width 300", and I drag halfway, it sees 150.
               // Wait. If `InteractiveViewer` is used, `details.delta` reported by GestureDetector IS usually unscaled (screen pixels).
               // SO dividing by scale corrects it.
               // Rotation uses `localPosition`. does `localPosition` need scaling?
               // `localPosition` is typically correct relative to the widget box.
               // So Rotation calculation based on atan2 of localPosition should remain VALID.
               
               final center = Offset(photo.width / 2, photo.height / 2);
               final currentPos = details.localPosition; // Do we need to scale this?
               // If I click at 100px (screen), but scale is 2.0, is localPosition 50 or 100?
               // In scaled view, localPosition is usually in the transformed space. 
               // I'll stick to NOT scaling localPosition for rotation (absolute positions) but scaling Delta.

              final angle = math.atan2(currentPos.dy - center.dy, currentPos.dx - center.dx);
              double deg = angle * (180 / math.pi) + 90;
              widget.onUpdate(photo.copyWith(rotation: deg % 360));
              
            } else if (_activeHandle != null) {
              // Resize Frame
              _handleResize(photo, Offset(dx, dy), _activeHandle!, _isCorner(_activeHandle!));
            } else if (widget.isSelected) {
              // Move Frame
              final globalDelta = _rotateVector(Offset(dx, dy), angle);
              widget.onUpdate(photo.copyWith(
                x: photo.x + globalDelta.dx,
                y: photo.y + globalDelta.dy,
              ));
            }
        },
        onPanEnd: (_) {
          _activeHandle = null;
          if (_isMoving) setState(() => _isMoving = false);
          widget.onDragEnd();
        },
        child: Container( // Wrap in Container to show Hover Border
           decoration: isHovered 
              ? BoxDecoration(border: Border.all(color: Colors.greenAccent, width: 4))
              : null,
           child: CustomPaint(
            size: Size(photo.width, photo.height),
            painter: PhotoPainter(
              image: _uiImage,
              photo: photo,
              isSelected: widget.isSelected,
              isEditingContent: widget.isEditingContent,
              globalRotation: widget.globalRotation,
              isExporting: widget.isExporting,
              isProxy: _isProxy,
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
  final bool isProxy; // NEW

  PhotoPainter({
    required this.image,
    required this.photo,
    required this.isSelected,
    required this.isEditingContent,
    this.globalRotation = 0,
    this.isExporting = false, // NEW
    this.isProxy = false, // NEW
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || size.width.isNaN || size.height.isNaN) return;

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
      
      // Draw Proxy Indicator (Offline Mode)
      if (isProxy && !isExporting) {
         _drawProxyIndicator(canvas, size);
      }
    }

    if (isSelected && !isExporting) { // CHECK EXPORT FLAG
      // Frame Border
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = isEditingContent ? 3 : 1.5;
      paint.color = isEditingContent ? Colors.orange : Colors.blue;
      canvas.drawRect(Offset.zero & size, paint);

      // Handles
      if (!isEditingContent && !photo.isLocked) { // Don't show handles if locked
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

  void _drawProxyIndicator(Canvas canvas, Size size) {
      // Draw a small "Cloud Off" icon in top-right corner
      final iconSize = 24.0;
      final padding = 4.0;
      
      final bgRect = Rect.fromLTWH(size.width - iconSize - padding * 2, 0, iconSize + padding * 2, iconSize + padding * 2);
      
      // Background for contrast
      final paint = Paint()..color = Colors.black.withOpacity(0.5);
      final path = Path()..moveTo(bgRect.left, 0)..lineTo(bgRect.right, 0)..lineTo(bgRect.right, bgRect.bottom)..lineTo(bgRect.left + 10, bgRect.bottom)..close(); 
      // Simple corner triangle or box? Box is safer.
      canvas.drawRect(Rect.fromLTWH(size.width - 24, 0, 24, 24), paint);

      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.cloud_off.codePoint),
          style: TextStyle(
            fontSize: 16,
            fontFamily: Icons.cloud_off.fontFamily,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(size.width - 20, 4));
  }

  void _drawImage(Canvas canvas, Size size, Paint paint) {
    // 1. Calculate Base "Cover" scale
    double imgW = image!.width.toDouble();
    double imgH = image!.height.toDouble();

    if (imgW <= 0 || imgH <= 0 || size.width <= 0 || size.height <= 0) return;
    
    final int orient = photo.exifOrientation;
    final int manualRot = globalRotation;
    
    // Swap dimensions for scale calculation if the image is logically rotated 90/270
    // EXIF orientations 5, 6, 7, 8 involve a 90 or 270 degree rotation.
    final bool isExifRotated = orient >= 5 && orient <= 8;
    final bool isManualRotated = manualRot == 90 || manualRot == 270;
    
    if (isExifRotated ^ isManualRotated) {
      final temp = imgW;
      imgW = imgH;
      imgH = temp;
    }

    final double scale0 = math.max(size.width / imgW, size.height / imgH);
    final double finalScale = scale0 * photo.contentScale;

    // Helper to apply transformations inside save/restore blocks
    void applyOrientations(Canvas canvas) {
        // EXIF Handling (Reference: http://sylvana.net/jpegcrop/exif_orientation.html)
        switch (orient) {
          case 2: // Mirror horizontal
            canvas.scale(-1, 1);
            break;
          case 3: // Rotate 180
            canvas.rotate(math.pi);
            break;
          case 4: // Mirror vertical
            canvas.scale(1, -1);
            break;
          case 5: // Mirror horizontal and rotate 270 CW
            canvas.rotate(-math.pi / 2);
            canvas.scale(-1, 1);
            break;
          case 6: // Rotate 90 CW
            canvas.rotate(math.pi / 2);
            break;
          case 7: // Mirror horizontal and rotate 90 CW
            canvas.rotate(math.pi / 2);
            canvas.scale(-1, 1);
            break;
          case 8: // Rotate 270 CW
            canvas.rotate(-math.pi / 2);
            break;
          default: // 1 or unknown: Normal
            break;
        }

        // Apply Manual Rotation (Global/Browser Rotation)
        if (manualRot != 0) {
          canvas.rotate((math.pi / 180) * manualRot);
        }
    }

    // 2. Draw Ghosting (Full image dimmed) if editing
    if (isEditingContent) {
       canvas.save();
       canvas.translate(size.width/2, size.height/2);
       canvas.translate(-photo.contentX * (imgW * finalScale / 2), -photo.contentY * (imgH * finalScale / 2));
       applyOrientations(canvas);
       canvas.scale(finalScale);
       paint.color = Colors.black.withOpacity(0.3);
       canvas.drawImage(image!, Offset(-image!.width / 2, -image!.height / 2), paint);
       canvas.restore();
    }

    // 3. Draw Scaled & Panned Image clipped inside frame
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width/2, size.height/2);
    canvas.translate(-photo.contentX * (imgW * finalScale / 2), -photo.contentY * (imgH * finalScale / 2));
    applyOrientations(canvas);
    canvas.scale(finalScale);

    paint.color = Colors.white;
    paint.filterQuality = FilterQuality.high;
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
      ..style = PaintingStyle.fill
      ..filterQuality = FilterQuality.high;
    
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
