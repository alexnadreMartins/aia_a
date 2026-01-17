import 'package:flutter/material.dart';

enum ResizeEdge { left, right, top, bottom }

class ResizablePane extends StatefulWidget {
  final Widget child;
  final double width; // Current width (controlled by parent usually, but here we might just use flex? No, resizing needs explicit pixels usually for Dock)
  // Actually, for a resizable dock, the PARENT usually holds the state of the width. 
  // This widget just detects the drag and reports delta.
  
  final double minSize;
  final double maxSize;
  final ResizeEdge edge;
  final Function(double delta) onResize;

  const ResizablePane({
    super.key,
    required this.child,
    required this.edge,
    required this.onResize,
    this.minSize = 100,
    this.maxSize = 600,
    this.width = 250, // Initial or current
  });

  @override
  State<ResizablePane> createState() => _ResizablePaneState();
}

class _ResizablePaneState extends State<ResizablePane> {
  bool _isResizing = false;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.edge == ResizeEdge.left || widget.edge == ResizeEdge.right;
    
    // Handle Widget
    Widget handle = MouseRegion(
      cursor: isHorizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent, // Capture easier
        onPanStart: (_) => setState(() => _isResizing = true),
        onPanEnd: (_) => setState(() => _isResizing = false),
        onPanUpdate: (details) {
           double delta = 0;
           if (widget.edge == ResizeEdge.left) delta = -details.delta.dx;
           if (widget.edge == ResizeEdge.right) delta = details.delta.dx;
           if (widget.edge == ResizeEdge.top) delta = -details.delta.dy;
           if (widget.edge == ResizeEdge.bottom) delta = details.delta.dy;
           
           widget.onResize(delta);
        },
        child: Container(
           width: isHorizontal ? 6 : double.infinity,
           height: isHorizontal ? double.infinity : 6,
           color: _isResizing ? Colors.blueAccent : Colors.transparent, // Highlight on drag
           child: Center(
              child: Container(
                 color: const Color(0xFF555555), // Lighter grey for visibility
                 width: isHorizontal ? 2 : double.infinity, // Thicker
                 height: isHorizontal ? double.infinity : 2,
              ),
           ),
        ),
      ),
    );

    if (isHorizontal) {
       return SizedBox(
         width: widget.width,
         child: Row(
            children: [
               if (widget.edge == ResizeEdge.left) handle,
               Expanded(child: widget.child),
               if (widget.edge == ResizeEdge.right) handle,
            ],
         ),
       );
    } else {
       // Vertical (Top/Bottom) - usually implies height control
       return SizedBox(
         height: widget.width, // We use 'width' param as 'size'
         child: Column(
            children: [
               if (widget.edge == ResizeEdge.top) handle,
               Expanded(child: widget.child),
               if (widget.edge == ResizeEdge.bottom) handle,
            ],
         ),
       );
    }
  }
}
