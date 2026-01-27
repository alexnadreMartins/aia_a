import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:exif/exif.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import '../models/batch_image_model.dart';
import 'dart:async';

class BatchScannerService {
  
  /// Scans a directory recursively and returns a list of [BatchImage] with metadata.
  /// Runs on a separate isolate to avoid blocking the UI.
  /// [onlyUsedInAlbums] : If true, only scans for .alem files and extracts images used in pages.
  static Future<List<BatchImage>> scanDirectory(String rootPath, {bool onlyUsedInAlbums = false}) async {
    if (onlyUsedInAlbums) {
       return await compute(_scanWorkerUsedOnly, rootPath);
    }
    return await compute(_scanWorker, rootPath);
  }

  /// Worker: Scans only images used in .alem projects found in subfolders
  static Future<List<BatchImage>> _scanWorkerUsedOnly(String rootPath) async {
      final rootDir = Directory(rootPath);
      if (!rootDir.existsSync()) return [];

      final Set<String> uniquePaths = {};
      final List<BatchImage> results = [];
      
      // 1. Find .alem files
      final projectFiles = rootDir.listSync(recursive: true)
         .whereType<File>()
         .where((f) => p.extension(f.path).toLowerCase() == '.alem');

      for (var pFile in projectFiles) {
          try {
             String content;
             // Try ZIP first (Standard .alem)
             try {
                final bytes = pFile.readAsBytesSync();
                final archive = ZipDecoder().decodeBytes(bytes);
                final jsonFile = archive.findFile('project.json');
                if (jsonFile != null) {
                   content = utf8.decode(jsonFile.content as List<int>);
                } else {
                   // Fallback: Maybe it IS a JSON file (Legacy)
                   content = utf8.decode(bytes);
                }
             } catch (_) {
                // Last Resort: Read as text (Legacy/Corrupt)
                content = pFile.readAsStringSync(encoding: latin1);
             }
             
             final jsonMap = jsonDecode(content);
             
             // Extract Pages
             if (jsonMap['pages'] != null) {
                final pages = jsonMap['pages'] as List;
                for (var page in pages) {
                   if (page['photos'] != null) {
                      final photos = page['photos'] as List;
                      for (var photo in photos) {
                         final path = photo['path'] as String?;
                         if (path != null && path.isNotEmpty) {
                            if (File(path).existsSync()) {
                               uniquePaths.add(path);
                            }
                         }
                      }
                   }
                }
             }
          } catch (e) {
             print("Error parsing ${pFile.path}: $e");
          }
      }
      
      // Convert to BatchImage
      for (var path in uniquePaths) {
         DateTime? date;
         try {
           date = File(path).lastModifiedSync();
         } catch (_) {}
         
         results.add(BatchImage(
            path: path,
            dateCaptured: date,
            cameraModel: null,
            brightness: 0.5
         ));
      }
      
      return results;
  }

  /// Worker function that runs in the isolate
  static Future<List<BatchImage>> _scanWorker(String rootPath) async {
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) return [];

    final List<BatchImage> results = [];
    
    // 1. Find all image files
    final List<FileSystemEntity> entities = rootDir.listSync(recursive: true);
    final imageFiles = entities.whereType<File>().where((f) {
      final ext = p.extension(f.path).toLowerCase();
      return ['.jpg', '.jpeg', '.png', '.webp'].contains(ext);
    }).toList();

    // 2. Extract Metadata (This can be slow, so we do simpler version or check need)
    // For 40,000 images, reading usage tags for EVERY image is very slow (approx 50ms per image = 30 mins).
    // We should optimize: 
    // - Date: File Modified Date (Fastest) vs EXIF (Correct). 
    // - Camera: Only needed if grouping by camera.
    // Strategy: Read File Modified Date first. EXIF only on demand or if requested?
    // The user requested "Catalog by Day, Photographer, Histogram". 
    // To do this fast, we need a smarter approach. Maybe reading headers only.
    
    for (var file in imageFiles) {
       DateTime? date;
       String? camera;
       double? brightness;

       // Fast: File Date
       try {
         date = file.lastModifiedSync();
       } catch (e) {}

       // Slow: EXIF (We will try to read just the header bytes here if possible, but package 'exif' reads file).
       // Optimization: For this demo, maybe we skip full EXIF for all 40k immediately? 
       // Or we do it in batches?
       // Let's implement a 'lazy' load or just accept the cost for now but mention it.
       // Actually 'exif' package is pure dart and can be slow. 
       
       // For the prototype, we will pull EXIF for a subset or just rely on FileTime for speed,
       // BUT the user asked for "Photographer". We MUST read EXIF.
       // Let's read EXIF but handle errors gracefully.
       
       // To make it usable for 40k images, we usually cache this or store in a DB. 
       // Here we might just scan.
       
       // NOTE: We are NOT reading bytes here to keep the initial scan fast.
       // We will add a method 'enrichMetadata' to load EXIF later or in chunks.
       
       results.add(BatchImage(
         path: file.path, 
         dateCaptured: date, 
         cameraModel: null, // To be loaded
         brightness: 0.5    // To be calculated
       ));
    }

    return results;
  }
  
  /// Loads deeper metadata (EXIF) for a chunk of images.
  /// Can be called in background while UI is active.
  static Future<List<BatchImage>> enrichMetadata(List<BatchImage> images) async {
      return await compute(_enrichWorker, images);
  }

  static Future<List<BatchImage>> _enrichWorker(List<BatchImage> images) async {
      List<BatchImage> enriched = [];
      
      for (var img in images) {
         DateTime? date = img.dateCaptured;
         String? camera = img.cameraModel;
         
         try {
             final fileBytes = await File(img.path).readAsBytes();
             final data = await readExifFromBytes(fileBytes);
             
             if (data.isNotEmpty) {
                // Date
                if (data.containsKey('Image DateTime')) {
                   final dateTag = data['Image DateTime']?.printable;
                   // Format: YYYY:MM:DD HH:MM:SS
                   if (dateTag != null) {
                      try {
                        final parts = dateTag.split(' ');
                        final dateParts = parts[0].split(':');
                        final timeParts = parts[1].split(':');
                        date = DateTime(
                          int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]),
                          int.parse(timeParts[0]), int.parse(timeParts[1]), int.parse(timeParts[2])
                        );
                      } catch (_) {}
                   }
                }
                
                // Camera
                if (data.containsKey('Image Model')) {
                   camera = data['Image Model']?.printable;
                }
             }
         } catch (e) {
            // print("Error reading EXIF for ${img.path}: $e");
         }
         
         enriched.add(img.copyWith(
           dateCaptured: date,
           cameraModel: camera ?? "Unknown"
         ));
      }
      return enriched;
  }
}
