import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/project_model.dart';
import '../models/asset_model.dart'; // For PhotoItem
import '../state/project_state.dart'; // For ProjectNotifier access if needed, or Logic reuse
import 'auto_select_engine.dart';
import 'metadata_helper.dart';

// --- Data Models ---

enum DiagramStatus { idle, running, paused, cancelled, completed }

class DiagramProgress {
  final String currentFolder;
  final int processedCount;
  final int totalCount;
  final int totalPhotosDiagrammed;
  final double currentStepProgress; // 0.0 to 1.0 for current folder
  final DiagramStatus status;

  DiagramProgress({
    this.currentFolder = "",
    this.processedCount = 0,
    this.totalCount = 0,
    this.totalPhotosDiagrammed = 0,
    this.currentStepProgress = 0.0,
    this.status = DiagramStatus.idle,
  });
  
  double get totalProgress => totalCount == 0 ? 0 : processedCount / totalCount;
}

// --- Service ---

class AutoDiagrammingService {
  // Singleton usually not needed if provider, but handy for simple logical loop
  static final AutoDiagrammingService _instance = AutoDiagrammingService._internal();
  factory AutoDiagrammingService() => _instance;
  AutoDiagrammingService._internal();

  final _progressController = StreamController<DiagramProgress>.broadcast();
  Stream<DiagramProgress> get progressStream => _progressController.stream;

  DiagramProgress _state = DiagramProgress();
  
  bool _isPaused = false;
  bool _isCancelled = false;
  Completer<void>? _pauseCompleter;

  // --- Controls ---

  void pause() {
    _isPaused = true;
    _updateStatus(DiagramStatus.paused);
  }

  void resume() {
    _isPaused = false;
    _pauseCompleter?.complete();
    _pauseCompleter = null;
    _updateStatus(DiagramStatus.running);
  }

  void cancel() {
    _isCancelled = true;
    if (_isPaused) resume(); // Break pause to exit
    _updateStatus(DiagramStatus.cancelled);
  }

  void _updateStatus(DiagramStatus status) {
    _state = DiagramProgress(
      currentFolder: _state.currentFolder,
      processedCount: _state.processedCount,
      totalCount: _state.totalCount,
      totalPhotosDiagrammed: _state.totalPhotosDiagrammed,
      currentStepProgress: _state.currentStepProgress,
      status: status,
    );
    _progressController.add(_state);
  }

  void _updateProgress({String? folder, int? processed, int? total, int? photosAdded, double? step}) {
    _state = DiagramProgress(
      currentFolder: folder ?? _state.currentFolder,
      processedCount: processed ?? _state.processedCount,
      totalCount: total ?? _state.totalCount,
      totalPhotosDiagrammed: (photosAdded != null) ? _state.totalPhotosDiagrammed + photosAdded : _state.totalPhotosDiagrammed,
      currentStepProgress: step ?? _state.currentStepProgress,
      status: _state.status,
    );
    _progressController.add(_state);
  }

  // --- Main Logic ---

  Future<void> startDiagramming({
    required String modelProjectPath,
    required String rootFolderPath,
    required String contractNumber,
  }) async {
    _isCancelled = false;
    _isPaused = false;
    _state = DiagramProgress(status: DiagramStatus.running);
    _progressController.add(_state);

    try {
      // 1. Analyze Model
      final modelProject = await _loadProject(modelProjectPath);
      if (modelProject == null) throw Exception("Erro ao ler projeto modelo.");
      
      // 2. Scan Folders
      final rootDir = Directory(rootFolderPath);
      final entries = rootDir.listSync().whereType<Directory>().toList();
      // Filter out non-student folders? e.g., "Output"
      final studentFolders = entries.where((d) => 
         !p.basename(d.path).toLowerCase().startsWith("output") &&
         !p.basename(d.path).startsWith(".")
      ).toList();

      _updateProgress(total: studentFolders.length, processed: 0);

      // 3. Process Loop
      for (var folder in studentFolders) {
        if (_isCancelled) break;
        await _checkPause();

        final folderName = p.basename(folder.path);
        _updateProgress(folder: folderName, step: 0.1);

        // A. Import & AutoSelect
        final photos = _scanPhotos(folder);
        await _checkPause();
        
        // Run Auto Select
        // Target count logic isn't supported by engine yet, it uses Time Clustering
        _updateProgress(step: 0.3);
        final selectedPhotos = await AutoSelectEngine.findBestPhotos(photos);
        
        // B. Diagramming (Magic)
        await _checkPause();
        _updateProgress(step: 0.6);
        
        final newProject = await _generateStudentProject(modelProject, selectedPhotos, contractNumber, folderName);
        
        // C. Save
        final savePath = p.join(folder.path, "${contractNumber}_$folderName.alem");
        await _saveProject(newProject, savePath);
        
        _updateProgress(
           processed: _state.processedCount + 1,
           photosAdded: selectedPhotos.length, // Approx
           step: 1.0
        );
      }

      if (!_isCancelled) {
         _updateStatus(DiagramStatus.completed);
      }

    } catch (e) {
      debugPrint("AutoDiagram Error: $e");
      _updateStatus(DiagramStatus.idle); // Or error state
      rethrow;
    }
  }

