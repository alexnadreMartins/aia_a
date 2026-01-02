import 'dart:math';
import '../models/project_model.dart';
import 'package:uuid/uuid.dart';

class AutoLayoutEngine {
  final double pageWidth;
  final double pageHeight;
  final double margin;

  AutoLayoutEngine({
    required this.pageWidth,
    required this.pageHeight,
    this.margin = 10,
  });

  List<PhotoItem> calculateMasonryLayout(List<Map<String, dynamic>> photosData) {
    if (photosData.isEmpty) return [];

    // Sort by area (approximation using width * height)
    // Python code: photos.sort(key=lambda p: p['width'] * p['height'], reverse=True)
    photosData.sort((a, b) {
       final areaA = (a['width'] as num) * (a['height'] as num);
       final areaB = (b['width'] as num) * (b['height'] as num);
       return areaB.compareTo(areaA);
    });

    double avgRatio = 0;
    for(var p in photosData) {
      avgRatio += (p['ratio'] as double);
    }
    avgRatio /= photosData.length;
 
    // Estimate columns
    // Python: no_cols = max(1, min(4, int(round(self.page_width / self.page_height * avg_ratio * 2)))
    int noCols = max(1, min(4, ((pageWidth / pageHeight) * avgRatio * 2).round()));

    List<double> colHeights = List.filled(noCols, margin);
    double colWidth = (pageWidth - (noCols + 1) * margin) / noCols;

    List<PhotoItem> layout = [];
    int zIndex = 0;

    for (var photo in photosData) {
      // Find shortest column
      // Python: col_idx = col_heights.index(min(col_heights))
      int colIdx = 0;
      double minH = colHeights[0];
      for(int i=1; i<noCols; i++) {
        if(colHeights[i] < minH) {
          minH = colHeights[i];
          colIdx = i;
        }
      }

      double photoRatio = photo['ratio'] as double;
      double pWidth = colWidth;
      double pHeight = pWidth / photoRatio;

      double x = margin + colIdx * (colWidth + margin);
      double y = colHeights[colIdx];

      layout.add(PhotoItem(
        id: const Uuid().v4(),
        path: photo['path'] as String,
        x: x,
        y: y,
        width: pWidth,
        height: pHeight,
        rotation: 0,
        zIndex: zIndex++,
      ));

      colHeights[colIdx] += pHeight + margin;
    }

    return layout;
  }
}
