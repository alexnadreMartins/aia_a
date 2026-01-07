import 'dart:math';
import '../models/project_model.dart';
import '../models/asset_model.dart';
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
          id: Uuid().v4(),
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

class SmartFlow {
  static Future<List<List<LibraryAsset>>> generateFlow(
    List<LibraryAsset> assets, {
    required bool isProjectHorizontal,
    Duration timeGapThreshold = const Duration(minutes: 30),
  }) async {
    if (assets.isEmpty) return [];

    // 1. Sort Chronologically
    assets.sort((a, b) {
      final dA = a.fileDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dB = b.fileDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dA.compareTo(dB);
    });

    // 2. Group by Day & Time Gap (Scene)
    List<List<LibraryAsset>> groups = [];
    if (assets.isNotEmpty) {
      List<LibraryAsset> currentGroup = [assets.first];
      for (int i = 1; i < assets.length; i++) {
        final prev = assets[i - 1];
        final curr = assets[i];
        
        final prevDate = prev.fileDate ?? DateTime(1970);
        final currDate = curr.fileDate ?? DateTime(1970);

        bool sameDay = prevDate.year == currDate.year && prevDate.month == currDate.month && prevDate.day == currDate.day;
        bool longGap = currDate.difference(prevDate).abs() > timeGapThreshold;

        if (!sameDay || longGap) {
          groups.add(currentGroup);
          currentGroup = [];
        }
        currentGroup.add(curr);
      }
      groups.add(currentGroup);
    }

    // 3. Generate Pages based on Rules
    List<List<LibraryAsset>> pages = [];

    for (var group in groups) {
      // Split into V and H
      List<LibraryAsset> verticals = group.where((a) => (a.height ?? 0) > (a.width ?? 0)).toList();
      List<LibraryAsset> horizontals = group.where((a) => (a.width ?? 0) >= (a.height ?? 0)).toList();

      // Rule: Opening (First Vertical of the Group/Day) - Logic suggests first page if possible?
      // User Spec: "First Vertical of Day = Opening; Last Vertical = Closing"
      // We will handle this by checking if it's the start of a group.
      
      // -- VERTICALS --
      // If Project is Horizontal: Verticals go 2 per page (Split)
      // If Project is Vertical: Verticals go 1 per page (Full)
      int vPerPege = isProjectHorizontal ? 2 : 1;
      
      int vIndex = 0;
      
      // Special Rule: Opening Page (First Vertical of the Group is Solitary)
      // Only applies if we have verticals and we are grouping by day.
      if (verticals.isNotEmpty && isProjectHorizontal) {
         // Add first vertical alone
         pages.add([verticals[0]]);
         vIndex = 1; // Start loop from second
      }
      
      for (int i = vIndex; i < verticals.length; i += vPerPege) {
        int end = (i + vPerPege < verticals.length) ? i + vPerPege : verticals.length;
        pages.add(verticals.sublist(i, end));
      }

      // -- HORIZONTALS --
      // If Project is Horizontal: Horizontals go 1 per page (Full)
      // If Project is Vertical: Horizontals go 2 per page (Split)
      int hPerPage = isProjectHorizontal ? 1 : 2;

      for (int i = 0; i < horizontals.length; i += hPerPage) {
        int end = (i + hPerPage < horizontals.length) ? i + hPerPage : horizontals.length;
        pages.add(horizontals.sublist(i, end));
      }
    }

    return pages;
  }
}
