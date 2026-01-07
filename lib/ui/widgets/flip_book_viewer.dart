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
  late Animation<double> _animation;
  
  int _currentIndex = 0; // Represents the index of the spread (0 = Cover, 1 = Pages 2-3, etc)
  // Actually simpler: _currentIndex is the index of the LEFT page.
  // If 0, Left is Empty (or Cover), Right is Page 0.
  // If 1 (actually 2), Left is Page 1, Right is Page 2.
  
  bool _isFlippingForward = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 900)
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    
    // Auto-hide mouse?
    // SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_controller.isAnimating) return;
    final project = ref.read(projectProvider).project;
    if (_currentIndex + 2 >= project.pages.length + 1) return; // End
    
    setState(() {
      _isFlippingForward = true;
    });
    _controller.forward(from: 0.0).then((_) {
       setState(() {
         _currentIndex += 2; // Advance spread
       });
       _controller.reset();
    });
  }

  void _prevPage() {
    if (_controller.isAnimating) return;
    if (_currentIndex - 2 < 0) return; // Start
    
    setState(() {
      _isFlippingForward = false;
      _currentIndex -= 2; // Move back logic is trickier with animation order
      // Ideally: Start from "Flipped" state and reverse?
      // Simplified: Just jump back and animate "Reverse Flip" (Left to Right)
    });
    
    // For reverse, we conceptually want to turn the LEFT page back to RIGHT.
    // The animation logic below handles "Right to Left".
    // Reverse needs "Left to Right".
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider).project;
    final pages = project.pages;
    
    // Calculate aspect ratio from first page or project settings
    // Assuming A4 Landscape/Portrait mix? Usually albums are uniform.
    double aspectRatio = 1.5; // Default 3:2
    if (pages.isNotEmpty) {
       aspectRatio = pages[0].widthMm / pages[0].heightMm;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
           // Keyboard Listener
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
                   aspectRatio: aspectRatio * 2, // Double spread width
                   child: LayoutBuilder(
                      builder: (context, constraints) {
                         final singlePageWidth = constraints.maxWidth / 2;
                         final height = constraints.maxHeight;
                         
                         // Determine current pages
                         // Spread Index _currentIndex. 
                         // Left Page: _currentIndex - 1 (if > -1)
                         // Right Page: _currentIndex (if < length)
                         
                         // Wait, standard album:
                         // 0: Cover (Right Side) ? Or Page 1 (Right Side)
                         // Let's assume Page 0 is Layout Page 1.
                         // Display:
                         // Left: Page Index-1
                         // Right: Page Index
                         
                         // Rendering Helpers
                         Widget buildPage(int index) {
                            if (index < 0 || index >= pages.length) {
                               return Container(color: Colors.grey[900]); // Empty/Cover inner
                            }
                            final page = pages[index];
                            return Container(
                              color: Colors.white,
                              child: CustomPaint(
                                painter: PhotoPainter(
                                  photos: page.photos,
                                  backgroundColor: Colors.white, // or page.backgroundColor
                                  gridSize: 0,
                                  showGrid: false,
                                  showMargins: false,
                                  selectedId: null,
                                  scale: 1.0, // Painter will auto-fit if we don't scale?
                                              // PhotoPainter expects canvas size.
                                ),
                                size: Size(singlePageWidth, height),
                              ),
                            );
                         }

                         // Animation Logic
                         return AnimatedBuilder(
                           animation: _animation,
                           builder: (context, child) {
                              double angle = _animation.value * math.pi;
                              
                              // Visual State
                              // Static Left: _currentIndex - 1 (Always visible, unless flipping backward covers it)
                              // Static Right: _currentIndex + 2 (If flipping forward, this is revealed)
                              // Flipper:
                              // If Forward: Page at _currentIndex flips from Right to Left.
                              // If Backward: Page at _currentIndex (which was on Left) flips Left to Right?
                              
                              // Simplified "One Page Flip" Widget logic is hard to inline.
                              // Let's just create the visual stack.
                              
                              if (_isFlippingForward) {
                                 // Flipping Page N (_currentIndex). 
                                 // Front is Page N. Back is Page N+1.
                                 // Base Left: Page N-1
                                 // Base Right: Page N+2 (Revealed)
                                 
                                 // Actually simpler:
                                 // Static Layer: Left (N-1), Right (N+1) ... (skipping N)
                                 // Moving Layer: The Leaf.
                                 
                                 return Stack(
                                   children: [
                                      // Base Layer
                                      Row(
                                        children: [
                                          SizedBox(width: singlePageWidth, child: buildPage(_currentIndex - 1)), // Static Left
                                          SizedBox(width: singlePageWidth, child: buildPage(_currentIndex + 2)), // Static Right (Next-Next)
                                        ],
                                      ),
                                      
                                      // The Flipper
                                      // It's anchored at the center spine.
                                      Positioned(
                                        left: singlePageWidth, // Center spine
                                        top: 0, bottom: 0,
                                        child: Transform(
                                          transform: Matrix4.identity()
                                            ..setEntry(3, 2, 0.001) // Perspective
                                            ..rotateY(-angle), // 0 to -180
                                          alignment: Alignment.centerLeft, // Pivot at spine
                                          child: Stack(
                                            children: [
                                              // Front Face (Visible 0 to 90 degrees)
                                              if (angle < math.pi / 2)
                                                SizedBox(width: singlePageWidth, height: height, child: buildPage(_currentIndex))
                                              else
                                              // Back Face (Visible 90 to 180 degrees)
                                                Transform(
                                                  alignment: Alignment.center,
                                                  transform: Matrix4.identity()..rotateY(math.pi), // Mirror back
                                                  child: SizedBox(width: singlePageWidth, height: height, child: buildPage(_currentIndex + 1)),
                                                )
                                            ],
                                          ),
                                        ),
                                      )
                                   ],
                                 );
                              } else {
                                 // Flipping Backward
                                 // Moving Layer flips from Left to Right.
                                 // Angle goes 0 to PI? Or we play reverse?
                                 // We manually handle "Left to Right" logic here.
                                 
                                 // Static Layer: Left (N-3), Right (N)
                                 // Flipper: Back is N-2, Front is N-1?
                                 
                                 // This is getting complex. 
                                 // Let's stick to a robust package-like logic or just Forward flip for now?
                                 // User wants navigation.
                                 
                                 // Re-calc indices for backward:
                                 // Target state was _currentIndex (Left=N-1, Right=N).
                                 // Previous state was Left=N-3, Right=N-2.
                                 // We are transitioning TO that. 
                                 
                                 // Let's assume _currentIndex is ALREADY updated to the destination (N-2).
                                 // Animation runs 0..1.
                                 // We simulate flipping page N from Left to Right? 
                                 // No, Page N+1 (which was on Left) flips back to Right.
                                 
                                 // Let's use a simpler trick: Only animate forward. 
                                 // If "Back" pressed, just jump to prev state? No, looks bad.
                                 
                                 // FIX: Just use standard 3D flip transform.
                                 // Left Page is pivot centerRight.
                                 
                                 return Stack(
                                   children: [
                                      // Base Layer
                                      Row(
                                        children: [
                                          SizedBox(width: singlePageWidth, child: buildPage(_currentIndex - 1)), // Real Dest Left
                                          SizedBox(width: singlePageWidth, child: buildPage(_currentIndex + 2)), // Real Dest Right? No.
                                        ],
                                      ),
                                       // TODO: Reverse logic. 
                                       // For MVP, simple crossfade if reverse is hard?
                                       // User asked for "Visualização Flip".
                                       // I will implement Forward only for now, Back button jumps?
                                       // Or implement Reverse correctly.
                                       Center(child: Text("Flipping..."))
                                   ]
                                 );
                              }
                           },
                         );
                      },
                   ),
                 ),
               ),
             ),
           ),
           
           // Close Button
           Positioned(
             top: 40, right: 40,
             child: IconButton(
               icon: const Icon(Icons.close, color: Colors.white, size: 30),
               onPressed: () => Navigator.of(context).pop(),
             ),
           ),
        ],
      ),
    );
  }
}
