import 'dart:io';
import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:aia_album/models/project_model.dart'; // For AlbumPage, PhotoItem
import 'package:uuid/uuid.dart';

class SmartFlow {
  /// Sort, Group, and Generate Pages based on Layout Rules
  static Future<List<AlbumPage>> generate({
    required List<String> imagePaths,
    required double pageWidthMm,
    required double pageHeightMm,
  }) async {
    if (imagePaths.isEmpty) return [];

    // 1. Analyze Photos (Date, Orientation)
    List<_SmartPhoto> analyzed = [];
    for (var path in imagePaths) {
       analyzed.add(await _analyze(path));
    }

    // 2. Sort Chronologically
    analyzed.sort((a, b) => a.date.compareTo(b.date));

    // 3. Group by Day
    // Map<String (YYYY-MM-DD), List<_SmartPhoto>>
    Map<String, List<_SmartPhoto>> groupedByDay = {};
    for (var p in analyzed) {
       final dayKey = "${p.date.year}-${p.date.month}-${p.date.day}";
       groupedByDay.putIfAbsent(dayKey, () => []).add(p);
    }

    final isProjectHorizontal = pageWidthMm > pageHeightMm;
    List<AlbumPage> pages = [];

    // Helper to create a page
    AlbumPage createPage(List<_SmartPhoto> photosOnPage, {bool isOpening = false, bool isClosing = false}) {
        List<PhotoItem> items = [];
        
        if (photosOnPage.length == 1) {
           // Check Orientation
           if (photosOnPage[0].isVertical) {
               // Vertical Solo -> Right Half (User Request)
               items.add(PhotoItem(
                 path: photosOnPage[0].path,
                 x: pageWidthMm * 0.525, y: pageHeightMm * 0.05,
                 width: pageWidthMm * 0.425, height: pageHeightMm * 0.9,
               ));
           } else {
               // Horizontal Solo -> Full Page (Hero)
               items.add(PhotoItem(
                 path: photosOnPage[0].path,
                 x: pageWidthMm * 0.05, y: pageHeightMm * 0.05,
                 width: pageWidthMm * 0.9, height: pageHeightMm * 0.9,
               ));
           }
           } else if (photosOnPage.length == 2) {
           // Pair (V in H-Proj, etc)
           if (isProjectHorizontal) {
              // Split Left/Right Symmetrically with small gap
              // Gap: 2%, Outer Margins: 2.5%, Height Margin: 5% (Top/Bottom 2.5%)
              final w = pageWidthMm * 0.465; // 46.5% width each = 93% total + 2% gap + 5% outer = 100%
              final h = pageHeightMm * 0.95; 
              final y = pageHeightMm * 0.025;
              
              items.add(PhotoItem(
                 path: photosOnPage[0].path,
                 x: pageWidthMm * 0.025, y: y,
                 width: w, height: h,
              ));
              items.add(PhotoItem(
                 path: photosOnPage[1].path,
                 x: pageWidthMm * 0.51, y: y, // 51% start (49% end of first + 2% gap)
                 width: w, height: h,
              ));
           } else {
              // Vertical Project with 2 photos? Usually Top/Bottom
              items.add(PhotoItem(
                 path: photosOnPage[0].path,
                 x: pageWidthMm * 0.05, y: pageHeightMm * 0.02,
                 width: pageWidthMm * 0.9, height: pageHeightMm * 0.47,
              ));
              items.add(PhotoItem(
                 path: photosOnPage[1].path,
                 x: pageWidthMm * 0.05, y: pageHeightMm * 0.51,
                 width: pageWidthMm * 0.9, height: pageHeightMm * 0.47,
              ));
           }
        }
        
        return AlbumPage(widthMm: pageWidthMm, heightMm: pageHeightMm, photos: items);
    }

    // 4. Process Groups
    int dayIndex = 0;
    for (var dayKey in groupedByDay.keys) {
       final photos = groupedByDay[dayKey]!;
       bool isFirstDay = (dayIndex == 0);
       bool isLastDay = (dayIndex == groupedByDay.length - 1);
       
       // Identification of Opening Photo (First Vertical of the Day)
       int openingIndex = -1;
       for (int i=0; i<photos.length; i++) {
          if (photos[i].isVertical) {
             openingIndex = i;
             break;
          }
       }
       
       // Identification of Closing Photo (Last Vertical of Event - Only if Last Day?)
       // User said: "ultima pagina gerada do album coloque a ultima foto portrait que existir"
       // So strictly the LAST vertical of the ENTIRE set.
       // Let's identify the Global Last Vertical first.
       
       // Wait, we are iterating days.
       // We can just process photos.
       // If we find the Global Last Vertical, we reserve it for end.
       
       // Let's refine logical flow:
       
       // A. Extract "Global Last Vertical" if exists (for Closing)
       // B. Iterate Days.
       //    For each day:
       //      1. Extract "First Vertical" -> Make Opening Page (Solo).
       //      2. Process Remaining Photos.
       //         - Sort/Group by orientation? "separar as fotos verticais das horizontais".
       //         - Implicitly: Process all H, then all V? Or keep partial chronological order?
       //         - "separadas por dia e horarios" -> implied chronological.
       //         - BUT "separar V das H" -> maybe group them?
       //         - Strongest rule: "se proj H, V em 2 por pagina". "H em 1 por pagina".
       //         - Usually we want to keep flow.
       //         - Let's accumulate V's in a buffer. When H comes, flush V buffer?
       
    }
    
    // Rewriting Loop logic with buffers:
    
    // Global Pre-processing:
    // Identify Last Vertical of Album (to remove it from standard flow and put at end)
    _SmartPhoto? globalClosingPhoto;
    if (analyzed.any((p) => p.isVertical)) {
       // Find last V
       final lastVIndex = analyzed.lastIndexWhere((p) => p.isVertical);
       globalClosingPhoto = analyzed[lastVIndex];
       analyzed.removeAt(lastVIndex); // Remove from flow, add at end
       
       // Re-group because we removed one
       groupedByDay.clear();
       for (var p in analyzed) {
          final k = "${p.date.year}-${p.date.month}-${p.date.day}";
          groupedByDay.putIfAbsent(k, () => []).add(p);
       }
    }
    
    dayIndex = 0;
    for (var dayKey in groupedByDay.keys) {
       final dayPhotos = groupedByDay[dayKey]!;
       
       // Find Opening V for this day
       _SmartPhoto? openingV;
       int opIndex = dayPhotos.indexWhere((p) => p.isVertical);
       if (opIndex != -1) {
          openingV = dayPhotos[opIndex];
          dayPhotos.removeAt(opIndex);
          // Add Opening Page immediately
          pages.add(createPage([openingV], isOpening: true));
       }
       
       // Now process remaining dayPhotos
       // Strategy: Separate H and V lists to "separar"?
       // User: "separar as fotos verticais das horizontais ... mas verticais em paginas horizontais colocar 2 em 1 pagina"
       // If I separate strictly, I might lose time context within the day.
       // But user explicitly asked to separate.
       // Let's separate H and V for the day.
       // And usually put H first or V first? 
       // User didn't specify order, but usually Opening is V, so maybe follow with Vs? 
       // Or H?
       // Let's process H then V for the day? Or V then H?
       // "primeira foto vertical do dia ... abertura".
       // Let's process: Opening V -> All Hs -> All Vs ?
       
       // Chronological Processing with Pairing
       int i = 0;
       while (i < dayPhotos.length) {
          final current = dayPhotos[i];
          bool consumedNext = false;
          
          if (isProjectHorizontal) {
             // Project HORIZONTAL
             if (current.isVertical) {
                // Try to pair with next Vertical
                if (i + 1 < dayPhotos.length && dayPhotos[i+1].isVertical) {
                   // Pair V + V
                   pages.add(createPage([current, dayPhotos[i+1]]));
                   consumedNext = true;
                } else {
                   // Solo V
                   pages.add(createPage([current]));
                }
             } else {
                // Horizontal -> Always Solo in Horizontal Project
                pages.add(createPage([current]));
             }
          } else {
             // Project VERTICAL
             if (current.isVertical) {
                // V -> Always Solo in Vertical Project
                pages.add(createPage([current]));
             } else {
                // Horizontal -> Try to stack 2 H if allowed?
                if (i + 1 < dayPhotos.length && !dayPhotos[i+1].isVertical) {
                   pages.add(createPage([current, dayPhotos[i+1]]));
                   consumedNext = true;
                } else {
                   pages.add(createPage([current]));
                }
             }
          }
          
          if (consumedNext) {
             i += 2;
          } else {
             i++;
          }
       }
       
       dayIndex++;
    }
    
    // Add Global Closing Page
    if (globalClosingPhoto != null) {
       pages.add(createPage([globalClosingPhoto], isClosing: true));
    }
    
    return pages;
  }
  
