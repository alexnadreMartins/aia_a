import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'image_loader.dart';

// Provides a unique integer version for each file path.
// When this increments, UI components watching it should rebuild/reload.
final imageVersionProvider = StateProvider.family<int, String>((ref, path) => 0);

class CacheService {
  static void invalidate(dynamic ref, String path) {
    // 1. Evict from memory cache (ImageLoader)
    ImageLoader.evict(path);
    
    // 2. Brute Force Flutter ImageCache Eviction
    // If specific eviction fails, we might need to clear more aggressively
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    print("CacheService: Cleared ENTIRE ImageCache for $path");
    
    // 3. Increment version to notify watchers
    ref.read(imageVersionProvider(path).notifier).state++;
    print("CacheService: Incremented version for $path");
  }
}
