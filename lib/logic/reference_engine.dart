import 'dart:io';
import 'dart:convert';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import '../models/project_model.dart';
import '../models/asset_model.dart';
import 'image_utils.dart';

class ReferenceData {
  final List<PageBlueprint> blueprints;
  final Map<String, Duration> cameraOffsets;
  
  ReferenceData({required this.blueprints, required this.cameraOffsets});
}

class ReferenceEngine {
  
  // Scans a folder for .alem projects and extracts blueprints AND time offsets
  static Future<ReferenceData> learnReference(String referenceFolderPath) async {
    final dir = Directory(referenceFolderPath);
    if (!await dir.exists()) return ReferenceData(blueprints: [], cameraOffsets: {});
    
    // Find .alem files (recursive)
    final projects = await dir.list(recursive: true)
      .where((fs) => fs.path.endsWith('.alem'))
      .toList();
      
    if (projects.isEmpty) return ReferenceData(blueprints: [], cameraOffsets: {});
    
    // Sort by newest
    projects.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    
    for (var fs in projects) {
       try {
           print("RD: Analyzing reference candidate: ${fs.path}");
           final file = File(fs.path);
           String jsonStr;
           try {
             final bytes = await file.readAsBytes();
             // Try ZIP First
             try {
                final archive = ZipDecoder().decodeBytes(bytes);
                final jsonFile = archive.findFile('project.json');
                if (jsonFile != null) {
                   jsonStr = utf8.decode(jsonFile.content as List<int>);
                } else {
                   jsonStr = utf8.decode(bytes);
                }
             } catch (_) {
                // Not a zip, try plain text
                jsonStr = await file.readAsString();
             }
           } catch (_) {
             // Fallback
             jsonStr = await file.readAsString(encoding: latin1);
           }
           
           final jsonMap = jsonDecode(jsonStr);
           final project = Project.fromJson(jsonMap);
           
           final bps = _extractBlueprints(project);
           
           // If we have valid blueprints, let's also try to learn Time Offsets
           // Priority 1: Read Explicit Offsets from Project (Manual TimeShift)
           Map<String, Duration> offsets = {};
           if (project.cameraTimeOffsets.isNotEmpty) {
               project.cameraTimeOffsets.forEach((key, sec) {
                   offsets[key] = Duration(seconds: sec);
               });
               print("RD: Loaded explicit offsets from reference: $offsets");
               return ReferenceData(blueprints: bps, cameraOffsets: offsets);
           }
           
           // Priority 2: Reverse Engineer from Layout (Legacy/Auto)
           if (bps.isNotEmpty) {
              offsets = await _learnTimeOffsets(project);
              print("RD: Learned offsets: $offsets");
              print("RD: Success. Learned from ${p.basename(fs.path)}");
              return ReferenceData(blueprints: bps, cameraOffsets: offsets);
           }
       } catch (e) {
           print("RD: Error parsing ${fs.path}: $e");
       }
    }
    
    print("RD: No valid blueprints found in any reference file.");
    return ReferenceData(blueprints: [], cameraOffsets: {});
  }
  
