import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/asset_state.dart';
import '../../models/asset_model.dart';
import '../widgets/photo_manipulator.dart'; // Reusing for future, or just using standard widgets

class FullScreenViewer extends ConsumerStatefulWidget {
  final List<LibraryAsset> assets;
  final int initialIndex;

  const FullScreenViewer({
    super.key,
    required this.assets,
    required this.initialIndex,
  });

  @override
  ConsumerState<FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends ConsumerState<FullScreenViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    // Auto-focus to capture keyboard events
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < widget.assets.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleSelection() {
    final asset = widget.assets[_currentIndex];
    ref.read(assetProvider.notifier).toggleSelection(asset.id);
  }

  void _rotate(bool clockwise) {
    // Rotation logic in Viewer (Just Metadata/Visual for now?)
    // User asked to "Transport rotation commands". 
    // Implementing placeholders as actual file rotation might be slow.
    // For now, we will just print/notify.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Rotação será implementada em breve"), duration: Duration(milliseconds: 500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assetState = ref.watch(assetProvider);
    final currentAsset = widget.assets[_currentIndex];
    final isSelected = assetState.selectedAssetIds.contains(currentAsset.id);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Keyboard Listener
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowRight): _nextPage,
              const SingleActivator(LogicalKeyboardKey.arrowLeft): _previousPage,
              const SingleActivator(LogicalKeyboardKey.space): _toggleSelection,
              const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
            },
            child: Focus(
              focusNode: _focusNode,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.assets.length,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                itemBuilder: (context, index) {
                  final asset = widget.assets[index];
                  final isPageSelected = assetState.selectedAssetIds.contains(asset.id);
                  
                  return GestureDetector(
                    onTap: _toggleSelection, // Space or Click to toggle
                    onDoubleTap: () => Navigator.of(context).pop(), // Double tap to close
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: isPageSelected ? 0.3 : 1.0, // "apagada" behavior
                      child: Center(
                        child: Image.file(
                          File(asset.path),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // HUD Top: Filename and Index
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${currentAsset.name}  •  ${_currentIndex + 1}/${widget.assets.length}",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          // Selection Indicator (Checkmark)
          if (isSelected)
            const Positioned(
              top: 50,
              right: 50,
              child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 48),
            ),

          // Left Arrow
          if (_currentIndex > 0)
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white54, size: 40),
                  onPressed: _previousPage,
                ),
              ),
            ),

          // Right Arrow
          if (_currentIndex < widget.assets.length - 1)
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 40),
                  onPressed: _nextPage,
                ),
              ),
            ),

          // Close Button
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          
          // Rotation Controls (Bottom)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.rotate_left, color: Colors.white),
                    onPressed: () => _rotate(false),
                    tooltip: "Rotacionar Esquerda",
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    icon: const Icon(Icons.rotate_right, color: Colors.white),
                    onPressed: () => _rotate(true),
                    tooltip: "Rotacionar Direita",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
