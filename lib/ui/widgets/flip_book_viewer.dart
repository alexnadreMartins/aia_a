import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/project_state.dart';
import '../../models/project_model.dart';
import 'photo_manipulator.dart'; // Reuse PhotoPainter for rendering

class FlipBookViewer extends ConsumerStatefulWidget {
  const FlipBookViewer({super.key});

  @override
  ConsumerState<FlipBookViewer> createState() => _FlipBookViewerState();
}

class _FlipBookViewerState extends ConsumerState<FlipBookViewer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  // Current "Left Page's Index" (The even number page on the left, 0=Cover-ish)
  // Standard album layout:
  // [Page i-1] [Page i]
  // Ideally:
  // Spread 0: [Empty] [Page 0]
  // Spread 1: [Page 1] [Page 2]
  // Spread 2: [Page 3] [Page 4]
  int _currentSpreadIndex = 0; 
  
  // 0 = Normal, 1 = Flipping Forward, -1 = Flipping Backward
  int _flipDirection = 0; 
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 900)
    );
     // Start at beginning
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_controller.isAnimating || _flipDirection != 0) return;
    final project = ref.read(projectProvider).project;
    // Check if we have more pages
    // Current spread shows (current*2 - 1) and (current*2)
    // Next spread shows (current*2 + 1) and (current*2 + 2)
    // Max index is length-1.
    
    // Simplification: _currentSpreadIndex is the "pair index" 0, 1, 2...
    // Pair 0: Left: -1, Right: 0
    // Pair 1: Left: 1, Right: 2
    // Pair 2: Left: 3, Right: 4
    
    int maxSpread = (project.pages.length / 2).ceil(); 
    if (_currentSpreadIndex >= maxSpread) return;

    setState(() {
      _flipDirection = 1;
    });
    
    _controller.forward(from: 0.0).then((_) {
       setState(() {
         _currentSpreadIndex++;
         _flipDirection = 0;
       });
       _controller.reset();
    });
  }

  void _prevPage() {
    if (_controller.isAnimating || _flipDirection != 0) return;
    if (_currentSpreadIndex <= 0) return;

    setState(() {
      _flipDirection = -1;
    });
    
    _controller.forward(from: 0.0).then((_) {
       setState(() {
         _currentSpreadIndex--;
         _flipDirection = 0;
       });
       _controller.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider).project;
    final pages = project.pages;
    
    // Calc Aspect Ratio from first page
    double aspectRatio = 1.5; 
    if (pages.isNotEmpty) {
       aspectRatio = pages[0].widthMm / pages[0].heightMm;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
           CallbackShortcuts(
             bindings: {
               const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
               const SingleActivator(LogicalKeyboardKey.arrowRight): _nextPage,
               const SingleActivator(LogicalKeyboardKey.arrowLeft): _prevPage,
             },
             child: Focus(
               autofocus: true,
               child: Center(
                 child: AspectRatio(
                   aspectRatio: aspectRatio * 2, // Double spread
                   child: LayoutBuilder(
                      builder: (context, constraints) {
                         final singleWidth = constraints.maxWidth / 2;
                         final height = constraints.maxHeight;

                         // Helpers to get page indices for a Spread Index
                         int getLeftIndex(int spread) {
                             if (spread == 0) return -1; // Empty/Cover
                             return (spread * 2) - 1;
                         }
                         int getRightIndex(int spread) {
                             return (spread * 2);
                         }

                         Widget buildPage(int index) {
                            if (index < 0 || index >= pages.length) {
                               return Container(color: const Color(0xFF111111)); // Empty
                            }
                            final page = pages[index];
                            return Container(
                              color: Colors.white,
                              // Add subtle shadow/gradient for depth
                              foregroundDecoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.black.withOpacity(0.05), Colors.transparent, Colors.black.withOpacity(0.02)],
                                  stops: const [0, 0.1, 1],
                                  begin: Alignment.centerRight, end: Alignment.centerLeft
                                )
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Scale based on page dimensions (mm) vs available pixels
                                  // Assuming page.widthMm matches singleWidth roughly in aspect ratio
                                  final double scaleX = constraints.maxWidth / page.widthMm;
                                  final double scaleY = constraints.maxHeight / page.heightMm;
                                  
                                  // Sort photos by Z-Index
                                  final sortedPhotos = List<PhotoItem>.from(page.photos)
                                     ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
                                     
                                  return Stack(
                                    children: [
                                      if (page.backgroundPath != null && page.backgroundPath!.isNotEmpty)
                                        Positioned.fill(
                                          child: Image.file(
                                            File(page.backgroundPath!),
                                            fit: BoxFit.cover,
                                          )
                                        ),
                                      ...sortedPhotos.map((photo) {
                                         if (photo.isText && photo.text != null) {
                                            return Positioned(
                                              left: photo.x * scaleX,
                                              top: photo.y * scaleY,
                                              width: photo.width * scaleX,
                                              height: photo.height * scaleY,
                                              child: Text(
                                                photo.text!,
                                                style: TextStyle(
                                                  fontSize: 12.0 * scaleX * 0.3,
                                                  color: Colors.black,
                                                ),
                                              )
                                            );
                                         }
                                         
                                         return Positioned(
                                           left: photo.x * scaleX,
                                           top: photo.y * scaleY,
                                           width: photo.width * scaleX,
                                           height: photo.height * scaleY,
                                           child: SinglePhotoRenderer(photo: photo),
                                         );
                                      }).toList(),
                                    ],
                                  );
                                }
                              ),
                            );
                         }

                         // ... (rest of build/Animation code same)
                         // Current Static State
                         final currentLeftIdx = getLeftIndex(_currentSpreadIndex);
                         final currentRightIdx = getRightIndex(_currentSpreadIndex);
                         
                         return AnimatedBuilder(
                           animation: _controller,
                           builder: (context, child) {
                              if (_flipDirection == 1) {
                                 final nextSpread = _currentSpreadIndex + 1;
                                 final nextLeft = getLeftIndex(nextSpread);
                                 final nextRight = getRightIndex(nextSpread);
                                 return Stack(children: [
                                   Row(children: [
                                      SizedBox(width: singleWidth, child: buildPage(currentLeftIdx)),
                                      SizedBox(width: singleWidth, child: buildPage(nextRight)),
                                   ]),
                                   Positioned(
                                      left: singleWidth, top: 0, bottom: 0,
                                      child: PageTurnWidget(
                                        amount: _controller.value, isRightPage: true,
                                        front: buildPage(currentRightIdx), back: buildPage(nextLeft),
                                        width: singleWidth, height: height,
                                      ),
                                   )
                                 ]);
                              } else if (_flipDirection == -1) {
                                 final prevSpread = _currentSpreadIndex - 1;
                                 final prevLeft = getLeftIndex(prevSpread);
                                 final prevRight = getRightIndex(prevSpread);
                                 return Stack(children: [
                                   Row(children: [
                                      SizedBox(width: singleWidth, child: buildPage(prevLeft)),
                                      SizedBox(width: singleWidth, child: buildPage(currentRightIdx)),
                                   ]),
                                   Positioned(
                                      left: 0, top: 0, bottom: 0,
                                      child: PageTurnWidget(
                                        amount: _controller.value, isRightPage: false,
                                        front: buildPage(currentLeftIdx), back: buildPage(prevRight),
                                        width: singleWidth, height: height,
                                      ),
                                   )
                                 ]);
                              } else {
                                 return Row(children: [
                                   SizedBox(width: singleWidth, child: buildPage(currentLeftIdx)),
                                   SizedBox(width: singleWidth, child: buildPage(currentRightIdx)),
                                 ]);
                              }
                           }
                         );
                      }
                   ),
                 ),
               ),
             ),
           ),
           // HUD / Back
           Positioned(
             top: 20, right: 20,
             child: IconButton(
               icon: const Icon(Icons.close, color: Colors.white), 
               onPressed: () => Navigator.pop(context),
               tooltip: "Sair (ESC)",
             )
           )
        ],
      )
    );
  }
}

