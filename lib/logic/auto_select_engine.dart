import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';

// TOP LEVEL FUNCTIONS (Must be outside class for compute)

Future<_PhotoMeta?> _getMetadataTask(String path) async {
    try {
      final file = File(path);
      // Fast path: File Mod Time if EXIF fails
      DateTime date = file.lastModifiedSync(); // Sync in isolate is fine
      
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
       // Decode
       final image = img.decodeImage(bytes);
       if (image == null) return size.toDouble(); 

       // Optimization: 
       // 1. Resize to 720px
       // 2. Center Crop 60%
       
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
       
       // Gray
       final grayscale = img.grayscale(cropped);
       
       double variance = _laplacianVariance(grayscale);
       
       double sizeScore = size / (1024 * 1024); // MB
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
     
     // Skip borders
     for (int y = 1; y < image.height - 1; y++) {
        for (int x = 1; x < image.width - 1; x++) {
           final p = image.getPixel(x, y);
           final lum = p.r; // Grayscale r=g=b
           
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

    // 1. Get Metadata (Parallel)
    List<_PhotoMeta> metas = [];
    
    onProgress?.call("Lendo Metadados (Multi-Core)...", 0, allPaths.length, 0);

    // Parallelize in chunks of 8
    final metaResults = await _processInBatches(
      allPaths, 
      (path) => compute(_getMetadataTask, path),
      concurrency: 8,
      onProgress: (done) => onProgress?.call("Lendo Metadados...", done, allPaths.length, 0)
    );
    
    for (var m in metaResults) {
      if (m != null) metas.add(m);
    }
    
    onProgress?.call("Agrupando...", allPaths.length, allPaths.length, 0);

    // 2. Sort & Group (Fast enough on main thread)
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

    // 3. Analyze Groups (Parallel)
    List<String> winners = [];
    int processedPhotos = 0;
    
    // Flatten list of photos that need scoring (groups > 1)
    // Actually, we process Groups. If group size > 1, all photos in it need scoring.
    // If we score ALL photos in parallel first, it's faster than doing it per group.
    
    List<_PhotoMeta> photosToScore = [];
    for (var g in groups) {
      if (g.length > 1) {
        photosToScore.addAll(g);
      } else {
        winners.add(g[0].path); // Singletons automatically win
      }
    }
    
    // Run scoring on photosToScore
    Map<String, double> scores = {};
    if (photosToScore.isNotEmpty) {
       onProgress?.call("Analisando Detalhes (Multi-Core)...", 0, photosToScore.length, winners.length);
       
       final scoreResults = await _processInBatches(
          photosToScore,
          (meta) async {
             final s = await compute(_calculateScoreTask, meta.path);
             return MapEntry(meta.path, s);
          },
          concurrency: 6, // Heavy task, keep slightly lower than 8 to avoid UI freeze completely
          onProgress: (done) => onProgress?.call("Analisando...", done, photosToScore.length, winners.length)
       );
       
       for (var entry in scoreResults) {
          scores[entry.key] = entry.value;
       }
    }

    // Resolve Winners
    for (var g in groups) {
      if (g.length > 1) {
         String best = g[0].path;
         double bestScore = -1;
         
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
    List<Future<R>> active = [];
    List<R> results = [];
    int i = 0;
    
    while (i < items.length || active.isNotEmpty) {
       // Fill pool
       while (active.length < concurrency && i < items.length) {
          final item = items[i];
          // We wrap the future to know which one finished? 
          // Actually simplest is just wait for ANY to finish.
          // But Future.any returns the value, not the index.
          
          // Better approach: Use a pool loop.
          // But to keep simple order, we can just push all and wait? No, heavy memory.
          
          // Let's execute and append to active.
          active.add(worker(item));
          i++;
       }
       
       if (active.isEmpty) break;

       // Wait for at least one to finish to make room?
       // Future.wait(active) waits for ALL.
       // We want a sliding window.
       
       // Quick and dirty sliding window:
       // Just split into chunks.
       // It's less efficient if one task is slow, but much simpler code.
       // The user said "use more power", chunks use 100% power of N threads until chunk ensures.
       // Let's use Chunking.
       break; // Switch to simpler chunk Logic below
    }
    
    // Chunk Implementation
    results = [];
    for (var j = 0; j < items.length; j += concurrency) {
       int end = (j + concurrency < items.length) ? j + concurrency : items.length;
       final chunk = items.sublist(j, end);
       final chunkFutures = chunk.map((item) => worker(item));
       
       final chunkResults = await Future.wait(chunkFutures);
       results.addAll(chunkResults);
       onProgress?.call(results.length);
    }
    return results;
  }

}

class _PhotoMeta {
   final String path;
   final DateTime dateTaken;
   _PhotoMeta(this.path, this.dateTaken);
}
