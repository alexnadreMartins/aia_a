import 'dart:io';
import 'package:exif/exif.dart';
import 'package:image/image.dart' as img_tools;
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

class PhotoMetadata {
  final DateTime? dateTaken;
  final String? cameraModel;
  final String? cameraSerial;
  final String? artist;
  final int orientation; 
  final bool isPortrait;

  PhotoMetadata({
    this.dateTaken,
    this.cameraModel,
    this.cameraSerial,
    this.artist,
    this.orientation = 1,
    this.isPortrait = false,
  });
}

class MetadataHelper {
  static Future<List<PhotoMetadata>> getMetadataBatch(List<String> paths) async {
    final List<PhotoMetadata> results = [];
    for (var path in paths) {
      results.add(await _extractMetadataForPath(path));
    }
    return results;
  }

  static Future<PhotoMetadata> _extractMetadataForPath(String path) async {
      final file = File(path);
      if (!file.existsSync()) return PhotoMetadata();

      Uint8List bytes;
      try {
           final raf = await file.open();
           // Increased to 512KB to ensure Camera Model is captured (TimeShift needs this)
           bytes = await raf.read(512 * 1024); 
           await raf.close();
      } catch (e) {
           bytes = Uint8List(0);
      }
      
      return _extractSingleMetadata(bytes, await file.lastModified());
  }

  static Future<PhotoMetadata> _extractSingleMetadata(Uint8List bytes, DateTime fallbackDate) async {
    Map<String, IfdTag> data = await readExifFromBytes(bytes);

    // Deep Scan removed to prevent blocking. 2MB buffer should suffice.
    
    DateTime? date;
    String? camera;
    String? serial;
    String? artist;
    int orientation = 1;

    // 1. Extract Date
    if (data.containsKey('Image DateTime')) {
      final dateStr = data['Image DateTime']?.toString();
      if (dateStr != null) {
        try {
          final parts = dateStr.split(' ');
          final dateParts = parts[0].replaceAll(':', '-');
          date = DateTime.parse('$dateParts ${parts[1]}');
        } catch (_) {}
      }
    }
    
    // Fallback to provided file date
    date ??= fallbackDate;

    // 2. Extract Camera
    if (data.containsKey('Image Model')) {
      camera = data['Image Model']?.toString();
    } else if (data.containsKey('Exif.Image.Model')) {
      camera = data['Exif.Image.Model']?.toString();
    }
    
    // Fallback if Camera is Unknown: Use Folder Name or "Unknown Camera"
    if (camera == null || camera.isEmpty) {
        if (data.containsKey('Image Make')) {
           camera = data['Image Make']?.toString();
        }
    }

    // 2.1 Extract Serial
    if (data.containsKey('Image BodySerialNumber')) {
      serial = data['Image BodySerialNumber']?.toString();
    } else if (data.containsKey('Exif Photo BodySerialNumber')) {
      serial = data['Exif Photo BodySerialNumber']?.toString();
    } else if (data.containsKey('Image CameraSerialNumber')) {
      serial = data['Image CameraSerialNumber']?.toString();
    } else if (data.containsKey('MakerNote SerialNumber')) {
      serial = data['MakerNote SerialNumber']?.toString();
    } else if (data.containsKey('Exif.MakerNote.SerialNumber')) {
      serial = data['Exif.MakerNote.SerialNumber']?.toString();
    }

    // 2.2 Extract Artist
    if (data.containsKey('Image Artist')) {
      artist = data['Image Artist']?.toString();
    } else if (data.containsKey('Exif.Image.Artist')) {
      artist = data['Exif.Image.Artist']?.toString();
    } else if (data.containsKey('Image OwnerName')) {
      artist = data['Image OwnerName']?.toString();
    }

    // 3. Extract Orientation
    if (data.containsKey('Image Orientation')) {
      final orientStr = data['Image Orientation']?.toString();
      if (orientStr != null) {
        if (orientStr.contains('Rotated 90 CW')) orientation = 6;
        else if (orientStr.contains('Rotated 180')) orientation = 3;
        else if (orientStr.contains('Rotated 270 CW')) orientation = 8;
        else {
           final match = RegExp(r'\d+').firstMatch(orientStr);
           if (match != null) orientation = int.parse(match.group(0)!);
        }
      }
    }

    // Determine if it's visually portrait
    bool portrait = (orientation == 6 || orientation == 8);
    
    // 4. Fallback: Heavy decoding only if needed
    if (!portrait && orientation == 1) {
       try {
         final info = img_tools.decodeImage(bytes);
         if (info != null && info.height > info.width) {
            portrait = true;
         }
       } catch (_) {}
    }

    return PhotoMetadata(
      dateTaken: date,
      cameraModel: camera,
      cameraSerial: serial,
      artist: artist,
      orientation: orientation,
      isPortrait: portrait,
    );
  }

  static double orientationToDegrees(int orientation) {
    switch (orientation) {
      case 3: return 180;
      case 6: return 90;
      case 8: return 270;
      default: return 0;
    }
  }
}

