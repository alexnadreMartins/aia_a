import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DockPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final List<String> tabs;
  final int selectedTabIndex;
  final Function(int) onTabSelected;
  final VoidCallback? onDetach;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;

  const DockPanel({
    super.key,
    required this.title,
    required this.child,
    this.tabs = const [],
    this.selectedTabIndex = 0,
    required this.onTabSelected,
    this.onDetach,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E), // Panel BG
        border: Border(
           right: BorderSide(color: Color(0xFF262626)),
           left: BorderSide(color: Color(0xFF262626)),
           bottom: BorderSide(color: Color(0xFF262626)), 
           top: BorderSide(color: Color(0xFF262626)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Tabs
          GestureDetector(
            onPanStart: onDragStart,
            onPanUpdate: onDragUpdate,
            onPanEnd: onDragEnd,
            child: Container(
              height: 36,
              decoration: const BoxDecoration(
                 color: Color(0xFF141414),
                 border: Border(bottom: BorderSide(color: Color(0xFF262626))),
              ),
              child: Row(
                 children: [
                    if (tabs.isEmpty)
                       Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                       )
                    else
                       Expanded(
                          child: ListView.builder(
                             scrollDirection: Axis.horizontal,
                             itemCount: tabs.length,
                             itemBuilder: (ctx, i) {
                                final isSelected = i == selectedTabIndex;
                                return GestureDetector(
                                   onTap: () => onTabSelected(i),
                                   child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                         color: isSelected ? const Color(0xFF1E1E1E) : Colors.transparent,
                                         border: isSelected ? const Border(top: BorderSide(color: Colors.blueAccent, width: 2)) : null,
                                      ),
                                      child: Text(
                                         tabs[i], 
                                         style: GoogleFonts.inter(
                                            fontSize: 12, 
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            color: isSelected ? Colors.white : Colors.white54
                                         )
                                      ),
                                   ),
                                );
                             },
                          ),
                       ),
                    
                    // Spacer to allow dragging on empty space
                    if (tabs.isNotEmpty)
                       Expanded(child: Container(color: Colors.transparent)),
                    
                    // Dock Actions (Detach)
                    if (onDetach != null)
                       IconButton(
                          icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white54),
                          tooltip: "Desacoplar Janela",
                          onPressed: onDetach,
                       ),
                       
                    // IF draggable (onDragUpdate != null), show a grab handle indicator
                    if (onDragUpdate != null && onDetach == null)
                       const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.drag_indicator, size: 16, color: Colors.white24),
                       ),
                 ],
              ),
            ),
          ),
          
          Expanded(child: child),
        ],
      ),
    );
  }
}
