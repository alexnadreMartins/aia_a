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
    '1_solo_horizontal_large': {
      'name': 'Solo Horizontal Large',
      'image_count': 1,
      'layout': [
        {'x': 0.05, 'y': 0.1, 'width': 0.9, 'height': 0.8}
      ]
    },
    '1_hero_landscape': {
      'name': 'Hero Landscape',
      'image_count': 1,
      'is_landscape_only': true,
      'layout': [
        {'x': 0.05, 'y': 0.25, 'width': 0.9, 'height': 0.5}
      ]
    },
    '1_vertical_half_right': {
       'name': 'Vertical Half Right',
       'image_count': 1,
       'is_portrait_only': true,
       'layout': [
         {'x': 0.525, 'y': 0.05, 'width': 0.425, 'height': 0.9} 
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
    '2_portrait_pair': {
      'name': 'Portrait Pair',
      'image_count': 2,
      'is_portrait_only': true,
      'layout': [
        {'x': 0.1, 'y': 0.15, 'width': 0.38, 'height': 0.7},
        {'x': 0.52, 'y': 0.15, 'width': 0.38, 'height': 0.7}
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
      'name': '2 Vertical Full',
      'image_count': 2,
      'layout': [
        {'x': 0.05, 'y': 0.05, 'width': 0.425, 'height': 0.9},
        {'x': 0.525, 'y': 0.05, 'width': 0.425, 'height': 0.9}
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
    },
    '3_mix_ratio': {
       'name': 'Mix Ratio',
       'image_count': 3,
       'layout': [
          {'x': 0.05, 'y': 0.05, 'width': 0.9, 'height': 0.4},
          {'x': 0.05, 'y': 0.5, 'width': 0.425, 'height': 0.45},
          {'x': 0.525, 'y': 0.5, 'width': 0.425, 'height': 0.45}
       ]
    },
    '4_cinema': {
       'name': 'Cinema Stripe',
       'image_count': 4,
       'layout': [
          {'x': 0.0, 'y': 0.05, 'width': 1.0, 'height': 0.2},
          {'x': 0.0, 'y': 0.27, 'width': 1.0, 'height': 0.2},
          {'x': 0.0, 'y': 0.49, 'width': 1.0, 'height': 0.2},
          {'x': 0.0, 'y': 0.71, 'width': 1.0, 'height': 0.2}
       ]
    },
    '6_grid': {
       'name': '3x2 Grid',
       'image_count': 6,
       'layout': [
          {'x': 0.05, 'y': 0.05, 'width': 0.28, 'height': 0.42},
          {'x': 0.36, 'y': 0.05, 'width': 0.28, 'height': 0.42},
          {'x': 0.67, 'y': 0.05, 'width': 0.28, 'height': 0.42},
          {'x': 0.05, 'y': 0.53, 'width': 0.28, 'height': 0.42},
          {'x': 0.36, 'y': 0.53, 'width': 0.28, 'height': 0.42},
          {'x': 0.67, 'y': 0.53, 'width': 0.28, 'height': 0.42}
       ]
    },

    // --- New THIN / SYMMETRIC Templates (User Request) ---
    // Spacing: 1.5% (0.015)
    
    // 2 Photos
    '2_thin_side': {
      'name': 'Side by Side (Thin)',
      'image_count': 2,
      'layout': [
        {'x': 0.015, 'y': 0.015, 'width': 0.4775, 'height': 0.97}, // 47.75% width
        {'x': 0.5075, 'y': 0.015, 'width': 0.4775, 'height': 0.97}
      ]
    },
    
    // 3 Photos
    '3_thin_1v_2h_left': { // 1 Vertical Left, 2 Horizontal Right
      'name': '1 Vert, 2 Horirz (Left)',
      'image_count': 3,
      'layout': [
        {'x': 0.015, 'y': 0.015, 'width': 0.4775, 'height': 0.97}, // Vert Left
        {'x': 0.5075, 'y': 0.015, 'width': 0.4775, 'height': 0.4775}, // Top Right
        {'x': 0.5075, 'y': 0.5075, 'width': 0.4775, 'height': 0.4775}  // Bot Right
      ]
    },
    '3_thin_1v_2h_right': { // 1 Vertical Right, 2 Horizontal Left
      'name': '1 Vert, 2 Hor z (Right)',
      'image_count': 3,
      'layout': [
        {'x': 0.015, 'y': 0.015, 'width': 0.4775, 'height': 0.4775}, // Top Left
        {'x': 0.015, 'y': 0.5075, 'width': 0.4775, 'height': 0.4775}, // Bot Left
        {'x': 0.5075, 'y': 0.015, 'width': 0.4775, 'height': 0.97}   // Vert Right
      ]
    },
    '3_thin_3cols': {
      'name': '3 Cols (Thin)',
      'image_count': 3,
      'layout': [
        {'x': 0.015, 'y': 0.015, 'width': 0.313, 'height': 0.97},
        {'x': 0.343, 'y': 0.015, 'width': 0.313, 'height': 0.97},
        {'x': 0.671, 'y': 0.015, 'width': 0.313, 'height': 0.97}
      ]
    },
    '3_thin_rows': {
      'name': '3 Rows (Thin)',
      'image_count': 3,
      'layout': [
        {'x': 0.015, 'y': 0.015, 'width': 0.97, 'height': 0.313},
        {'x': 0.015, 'y': 0.343, 'width': 0.97, 'height': 0.313},
        {'x': 0.015, 'y': 0.671, 'width': 0.97, 'height': 0.313}
      ]
    },

    // 4 Photos
    '4_thin_grid': {
        'name': '2x2 Grid (Thin)',
        'image_count': 4,
        'layout': [
            {'x': 0.015, 'y': 0.015, 'width': 0.4775, 'height': 0.4775},
            {'x': 0.5075, 'y': 0.015, 'width': 0.4775, 'height': 0.4775},
            {'x': 0.015, 'y': 0.5075, 'width': 0.4775, 'height': 0.4775}, // Fixed coordinate typo (was 0.525 previously)
            {'x': 0.5075, 'y': 0.5075, 'width': 0.4775, 'height': 0.4775}
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