  Future<void> _checkPause() async {
    if (_isPaused) {
      _pauseCompleter = Completer();
      await _pauseCompleter!.future;
    }
  }

  // --- Helpers ---

  Future<Project?> _loadProject(String path) async {
     try {
       final file = File(path);
       if (!await file.exists()) return null;
       final jsonStr = await file.readAsString();
       final jsonMap = jsonDecode(jsonStr);
       return Project.fromJson(jsonMap);
     } catch (e) {
       debugPrint("Error loading project: $e");
       return null;
     }
  }
  
  List<String> _scanPhotos(Directory dir) {
    return dir.listSync(recursive: true)
      .whereType<File>()
      .where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return ['.jpg', '.jpeg', '.png'].contains(ext);
      })
      .map((f) => f.path)
      .toList();
  }
  
  int _countModelSlots(Project project) {
    int count = 0;
    for (var page in project.pages) {
       // Only count photos/placeholders, not stickers/text if possible?
       // PhotoItem has 'isText'. 
       // We want photo slots.
       count += page.photos.where((p) => !p.isText).length; 
    }
    return count == 0 ? 80 : count;
  }

  Future<Project> _generateStudentProject(Project model, List<String> selectedPhotos, String contract, String studentName) async {
     // A. Prepare Available Photos with Metadata (Dimensions + Date + Camera)
     List<_PhotoMetaInfo> availablePhotos = [];
     
     // 1. Fetch EXIF Metadata (Date & Camera) in background
     final metadataList = await MetadataHelper.getMetadataBatch(selectedPhotos);
     // Create a lookup map for faster access if needed, or just iterate parallel since order preserves?
     // getMetadataBatch preserves order of input list.
     
     for (int i = 0; i < selectedPhotos.length; i++) {
        final path = selectedPhotos[i];
        final meta = metadataList[i];
        
        int w = 0;
        int h = 0;
        // 2. Fetch Dimensions (UI) - needed for precise aspect ratio logic
        // (MetadataHelper gives orientation but UI gives exact pixels for layout if needed)
        try {
           final bytes = await File(path).readAsBytes();
           final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
           final descriptor = await ui.ImageDescriptor.encoded(buffer);
           w = descriptor.width;
           h = descriptor.height;
           descriptor.dispose();
           buffer.dispose();
        } catch (e) {
           // ignore
        }
        
        
        // Apply Time Offsets (Time Shift)
        final offsets = model.cameraTimeOffsets;
        DateTime date = meta.dateTaken ?? DateTime(1970);
        
        if (offsets.isNotEmpty) {
           String key = meta.cameraModel ?? "";
           // Prefer Model_Serial
           if (meta.cameraSerial != null && meta.cameraSerial!.isNotEmpty) {
              key = "${meta.cameraModel ?? 'Unknown'}_${meta.cameraSerial}";
           } else if (key.isEmpty) {
              key = "Unknown";
           }
           
           final offset = offsets[key] ?? offsets[meta.cameraModel] ?? 0;
           if (offset != 0) {
              date = date.add(Duration(seconds: offset));
           }
        }
        
        availablePhotos.add(_PhotoMetaInfo(path, w, h, date, meta.cameraModel));
     }

     // 3. Advanced Sorting: Day > Camera > Time
     availablePhotos.sort((a, b) {
        // A. Day Comparison
        final da = a.date ?? DateTime(0);
        final db = b.date ?? DateTime(0);
        
        // Truncate to Day
        final dayA = DateTime(da.year, da.month, da.day);
        final dayB = DateTime(db.year, db.month, db.day);
        
        int dayC = dayA.compareTo(dayB);
        if (dayC != 0) return dayC;
        
        // B. Camera Comparison
        final ca = a.camera ?? "";
        final cb = b.camera ?? "";
        int camC = ca.compareTo(cb);
        if (camC != 0) return camC;
        
        // C. Time Comparison
        return da.compareTo(db);
     });
     
     List<AlbumPage> newPages = [];
     
     // Detect Recyclable Pages (Any page with slots)
     List<ProjectPageTemplate> recyclableTemplates = [];
     
     // 1. Process Model Pages (First Pass)
     for (int i = 0; i < model.pages.length; i++) {
        var modelPage = model.pages[i];
        
        // Check if page has slots (for recycling later)
        bool hasSlots = modelPage.photos.any((p) => !_isTemplate(p));
        if (hasSlots) {
           recyclableTemplates.add(ProjectPageTemplate(modelPage, i));
        }

        if (availablePhotos.isEmpty) {
            newPages.add(modelPage); 
            continue; 
        }
        
        final filledPage = _fillPageSlots(modelPage, availablePhotos);
        newPages.add(filledPage);
     }
     
     // 2. Overflow Handling (Recycle)
     if (availablePhotos.isNotEmpty && recyclableTemplates.isNotEmpty) {
         // Sort templates by index to keep sequence naturally? They are already sorted by adding order.
         int templateIndex = 0;
         int safetyLimit = 1000; 
         int loopCount = 0;
         
         while (availablePhotos.isNotEmpty && loopCount < safetyLimit) {
             loopCount++;
             
             // Pick next template (Round Robin)
             final template = recyclableTemplates[templateIndex];
             templateIndex = (templateIndex + 1) % recyclableTemplates.length;
             
             // Clone Page (New ID)
             // We need to Reset the slots to their original state (which might have been filled in the model?)
             // Actually, `modelPage` from `model.pages` is the source. It has placeholders.
             // So we just use `template.page`.
             
             final freshPage = template.page.copyWith(id: Uuid().v4());
             
             final filledPage = _fillPageSlots(freshPage, availablePhotos);
             newPages.add(filledPage);
         }
     }
     
     // B. Update Project Info
     return model.copyWith(
       id: Uuid().v4(),
       name: "${contract}_$studentName",
       contractNumber: contract,
       pages: newPages,
       allImagePaths: selectedPhotos 
     );
  }

  AlbumPage _fillPageSlots(AlbumPage page, List<_PhotoMetaInfo> availablePhotos) {
      final slots = <PhotoItem>[];
      final templates = <PhotoItem>[];
      
      for (var item in page.photos) {
         if (_isTemplate(item)) {
            templates.add(item);
         } else {
            slots.add(item);
         }
      }
      
      if (slots.isEmpty) return page;

      final filledPhotos = <PhotoItem>[...templates]; 
      
      // Map slots to new photos
      Map<String, String> assignments = {};
      
      for (var slot in slots) {
           if (availablePhotos.isEmpty) break;
           
           bool slotIsVert = (slot.height > slot.width);
           int matchIndex = -1;
           int lookAhead = 10;
           
           for (int i = 0; i < availablePhotos.length && i < lookAhead; i++) {
               bool photoIsVert = availablePhotos[i].height > availablePhotos[i].width;
               if (slotIsVert == photoIsVert) {
                  matchIndex = i;
                  break;
               }
           }
           if (matchIndex == -1) matchIndex = 0; 
           
           final selected = availablePhotos.removeAt(matchIndex);
           assignments[slot.id] = selected.path;
      }
      
      // Rebuild preserving order
      final finalPhotos = <PhotoItem>[];
      for (var item in page.photos) {
          if (assignments.containsKey(item.id)) {
             finalPhotos.add(item.copyWith(
                 path: assignments[item.id],
                 contentX: 0, contentY: 0, contentScale: 1.0
             ));
          } else {
             finalPhotos.add(item);
          }
      }
      
      return page.copyWith(photos: finalPhotos);
  }
  

  
  bool _isTemplate(PhotoItem item) {
     if (item.isText) return true;
     final p = item.path.toLowerCase();
     if (p.contains("assets") || p.contains("templates")) return true;
     // Add more heuristics if needed
     return false;
  }



  bool validationIncludes(List<PhotoItem> list, PhotoItem item) {
      return list.any((e) => e.id == item.id);
  }

  Future<void> _saveProject(Project project, String path) async {
     try {
       final jsonStr = jsonEncode(project.toJson());
       await File(path).writeAsString(jsonStr);
     } catch (e) {
       debugPrint("Save Error: $e");
       rethrow;
     }
  }

}

class _PhotoMetaInfo {
   final String path;
   final int width;
   final int height;
   final DateTime? date;
   final String? camera;
   _PhotoMetaInfo(this.path, this.width, this.height, this.date, this.camera);
}

class ProjectPageTemplate {
   final AlbumPage page;
   final int originalIndex;
   ProjectPageTemplate(this.page, this.originalIndex);
}