  static Future<_SmartPhoto> _analyze(String path) async {
     final file = File(path);
     DateTime date = await file.lastModified(); 
     bool isVertical = false;
     
     try {
       final bytes = await file.readAsBytes();
       final tags = await readExifFromBytes(bytes);
       
       // 1. Parse Date
       if (tags.containsKey('Image DateTime')) {
          final dateStr = tags['Image DateTime']?.printable;
          if (dateStr != null) {
             try {
                final parts = dateStr.split(' ');
                final dateParts = parts[0].split(':');
                final timeParts = parts[1].split(':');
                date = DateTime(
                  int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]),
                  int.parse(timeParts[0]), int.parse(timeParts[1]), int.parse(timeParts[2])
                );
             } catch (_) {}
          }
       }
       
       // 2. Parse Orientation & Dimensions
       int w = 0;
       int h = 0;
       if (tags.containsKey('EXIF ExifImageWidth')) {
          w = int.tryParse(tags['EXIF ExifImageWidth']?.printable ?? "0") ?? 0;
       }
       if (tags.containsKey('EXIF ExifImageLength')) {
          h = int.tryParse(tags['EXIF ExifImageLength']?.printable ?? "0") ?? 0;
       }
       
       // Fallback only if strict 0
       if (w == 0 || h == 0) {
           // Try decode image headers only suitable for small check?
           // Or just assume decode full image if needed (slow but safer)
           // Let's try decodeImage only if EXIF failed dimensions
       }

