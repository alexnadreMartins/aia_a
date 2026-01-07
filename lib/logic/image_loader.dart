import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

class ImageLoader {
  static final Map<String, ui.Image> _cache = {};

  static Future<ui.Image> loadImage(String path) async {
    if (_cache.containsKey(path)) {
       print("ImageLoader: Cache HIT for $path");
       return _cache[path]!;
    }
    
    print("ImageLoader: Reading DISK for $path");
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _cache[path] = frame.image;
    return frame.image;
  }

  static void evict(String path) {
    if (_cache.containsKey(path)) {
      _cache.remove(path);
    }
  }
}
