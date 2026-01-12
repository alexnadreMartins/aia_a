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
      'name': 'Centered Large (95%)',
      'image_count': 1,
      'layout': [
        {'x': 0.025, 'y': 0.025, 'width': 0.95, 'height': 0.95}
      ]
    },
    '1_centered_medium': {
      'name': 'Centered Medium',
      'image_count': 1,
      'layout': [
        {'x': 0.15, 'y': 0.15, 'width': 0.7, 'height': 0.7}
      ]
    },
    '1_solo_horizontal_large': {
      'name': 'Solo Horizontal',
      'image_count': 1,
      'layout': [
        {'x': 0.025, 'y': 0.025, 'width': 0.95, 'height': 0.95}
      ]
    },
    '1_hero_landscape': {
      'name': 'Hero Landscape',
      'image_count': 1,
      'is_landscape_only': true,
      'layout': [
        {'x': 0.025, 'y': 0.1, 'width': 0.95, 'height': 0.8}
      ]
    },
    '1_vertical_half_right': {
       'name': 'Vertical Half Right',
       'image_count': 1,
       'is_portrait_only': true,
       'layout': [
         {'x': 0.51, 'y': 0.025, 'width': 0.465, 'height': 0.95} 
       ]
    },
    
    // --- 2 Photos ---
    '2_side_by_side': {
      'name': 'Side by Side (95%)',
      'image_count': 2,
      'layout': [
        {'x': 0.025, 'y': 0.025, 'width': 0.465, 'height': 0.95},
        {'x': 0.51, 'y': 0.025, 'width': 0.465, 'height': 0.95}
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
      'name': 'Top & Bottom (95%)',
      'image_count': 2,
      'layout': [
        {'x': 0.025, 'y': 0.025, 'width': 0.95, 'height': 0.465},
        {'x': 0.025, 'y': 0.51, 'width': 0.95, 'height': 0.465}
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
    '2_portrait_pair': {
      'name': 'Portrait Pair (95%)',
      'image_count': 2,
      'is_portrait_only': true,
      'layout': [
        {'x': 0.025, 'y': 0.025, 'width': 0.465, 'height': 0.95},
        {'x': 0.51, 'y': 0.025, 'width': 0.465, 'height': 0.95}
      ]
    },
    'event_opening': {
      'name': 'Event Opening',
      'image_count': 1,
      'layout': [
        {'x': 0.5, 'y': 0.0, 'width': 0.5, 'height': 1.0}
      ]
    },
    '2_vertical_full': {
      'name': '2 Vertical (95%)',
      'image_count': 2,
      'layout': [
        {'x': 0.025, 'y': 0.025, 'width': 0.465, 'height': 0.95},
        {'x': 0.51, 'y': 0.025, 'width': 0.465, 'height': 0.95}
      ]
    },

    // --- 3 Photos ---
    '3_one_big_two_small': { // Classic Blurb
      'name': 'One Big, Two Small',
      'image_count': 3,
      'layout': [
        {'x': 0.025, 'y': 0.025, 'width': 0.49, 'height': 0.95}, // Big Left
        {'x': 0.54, 'y': 0.025, 'width': 0.435, 'height': 0.465}, // Top Right
        {'x': 0.54, 'y': 0.51, 'width': 0.435, 'height': 0.465}  // Bottom Right
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
        {'x': 0.025, 'y': 0.025, 'width': 0.3, 'height': 0.95},
        {'x': 0.35, 'y': 0.025, 'width': 0.3, 'height': 0.95},
        {'x': 0.675, 'y': 0.025, 'width': 0.3, 'height': 0.95}
      ]
    },

    // --- 4 Photos ---
    '4_grid': {
        'name': '2x2 Grid (95%)',
        'image_count': 4,
        'layout': [
            {'x': 0.025, 'y': 0.025, 'width': 0.465, 'height': 0.465},
            {'x': 0.51, 'y': 0.025, 'width': 0.465, 'height': 0.465},
            {'x': 0.025, 'y': 0.51, 'width': 0.465, 'height': 0.465},
            {'x': 0.51, 'y': 0.51, 'width': 0.465, 'height': 0.465}
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