       bool swapDimensions = false;
       if (tags.containsKey('Image Orientation')) {
          // Orientation values:
          // 1: Horizontal (Normal)
          // 3: Rotate 180
          // 6: Rotate 90 CW (Portrait)
          // 8: Rotate 270 CW (Portrait)
          final orientationVal = tags['Image Orientation']?.values.toList();
          if (orientationVal != null && orientationVal.isNotEmpty) {
             final val = orientationVal[0]; // Usually int
             if (val == 6 || val == 8 || val == 5 || val == 7) {
                swapDimensions = true;
             }
          } else {
             // Sometimes printable is "Rotated 90"
             final str = tags['Image Orientation']?.printable ?? "";
             if (str.contains("Rotated 90") || str.contains("Rotated 270")) {
                swapDimensions = true;
             }
          }
       }
       
       if (w > 0 && h > 0) {
          if (swapDimensions) {
             isVertical = w > h; // Swapped: Width becomes Height
          } else {
             isVertical = h > w;
          }
       } else {
          // If no EXIF W/H, try decoding (expensive fallback)
          final image = img.decodeImage(bytes);
          if (image != null) {
             isVertical = image.height > image.width;
          }
       }
       
     } catch (e) {
       // Fallback
       try {
          final bytes = await file.readAsBytes();
          final image = img.decodeImage(bytes);
           if (image != null) {
              isVertical = image.height > image.width;
           }
       } catch (_) {}
     }
     
     return _SmartPhoto(path, date, isVertical);
  }
}

class _SmartPhoto {
  final String path;
  final DateTime date;
  final bool isVertical;
  
  _SmartPhoto(this.path, this.date, this.isVertical);
}