class SinglePhotoRenderer extends StatefulWidget {
  final PhotoItem photo;
  const SinglePhotoRenderer({super.key, required this.photo});

  @override
  State<SinglePhotoRenderer> createState() => _SinglePhotoRendererState();
}

class _SinglePhotoRendererState extends State<SinglePhotoRenderer> {
  ui.Image? _loadedImage;
  
  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant SinglePhotoRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.path != widget.photo.path) {
       _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.photo.path.isEmpty) return;
    try {
      final file = File(widget.photo.path);
      if (!await file.exists()) return;
      
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _loadedImage = frame.image;
        });
      }
    } catch (e) {
      debugPrint("Error loading image for flip book: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedImage == null) {
       return const SizedBox(); 
    }
    // Use the exact same painter as the editor to guarantee identical rendering (rotation, pan, zoom)
    return CustomPaint(
      painter: PhotoPainter(
        image: _loadedImage,
        photo: widget.photo,
        isSelected: false,
        isEditingContent: false,
      ),
      size: Size.infinite,
    );
  }
}


class PageTurnWidget extends StatelessWidget {
  final double amount; // 0.0 to 1.0 progress
  final bool isRightPage; // If true, flips Right->Left. If false, Left->Right.
  final Widget front; // Visible when amount=0
  final Widget back; // Visible when amount=1
  final double width;
  final double height;
  
  const PageTurnWidget({
    super.key, 
    required this.amount, 
    required this.isRightPage,
    required this.front,
    required this.back,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
      // Angle:
      // If RightPage: Rotate Y from 0 to -180 (-PI). 
      // If LeftPage: Rotate Y from 0 to 180 (PI). 
      
      double angle = 0.0;
      if (isRightPage) {
         angle = -amount * math.pi;
      } else {
         angle = amount * math.pi;
      }
      
      // Pivot
      final Alignment alignment = isRightPage ? Alignment.centerLeft : Alignment.centerRight;
      
      return Transform(
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(angle),
        alignment: alignment,
        child: Stack(
          children: [
             // Front Face
             // Visible if rotation is less than 90 degrees absolute
             if (amount < 0.5) 
                SizedBox(width: width, height: height, child: front),
             
             // Back Face
             // Visible if rotation > 90
             if (amount >= 0.5)
               Transform(
                 alignment: Alignment.center,
                 transform: Matrix4.identity()..rotateY(math.pi), // Mirror content so it reads correctly
                 child: SizedBox(width: width, height: height, child: back),
               )
          ]
        ),
      );
  }
}
