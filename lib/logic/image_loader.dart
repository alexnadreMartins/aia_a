import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

class ImageLoader {
  static final Map<String, ui.Image> _cache = {};

  static Future<ui.Image> loadImage(String path) async {
    if (_cache.containsKey(path)) return _cache[path]!;
    
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _cache[path] = frame.image;
    return frame.image;
  }
}
