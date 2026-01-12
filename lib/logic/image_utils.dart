import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/painting.dart';
import 'package:exif/exif.dart';

class ImageUtils {
  
  static Future<DateTime> getDateTaken(String path) async {
    try {
      final file = File(path);
      // Fast path: File Mod Time as default
      DateTime date = file.lastModifiedSync(); 
      
      try {
        final bytes = await file.readAsBytes();
        final tags = await readExifFromBytes(bytes);
        if (tags.containsKey('Image DateTime')) {
           final val = tags['Image DateTime']?.printable;
           // Format: "YYYY:MM:DD HH:MM:SS"
           if (val != null) {
              final parts = val.split(' ');
              if (parts.length == 2) {
                 final datePart = parts[0].replaceAll(':', '-');
                 date = DateTime.parse("${datePart}T${parts[1]}");
              }
           }
        }
      } catch (e) {
        // ignore exif error
      }
      return date;
    } catch (e) {
      return DateTime.now();
    }
  }

  static final Map<String, Rect?> _holeCache = {};

  /// Detects a transparent "hole" in an image (e.g. PNG template).
  /// Returns a normalized Rect (0.0 - 1.0) defining the bounds of the transparent area.
  /// Returns null if no hole is found or error occurs.
  static Future<Rect?> detectHole(String path) async {
    if (_holeCache.containsKey(path)) return _holeCache[path];

    try {
      final file = File(path);
      if (!await file.exists()) {
         _holeCache[path] = null;
         return null;
      }

      final bytes = await file.readAsBytes();
      // Decode image
      final image = img.decodeImage(bytes);
      if (image == null) {
         _holeCache[path] = null;
         return null;
      }

      int minX = image.width;
      int maxX = 0;
      int minY = image.height;
      int maxY = 0;
      bool found = false;

      // Scan for transparency
      // Threshold: alpha < 10 (out of 255)
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          if (pixel.a < 10) { 
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            found = true;
          }
        }
      }

      if (!found) {
         _holeCache[path] = null;
         return null;
      }

      // Calculate relative coordinates
      final rect = Rect.fromLTRB(
        minX / image.width, 
        minY / image.height, 
        (maxX + 1) / image.width, // +1 to include the last pixel 
        (maxY + 1) / image.height
      );
      
      _holeCache[path] = rect;
      return rect;

    } catch (e) {
      debugPrint("Error detecting hole in $path: $e");
      return null;
    }
  }
}
