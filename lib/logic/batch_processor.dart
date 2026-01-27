import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import '../models/batch_image_model.dart';
import 'editor/color_matrix_helper.dart';

class BatchProgress {
  final int processedCount;
  final int totalCount;
  final String? lastError;
  final List<String> failedPaths;

  BatchProgress({
    required this.processedCount,
    required this.totalCount,
    this.lastError,
    required this.failedPaths,
  });
}

class BatchProcessor {
  
  /// Process a list of images and save them to outputDir.
  /// If [outputDir] is null, the original files will be overwritten.
  /// Returns a stream of progress updates.
  static Stream<BatchProgress> processBatch(List<BatchImage> images, String? outputDir) async* {
    int completed = 0;
    int total = images.length;
    List<String> failedPaths = [];
    String? lastError;

    // Create output dir if needed and provided
    if (outputDir != null) {
      final outDir = Directory(outputDir);
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
    }

    // Concurrency Control
    int maxConcurrent = 6;
    int running = 0;
    final queue = List<BatchImage>.from(images);
    final completer = Completer<void>();

    // Helper to emit progress
    void emit() {
        // We can't yield from inside a closure, so we might need a controller or just straightforward chunking.
        // For simplicity in a generator, let's use chunks.
    }

    // Alternative: Chunked processing to simplify Stream generation
    // We process 'maxConcurrent' items at a time.
    
    for (var i = 0; i < total; i += maxConcurrent) {
      final end = (i + maxConcurrent < total) ? i + maxConcurrent : total;
      final chunk = images.sublist(i, end);
      
      final futures = chunk.map((image) async {
         try {
            await _processSingle(image, outputDir);
         } catch (e) {
            print("Error processing ${image.path}: $e");
            failedPaths.add(image.path);
            lastError = e.toString();
         } finally {
            completed++;
         }
      });
      
      await Future.wait(futures);
      yield BatchProgress(
        processedCount: completed,
        totalCount: total,
        lastError: lastError,
        failedPaths: List.from(failedPaths)
      );
    }
  }

  static Future<void> _processSingle(BatchImage image, String? outputDir) async {
       // Determine destination
      String destPath;
      if (outputDir == null) {
        destPath = image.path; // Overwrite
      } else {
        final filename = path.basename(image.path);
        destPath = path.join(outputDir, filename);
      }

      if (image.adjustments != null) {
        // Process with adjustments
        await compute(_processOneImageCompute, _ProcessJob(image, destPath));
      } else {
        // No adjustments
        if (outputDir != null) {
           // Simple Copy
           File(image.path).copySync(destPath);
        } else {
           // Overwrite with no changes = do nothing
        }
      }
  }

  // Isolated function
  static Future<void> _processOneImageCompute(_ProcessJob job) async {
    final tempPath = "${job.destinationPath}.tmp";
    try {
      final file = File(job.image.path);
      final bytes = await file.readAsBytes();
      var rawImg = img.decodeImage(bytes);
      
      if (rawImg == null) throw Exception("Could not decode image");

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
      
      // Encode
      final jpg = img.encodeJpg(rawImg, quality: 90);
      
      // Atomic Write
      // 1. Write to .tmp
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(jpg, flush: true);
      
      // 2. Rename to dest (Overwrite)
      // On Windows, rename might fail if dest exists and is open. 
      // We might need to delete dest first if it exists.
      final destFile = File(job.destinationPath);
      if (await destFile.exists()) {
         try {
           await destFile.delete();
         } catch (_) {
           // If delete fails, try rename anyway (might be same file? no, we are writing to tmp)
           // If delete fails, it might be locked.
           throw Exception("Target file is locked or cannot be overwritten.");
         }
      }
      await tempFile.rename(job.destinationPath);
      
    } catch (e) {
      // Cleanup temp
      try {
        final tmp = File(tempPath);
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      
      rethrow;
    }
  }
}

class _ProcessJob {
  final BatchImage image;
  final String destinationPath;
  _ProcessJob(this.image, this.destinationPath);
}
