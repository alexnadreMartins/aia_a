import '../models/project_model.dart';

class TemplateSystem {
  static const Map<String, dynamic> templates = {
    // --- 1 Photo ---
    '1_full_page': {
      'name': 'Full Page',
      'image_count': 1,
      'layout': [
        {'x': 0.0, 'y': 0.0, 'width': 1.0, 'height': 1.0}
      ]
    },
    '1_centered_large': {
      'name': 'Centered Large',
      'image_count': 1,
      'layout': [
        {'x': 0.1, 'y': 0.1, 'width': 0.8, 'height': 0.8}
      ]
    },
    '1_centered_medium': {
      'name': 'Centered Medium',
      'image_count': 1,
      'layout': [
        {'x': 0.2, 'y': 0.2, 'width': 0.6, 'height': 0.6}
      ]
    },
    
    // --- 2 Photos ---
    '2_side_by_side': {
      'name': 'Side by Side',
      'image_count': 2,
      'layout': [
        {'x': 0.05, 'y': 0.2, 'width': 0.425, 'height': 0.6},
        {'x': 0.525, 'y': 0.2, 'width': 0.425, 'height': 0.6}
      ]
    },
    '2_full_horizontal': {
      'name': 'Full Horizontal Split',
      'image_count': 2,
      'layout': [
        {'x': 0.0, 'y': 0.0, 'width': 1.0, 'height': 0.5},
        {'x': 0.0, 'y': 0.5, 'width': 1.0, 'height': 0.5}
      ]
    },
    '2_top_bottom': {
      'name': 'Top & Bottom',
      'image_count': 2,
      'layout': [
        {'x': 0.1, 'y': 0.05, 'width': 0.8, 'height': 0.425},
        {'x': 0.1, 'y': 0.525, 'width': 0.8, 'height': 0.425}
      ]
    },
    '2_full_vertical_split': {
       'name': 'Full Vertical Split',
       'image_count': 2,
       'layout': [
          {'x': 0.0, 'y': 0.0, 'width': 0.5, 'height': 1.0},
          {'x': 0.5, 'y': 0.0, 'width': 0.5, 'height': 1.0}
       ]
    },

    // --- 3 Photos ---
    '3_one_big_two_small': { // Classic Blurb
      'name': 'One Big, Two Small',
      'image_count': 3,
      'layout': [
        {'x': 0.05, 'y': 0.05, 'width': 0.55, 'height': 0.9}, // Big Left
        {'x': 0.65, 'y': 0.05, 'width': 0.3, 'height': 0.425}, // Top Right
        {'x': 0.65, 'y': 0.525, 'width': 0.3, 'height': 0.425}  // Bottom Right
      ]
    },
    '3_columns_full': {
      'name': 'Three Columns Full',
      'image_count': 3,
      'layout': [
        {'x': 0.0, 'y': 0.0, 'width': 0.333, 'height': 1.0},
        {'x': 0.333, 'y': 0.0, 'width': 0.333, 'height': 1.0},
        {'x': 0.666, 'y': 0.0, 'width': 0.334, 'height': 1.0}
      ]
    },
    '3_columns': {
      'name': 'Three Columns',
      'image_count': 3,
      'layout': [
        {'x': 0.05, 'y': 0.2, 'width': 0.26, 'height': 0.6},
        {'x': 0.37, 'y': 0.2, 'width': 0.26, 'height': 0.6},
        {'x': 0.69, 'y': 0.2, 'width': 0.26, 'height': 0.6}
      ]
    },

    // --- 4 Photos ---
    '4_grid': {
        'name': '2x2 Grid',
        'image_count': 4,
        'layout': [
            {'x': 0.05, 'y': 0.05, 'width': 0.425, 'height': 0.425},
            {'x': 0.525, 'y': 0.05, 'width': 0.425, 'height': 0.425},
            {'x': 0.05, 'y': 0.525, 'width': 0.425, 'height': 0.425},
            {'x': 0.525, 'y': 0.525, 'width': 0.425, 'height': 0.425}
        ]
    },
    '4_grid_full': {
        'name': '2x2 Full Bleed',
        'image_count': 4,
        'layout': [
            {'x': 0.0, 'y': 0.0, 'width': 0.5, 'height': 0.5},
            {'x': 0.5, 'y': 0.0, 'width': 0.5, 'height': 0.5},
            {'x': 0.0, 'y': 0.5, 'width': 0.5, 'height': 0.5},
            {'x': 0.5, 'y': 0.5, 'width': 0.5, 'height': 0.5}
        ]
    },
    '4_one_big_three_small': {
       'name': 'Main + 3 Bottom',
       'image_count': 4,
       'layout': [
          {'x': 0.05, 'y': 0.05, 'width': 0.9, 'height': 0.55},
          {'x': 0.05, 'y': 0.65, 'width': 0.26, 'height': 0.3},
          {'x': 0.37, 'y': 0.65, 'width': 0.26, 'height': 0.3},
          {'x': 0.69, 'y': 0.65, 'width': 0.26, 'height': 0.3}
       ]
    }
  };

  /// Returns the best template key for the given count and optionally aspect ratios.
  /// For now, just selects the first matching one or a default.
  static List<String> getTemplatesForCount(int count) {
    if (count > 4) return ['4_grid']; // Fallback for now
    
    // keys where image_count matches
    return templates.entries
        .where((e) => e.value['image_count'] == count)
        .map((e) => e.key)
        .toList();
  }

  static String getBestTemplateFor(int count) {
      if (count == 1) return '1_centered_large';
      if (count == 2) return '2_side_by_side';
      if (count == 3) return '3_one_big_two_small';
      if (count == 4) return '4_grid';
      // Fallback
      return (count > 4) ? '4_grid' : '1_full_page';
  }

  static List<PhotoItem> applyTemplate(String templateId, List<PhotoItem> currentPhotos, double pageW, double pageH) {
    final template = templates[templateId] ?? templates['4_grid']; // fallback
    if (template == null) return currentPhotos;
    
    final layout = template['layout'] as List;
    List<PhotoItem> newPhotos = [];
    
    // If we have more photos than slots, we might need to handle overflow or just stack them.
    // For this implementation, we fill slots and stack remaining or ignore. 
    // Let's loop through photos.
    for (int i = 0; i < currentPhotos.length; i++) {
      // If we run out of slots, we just pile them in the last slot or center them?
      // Better: Loop slots modulo data length? No, that looks bad.
      // Use the last slot for remaining?
      
      final slotIndex = (i < layout.length) ? i : layout.length - 1;
      final slot = layout[slotIndex];
      
      final p = currentPhotos[i];
      
      // Calculate fit (Cover or Contain? Blurb usually Covers/Crops or Fits)
      // We set the BOX to the slot. The user can then pan/zoom inside (which we need to implement in Manipulator).
      // For now, we set the PhotoItem bounds to the slot.
      
      newPhotos.add(p.copyWith(
        x: (slot['x'] as double) * pageW,
        y: (slot['y'] as double) * pageH,
        width: (slot['width'] as double) * pageW,
        height: (slot['height'] as double) * pageH,
        rotation: 0,
        // zIndex should be preserved or reset? Reset for clean layout.
        zIndex: i,
      ));
    }
    return newPhotos;
  }
}
