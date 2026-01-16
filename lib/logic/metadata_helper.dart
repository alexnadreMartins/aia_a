import 'dart:io';
import 'package:exif/exif.dart';
import 'package:image/image.dart' as img_tools;
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

class PhotoMetadata {
  final DateTime? dateTaken;
  final String? cameraModel;
  final String? cameraSerial;
  final int orientation; 
  final bool isPortrait;

  PhotoMetadata({
    this.dateTaken,
    this.cameraModel,
    this.cameraSerial,
    this.orientation = 1,
    this.isPortrait = false,
  });
}

class MetadataHelper {
  static Future<List<PhotoMetadata>> getMetadataBatch(List<String> paths) async {
    final List<_MetadataInput> inputs = [];
    for (var path in paths) {
      final file = File(path);
      if (await file.exists()) {
      if (await file.exists()) {
        Uint8List bytes;
        try {
           // Read only first 128KB to avoid loading full image into memory
           // Most EXIF data is in the header.
           final randomAccessFile = await file.open();
           bytes = await randomAccessFile.read(128 * 1024); 
           await randomAccessFile.close();
        } catch (e) {
           // Fallback or just empty
           bytes = Uint8List(0);
        }
        
        final stats = await file.stat();
        inputs.add(_MetadataInput(path, bytes, stats.modified));
      }
      }
    }
    
    return compute(_extractMetadataBatchInBackground, inputs);
  }

  static Future<List<PhotoMetadata>> _extractMetadataBatchInBackground(List<_MetadataInput> inputs) async {
    final List<PhotoMetadata> results = [];
    for (var input in inputs) {
      results.add(await _extractSingleMetadata(input));
    }
    return results;
  }

  static Future<PhotoMetadata> _extractSingleMetadata(_MetadataInput input) async {
    final data = await readExifFromBytes(input.bytes);

    DateTime? date;
    String? camera;
    String? serial;
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
    date ??= input.fallbackDate;

    // 2. Extract Camera
    if (data.containsKey('Image Model')) {
      camera = data['Image Model']?.toString();
    } else if (data.containsKey('Exif.Image.Model')) {
      camera = data['Exif.Image.Model']?.toString();
    }
    
    // Fallback if Camera is Unknown: Use Folder Name or "Unknown Camera"
    if (camera == null || camera.isEmpty) {
        // Try to guess from Manufacturer
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
         final info = img_tools.decodeImage(input.bytes);
         if (info != null && info.height > info.width) {
            portrait = true;
         }
       } catch (_) {}
    }

    return PhotoMetadata(
      dateTaken: date,
      cameraModel: camera,
      cameraSerial: serial,
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

class _MetadataInput {
  final String path;
  final Uint8List bytes;
  final DateTime fallbackDate;
  _MetadataInput(this.path, this.bytes, this.fallbackDate);
}
