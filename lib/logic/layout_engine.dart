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

  List<PhotoItem> calculateFlexibleGridLayout(List<Map<String, dynamic>> photosData, {int maxRows = 3}) {
    if (photosData.isEmpty) return [];

    // Group photos into rows
    int photosPerPage = photosData.length;
    int itemsPerRow = (photosPerPage / maxRows).ceil();
    if (itemsPerRow < 1) itemsPerRow = 1;

    double currentY = margin;
    List<PhotoItem> layout = [];
    int zIndex = 0;

    for (int i = 0; i < photosData.length; i += itemsPerRow) {
      final rowItems = photosData.sublist(i, (i + itemsPerRow) < photosData.length ? (i + itemsPerRow) : photosData.length);
      
      // Calculate total ratio of the row to distribute width
      double totalRatio = 0;
      for (var p in rowItems) {
        totalRatio += (p['ratio'] as double);
      }

      double availableWidth = pageWidth - (rowItems.length + 1) * margin;
      double currentX = margin;
      
      // To keep it balanced, we find the "ideal" height for this row
      // RowHeight = AvailableWidth / TotalRatio
      double rowHeight = availableWidth / totalRatio;
      
      // Caps row height to avoid extreme vertical stretching if few photos
      double maxRowHeight = (pageHeight - (maxRows + 1) * margin) / maxRows;
      if (rowHeight > maxRowHeight) rowHeight = maxRowHeight;

      for (var photo in rowItems) {
        double ratio = photo['ratio'] as double;
        double pWidth = rowHeight * ratio;
        
        // If the rowHeight was capped, we might not use full width, which is fine to keep proportions
        
        layout.add(PhotoItem(
          id: const Uuid().v4(),
          path: photo['path'] as String,
          x: currentX,
          y: currentY,
          width: pWidth,
          height: rowHeight,
          rotation: 0,
          zIndex: zIndex++,
          exifOrientation: photo['orientation'] ?? 1,
        ));
        
        currentX += pWidth + margin;
      }
      
      currentY += rowHeight + margin;
    }

    return layout;
  }
}
