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
import 'reference_engine.dart';

class RapidDiagrammingService {
  
  static Future<Project> generateProject({
    required Project currentProject,
    required List<String> allPhotoPaths,
    required String projectName,
    String? customTemplateDir,
    String? referencePath, 
    bool useAutoSelect = true,
    String? contractNumber, // NEW
  }) async {
    
    // Page Size
    double pW = 300.0;
    double pH = 300.0;
    if (currentProject.pages.isNotEmpty) {
       pW = currentProject.pages[0].widthMm;
       pH = currentProject.pages[0].heightMm;
    }

    // 0. AUTO-SELECT
    List<String> selectedPaths;
    if (useAutoSelect) {
       print("RD: Starting Auto-Selection...");
       try {
         selectedPaths = await AutoSelectEngine.findBestPhotos(allPhotoPaths);
       } catch(e) {
         print("RD: AutoSelect failed, using all.");
         selectedPaths = List.from(allPhotoPaths);
       }
    } else {
       selectedPaths = List.from(allPhotoPaths);
    }
    
    // 0.5 REFERENCE & TIME SYNC LEARN
    List<PageBlueprint> blueprints = [];
    Map<String, Duration> timeOffsets = {};
    
    if (referencePath != null) {
       print("RD: Learning from reference: $referencePath");
       final refData = await ReferenceEngine.learnReference(referencePath);
       blueprints = refData.blueprints;
       timeOffsets = refData.cameraOffsets;
       print("RD: Learned offsets: $timeOffsets");
    }
    
    // 0.6 PRE-CALCULATE CORRECTED DATES (SMART SYNC)
    Map<String, DateTime> photoDates = {};
    print("RD: Calculating corrected timestamps...");
    
    const int batchSize = 10;
    for (int i = 0; i < selectedPaths.length; i += batchSize) {
        int end = (i + batchSize < selectedPaths.length) ? i + batchSize : selectedPaths.length;
        final batch = selectedPaths.sublist(i, end);
        
        final futuresDate = batch.map((p) => ImageUtils.getDateTaken(p));
        final futuresModel = batch.map((p) => ImageUtils.getCameraModel(p));
        
        final dates = await Future.wait(futuresDate);
        final models = await Future.wait(futuresModel);
        
        for (int j = 0; j < batch.length; j++) {
           final path = batch[j];
           DateTime d = dates[j];
           final m = models[j];
           
           if (m != null && timeOffsets.containsKey(m)) {
               d = d.add(timeOffsets[m]!);
               print("RD: Applied offset ${timeOffsets[m]} to $m photo: $path");
           }
           photoDates[path] = d;
        }
    }

    // 1. Group by Prefix
    Map<String, List<String>> groups = {};
    for (var path in selectedPaths) {
       final name = p.basename(path);
       final parts = name.split('_');
       String prefix = "0";
       
       if (parts.isNotEmpty) {
           int? pInt = int.tryParse(parts[0]);
           if (pInt != null) {
              prefix = pInt.toString(); 
           } else {
              final match = RegExp(r'^(\d+)').firstMatch(name);
              if (match != null) {
                 prefix = int.parse(match.group(1)!).toString();
              } else {
                 prefix = "Misc";
              }
           }
       }
       groups.putIfAbsent(prefix, () => []).add(path);
    }
    
    // Sort Groups by CORRECTED DATE
    for (var key in groups.keys) {
        var photos = groups[key]!;
        photos.sort((a, b) {
           final da = photoDates[a] ?? DateTime.now();
           final db = photoDates[b] ?? DateTime.now();
           return da.compareTo(db);
        });
    }
    
    // --- EXECUTION BRANCH ---
    List<AlbumPage> newPages = [];
    
    if (blueprints.isNotEmpty) {
       // === REFERENCE MODE ===
       final appDir = await getApplicationSupportDirectory();
       final templateDir = Directory(p.join(appDir.path, 'templates'));
       final docsDir = await getApplicationDocumentsDirectory();
       final defaultExternalDir = Directory(p.join(docsDir.path, 'AiaAlbum', 'Templates'));
       final userTemplateDir = customTemplateDir != null ? Directory(customTemplateDir) : defaultExternalDir;
       
       for (var pageBP in blueprints) {
           String? tPath = await _findTemplateExact(templateDir, pageBP.templateName);
           if (tPath == null) tPath = await _findTemplateExact(userTemplateDir, pageBP.templateName);
           
           if (tPath == null) {
              print("RD: Warning - Reference template ${pageBP.templateName} not found locally.");
              continue; 
           }
           
           final pageId = Uuid().v4();
           List<PhotoItem> items = [];
           items.add(PhotoItem(id: Uuid().v4(), path: tPath, x: 0, y: 0, width: pW, height: pH, zIndex: 0));
           
           for (var slot in pageBP.slots) {
              String? bestPhoto;
              String slotPrefix = slot.eventPrefix;
              int? sInt = int.tryParse(slotPrefix);
              if (sInt != null) slotPrefix = sInt.toString();

              if (groups.containsKey(slotPrefix)) {
                 final candidates = groups[slotPrefix]!;
                 for (int i=0; i<candidates.length; i++) {
                    bool isV = await _isVertical(candidates[i]);
                    if (isV == slot.isVertical) {
                       bestPhoto = candidates.removeAt(i); 
                       break;
                    }
                 }
                 if (bestPhoto == null && candidates.isNotEmpty) {
                    bestPhoto = candidates.removeAt(0);
                 }
              }
              
              if (bestPhoto != null) {
                 items.add(PhotoItem(
                    id: Uuid().v4(),
                    path: bestPhoto,
                    x: slot.x, y: slot.y, width: slot.w, height: slot.h,
                    zIndex: 1
                 ));
              }
           }
           newPages.add(AlbumPage(id: pageId, photos: items, widthMm: pW, heightMm: pH));
       }

    } else {
       // === STANDARD LOGIC ===
       
       final sortedKeys = groups.keys.toList()..sort((a, b) {
          int? ia = int.tryParse(a);
          int? ib = int.tryParse(b);
          if (ia != null && ib != null) return ia.compareTo(ib);
          return a.compareTo(b);
       });

       final appDir = await getApplicationSupportDirectory();
       final templateDir = Directory(p.join(appDir.path, 'templates'));
       final docsDir = await getApplicationDocumentsDirectory();
       final defaultExternalDir = Directory(p.join(docsDir.path, 'AiaAlbum', 'Templates'));
       final userTemplateDir = customTemplateDir != null ? Directory(customTemplateDir) : defaultExternalDir;

       // --- 1. OPENING (Template 1) ---
       String? openingPhotoPath;
       if (groups.containsKey("1")) {
          final photos1 = groups["1"]!;
          if (photos1.isNotEmpty) {
             for (int i = photos1.length - 1; i >= 0; i--) {
                if (await _isVertical(photos1[i])) {
                   openingPhotoPath = photos1[i];
                   photos1.removeAt(i); 
                   break;
                }
             }
          }
       }
       if (openingPhotoPath == null && groups.containsKey("8")) {
          final photos8 = groups["8"]!;
          if (photos8.isNotEmpty) {
             for (int i = photos8.length - 1; i >= 0; i--) {
                if (await _isVertical(photos8[i])) {
                   openingPhotoPath = photos8[i];
                   photos8.removeAt(i);
                   break;
                }
             }
          }
       }
      
       if (openingPhotoPath != null) {
            String? t1Path = await _findTemplate(templateDir, "1");
            if (t1Path == null) t1Path = await _findTemplate(userTemplateDir, "1");
            
            final pageId = Uuid().v4();
            List<PhotoItem> items = [];
            Rect? holeRect;
            if (t1Path != null) {
                holeRect = await ImageUtils.detectHole(t1Path);
                items.add(PhotoItem(id: Uuid().v4(), path: t1Path, x: 0, y: 0, width: pW, height: pH, zIndex: 0));
            }
            double x, y, w, h;
            if (holeRect != null) {
                x = holeRect.left * pW; y = holeRect.top * pH; w = holeRect.width * pW; h = holeRect.height * pH;
            } else {
                x = pW * 0.05; y = pH * 0.05; w = pW * 0.9; h = pH * 0.9;
            }
            items.add(PhotoItem(id: Uuid().v4(), path: openingPhotoPath, x: x, y: y, width: w, height: h, zIndex: 1));
            newPages.add(AlbumPage(id: pageId, photos: items, widthMm: pW, heightMm: pH));
       }

       // --- 2. ENDING (Template 12) ---
       String? finalSpecialPhoto;
       if (groups.containsKey("8")) {
           final photos8 = groups["8"]!;
           if (photos8.isNotEmpty) {
              for (int i = photos8.length - 1; i >= 0; i--) {
                 if (await _isVertical(photos8[i])) {
                    finalSpecialPhoto = photos8[i];
                    photos8.removeAt(i); 
                    break;
                 }
              }
           }
       }
       if (finalSpecialPhoto == null && groups.containsKey("1")) {
           final photos1 = groups["1"]!;
            if (photos1.isNotEmpty) {
              for (int i = photos1.length - 1; i >= 0; i--) {
                 if (await _isVertical(photos1[i])) {
                    finalSpecialPhoto = photos1[i];
                    photos1.removeAt(i);
                    break;
                 }
              }
           }
       }

       // --- 3. PROCESS EVENTS ---
       for (var prefix in sortedKeys) {
          var photos = groups[prefix]!;
          if (photos.isEmpty) continue;
          
          String? templatePath = await _findTemplate(templateDir, prefix); 
          if (templatePath == null) {
             templatePath = await _findTemplate(userTemplateDir, prefix);
          }
          
          String? eventCoverPhoto;
          int coverIndex = -1;
          for (int i = photos.length - 1; i >= 0; i--) {
             if (await _isVertical(photos[i])) {
                coverIndex = i;
                break;
             }
          }
          if (coverIndex == -1) {
             for (int i=0; i<photos.length; i++) {
                if (await _isVertical(photos[i])) {
                   coverIndex = i;
                   break;
                }
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
                holeRect = await ImageUtils.detectHole(templatePath);
                items.add(PhotoItem(id: Uuid().v4(), path: templatePath, x: 0, y: 0, width: pW, height: pH, zIndex: 0));
             }
             
             if (eventCoverPhoto != null) {
                double x, y, w, h;
                if (holeRect != null) {
                   x = holeRect.left * pW; y = holeRect.top * pH; w = holeRect.width * pW; h = holeRect.height * pH;
                } else {
                   x = pW * 0.05; y = pH * 0.05; w = pW * 0.9; h = pH * 0.9;
                }
                items.add(PhotoItem(id: Uuid().v4(), path: eventCoverPhoto, x: x, y: y, width: w, height: h, zIndex: 1));
             }
             newPages.add(AlbumPage(id: pageId, photos: items, widthMm: pW, heightMm: pH));
          }
          
          while (photos.isNotEmpty) {
             final currentPath = photos.removeAt(0);
             final isVert = await _isVertical(currentPath);
             
             if (!isVert) {
                 final pageItems = TemplateSystem.applyTemplate('1_solo_horizontal_large', [PhotoItem(id: Uuid().v4(), path: currentPath, width: pW, height: pH)], pW, pH);
                 newPages.add(AlbumPage(id: Uuid().v4(), photos: pageItems, widthMm: pW, heightMm: pH));
             } else {
                 int partnerIndex = -1;
                 for(int i=0; i<photos.length; i++) {
                    if (await _isVertical(photos[i])) {
                       partnerIndex = i;
                       break;
                    }
                 }
                 if (partnerIndex != -1) {
                     final partnerPath = photos.removeAt(partnerIndex);
                     final pageItems = TemplateSystem.applyTemplate('2_portrait_pair', [PhotoItem(id: Uuid().v4(), path: currentPath, width: pW, height: pH), PhotoItem(id: Uuid().v4(), path: partnerPath, width: pW, height: pH)], pW, pH);
                     newPages.add(AlbumPage(id: Uuid().v4(), photos: pageItems, widthMm: pW, heightMm: pH));
                 } else {
                     final pageItems = TemplateSystem.applyTemplate('1_vertical_half_right', [PhotoItem(id: Uuid().v4(), path: currentPath, width: pW, height: pH)], pW, pH);
                     newPages.add(AlbumPage(id: Uuid().v4(), photos: pageItems, widthMm: pW, heightMm: pH));
                 }
             }
          }
       }
       
       // --- 4. ENDING PAGE CREATION (Template 12) ---
       if (finalSpecialPhoto != null) {
          String? tEndPath = await _findTemplate(templateDir, "12");
          if (tEndPath == null) tEndPath = await _findTemplate(userTemplateDir, "12");
          
          final pageId = Uuid().v4();
          List<PhotoItem> items = [];
          
          Rect? holeRect;
          if (tEndPath != null) {
              holeRect = await ImageUtils.detectHole(tEndPath);
              items.add(PhotoItem(id: Uuid().v4(), path: tEndPath, x: 0, y: 0, width: pW, height: pH, zIndex: 0));
          }
          double x, y, w, h;
          if (holeRect != null) {
              x = holeRect.left * pW; y = holeRect.top * pH; w = holeRect.width * pW; h = holeRect.height * pH;
          } else {
              x = pW * 0.1; y = pH * 0.1; w = pW * 0.8; h = pH * 0.8;
          }
          items.add(PhotoItem(id: Uuid().v4(), path: finalSpecialPhoto, x: x, y: y, width: w, height: h, zIndex: 1));
          newPages.add(AlbumPage(id: pageId, photos: items, widthMm: pW, heightMm: pH));
       }
    } 
    
    // --- LABELING LOGIC (LAST STEP) ---
    if (contractNumber != null && contractNumber.isNotEmpty && newPages.isNotEmpty) {
        // Defines
        double textW = pW * 0.30; // Increased width to fit Name
        double textH = pH * 0.02; 
        
        // Format: "Contract - Name - 01"
        final String labelTextStart = "$contractNumber - $projectName - 01";
        final String labelTextEnd = "$contractNumber - $projectName - End";
        
        // 1. Tag First Page
        final p1 = newPages[0];
        final label1 = PhotoItem(
           id: Uuid().v4(),
           path: "",
           text: labelTextStart,
           isText: true,
           x: p1.widthMm - textW - 5, 
           y: p1.heightMm - textH - 5, 
           width: textW,
           height: textH,
           zIndex: 100
        );
        newPages[0] = p1.copyWith(
           label: labelTextStart,
           photos: [...p1.photos, label1] 
        );
        
        // 2. Tag Last Page
        if (newPages.length > 1) {
            final pLast = newPages[newPages.length - 1];
            final labelLast = PhotoItem(
               id: Uuid().v4(),
               path: "",
               text: labelTextEnd,
               isText: true,
               x: pLast.widthMm - textW - 5,
               y: pLast.heightMm - textH - 5,
               width: textW,
               height: textH,
               zIndex: 100
            );
            newPages[newPages.length - 1] = pLast.copyWith(
               label: labelTextEnd,
               photos: [...pLast.photos, labelLast]
            );
        }
    }
    
    return currentProject.copyWith(
        pages: newPages, 
        name: projectName,
        contractNumber: contractNumber ?? currentProject.contractNumber
    );
  }
  
  static Future<String?> _findTemplate(Directory dir, String prefix) async {
     if (!await dir.exists()) return null;
     
     List<String> candidates = [
        "$prefix.png", "$prefix.jpg", "$prefix.jpeg",
        "${prefix}_template.png", "${prefix}_template.jpg"
     ];
     
     if (prefix.length == 1 && int.tryParse(prefix) != null) {
        String padded = prefix.padLeft(2, '0');
        candidates.add("$padded.png");
        candidates.add("$padded.jpg");
        candidates.add("${padded}_template.png");
        candidates.add("${padded}_template.jpg");
     }

     for (var opt in candidates) {
        final f = File(p.join(dir.path, opt));
        if (await f.exists()) return f.path;
     }
     
     return null;
  }
  
  static Future<String?> _findTemplateExact(Directory dir, String filename) async {
     if (!await dir.exists()) return null;
     final f = File(p.join(dir.path, filename));
     if (await f.exists()) return f.path;
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
