import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../models/project_model.dart';
import '../models/asset_model.dart';
import 'template_system.dart';
import 'dart:ui' as ui;
import 'auto_select_engine.dart';
import 'image_utils.dart';
import 'package:flutter/painting.dart';

class RapidDiagrammingService {
  
  static Future<Project> generateProject({
    required Project currentProject,
    required List<String> allPhotoPaths,
    required String projectName,
    String? customTemplateDir,
    bool useAutoSelect = true,
  }) async {
    
    // Determine Page Size from Current Project
    double pW = 300.0;
    double pH = 300.0;
    
    if (currentProject.pages.isNotEmpty) {
       pW = currentProject.pages[0].widthMm;
       pH = currentProject.pages[0].heightMm;
    }

    // 0. AUTO-SELECT BEST PHOTOS
    List<String> selectedPaths;
    
    if (useAutoSelect) {
       print("RD: Starting Auto-Selection...");
       try {
         selectedPaths = await AutoSelectEngine.findBestPhotos(allPhotoPaths);
         print("RD: Auto-Selection finished. Selected ${selectedPaths.length} from ${allPhotoPaths.length}");
       } catch(e) {
         print("RD: AutoSelect failed: $e, using all photos.");
         selectedPaths = allPhotoPaths;
       }
    } else {
       print("RD: Skipping Auto-Selection (User preferred).");
       selectedPaths = List.from(allPhotoPaths);
    }
    
    // 1. Group by Prefix
    // Sort primarily by filename to group prefixes correctly? No, prefix extraction handles it.
    // But we need consistent iteration order.
    
    Map<String, List<String>> groups = {};
    for (var path in selectedPaths) {
       final name = p.basename(path);
       final parts = name.split('_');
       String prefix = "0";
       if (parts.isNotEmpty && int.tryParse(parts[0]) != null) {
          prefix = parts[0];
       } else {
          final match = RegExp(r'^(\d+)').firstMatch(name);
          if (match != null) {
             prefix = match.group(1)!;
          } else {
             prefix = "Misc";
          }
       }
       groups.putIfAbsent(prefix, () => []).add(path);
    }
    
    // Sort keys
    final sortedKeys = groups.keys.toList()..sort((a, b) {
       int? ia = int.tryParse(a);
       int? ib = int.tryParse(b);
       if (ia != null && ib != null) return ia.compareTo(ib);
       return a.compareTo(b);
    });

    // Prepare Template Directories
    final appDir = await getApplicationSupportDirectory();
    final templateDir = Directory(p.join(appDir.path, 'templates'));
    
    final docsDir = await getApplicationDocumentsDirectory();
    final defaultExternalDir = Directory(p.join(docsDir.path, 'AiaAlbum', 'Templates'));
    
    // Use custom if provided, else default external
    final userTemplateDir = customTemplateDir != null ? Directory(customTemplateDir) : defaultExternalDir;
    
    List<AlbumPage> newPages = [];
    
    // Album End Special: Try Event 8, then Event 1
    String? finalSpecialPhoto;
    
    // Try Group 8
    if (groups.containsKey("8")) {
        final photos8 = groups["8"]!;
        for (var path in photos8.reversed) { // Take last vertical of 8? Or just any? User said "uma foto vertical do evento 8"
           if (await _isVertical(path)) {
              finalSpecialPhoto = path;
              photos8.remove(path); // Remove so it doesn't get used inside
              break;
           }
        }
    }
    
    // Fallback to Group 1
    if (finalSpecialPhoto == null && groups.containsKey("1")) {
        final photos1 = groups["1"]!;
        for (var path in photos1.reversed) {
           if (await _isVertical(path)) {
              finalSpecialPhoto = path;
              photos1.remove(path);
              break;
           }
        }
    }

    // Process Groups
    for (var prefix in sortedKeys) {
       var photos = groups[prefix]!;
       if (photos.isEmpty) continue;
       
       // CHRONOLOGICAL SORT
       // Map path -> date
       Map<String, DateTime> dates = {};
       
       // Process in batches of 10 to avoid memory spikes
       const int batchSize = 10;
       for (int i = 0; i < photos.length; i += batchSize) {
           int end = (i + batchSize < photos.length) ? i + batchSize : photos.length;
           final batch = photos.sublist(i, end);
           final futures = batch.map((p) => ImageUtils.getDateTaken(p));
           final results = await Future.wait(futures);
           for (int j = 0; j < batch.length; j++) {
              dates[batch[j]] = results[j];
           }
       }
       photos.sort((a, b) => dates[a]!.compareTo(dates[b]!));
       
       // -- Start Event Page --
       String? templatePath = await _findTemplate(templateDir, prefix); 
       if (templatePath == null) {
          templatePath = await _findTemplate(userTemplateDir, prefix);
       }
       
       String? eventCoverPhoto;
       
       // Find Cover Vertical
       int coverIndex = -1;
       for (int i=0; i<photos.length; i++) {
          if (await _isVertical(photos[i])) {
             coverIndex = i;
             break;
          }
       }
       
       if (coverIndex != -1) {
          eventCoverPhoto = photos.removeAt(coverIndex);
       }
       
       if (templatePath != null || eventCoverPhoto != null) {
          final pageId = Uuid().v4();
          List<PhotoItem> items = [];
          
          Rect? holeRect;
          if (templatePath != null) {
             // Detect Hole!
             holeRect = await ImageUtils.detectHole(templatePath);
             
             items.add(PhotoItem(
                id: Uuid().v4(),
                path: templatePath,
                x: 0, y: 0, width: pW, height: pH, // Full Page
                rotation: 0,
                zIndex: 0, 
             ));
          }
          
          if (eventCoverPhoto != null) {
             double x, y, w, h;
             
             if (holeRect != null) {
                // Use Hole Dimensions
                x = holeRect.left * pW;
                y = holeRect.top * pH;
                w = holeRect.width * pW;
                h = holeRect.height * pH;
             } else {
                // Default fallback (Tight 95%)
                x = pW * 0.025;
                y = pH * 0.025;
                w = pW * 0.95;
                h = pH * 0.95;
             }
             
             items.add(PhotoItem(
                id: Uuid().v4(),
                path: eventCoverPhoto,
                x: x, y: y, width: w, height: h,
                rotation: 0,
                zIndex: 1
             ));
          }
          newPages.add(AlbumPage(id: pageId, photos: items, widthMm: pW, heightMm: pH));
       }
       
       // -- Flow Remaining Photos --
       while (photos.isNotEmpty) {
          final currentPath = photos.removeAt(0); // Take first
          final isVert = await _isVertical(currentPath);
          
          if (!isVert) {
              // Horizontal: Solo Page
              final pageItems = TemplateSystem.applyTemplate(
                 '1_solo_horizontal_large', 
                 [PhotoItem(id: Uuid().v4(), path: currentPath, width: pW, height: pH)], 
                 pW, pH
              );
              newPages.add(AlbumPage(id: Uuid().v4(), photos: pageItems, widthMm: pW, heightMm: pH));
          
          } else {
              // Vertical: Look for partner?
              int partnerIndex = -1;
              for(int i=0; i<photos.length; i++) {
                 if (await _isVertical(photos[i])) {
                    partnerIndex = i;
                    break;
                 }
              }
              
              if (partnerIndex != -1) {
                  // Pair found
                  final partnerPath = photos.removeAt(partnerIndex);
                  
                  final pageItems = TemplateSystem.applyTemplate(
                     '2_portrait_pair', 
                     [
                       PhotoItem(id: Uuid().v4(), path: currentPath, width: pW, height: pH),
                       PhotoItem(id: Uuid().v4(), path: partnerPath, width: pW, height: pH)
                     ], 
                     pW, pH
                  );
                  newPages.add(AlbumPage(id: Uuid().v4(), photos: pageItems, widthMm: pW, heightMm: pH));
              } else {
                  // No partner vertical found -> Solo Vertical
                  final pageItems = TemplateSystem.applyTemplate(
                     '1_vertical_half_right', 
                     [PhotoItem(id: Uuid().v4(), path: currentPath, width: pW, height: pH)], 
                     pW, pH
                  );
                  newPages.add(AlbumPage(id: Uuid().v4(), photos: pageItems, widthMm: pW, heightMm: pH));
              }
          }
       }
    }
    
    // -- Final Post-Loop: Album End (Template 12) --
    if (finalSpecialPhoto != null) {
        String? t12Path = await _findTemplate(templateDir, "12");
        if (t12Path == null) {
           t12Path = await _findTemplate(userTemplateDir, "12");
        }
        
        final pageId = Uuid().v4();
        List<PhotoItem> items = [];
        
        Rect? holeRect;
        if (t12Path != null) {
            holeRect = await ImageUtils.detectHole(t12Path);
            items.add(PhotoItem(
              id: Uuid().v4(),
              path: t12Path,
              x: 0, y: 0, width: pW, height: pH,
              zIndex: 0
            ));
        }
        
        double x, y, w, h;
        if (holeRect != null) {
            x = holeRect.left * pW;
            y = holeRect.top * pH;
            w = holeRect.width * pW;
            h = holeRect.height * pH;
        } else {
            x = pW * 0.1;
            y = pH * 0.1;
            w = pW * 0.8;
            h = pH * 0.8;
        }

        items.add(PhotoItem(
           id: Uuid().v4(),
           path: finalSpecialPhoto,
           x: x, y: y, width: w, height: h,
           zIndex: 1
        ));
        
        newPages.add(AlbumPage(id: pageId, photos: items, widthMm: pW, heightMm: pH));
    }
    
    return currentProject.copyWith(
       pages: newPages,
       name: projectName 
    );
  }
  
  static Future<String?> _findTemplate(Directory dir, String prefix) async {
     if (!await dir.exists()) return null;
     
     // Look for "prefix.png", "prefix.jpg"
     final options = ["$prefix.png", "$prefix.jpg", "$prefix.jpeg"];
     for (var opt in options) {
        final f = File(p.join(dir.path, opt));
        if (await f.exists()) return f.path;
     }
     
     // Maybe "prefix_template.png"?
     final options2 = ["${prefix}_template.png", "${prefix}_template.jpg"];
     for (var opt in options2) {
        final f = File(p.join(dir.path, opt));
        if (await f.exists()) return f.path;
     }
     
     return null;
  }
  
  static Future<bool> _isVertical(String path) async {
     try {
       final bytes = await File(path).readAsBytes();
       final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
       final descriptor = await ui.ImageDescriptor.encoded(buffer);
       final isVert = descriptor.height > descriptor.width;
       descriptor.dispose();
       buffer.dispose();
       return isVert;
     } catch (e) {
       return false;
     }
  }

}
