
import 'package:flutter/material.dart';

class ScopeWidget extends StatefulWidget {
  final String title;
  final Widget child; // Widget builder actually? No, child needs to be responsive.
  final String helpTitle;
  final String helpContent;
  final Offset initialOffset;
  final Function(Offset) onDragEnd;
  final Size initialSize;
  final Function(Size)? onResizeEnd;

  const ScopeWidget({
    super.key,
    required this.title,
    required this.child,
    required this.helpTitle,
    required this.helpContent,
    required this.initialOffset,
    required this.onDragEnd,
    this.initialSize = const Size(260, 160),
    this.onResizeEnd,
  });

  @override
  State<ScopeWidget> createState() => _ScopeWidgetState();
}

class _ScopeWidgetState extends State<ScopeWidget> {
  late Offset position;
  late Size size;

  @override
  void initState() {
    super.initState();
    position = widget.initialOffset;
    size = widget.initialSize;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
          boxShadow: [
             BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)
          ]
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Header (Draggable)
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      position += details.delta;
                    });
                  },
                  onPanEnd: (_) => widget.onDragEnd(position),
                  child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                     decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.white12)),
                        color: Colors.transparent, // Hit test
                     ),
                     child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                           Text(widget.title.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                           GestureDetector(
                              onTap: _showHelp,
                              child: const Icon(Icons.help_outline, color: Colors.white54, size: 14),
                           )
                        ],
                     ),
                  ),
                ),
                // Content
                Expanded(
                   child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: widget.child,
                   ),
                ),
              ],
            ),
            
            // Resize Handle (Bottom Right)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    size = Size(
                      (size.width + details.delta.dx).clamp(150.0, 600.0),
                      (size.height + details.delta.dy).clamp(100.0, 500.0),
                    );
                  });
                },
                onPanEnd: (_) => widget.onResizeEnd?.call(size),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
                  ),
                  child: const Icon(Icons.north_west, size: 12, color: Colors.white24), 
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp() {
     showDialog(
        context: context, 
        builder: (ctx) => AlertDialog(
           backgroundColor: const Color(0xFF222222),
           title: Text(widget.helpTitle, style: const TextStyle(color: Colors.white)),
           content: Text(widget.helpContent, style: const TextStyle(color: Colors.white70)),
           actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendi"))
           ],
        )
     );
  }
}
