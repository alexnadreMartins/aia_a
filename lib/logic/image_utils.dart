import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/painting.dart';
import 'package:exif/exif.dart';

class ImageUtils {
  
  static Future<DateTime> getDateTaken(String path) async {
    try {
      final file = File(path);
      // Default: File Mod Time (fallback)
      DateTime bestDate = file.lastModifiedSync(); 
      bool foundExif = false;
      
      try {
        // Optimization: Read only first 256KB for Headers. 
        // Most EXIF data is at the start. Reading 20MB files is slow.
        final int maxBytes = 256 * 1024; 
        final int len = await file.length();
        final List<int> bytes = await file.openRead(0, len > maxBytes ? maxBytes : len).first;
        
        final tags = await readExifFromBytes(bytes);
        
        // Priority 1: DateTimeOriginal (The actual shutter click)
        if (tags.containsKey('Image DateTimeOriginal')) {
             final val = tags['Image DateTimeOriginal']?.printable;
             final d = _parseExifDate(val);
             if (d != null) return d; 
        }

        // Priority 2: DateTimeDigitized
        if (tags.containsKey('Image DateTimeDigitized')) {
             final val = tags['Image DateTimeDigitized']?.printable;
             final d = _parseExifDate(val);
             if (d != null) return d;
        }

        // Priority 3: Image DateTime (Modified usually)
        if (tags.containsKey('Image DateTime')) {
             final val = tags['Image DateTime']?.printable;
             final d = _parseExifDate(val);
             if (d != null) return d;
        }
        
      } catch (e) {
        // ignore exif error
      }
      return bestDate;
    } catch (e) {
      return DateTime.now();
    }
  }

  static DateTime? _parseExifDate(String? val) {
     if (val == null || val.trim().isEmpty) return null;
     try {
       // Format: "YYYY:MM:DD HH:MM:SS"
       final parts = val.split(' ');
       if (parts.length >= 2) {
          final datePart = parts[0].replaceAll(':', '-');
          final timePart = parts[1];
          return DateTime.parse("${datePart}T$timePart");
       }
     } catch (_) {}
     return null;
  }

  static Future<String?> getCameraModel(String path) async {
    try {
      final file = File(path);
      final int maxBytes = 256 * 1024; 
      final int len = await file.length();
      final List<int> bytes = await file.openRead(0, len > maxBytes ? maxBytes : len).first;
      
      final tags = await readExifFromBytes(bytes);
      
      if (tags.containsKey('Image Model')) {
          return tags['Image Model']?.printable;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static final Map<String, Rect?> _holeCache = {};

  /// Detects a transparent "hole" in an image (e.g. PNG template).
  /// Returns a normalized Rect (0.0 - 1.0) defining the bounds of the transparent area.
  /// Returns null if no hole is found or error occurs.
  static Future<Rect?> detectHole(String path) async {
    if (_holeCache.containsKey(path)) return _holeCache[path];

    try {
      // Offload to Isolate
      try {
        final List<double>? bounds = await Isolate.run(() async {
            final f = File(path);
            if (!f.existsSync()) return null; // Sync inside Isolate for simplicity
            
            final bytes = f.readAsBytesSync();
            final image = img.decodeImage(bytes);
            if (image == null) return null;
            
            int minX = image.width;
            int maxX = 0;
            int minY = image.height;
            int maxY = 0;
            bool found = false;

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
            
            if (!found) return null;

            return <double>[
               minX / image.width,
               minY / image.height,
               (maxX + 1) / image.width,
               (maxY + 1) / image.height
            ];
        });
        
        if (bounds == null) {
           _holeCache[path] = null;
           return null;
        }
        
        final rect = Rect.fromLTRB(bounds[0], bounds[1], bounds[2], bounds[3]);
        _holeCache[path] = rect;
        return rect;

      } catch (e) {
         debugPrint("Isolate error for $path: $e");
         return null;
      }

    } catch (e) {
      debugPrint("Error detecting hole in $path: $e");
      return null;
    }
  }
}