  static Future<Map<String, Duration>> _learnTimeOffsets(Project project) async {
      // 1. Flatten Project into a sequential list of photos
      List<ReferencePhoto> sequence = [];
      
      for (var page in project.pages) {
          // Sort items by visual order (top-left to bottom-right)
          // This ensures we respect the "Author's Chronology"
          var sortedPhotos = List<PhotoItem>.from(page.photos);
          sortedPhotos.sort((a, b) {
             if ((a.y - b.y).abs() > 50) return a.y.compareTo(b.y);
             return a.x.compareTo(b.x);
          });
          
          for (var item in sortedPhotos) {
             // Skip templates
             if (p.basename(item.path).toLowerCase().contains("template")) continue;
             
             final date = await ImageUtils.getDateTaken(item.path);
             final model = await ImageUtils.getCameraModel(item.path);
             
             if (model != null) {
                sequence.add(ReferencePhoto(path: item.path, date: date, model: model));
             }
          }
      }
      
      if (sequence.isEmpty) return {};
      
      // 2. Identify Master Camera (Most frequent)
      Map<String, int> counts = {};
      for (var p in sequence) {
         counts[p.model] = (counts[p.model] ?? 0) + 1;
      }
      
      var sortedModels = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      if (sortedModels.isEmpty) return {};
      
      String masterModel = sortedModels.first;
      print("RD: Master Camera identified as: $masterModel");
      
      // 3. Calculate Offsets for other cameras
      Map<String, List<Duration>> rawOffsets = {};
      
      for (int i = 0; i < sequence.length; i++) {
          final current = sequence[i];
          if (current.model == masterModel) continue;
          
          // Find surrounding Master photos
          ReferencePhoto? prevMaster;
          ReferencePhoto? nextMaster;
          
          // Look back
          for (int j = i - 1; j >= 0; j--) {
             if (sequence[j].model == masterModel) {
                prevMaster = sequence[j];
                break;
             }
          }
          
          // Look forward
          for (int j = i + 1; j < sequence.length; j++) {
             if (sequence[j].model == masterModel) {
                nextMaster = sequence[j];
                break;
             }
          }
          
          DateTime? expectedTime;
          
          if (prevMaster != null && nextMaster != null) {
             // Sandwich: Suggest midpoint
             final diff = nextMaster.date.difference(prevMaster.date).inMilliseconds;
             expectedTime = prevMaster.date.add(Duration(milliseconds: (diff / 2).round()));
          } else if (prevMaster != null) {
             // Only prev: Suggest prev + 1 sec
             expectedTime = prevMaster.date.add(Duration(seconds: 1));
          } else if (nextMaster != null) {
             // Only next: Suggest next - 1 sec
             expectedTime = nextMaster.date.subtract(Duration(seconds: 1));
          }
          
          if (expectedTime != null) {
             final offset = expectedTime.difference(current.date);
             rawOffsets.putIfAbsent(current.model, () => []).add(offset);
          }
      }
      
      // Average the offsets
      Map<String, Duration> finalOffsets = {};
      for (var model in rawOffsets.keys) {
          final list = rawOffsets[model]!;
          if (list.isEmpty) continue;
          
          int totalMs = list.fold(0, (sum, d) => sum + d.inMilliseconds);
          final avgMs = (totalMs / list.length).round();
          finalOffsets[model] = Duration(milliseconds: avgMs);
      }
      
      return finalOffsets;
  }

  static List<PageBlueprint> _extractBlueprints(Project project) {
     List<PageBlueprint> blueprints = [];
     
     for (var page in project.pages) {
        String? templateName;
        List<SlotBlueprint> slots = [];
        
        // Analyze Items on Page
        for (var item in page.photos) {
           final base = p.basename(item.path);
           
           // Template? (usually png/high res, zIndex 0, large)
           bool isTemplate = base.contains("template") || (item.width > 200 && item.zIndex == 0);
           // Also check extension, some templates are .jpg
           
           if (isTemplate) {
               templateName = base;
           } else {
               // Photo Slot
               // Deduce Event Prefix (1_, 8_, etc)
               String prefix = "Misc";
               
               // Try extracting prefix from "1_IMG..." or just "1"
               final parts = base.split('_');
               if (parts.isNotEmpty && int.tryParse(parts[0]) != null) {
                  prefix = parts[0];
               } else {
                   final match = RegExp(r'^(\d+)').firstMatch(base);
                   if (match != null) prefix = match.group(1)!;
               }

               // Normalize prefix to int string if possible ("07" -> "7")
               if (int.tryParse(prefix) != null) {
                   prefix = int.parse(prefix).toString();
               }
               
               // Orientation
               bool isVertical = item.height > item.width;
               
               slots.add(SlotBlueprint(
                 x: item.x,
                 y: item.y,
                 w: item.width,
                 h: item.height,
                 eventPrefix: prefix,
                 isVertical: isVertical
               ));
           }
        }
        
        // If valid definition found
        if (templateName != null) {
           // Sort slots (Reading order: Top-Left to Bottom-Right)
           slots.sort((a,b) {
              if ((a.y - b.y).abs() > 50) return a.y.compareTo(b.y);
              return a.x.compareTo(b.x);
           });
           
           blueprints.add(PageBlueprint(
              templateName: templateName,
              slots: slots
           ));
        }
     }
     
     return blueprints;
  }
}

class PageBlueprint {
  final String templateName;
  final List<SlotBlueprint> slots;
  PageBlueprint({required this.templateName, required this.slots});
}

class SlotBlueprint {
  final double x, y, w, h;
  final String eventPrefix;
  final bool isVertical;
  
  SlotBlueprint({
    required this.x, required this.y, required this.w, required this.h,
    required this.eventPrefix, required this.isVertical
  });
}

class ReferencePhoto {
   final String path;
   final DateTime date;
   final String model;
   ReferencePhoto({required this.path, required this.date, required this.model});
}
