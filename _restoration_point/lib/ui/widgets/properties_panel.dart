import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/project_state.dart';
import '../../models/project_model.dart';

class PropertiesPanel extends ConsumerStatefulWidget {
  final PhotoItem photo;
  final bool isEditingContent;

  const PropertiesPanel({
    Key? key,
    required this.photo,
    required this.isEditingContent,
  }) : super(key: key);

  @override
  ConsumerState<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends ConsumerState<PropertiesPanel> {
  // Local values to maintain fluidity during drag
  double? _localWidth;
  double? _localHeight;
  double? _localRotation;
  double? _localX;
  double? _localY;
  double? _localScale;
  double? _localContentX;
  double? _localContentY;

  @override
  void didUpdateWidget(PropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the photo Id changed, reset local values
    if (widget.photo.id != oldWidget.photo.id) {
       _resetLocalValues();
    }
  }

  void _resetLocalValues() {
    _localWidth = null;
    _localHeight = null;
    _localRotation = null;
    _localX = null;
    _localY = null;
    _localScale = null;
    _localContentX = null;
    _localContentY = null;
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final isEditingContent = widget.isEditingContent;

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF2D2D2D),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditingContent ? "EDITING IMAGE" : "EDITING FRAME", 
                style: TextStyle(fontWeight: FontWeight.bold, color: isEditingContent ? Colors.orangeAccent : Colors.blueAccent)),
            const SizedBox(height: 10),
            
            if (!isEditingContent) ...[
              const Text("Frame Geometry", style: TextStyle(color: Colors.white70,  fontWeight: FontWeight.bold)),
              _buildSlider("Width", _localWidth ?? photo.width, 20, 800, (v) {
                  setState(() => _localWidth = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(width: v));
              }),
              _buildSlider("Height", _localHeight ?? photo.height, 20, 800, (v) {
                  setState(() => _localHeight = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(height: v));
              }),
              _buildSlider("Rotation", _localRotation ?? photo.rotation, 0, 360, (v) {
                  setState(() => _localRotation = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(rotation: v));
              }),
              _buildSlider("X Pos", _localX ?? photo.x, -100, 1000, (v) {
                  setState(() => _localX = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(x: v));
              }),
              _buildSlider("Y Pos", _localY ?? photo.y, -100, 1000, (v) {
                  setState(() => _localY = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(y: v));
              }),
            ],

            if (isEditingContent) ...[
              const Text("Image Crop", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              _buildSlider("Scale", _localScale ?? photo.contentScale, 0.1, 5.0, (v) {
                  setState(() => _localScale = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(contentScale: v));
              }),
              _buildSlider("Pan X", _localContentX ?? photo.contentX, -5.0, 5.0, (v) {
                  setState(() => _localContentX = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(contentX: v));
              }),
              _buildSlider("Pan Y", _localContentY ?? photo.contentY, -5.0, 5.0, (v) {
                  setState(() => _localContentY = v);
                  ref.read(projectProvider.notifier).updatePhoto(photo.id, (p) => p.copyWith(contentY: v));
              }),
            ],

            const Divider(color: Colors.grey),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!isEditingContent) ...[
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white70),
                    tooltip: "Duplicate",
                    onPressed: () => ref.read(projectProvider.notifier).duplicatePhoto(photo.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.flip_to_front, color: Colors.white70),
                    tooltip: "Bring to Front",
                    onPressed: () => ref.read(projectProvider.notifier).bringToFront(photo.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.flip_to_back, color: Colors.white70),
                    tooltip: "Send to Back",
                    onPressed: () => ref.read(projectProvider.notifier).sendToBack(photo.id),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  tooltip: "Delete Frame",
                  onPressed: () {
                      ref.read(projectProvider.notifier).removePhoto(photo.id);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!isEditingContent)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.crop),
                  label: const Text("Edit Image Crop"),
                  onPressed: () {
                      _resetLocalValues();
                      ref.read(projectProvider.notifier).setEditingContent(true);
                  },
                ),
              ),
            if (isEditingContent)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text("Done Cropping"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () {
                      _resetLocalValues();
                      ref.read(projectProvider.notifier).setEditingContent(false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
               thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
               overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
               trackHeight: 2,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: (v) {
                 // Clear local value to sync with source of truth
                 _resetLocalValues();
                 ref.read(projectProvider.notifier).saveHistorySnapshot();
              },
            ),
          ),
        ),
        SizedBox(width: 35, child: Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.white54, fontSize: 10))),
      ],
    );
  }
}

