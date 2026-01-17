import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';
// import 'package:face_detection_tflite/face_detection_tflite.dart'; // REMOVED
import 'dart:typed_data';

// TOP LEVEL FUNCTIONS (Must be outside class for compute)

// TOP LEVEL FUNCTIONS (Must be outside class for compute)

Future<_PhotoMeta?> _getMetadataTask(String path) async {
    try {
      final file = File(path);
      // Fast path: File Mod Time if EXIF fails
      DateTime date = file.lastModifiedSync(); 
      
      try {
        final bytes = file.readAsBytesSync();
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
      return _PhotoMeta(path, date);
    } catch (e) {
      return null;
    }
}

Future<double> _calculateScoreTask(String path) async {
     try {
       final file = File(path);
       final size = await file.length();
       
       final bytes = await file.readAsBytes();
       final image = img.decodeImage(bytes);
       if (image == null) return size.toDouble(); 

       // Optimization: Resize to 720px & Center Crop
       img.Image diffImage = image;
       if (image.width > 720) {
          diffImage = img.copyResize(image, width: 720);
       }
       
       final cropped = img.copyCrop(
          diffImage, 
          x: (diffImage.width * 0.2).toInt(), 
          y: (diffImage.height * 0.2).toInt(), 
          width: (diffImage.width * 0.6).toInt(), 
          height: (diffImage.height * 0.6).toInt()
       );
       
       final grayscale = img.grayscale(cropped);
       double variance = _laplacianVariance(grayscale);
       
       // Score = Variance (Sharpness) + Size (Mbps bonus)
       double sizeScore = size / (1024 * 1024); 
       double sharpScore = variance / 10.0; 
       
       return (sharpScore) + (sizeScore * 0.5);

     } catch (e) {
       print("Error scoring $path: $e");
       return 0.0;
     }
}

double _laplacianVariance(img.Image image) {
     double sum = 0;
     double sumSq = 0;
     int count = 0;
     
     for (int y = 1; y < image.height - 1; y++) {
        for (int x = 1; x < image.width - 1; x++) {
           final p = image.getPixel(x, y);
           final lum = p.r;
           
           final p_up = image.getPixel(x, y-1).r;
           final p_down = image.getPixel(x, y+1).r;
           final p_left = image.getPixel(x-1, y).r;
           final p_right = image.getPixel(x+1, y).r;
           
           final lap = (p_up + p_down + p_left + p_right) - (4 * lum);
           
           sum += lap;
           sumSq += (lap * lap);
           count++;
        }
     }
     
     if (count == 0) return 0;
     double mean = sum / count;
     double variance = (sumSq / count) - (mean * mean);
     return variance;
}


class AutoSelectEngine {
  
  static Future<List<String>> findBestPhotos(List<String> allPaths, {
    Function(String phase, int processed, int total, int selected)? onProgress,
  }) async {
    if (allPaths.isEmpty) return [];

    // 1. Get Metadata
    onProgress?.call("Lendo Metadados...", 0, allPaths.length, 0);

    // Concurrency Boost: Increased to 12
    final metaResults = await _processInBatches(
      allPaths, 
      (path) => compute(_getMetadataTask, path),
      concurrency: 12, 
      onProgress: (done) => onProgress?.call("Lendo Metadados...", done, allPaths.length, 0)
    );
    
    List<_PhotoMeta> metas = [];
    for (var m in metaResults) if (m != null) metas.add(m);
    
    // 2. Sort & Group
    metas.sort((a, b) => a.dateTaken.compareTo(b.dateTaken));

    List<List<_PhotoMeta>> groups = [];
    if (metas.isNotEmpty) {
      List<_PhotoMeta> currentGroup = [metas[0]];
      for (int i = 1; i < metas.length; i++) {
        final prev = currentGroup.last;
        final curr = metas[i];
        final diff = curr.dateTaken.difference(prev.dateTaken).inSeconds.abs();
        if (diff <= 5) { 
           currentGroup.add(curr);
        } else {
           groups.add(currentGroup);
           currentGroup = [curr];
        }
      }
      groups.add(currentGroup);
    }

    // 3. Analyze Groups
    List<String> winners = [];
    List<_PhotoMeta> photosToScore = [];
    
    // Identify photos that need scoring
    for (var g in groups) {
      if (g.length > 1) {
        photosToScore.addAll(g);
      } else {
        winners.add(g[0].path); 
      }
    }
    
    Map<String, double> scores = {};
    
    if (photosToScore.isNotEmpty) {
       // A. Calculate Sharpness First (Base Score)
       onProgress?.call("Analisando Nitidez...", 0, photosToScore.length, winners.length);
       
       // Concurrency Boost: Increased to 12 for maximum CPU utilization
       final scoreResults = await _processInBatches(
          photosToScore,
          (meta) async {
             final s = await compute(_calculateScoreTask, meta.path);
             return MapEntry(meta.path, s);
          },
          concurrency: 12, 
          onProgress: (done) => onProgress?.call("Analisando Nitidez...", done, photosToScore.length, winners.length)
       );
       
       for (var entry in scoreResults) {
          scores[entry.key] = entry.value; 
       }
    }

    // 4. Resolve Winners
    for (var g in groups) {
      if (g.length > 1) {
         String best = g[0].path;
         double bestScore = -99999;
         
         for (var p in g) {
            double s = scores[p.path] ?? 0.0;
            if (s > bestScore) {
                bestScore = s;
                best = p.path;
            }
         }
         winners.add(best);
      }
    }

    return winners;
  }
  
  static Future<List<R>> _processInBatches<T, R>(
    List<T> items, 
    Future<R> Function(T) worker, 
    {required int concurrency, Function(int done)? onProgress}
  ) async {
    List<R> results = [];
    int i = 0;
    while (i < items.length) {
       int end = (i + concurrency < items.length) ? i + concurrency : items.length;
       final chunk = items.sublist(i, end);
       final chunkFutures = chunk.map((item) => worker(item));
       final chunkResults = await Future.wait(chunkFutures);
       results.addAll(chunkResults);
       i += concurrency;
       onProgress?.call(results.length);
       await Future.delayed(Duration(milliseconds: 5)); 
    }
    return results;
  }

}

class _PhotoMeta {
   final String path;
   final DateTime dateTaken;
   _PhotoMeta(this.path, this.dateTaken);
}
