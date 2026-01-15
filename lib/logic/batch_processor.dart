import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import '../models/batch_image_model.dart';
import 'editor/color_matrix_helper.dart';

class BatchProcessor {
  
  /// Process a list of images and save them to outputDir.
  /// If [outputDir] is null, the original files will be overwritten.
  /// Returns a stream of progress updates (completed count).
  static Stream<int> processBatch(List<BatchImage> images, String? outputDir) async* {
    int completed = 0;
    
    // Create output dir if needed and provided
    if (outputDir != null) {
      final outDir = Directory(outputDir);
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
    }

    // Process sequentially
    for (var image in images) {
      // Determine destination
      String destPath;
      if (outputDir == null) {
        destPath = image.path; // Overwrite
      } else {
        final filename = path.basename(image.path);
        destPath = path.join(outputDir, filename);
      }

      if (image.adjustments != null) {
        await compute(_processOneImage, _ProcessJob(image, destPath));
      } else {
        // If overwrite mode and no adjustments, do nothing (file is already there)
        if (outputDir != null) {
           final filename = path.basename(image.path); // Redundant calc but safe
           File(image.path).copySync(destPath);
        }
      }
      completed++;
      yield completed;
    }
  }

  static Future<void> _processOneImage(_ProcessJob job) async {
    try {
      final file = File(job.image.path);
      final bytes = await file.readAsBytes();
      var rawImg = img.decodeImage(bytes);
      
      if (rawImg == null) return; // Error decoding

      // Apply Matrix
      final adj = job.image.adjustments!;
      final matrix = ColorMatrixHelper.getMatrix(
        exposure: adj.exposure,
        contrast: adj.contrast,
        brightness: adj.brightness,
        saturation: adj.saturation,
        temperature: adj.temperature,
        tint: adj.tint,
      );
      
      rawImg = ColorMatrixHelper.applyColorMatrix(rawImg, matrix);
      
      // Resize? (Optional, maybe keep original size)

      // Encode
      final jpg = img.encodeJpg(rawImg, quality: 90);
      
      final filename = path.basename(job.image.path);
      final destPath = path.join(job.outputDir, filename);
      File(destPath).writeAsBytesSync(jpg);
      
    } catch (e) {
      print("Error processing ${job.image.path}: $e");
    }
  }
}

class _ProcessJob {
  final BatchImage image;
  final String outputDir;
  _ProcessJob(this.image, this.outputDir);
}
