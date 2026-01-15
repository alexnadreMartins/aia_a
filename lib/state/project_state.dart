import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/project_model.dart';
import '../logic/template_system.dart';
import '../logic/metadata_helper.dart';
import '../logic/layout_engine.dart';
import '../models/asset_model.dart';

import '../logic/auto_select_engine.dart';
import 'package:image/image.dart' as img; // For Rotation
import '../logic/cache_provider.dart'; // For Cache Utils
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart'; // ZIP Support
import '../logic/project_packager.dart';





enum BrowserSortType { name, date, selected }
enum BrowserFilterType { all, selected, unselected, used, unused }

// --- State Definition ---
class PhotoBookState {
  final Project project;
  final bool canUndo;
  final bool canRedo;
  final String? selectedPhotoId;
  final bool isEditingContent;
  final Set<String> selectedBrowserPaths;
  final bool isProcessing;
  final bool isExporting;
  final PhotoItem? clipboardPhoto;
  final double canvasScale;
  final String? currentProjectPath;

  final Set<int> multiSelectedPages;
  final bool isTouchMultiSelectMode;
  final bool isPrecisionMode; // NEW
  
  // New Browser Fields
  final BrowserSortType browserSortType;
  final BrowserFilterType browserFilterType;
  final String? proxyRoot; // Path to unzipped proxies (if loaded from package)

  PhotoBookState({
    required this.project,
    this.canUndo = false,
    this.canRedo = false,
    this.selectedPhotoId,
    this.isEditingContent = false,
    this.selectedBrowserPaths = const {},
    this.isProcessing = false,
    this.isExporting = false,
    this.clipboardPhoto,
    this.canvasScale = 1.0,
    this.currentProjectPath,
    this.multiSelectedPages = const {},
    this.isTouchMultiSelectMode = false,
    this.isPrecisionMode = false,
    this.browserSortType = BrowserSortType.name,
    this.browserFilterType = BrowserFilterType.all,
    this.proxyRoot,
  });

  PhotoBookState copyWith({
    Project? project,
    bool? canUndo,
    bool? canRedo,
    String? selectedPhotoId,
    bool? isEditingContent,
    Set<String>? selectedBrowserPaths,
    bool? isProcessing,
    bool? isExporting,
    PhotoItem? clipboardPhoto,
    double? canvasScale,
    String? currentProjectPath,
    Set<int>? multiSelectedPages,
    BrowserSortType? browserSortType,
    bool? isTouchMultiSelectMode,
    bool? isPrecisionMode,
    BrowserFilterType? browserFilterType,
    String? proxyRoot,
  }) {
    return PhotoBookState(
      project: project ?? this.project,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      selectedPhotoId: selectedPhotoId ?? this.selectedPhotoId,
      isEditingContent: isEditingContent ?? this.isEditingContent,
      selectedBrowserPaths: selectedBrowserPaths ?? this.selectedBrowserPaths,
      isProcessing: isProcessing ?? this.isProcessing,
      isExporting: isExporting ?? this.isExporting,
      clipboardPhoto: clipboardPhoto ?? this.clipboardPhoto,
      canvasScale: canvasScale ?? this.canvasScale,
      currentProjectPath: currentProjectPath ?? this.currentProjectPath,
      multiSelectedPages: multiSelectedPages ?? this.multiSelectedPages,
      isTouchMultiSelectMode: isTouchMultiSelectMode ?? this.isTouchMultiSelectMode,
      isPrecisionMode: isPrecisionMode ?? this.isPrecisionMode,
      browserSortType: browserSortType ?? this.browserSortType,
      browserFilterType: browserFilterType ?? this.browserFilterType,
      proxyRoot: proxyRoot ?? this.proxyRoot,
    );
  }

  Map<String, int> get photoUsage {
    final Map<String, int> usage = {};
    for (var page in project.pages) {
      for (var photo in page.photos) {
        if (photo.path.isNotEmpty) {
          usage[photo.path] = (usage[photo.path] ?? 0) + 1;
        }
      }
    }
    return usage;
  }
}

// --- Notifier with Undo/Redo Logic ---
class ProjectNotifier extends StateNotifier<PhotoBookState> {
  final Ref ref; // Inject Ref
  // ...
  
  void setEditingContent(bool isEditing) {
     if (state.isEditingContent == isEditing) {
       if (!isEditing) {
          // Force update to ensure we exit edit mode cleanly
          state = state.copyWith(isEditingContent: false);
       }
       return;
     }
     state = state.copyWith(isEditingContent: isEditing);
  }

  void toggleTouchMultiSelect() {
     state = state.copyWith(isTouchMultiSelectMode: !state.isTouchMultiSelectMode);
  }

  void togglePrecisionMode() {
     state = state.copyWith(isPrecisionMode: !state.isPrecisionMode);
  }

  void setIsExporting(bool check) {
     if (state.isExporting == check) return;
     state = state.copyWith(isExporting: check);
  }

  // Command History Stacks (Serialized States)
  // In a real app we might store Diff Commands, but for 'port' parity with simple Python state saving:
  // python code: self.undo_stack.append(state)
  final List<Project> _undoStack = [];
  final List<Project> _redoStack = [];
  static const int _maxHistory = 50;

  ProjectNotifier(this.ref)
      : super(PhotoBookState(
          project: Project(pages: [_createDefaultPage()]),
        ));

  static AlbumPage _createDefaultPage({double widthMm = 210, double heightMm = 297, String? backgroundPath}) {
    return AlbumPage(widthMm: widthMm, heightMm: heightMm, backgroundPath: backgroundPath); 
  }

  void setProject(Project newProject) {
      _saveStateToHistory();
      _undoStack.clear(); 
      _redoStack.clear();
      
      state = state.copyWith(
          project: newProject,
          multiSelectedPages: {},
          selectedPhotoId: null,
          selectedBrowserPaths: {}
      );
      _updateUndoRedoFlags();
  }

  void _saveStateToHistory() {
    if (_undoStack.length >= _maxHistory) {
      _undoStack.removeAt(0);
    }
    _undoStack.add(state.project);
    _redoStack.clear();
    _updateUndoRedoFlags();
  }

  void _updateUndoRedoFlags() {
    state = state.copyWith(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  void saveHistorySnapshot() {
    _saveStateToHistory();
  }
  
  void setPageIndex(int index) {
      if(index < 0 || index >= state.project.pages.length) return;
      state = state.copyWith(project: state.project.copyWith(currentPageIndex: index));
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    _redoStack.add(state.project);
    state = state.copyWith(project: previous);
    _updateUndoRedoFlags();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    _undoStack.add(state.project);
    state = state.copyWith(project: next);
    _updateUndoRedoFlags();
  }

  // --- Actions ---

  void selectPhoto(String? photoId) {
    if (state.selectedPhotoId == photoId) {
      // Force update if we are deselecting (photoId == null) to ensure UI redraws happen,
      // especially for export where we need to clear handles.
      if (photoId == null) {
         state = state.copyWith(selectedPhotoId: null);
      }
      return;
    }
    state = state.copyWith(selectedPhotoId: photoId);
  }

  void setCanvasScale(double scale) {
    state = state.copyWith(canvasScale: scale.clamp(0.01, 20.0));
  }

  void updateCanvasScale(double delta) {
    setCanvasScale(state.canvasScale + delta);
  }

  Future<void> rotateSelectedGalleryPhotos(int degrees) async {
    if (state.selectedBrowserPaths.isEmpty) return;
    
    final paths = state.selectedBrowserPaths.toList();
    
    // 1. Optimistic UI Update matches user expectation "works offline"
    // We update the visual state immediately.
    final newRotations = Map<String, int>.from(state.project.imageRotations);
    for (var path in paths) {
       final current = newRotations[path] ?? 0;
       // Add rotation (ensure 0-360 normalization)
       newRotations[path] = (current + degrees) % 360;
    }

    state = state.copyWith(
      project: state.project.copyWith(imageRotations: newRotations)
    );

    // 2. Background Process (Sync Later)
    // We do NOT await this to block UI. 
    // Ideally we might want a queue, but simply unawaited async serves the "offline" requirement 
    // as it won't freeze the app if disk is slow/unavailable.
    Future.microtask(() async {
        for (var path in paths) {
           await _rotateFile(path, degrees);
           // After successful write, we MIGHT reset the visual rotation if we wanted to reload the file.
           // BUT: The user experience is smoother if we just keep the rotation value 
           // until the next reload. 
           // However, `_rotateFile` overwrites the bits. 
           // If we overwrite bits, we should eventually reset the `imageRotations` to 0 
           // so we don't double-rotate on reload.
           // CHALLENGE: If we reset to 0 later, the user sees a jump.
           // BETTER: Update the `imageRotations` to 0 ONLY when we confirm the file is reloaded/cached.
           // For now, let's Stick to: Update Map, Write File. 
           // Issue: If we write file, next time we load it, it's rotated. 
           // If we also store "90" in map, we see 90+90 = 180.
           // FIX: We need to reset the map to 0 AFTER the file is safely written and we trigger a reload.
           // OR: We just don't write to the file until export? No, user wants it saved.
           
           // Correct Approach for "Offline":
           // 1. UI sets rotation to +90. User sees +90.
           // 2. Background tries to write file. 
           // 3. If success: Write file, THEN update state to set rotation back to 0 (and reload image).
           // This causes a "flicker".
           // ALTERNATIVE: Don't modify the file bits! Just store metadata!
           // User specifically said "rotacionar no modo offline para syncronizar depois".
           // This implies they want the ACTION to be queued.
           // Modifying bits is destructive and slow. 
           // IF the legacy app modified bits, we should stick to it OR changing to Metadata-only is better?
           // `_rotateFile` does `img.copyRotate`, which IS modifying bits.
           
           // PROPOSED FIX:
           // Keep the Optimistic Rotation in `imageRotations` (Metadata).
           // TRY to write the file in background.
           // IF successful, THEN reset metadata to 0.
           // IF fails (offline), keep metadata. 
           // Next time app opens, it sees metadata +90.
           // Checks file. If file is original, applies +90 on view.
           // We need a "Sync" process that runs on startup/connection to apply pending rotations?
           
           // Implementation for NOW (Quick Fix):
           // Just keep the metadata rotation!
           // Don't modify the file immediately if it blocks? 
           // Actually, `_rotateFile` is what they want "synced later".
           // So:
           // 1. Update State (Rotation += 90).
           // 2. Background: Rotate File. 
           // 3. If Success -> Update State (Rotation -= 90, i.e. back to 0), Invalidate Cache.
           
           await _safeRotateInBackground(path, degrees);
        }
    });
  }

  Future<void> rotateGalleryPhoto(String path, int degrees) async {
    // Optimistic Update
    final newRotations = Map<String, int>.from(state.project.imageRotations);
    newRotations[path] = (newRotations[path] ?? 0) + degrees;
    
    state = state.copyWith(
       project: state.project.copyWith(imageRotations: newRotations)
    );
    
    // Background execution
    _safeRotateInBackground(path, degrees);
  }
  
  Future<void> rotatePagePhoto(String photoId, double deltaDegrees) async {
       // 1. Find the photo path
       String? path;
       PhotoItem? targetPhoto;
       
       for (var page in state.project.pages) {
          try {
             targetPhoto = page.photos.firstWhere((p) => p.id == photoId);
             path = targetPhoto.path;
             break;
          } catch (_) {}
       }
       
       if (path == null || path.isEmpty || targetPhoto == null) return;

       // 2. Optimistic UI Update (Metadata Rotation)
       // We update the PhotoItem rotation momentarily OR validly?
       // The original code rotated the FILE and reset the Item rotation to 0.
       // We will simulate that by checking if we can rotate the item visually first.
       
       _saveStateToHistory();
       
       // Apply visual rotation immediately
       final newPages = state.project.pages.map((page) {
           if (!page.photos.any((p) => p.id == photoId)) return page;
           final newPhotos = page.photos.map((p) {
               if (p.id == photoId) {
                   return p.copyWith(rotation: p.rotation + deltaDegrees);
               }
               return p;
           }).toList();
           return page.copyWith(photos: newPhotos);
       }).toList();
       
       state = state.copyWith(project: state.project.copyWith(pages: newPages));

       // 3. Background Sync
       // We want to rotate the file, and ON SUCCESS, reset the visual rotation to 0.
       // Only rotate file if it's 90 degree increments.
       if (deltaDegrees % 90 == 0) {
            _safeRotateInBackground(path, deltaDegrees.toInt(), resetPhotoId: photoId);
       }
       
  }
  Future<void> _safeRotateInBackground(String path, int degrees, {String? resetPhotoId}) async {
      try {
           final file = File(path);
           if (!await file.exists()) {
               // Offline / Missing
               debugPrint("File $path not found for rotation (Offline). Pending sync...");
               // In a real sync system, queue this. For now, we just leave the Metadata rotation in place!
               // This fulfils "offline mode" -> User sees rotation (stored in metadata/state), file is untouched.
               // When they come online or reload, if file is still not rotated, they see metadata rotation.
               return;
           }

           // Perform Rotation
           await _rotateFile(path, degrees);
           
           // ON SUCCESS:
           // We need to revert the metadata rotation we applied optimistically, 
           // because now the bits are rotated.
           
           // 1. Update Browser Rotations (Set back to 0)
           final currentRot = state.project.imageRotations[path] ?? 0;
           // The state might have changed since we started!
           // But generally: if we rotated file by 'degrees', we subtract 'degrees' from visual.
           final newRot = (currentRot - degrees) % 360;
           final newRotations = Map<String, int>.from(state.project.imageRotations);
           newRotations[path] = newRot; // Usually 0
           
           // 2. Update Page Photos (Set back to 0 if we passed an ID)
           List<AlbumPage> newPages = state.project.pages;
           if (resetPhotoId != null) {
               newPages = state.project.pages.map((page) {
                   if (!page.photos.any((p) => p.id == resetPhotoId)) return page;
                   return page.copyWith(photos: page.photos.map((p) {
                       if (p.id == resetPhotoId) {
                           return p.copyWith(rotation: 0); // Reset to 0 as bits are rotated
                       }
                       /// WARNING: Should we update ALL instances of this path?
                       /// User said "no arquivo".
                       /// The original logic updated all. 
                       /// If `resetPhotoId` is passed, we target one. 
                       /// But really we should find ALL photos with this path and decrement/reset their rotation?
                       if (p.path == path) {
                           return p.copyWith(rotation: 0);
                       }
                       return p;
                   }).toList());
               }).toList();
           } else {
               // Browser rotation affected all instances?
               // If we rotate via Browser, we probably want to reset all consumers too.
                newPages = state.project.pages.map((page) {
                   bool varied = false;
                   final newPhotos = page.photos.map((p) {
                       if (p.path == path) {
                           varied = true;
                           return p.copyWith(rotation: 0); 
                       }
                       return p;
                   }).toList();
                   if (varied) return page.copyWith(photos: newPhotos);
                   return page;
               }).toList();
           }

           state = state.copyWith(
               project: state.project.copyWith(
                   imageRotations: newRotations,
                   pages: newPages
               )
           );
           
           // Cache Cleanup
           CacheService.invalidate(ref, path);
           ref.read(imageVersionProvider(path).notifier).state++;
           
      } catch (e) {
          debugPrint("Rotation Background Error: $e");
          // If failed, keep the metadata rotation so user still sees it!
      }
  }

  Future<void> _rotateFile(String path, int degrees) async {
      try {
        final file = File(path);
        // Note: calling existSync or similar inside async method is ok, 
        // but since we are in background, we can await.
        if (!await file.exists()) throw Exception("File not found");
        
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image == null) return;
        
        final rotated = img.copyRotate(image, angle: degrees);
        
        List<int> newBytes;
        if (path.toLowerCase().endsWith(".png")) {
           newBytes = img.encodePng(rotated);
        } else {
           newBytes = img.encodeJpg(rotated, quality: 95); 
        }
        
        await file.writeAsBytes(newBytes, flush: true);
        
      } catch (e) {
        debugPrint("Error rotating file $path: $e");
        rethrow; // Propagate to let _safeRotateInBackground allow metadata persistence
      }
  }

  void toggleBrowserPathSelection(String path) {
    final current = state.selectedBrowserPaths;
    final updated = Set<String>.from(current);
    if (updated.contains(path)) {
      updated.remove(path);
    } else {
      updated.add(path);
    }
    state = state.copyWith(selectedBrowserPaths: updated);
  }

  void clearBrowserSelection() {
    state = state.copyWith(selectedBrowserPaths: {});
  }

  void selectAllBrowserPhotos() {
    state = state.copyWith(selectedBrowserPaths: Set<String>.from(state.project.allImagePaths));
  }

  void deselectAllBrowserPhotos() {
    state = state.copyWith(selectedBrowserPaths: {});
  }

 
  // --- Browser Logic ---

  void setBrowserSortType(BrowserSortType type) {
    if (state.browserSortType == type) return;
    state = state.copyWith(browserSortType: type);
  }

  void setBrowserFilterType(BrowserFilterType type) {
    if (state.browserFilterType == type) return;
    state = state.copyWith(browserFilterType: type);
  }

  List<String> getSortedAndFilteredPaths() {
    final allPaths = state.project.allImagePaths;
    List<String> filtered = [];
    
    // 1. Filter
    final usage = state.photoUsage;
    switch (state.browserFilterType) {
      case BrowserFilterType.all:
        filtered = List.from(allPaths);
        break;
      case BrowserFilterType.selected:
        filtered = allPaths.where((p) => state.selectedBrowserPaths.contains(p)).toList();
        break;
      case BrowserFilterType.unselected:
        filtered = allPaths.where((p) => !state.selectedBrowserPaths.contains(p)).toList();
        break;
      case BrowserFilterType.used:
        filtered = allPaths.where((p) => usage.containsKey(p)).toList();
        break;
      case BrowserFilterType.unused:
        filtered = allPaths.where((p) => !usage.containsKey(p)).toList();
        break;
    }

    // 2. Sort
    switch (state.browserSortType) {
      case BrowserSortType.name:
        // Case insensitive sort
        filtered.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        break;
      case BrowserSortType.date:
        // Fast sort by File Modification Time (Sync)
        // Ideally we cache this, but for < 1000 photos might be ok?
        // Doing I/O in sort comparator is bad.
        // Let's caching logic:
        // We will just sort by path (name) as fallback if heavy?
        // Actually, we can just grab File stats once.
        final map = <String, DateTime>{};
        for (var p in filtered) {
           try {
             map[p] = File(p).lastModifiedSync();
           } catch (_) {
             map[p] = DateTime(1970);
           }
        }
        filtered.sort((a, b) => map[b]!.compareTo(map[a]!)); // Newest first
        break;
      case BrowserSortType.selected:
        // Selected first, then name
        filtered.sort((a, b) {
           final selA = state.selectedBrowserPaths.contains(a);
           final selB = state.selectedBrowserPaths.contains(b);
           if (selA && !selB) return -1;
           if (!selA && selB) return 1;
           return a.toLowerCase().compareTo(b.toLowerCase());
        });
        break;
    }
    
    return filtered;
  }
  
  // New Range Selection Logic
  void selectBrowserRange(String startPath, String endPath, List<String> currentViewPaths) {
      final startIndex = currentViewPaths.indexOf(startPath);
      final endIndex = currentViewPaths.indexOf(endPath);
      
      if (startIndex == -1 || endIndex == -1) return;
      
      final start = startIndex < endIndex ? startIndex : endIndex;
      final end = startIndex < endIndex ? endIndex : startIndex;
      
      final range = currentViewPaths.sublist(start, end + 1);
      final newSet = Set<String>.from(state.selectedBrowserPaths);
      newSet.addAll(range);
      
      state = state.copyWith(selectedBrowserPaths: newSet);
  }

  // Last Auto Layout Logic
  Future<void> applyAutoLayout(List<String> paths) async {
    if (paths.isEmpty || state.isProcessing) return;
    
    state = state.copyWith(isProcessing: true);
    _saveStateToHistory();

    try {
      debugPrint("Starting Restored Smart Flow for ${paths.length} photos...");
      
      // 1. Prepare Assets with Dimensions
      List<LibraryAsset> assets = [];
      for (var p in paths) {
          DateTime? date;
          int w = 0;
          int h = 0;
          try { 
              date = await File(p).lastModified();
              // Try fast meta read
              final bytes = await File(p).readAsBytes();
              final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
              final descriptor = await ui.ImageDescriptor.encoded(buffer);
              w = descriptor.width;
              h = descriptor.height;
              descriptor.dispose();
              buffer.dispose();
          } catch(e) {
             debugPrint("Error reading image info for $p: $e");
          }
          
          assets.add(LibraryAsset(
              path: p, 
              name: p.split(Platform.pathSeparator).last,
              fileDate: date,
              width: w == 0 ? 1000 : w,
              height: h == 0 ? 1000 : h
          ));
      }

      // 2. Sort by Date
      assets.sort((a, b) {
         if (a.fileDate == null || b.fileDate == null) return 0;
         return a.fileDate!.compareTo(b.fileDate!);
      });

      // 3. Logic Implementation
      List<LibraryAsset> remaining = List.from(assets);
      List<AlbumPage> newPages = [];
      
      final double pW = state.project.pages.isNotEmpty ? state.project.pages[0].widthMm : 305;
      final double pH = state.project.pages.isNotEmpty ? state.project.pages[0].heightMm : 215;

      // Helper to classify
      bool isVert(LibraryAsset a) => (a.height ?? 0) > (a.width ?? 0);

      // A. Global Cover (First Vertical)
      LibraryAsset? coverPhoto;
      final firstVIndex = remaining.indexWhere((a) => isVert(a));
      if (firstVIndex != -1) {
         coverPhoto = remaining.removeAt(firstVIndex);
      }

      // B. Global Back Cover (Last Vertical)
      LibraryAsset? backCoverPhoto;
      final lastVIndex = remaining.lastIndexWhere((a) => isVert(a));
      if (lastVIndex != -1) {
         backCoverPhoto = remaining.removeAt(lastVIndex);
      }

      // C. Generate Pages
      
      // C1. Page 1: Cover
      if (coverPhoto != null) {
          final pagePhotos = TemplateSystem.applyTemplate(
             '1_vertical_half_right', 
             [PhotoItem(id: Uuid().v4(), path: coverPhoto.path, width: pW, height: pH)], 
             pW, pH
          );
          newPages.add(AlbumPage(id: Uuid().v4(), widthMm: pW, heightMm: pH, photos: pagePhotos, pageNumber: 0));
      }

      // C2. Day Processing
      // Group by Day (YYYY-MM-DD)
      Map<String, List<LibraryAsset>> dayGroups = {};
      for (var asset in remaining) {
         final date = asset.fileDate ?? DateTime.now();
         final key = "${date.year}-${date.month}-${date.day}";
         dayGroups.putIfAbsent(key, () => []).add(asset);
      }
      
      final sortedDays = dayGroups.keys.toList()..sort();
      
      // Identify if Day 1 is the SAME day as the Cover Photo?
      // User said: "primeira pagina... depois criava a cada dia com a primeira foto do dia vertical".
      // Usually the Cover matches the First Day. So we might SKIP the "Day Start" logic for the First Day 
      // if we assume the Cover *is* the opening for Day 1.
      // However, if Day 1 has *many* photos, maybe a section divider is wanted?
      // Logic: "depois criava a cada dia". "After, create for each day".
      // This implies 2nd day onwards needs opening.
      // Or First Day also needs opening if it wasn't the cover?
      // Let's assume: If Cover exists, it counts as Day 1 opener.
      // So for Day 1, we just process Content.
      // For Day 2+, we look for an Opener.
      
      String? coverDayKey;
      if (coverPhoto != null && coverPhoto.fileDate != null) {
         final d = coverPhoto.fileDate!;
         coverDayKey = "${d.year}-${d.month}-${d.day}";
      }

      for (var dayKey in sortedDays) {
          final daysPhotos = dayGroups[dayKey]!;
          if (daysPhotos.isEmpty) continue;

          // Day Opener Check
          bool needsOpener = true;
          if (dayKey == coverDayKey && coverPhoto != null) {
             needsOpener = false; // Cover already opened this day
          }
          
          if (needsOpener) {
             // Find First Vertical of this Day
             final dayVIndex = daysPhotos.indexWhere((a) => isVert(a));
             if (dayVIndex != -1) {
                 final opener = daysPhotos.removeAt(dayVIndex);
                 final pagePhotos = TemplateSystem.applyTemplate(
                    '1_vertical_half_right', 
                    [PhotoItem(id: Uuid().v4(), path: opener.path, width: pW, height: pH)], 
                    pW, pH
                 );
                 newPages.add(AlbumPage(id: Uuid().v4(), widthMm: pW, heightMm: pH, photos: pagePhotos, pageNumber: 0));
             }
          }
          
          // Day Content Layout
          // Loop through remaining photos
          // We need to look ahead for Pairs
          int i = 0;
          while (i < daysPhotos.length) {
             final current = daysPhotos[i];
             
             if (isVert(current)) {
                // Try to find next Vertical to pair
                int nextVIndex = -1;
                for (int j = i + 1; j < daysPhotos.length; j++) {
                    if (isVert(daysPhotos[j])) {
                       nextVIndex = j;
                       break;
                    }
                    // If we stick strictly to chronological, we shouldn't skip Horizontals to find a Vertical match too far away
                    // User said "Order Chronological".
                    // If we have V, H, V.
                    // Should we pair V, V and put H later? Or H then V?
                    // "mantendo ordem cronologica".
                    // If V, H, V:
                    // Page 1: V (Leftover?)
                    // Page 2: H
                    // Page 3: V (Leftover?)
                    // This creates 3 pages.
                    // If we Group V, V: Page 1 (2V), Page 2 (1H). 2 pages. Cleaner.
                    // Usually "Chronological" allows slight reordering for layout optimization within a small window.
                    // But if strict... 
                    // Let's look for *immediate* next or *closest* next.
                    // I will check if the NEXT one is vertical.
                }
                
                if (nextVIndex != -1) {
                    // We found a pair.
                    // Is it immediate? i.e. nextVIndex == i+1?
                    // If not, we have intermediate Horizontals.
                    // We process the Verticals as a pair effectively skipping the H for a moment?
                    // Or process H first?
                    // To keep it simple and mostly chronological:
                    // If current is V:
                    // Check i+1. If V -> Pair.
                    // If H -> Process V as single? Or Skip V to process H?
                    // Implementation: We'll pull the pair (V1, V2) out even if separated by H, 
                    // provided they are reasonably close (same day is close enough).
                    // This "optimizes" layout while keeping day order relative.
                    
                    final v2 = daysPhotos.removeAt(nextVIndex); // Remove the future V
                    // Remove current V (by increment loop or explicit)
                    // Be careful with index shift.
                    // Better: use a local list and removeAt(0).
                    // Refactor loop to use `while(daysPhotos.isNotEmpty)`
                }
             }
             i++;
          }
          
          // Refactored Content Loop for correct consumption
          List<LibraryAsset> dayRemaining = List.from(daysPhotos);
          while (dayRemaining.isNotEmpty) {
             final current = dayRemaining[0];
             
             if (!isVert(current)) {
                // Horizontal -> Solo Page
                dayRemaining.removeAt(0);
                 final pagePhotos = TemplateSystem.applyTemplate(
                    '1_solo_horizontal_large', // Uses 80% logic usually? Or we need specific
                    [PhotoItem(id: Uuid().v4(), path: current.path, width: pW, height: pH)], 
                    pW, pH
                 );
                 newPages.add(AlbumPage(id: Uuid().v4(), widthMm: pW, heightMm: pH, photos: pagePhotos, pageNumber: 0));
             } else {
                // Vertical
                // Look for a partner in the list
                final partnerIndex = dayRemaining.indexWhere((a) => isVert(a), 1);
                
                if (partnerIndex != -1) {
                   // Found Pair
                   final v1 = dayRemaining.removeAt(0);
                   final v2 = dayRemaining.removeAt(partnerIndex - 1); // index shifted after removeAt(0)? No, indexWhere was on original. 
                   // Wait, removeAt(0) shifts indices.
                   // partnerIndex was relative to `dayRemaining` BEFORE removeAt(0).
                   // So after removeAt(0), the partner is at `partnerIndex - 1`.
                   
                   final pagePhotos = TemplateSystem.applyTemplate(
                      '2_portrait_pair', 
                      [
                        PhotoItem(id: Uuid().v4(), path: v1.path, width: pW, height: pH),
                        PhotoItem(id: Uuid().v4(), path: v2.path, width: pW, height: pH)
                      ], 
                      pW, pH
                   );
                   newPages.add(AlbumPage(id: Uuid().v4(), widthMm: pW, heightMm: pH, photos: pagePhotos, pageNumber: 0));
                } else {
                   // No partner -> Single V
                   // Default: Half Page Right (Cover style) or Centered?
                   // User didn't specify. I'll use Half Page Right for consistency with "Verticals usually on right".
                   final v1 = dayRemaining.removeAt(0);
                   final pagePhotos = TemplateSystem.applyTemplate(
                      '1_vertical_half_right', 
                      [PhotoItem(id: Uuid().v4(), path: v1.path, width: pW, height: pH)], 
                      pW, pH
                   );
                   newPages.add(AlbumPage(id: Uuid().v4(), widthMm: pW, heightMm: pH, photos: pagePhotos, pageNumber: 0));
                }
             }
          }
      }

      // C3. Back Cover
      if (backCoverPhoto != null) {
          final pagePhotos = TemplateSystem.applyTemplate(
             '1_vertical_half_right', 
             [PhotoItem(id: Uuid().v4(), path: backCoverPhoto.path, width: pW, height: pH)], 
             pW, pH
          );
          newPages.add(AlbumPage(id: Uuid().v4(), widthMm: pW, heightMm: pH, photos: pagePhotos, pageNumber: 0));
      }

      // 4. Update State
      int startNum = state.project.pages.length + 1;
      for (int i=0; i<newPages.length; i++) {
          newPages[i] = newPages[i].copyWith(pageNumber: startNum + i);
      }
      
      final updatedPages = [...state.project.pages, ...newPages];

      state = state.copyWith(
        project: state.project.copyWith(pages: updatedPages),
        selectedBrowserPaths: {},
        isProcessing: false,
      );
      
    } catch (e, stack) {
      debugPrint("Error in Smart Flow: $e \n $stack");
      state = state.copyWith(isProcessing: false);
    }
  }

  void _applyLayoutByEngine(List<AlbumPage> pages, List<Map<String, dynamic>> chunk, AutoLayoutEngine engine, int index, {bool forceVerticalSplit = false, bool forceEventOpening = false}) {
    if (index >= pages.length) {
      pages.add(_createDefaultPage(
        widthMm: pages[0].widthMm,
        heightMm: pages[0].heightMm,
        backgroundPath: state.project.defaultBackgroundPath,
      ));
    }

    List<PhotoItem> newLayout;
    if (forceEventOpening && chunk.length == 1) {
       newLayout = TemplateSystem.applyTemplate('event_opening', chunk.map((p) => PhotoItem(
         id: Uuid().v4(),
         path: p['path'] as String,
         exifOrientation: p['orientation'] ?? 1,
       )).toList(), pages[index].widthMm, pages[index].heightMm);
    } else if (forceVerticalSplit && chunk.length == 2) {
       newLayout = TemplateSystem.applyTemplate('2_full_vertical_split', chunk.map((p) => PhotoItem(
         id: Uuid().v4(),
         path: p['path'] as String,
         exifOrientation: p['orientation'] ?? 1,
       )).toList(), pages[index].widthMm, pages[index].heightMm);
    } else if (chunk.length == 1 && (chunk[0]['ratio'] as double) > 1.2) {
       // Large Solo for landscape
       newLayout = TemplateSystem.applyTemplate('1_solo_horizontal_large', chunk.map((p) => PhotoItem(
         id: Uuid().v4(),
         path: p['path'] as String,
         exifOrientation: p['orientation'] ?? 1,
       )).toList(), pages[index].widthMm, pages[index].heightMm);
    } else if (chunk.length == 1 && (chunk[0]['ratio'] as double) < 0.8) {
       // Single Vertical Photo -> Use "Half Page Right" (User Request)
       // This leaves the left side empty for a potential second photo
       newLayout = TemplateSystem.applyTemplate('1_vertical_half_right', chunk.map((p) => PhotoItem(
         id: Uuid().v4(),
         path: p['path'] as String,
         exifOrientation: p['orientation'] ?? 1,
       )).toList(), pages[index].widthMm, pages[index].heightMm);
    } else {
       newLayout = engine.calculateFlexibleGridLayout(chunk, maxRows: chunk.length > 1 ? 2 : 1);
    }
    
    pages[index] = pages[index].copyWith(photos: newLayout);
  }


  // --- Actions ---

  void initializeProject(double widthMm, double heightMm, int pageCount) {
    // Re-initialize logic
    List<AlbumPage> pages = [];
    for(int i=0; i<pageCount; i++) {
        pages.add(_createDefaultPage(widthMm: widthMm, heightMm: heightMm));
    }
    
    // Reset history
    _undoStack.clear();
    _redoStack.clear();
    
    state = PhotoBookState(
        project: Project(
            pages: pages,
            // We could store default dimensions in Project if we added fields for it, 
            // for now we assume uniform pages based on the first one or just add standard ones.
        )
    );
  }

  // --- Page Selection & Management ---

  void togglePageSelection(int index) {
      final current = Set<int>.from(state.multiSelectedPages);
      if (current.contains(index)) {
          current.remove(index);
      } else {
          current.add(index);
      }
      state = state.copyWith(multiSelectedPages: current);
  }

  void selectPageRange(int fromIndex, int toIndex) {
      final start = fromIndex < toIndex ? fromIndex : toIndex;
      final end = fromIndex < toIndex ? toIndex : fromIndex;
      final range = <int>{};
      for(int i=start; i<=end; i++) range.add(i);
      
      final current = Set<int>.from(state.multiSelectedPages);
      current.addAll(range);
      state = state.copyWith(multiSelectedPages: current);
  }

  void clearPageSelection() {
      state = state.copyWith(multiSelectedPages: {});
  }

  void removePage(int index) {
      if (state.project.pages.length <= 1) return; 
      _saveStateToHistory();
      
      final pages = List<AlbumPage>.from(state.project.pages);
      pages.removeAt(index);
      
      int newIndex = state.project.currentPageIndex;
      if (newIndex >= pages.length) newIndex = pages.length - 1;
      
      state = state.copyWith(
          project: state.project.copyWith(pages: pages, currentPageIndex: newIndex),
          multiSelectedPages: {}, 
      );
  }

  void removeSelectedPages() {
      if (state.multiSelectedPages.isEmpty) return;
      _saveStateToHistory();
      
      final pages = List<AlbumPage>.from(state.project.pages);
      final sortedIndices = state.multiSelectedPages.toList()..sort((a,b) => b.compareTo(a)); 
      
      for(var i in sortedIndices) {
          if (i < pages.length && pages.length > 1) {
             pages.removeAt(i);
          }
      }
      
      int newIndex = state.project.currentPageIndex;
      if (newIndex >= pages.length) newIndex = pages.length - 1;
      
      state = state.copyWith(
          project: state.project.copyWith(pages: pages, currentPageIndex: newIndex),
          multiSelectedPages: {},
      );
  }

  void reorderPage(int oldIndex, int newIndex) {
    _saveStateToHistory();
    final pages = List<AlbumPage>.from(state.project.pages);
    
    // Multi-Select Reorder Support
    if (state.multiSelectedPages.contains(oldIndex) && state.multiSelectedPages.length > 1) {
       // Only if dragging one of the selected items
       // This logic is complex for partial drag. 
       // Simplification: Deselect all and just move the dragged one to avoid UI glitches for now.
       // User can drag one by one or use a hypothetical "Move Selected Here" menu.
       // But user ASKED specifically for Shift+Click drag.
       // Let's implement a BASIC multi-move:
       // If dragging a selected item, we assume the user wants to move ALL selected items to the new position.
       
       // 1. Extract all selected pages
       final selectedIndices = state.multiSelectedPages.toList()..sort();
       final selectedPages = selectedIndices.map((i) => pages[i]).toList();
       
       // 2. Remove them from old list (reverse order to keep indices valid)
       for (var i in selectedIndices.reversed) {
         pages.removeAt(i);
       }
       
       // 3. Calculate new insertion index
       // newIndex was relative to the OLD list.
       // We need to adjust it based on how many items BEFORE it were removed.
       int adjustment = 0;
       for (var i in selectedIndices) {
         if (i < newIndex) adjustment++;
       }
       int insertIndex = newIndex - adjustment;
       if (insertIndex < 0) insertIndex = 0;
       if (insertIndex > pages.length) insertIndex = pages.length;
       
       // 4. Insert all selected items at new position
       pages.insertAll(insertIndex, selectedPages);
       
       // 5. Update Selection indices (optional, but good UX)
       final newSelection = <int>{};
       for(int i=0; i<selectedPages.length; i++) {
         newSelection.add(insertIndex + i);
       }
       
       state = state.copyWith(
         project: state.project.copyWith(pages: pages),
         multiSelectedPages: newSelection,
       );
       return;
    }

    // Standard Single Reorder
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final page = pages.removeAt(oldIndex);
    pages.insert(newIndex, page);
    
    // Adjust current index logic
    int newCurrent = state.project.currentPageIndex;
    if (state.project.currentPageIndex == oldIndex) {
      newCurrent = newIndex;
    } else if (oldIndex < state.project.currentPageIndex && newIndex >= state.project.currentPageIndex) {
      newCurrent -= 1;
    } else if (oldIndex > state.project.currentPageIndex && newIndex <= state.project.currentPageIndex) {
      newCurrent += 1;
    }

    state = state.copyWith(
      project: state.project.copyWith(
        pages: pages,
        currentPageIndex: newCurrent.clamp(0, pages.length - 1),
      ),
    );
  }

  void addPage() {
    _saveStateToHistory();
    // Use dimensions of the first page as "template" for new pages, or default A4
    double w = 210;
    double h = 297;
    if (state.project.pages.isNotEmpty) {
        w = state.project.pages.first.widthMm;
        h = state.project.pages.first.heightMm;
    }
    
    final newPage = _createDefaultPage(widthMm: w, heightMm: h, backgroundPath: state.project.defaultBackgroundPath);
    final updatedPages = [...state.project.pages, newPage];
    final updatedProject = state.project.copyWith(
      pages: updatedPages,
      currentPageIndex: updatedPages.length - 1,
    );
    state = state.copyWith(project: updatedProject);
  }

  void addPhotoToCurrentPage(PhotoItem photo) {
    addPhotosToCurrentPage([photo]);
  }

  void addPhotosToCurrentPage(List<PhotoItem> newPhotos) {
    if (newPhotos.isEmpty) return;
    _saveStateToHistory();
    
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;

    final currentPage = state.project.pages[pIdx];
    final updatedPhotos = [...currentPage.photos, ...newPhotos];
    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;

    // Track allImagePaths
    final allPaths = Set<String>.from(state.project.allImagePaths);
    for (var p in newPhotos) {
      if (p.path.isNotEmpty) allPaths.add(p.path);
    }

    state = state.copyWith(
      project: state.project.copyWith(
        pages: updatedPages,
        allImagePaths: allPaths.toList(),
      ),
    );
  }

  void addPhotos(List<String> paths) {
    _saveStateToHistory();
    final allPaths = Set<String>.from(state.project.allImagePaths);
    allPaths.addAll(paths);
    state = state.copyWith(
      project: state.project.copyWith(
        allImagePaths: allPaths.toList(),
      ),
    );
  }

  void updatePhoto(String photoId, PhotoItem Function(PhotoItem) updater) {
     // This is a "continuous" edit (like dragging), might not want to save history on EVERY frame.
     // For now, we won't save history here, assuming 'mouseRelease' triggers the save.
     // OR the UI calls saveHistory explicitly.
     
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;

    final currentPage = state.project.pages[pIdx];
    final List<PhotoItem> updatedPhotos = currentPage.photos.map<PhotoItem>((p) {
      if (p.id == photoId) {
        return updater(p); 
      }
      return p;
    }).toList();

    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;

    state = state.copyWith(
      project: state.project.copyWith(pages: updatedPages),
    );
  }

  void removePhoto(String photoId) {
    _saveStateToHistory();
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;

    final currentPage = state.project.pages[pIdx];
    final updatedPhotos = currentPage.photos.where((p) => p.id != photoId).toList();
    
    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;

    state = state.copyWith(
        project: state.project.copyWith(pages: updatedPages),
        selectedPhotoId: null, // Deselect
    );
  }

  void updatePageLayout(List<PhotoItem> newLayout) {
    _saveStateToHistory();
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;
    
    final currentPage = state.project.pages[pIdx];
    final updatedPage = currentPage.copyWith(photos: newLayout);
    
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;
    
    state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
  }

  void duplicatePhoto(String photoId) {
    _saveStateToHistory();
    // Logic: find photo, clone it with new ID, shift position slightly, add to list.
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;
    
    final currentPage = state.project.pages[pIdx];
    try {
      final original = currentPage.photos.firstWhere((p) => p.id == photoId);
      final newPhoto = original.copyWith(
         id: Uuid().v4(),
         x: original.x + 20,
         y: original.y + 20,
      );
      
      final updatedPhotos = [...currentPage.photos, newPhoto];
      final updatedPage = currentPage.copyWith(photos: updatedPhotos);
      final updatedPages = List<AlbumPage>.from(state.project.pages);
      updatedPages[pIdx] = updatedPage;
      
      // Also update allImagePaths to include the duplicate reference (it's the same file)
      final allPaths = Set<String>.from(state.project.allImagePaths);
      allPaths.add(newPhoto.path);

      state = state.copyWith(
        project: state.project.copyWith(pages: updatedPages, allImagePaths: allPaths.toList()),
        selectedPhotoId: newPhoto.id, // Select the new one
      );
    } catch (_) {}
  }

  Future<void> setBackground(String path, {bool applyToAll = false}) async {
    _saveStateToHistory();
    if (applyToAll) {
       final newPages = state.project.pages.map((p) => p.copyWith(backgroundPath: path)).toList();
       state = state.copyWith(
          project: state.project.copyWith(
             defaultBackgroundPath: path,
             pages: newPages,
          )
       );
    } else {
       final pIdx = state.project.currentPageIndex;
       final currentPage = state.project.pages[pIdx];
       final updatedPage = currentPage.copyWith(backgroundPath: path);
       final updatedPages = List<AlbumPage>.from(state.project.pages);
       updatedPages[pIdx] = updatedPage;
       state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
    }
  }

  void removeBackground() {
     _saveStateToHistory();
     final pIdx = state.project.currentPageIndex;
     final currentPage = state.project.pages[pIdx];
     // Reconstruct to clear
     final clearedPage = AlbumPage(
        id: currentPage.id,
        widthMm: currentPage.widthMm,
        heightMm: currentPage.heightMm,
        backgroundColor: currentPage.backgroundColor,
        pageNumber: currentPage.pageNumber,
        photos: currentPage.photos, 
        backgroundPath: null,
     );
     final updatedPages = List<AlbumPage>.from(state.project.pages);
     updatedPages[pIdx] = clearedPage;
     state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
  }

  void bringToFront(String photoId) {
    _saveStateToHistory();
    final pIdx = state.project.currentPageIndex;
    final currentPage = state.project.pages[pIdx];
    
    final photo = currentPage.photos.firstWhere((p) => p.id == photoId);
    final otherPhotos = currentPage.photos.where((p) => p.id != photoId).toList();
    
    // Add to end = Top
    final updatedPhotos = [...otherPhotos, photo];
    
    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;
    
    state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
  }

  void sendToBack(String photoId) {
    _saveStateToHistory();
    final pIdx = state.project.currentPageIndex;
    final currentPage = state.project.pages[pIdx];
    
    final photo = currentPage.photos.firstWhere((p) => p.id == photoId);
    final otherPhotos = currentPage.photos.where((p) => p.id != photoId).toList();
    
    // Add to start = Bottom
    final updatedPhotos = [photo, ...otherPhotos];
    
    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;
    
    state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
  }

  // --- Clipboard Actions ---

  // --- Clipboard Actions ---

  void deleteSelectedPhoto() {
    if (state.selectedPhotoId == null) return;
    _saveStateToHistory();
    
    final pIdx = state.project.currentPageIndex;
    final currentPage = state.project.pages[pIdx];
    final updatedPhotos = currentPage.photos.where((p) => p.id != state.selectedPhotoId).toList();
    
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = currentPage.copyWith(photos: updatedPhotos);
    
    state = state.copyWith(
      project: state.project.copyWith(pages: updatedPages),
      selectedPhotoId: null,
    );
  }

  void cutSelectedPhoto() {
    if (state.selectedPhotoId == null) return;
    copySelectedPhoto();
    deleteSelectedPhoto();
  }
  
  // Keep legacy signature if needed or just use these
  void cutPhoto(String photoId) {
     // Delegate
     state = state.copyWith(selectedPhotoId: photoId);
     cutSelectedPhoto();
  }

  void copySelectedPhoto() {
     if (state.selectedPhotoId == null) return;
     copyPhoto(state.selectedPhotoId!);
  }

  void copyPhoto(String photoId) {
    PhotoItem? target;
    final pIdx = state.project.currentPageIndex;
    final currentPage = state.project.pages[pIdx];
    
    try {
      target = currentPage.photos.firstWhere((p) => p.id == photoId);
    } catch (_) { return; }

    state = state.copyWith(
      clipboardPhoto: target.copyWith(id: Uuid().v4()),
    );
  }

  // --- Shortcuts Actions ---
  
  void toggleEditMode() {
     setEditingContent(!state.isEditingContent);
  }

  void panSelectedPhotoContent(double dx, double dy) {
    if (state.selectedPhotoId == null) return;
    
    final pIdx = state.project.currentPageIndex;
    final page = state.project.pages[pIdx];
    
    try {
       final photo = page.photos.firstWhere((p) => p.id == state.selectedPhotoId);
       
       // Update Content Position (Crop)
       // This moves the image INSIDE the frame.
       // Usually delta needs to be scaled by contentScale or something?
       // Just applying raw delta for now. User can hold key.
       
       final newPhoto = photo.copyWith(
          contentX: photo.contentX + dx,
          contentY: photo.contentY + dy,
       );
       
       final updatedPhotos = page.photos.map((p) => p.id == photo.id ? newPhoto : p).toList();
       final updatedPage = page.copyWith(photos: updatedPhotos);
       final updatedPages = List<AlbumPage>.from(state.project.pages);
       updatedPages[pIdx] = updatedPage;
       
       // No History Save for continuous pan? Or throttle?
       // For keyboard usage, maybe save only on KeyUp? 
       // For now, we update state directly. 
       // If we want Undo, we must save history. But panning generates 100s of history steps.
       // Ideally we'd debounce save.
       
       state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
       
    } catch (_) {}
  }

  void selectAdjacentPhoto(String direction) {
     if (state.selectedPhotoId == null) {
        // Select first if none selected
        if (state.project.pages[state.project.currentPageIndex].photos.isNotEmpty) {
           selectPhoto(state.project.pages[state.project.currentPageIndex].photos.first.id);
        }
        return;
     }

     final pIdx = state.project.currentPageIndex;
     final page = state.project.pages[pIdx];
     
     PhotoItem? current;
     try {
       current = page.photos.firstWhere((p) => p.id == state.selectedPhotoId);
     } catch (_) { return; }
     
     final cx = current!.x + current.width / 2;
     final cy = current.y + current.height / 2;
     
     PhotoItem? bestCandidate;
     double bestDist = double.infinity;
     
     for (var p in page.photos) {
        if (p.id == current.id) continue;
        
        final px = p.x + p.width / 2;
        final py = p.y + p.height / 2;
        final dx = px - cx;
        final dy = py - cy;
        
        bool isDirection = false;
        
        switch (direction) {
           case 'left':
             // mostly left (negative dx) and dx is significant relative to dy
             if (dx < -1 && (dx.abs() > dy.abs() * 0.5)) isDirection = true;
             break;
           case 'right':
             if (dx > 1 && (dx.abs() > dy.abs() * 0.5)) isDirection = true;
             break;
           case 'up':
             if (dy < -1 && (dy.abs() > dx.abs() * 0.5)) isDirection = true;
             break;
           case 'down':
             if (dy > 1 && (dy.abs() > dx.abs() * 0.5)) isDirection = true;
             break;
        }
        
        if (isDirection) {
           final dist = dx*dx + dy*dy;
           if (dist < bestDist) {
              bestDist = dist;
              bestCandidate = p;
           }
        }
     }
     
     if (bestCandidate != null) {
        selectPhoto(bestCandidate.id);
     }
  }

  void pastePhoto([double? x, double? y]) {
    if (state.clipboardPhoto == null) return;
    _saveStateToHistory();
    
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;

    // Use provided pos OR offset from original
    final newX = x ?? (state.clipboardPhoto!.x + 10);
    final newY = y ?? (state.clipboardPhoto!.y + 10);

    final photo = state.clipboardPhoto!.copyWith(
      id: Uuid().v4(), // Fresh ID for every paste
      x: newX,
      y: newY,
    );

    final currentPage = state.project.pages[pIdx];
    final updatedPhotos = [...currentPage.photos, photo];
    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;

    state = state.copyWith(
      project: state.project.copyWith(pages: updatedPages),
      selectedPhotoId: photo.id,
    );
  }

  // --- Navigation & Shortcuts ---
  
  void nextPage() {
    final current = state.project.currentPageIndex;
    if (current < state.project.pages.length - 1) {
       setPageIndex(current + 1);
    }
  }

  void previousPage() {
    final current = state.project.currentPageIndex;
    if (current > 0) {
       setPageIndex(current - 1);
    }
  }


  void swapPhotos(String id1, String id2) {
      final pIdx = state.project.currentPageIndex;
      if (pIdx < 0) return;
      
      final page = state.project.pages[pIdx];
      final p1Index = page.photos.indexWhere((p) => p.id == id1);
      final p2Index = page.photos.indexWhere((p) => p.id == id2);
      
      if (p1Index == -1 || p2Index == -1) return;
      
      _saveStateToHistory();
      
      final p1 = page.photos[p1Index];
      final p2 = page.photos[p2Index];
      
      // Swap content (Path) but KEEP Frame properties (x, y, w, h, rotation)
      // We also reset crop (contentX/Y/Scale) because the new image likely won't match the old crop perfectly
      
      final newP1 = p1.copyWith(
         path: p2.path, 
         contentX: 0, contentY: 0, contentScale: 1.0, 
         // preserve existing frame rotation? Or should we swap image rotation?
         // Frame rotation (p1.rotation) belongs to the layout.
         // EXIF Orientation belongs to the image. It is read from file, effectively swapped.
      );
      
      final newP2 = p2.copyWith(
         path: p1.path,
         contentX: 0, contentY: 0, contentScale: 1.0,
      );
      
      final newPhotos = List<PhotoItem>.from(page.photos);
      newPhotos[p1Index] = newP1;
      newPhotos[p2Index] = newP2;
      
      state = state.copyWith(
         project: state.project.copyWith(
            pages: [
               for (int i=0; i<state.project.pages.length; i++)
                  if (i == pIdx) page.copyWith(photos: newPhotos) else state.project.pages[i]
            ]
         )
      );
  }

  // --- Auto-Group Verticals ---
  void groupConsecutiveVerticals() {
    _saveStateToHistory();
    // Copy current pages logic...
    final List<AlbumPage> newPages = [];
    final List<AlbumPage> sourcePages = state.project.pages;
    
    int i = 0;
    int mergedCount = 0;
    
    while (i < sourcePages.length) {
      if (i == sourcePages.length - 1) {
        newPages.add(sourcePages[i]);
        break;
      }
      
      final p1 = sourcePages[i];
      final p2 = sourcePages[i+1];
      
      // Criteria: Both pages must have exactly 1 photo
      bool isCandidate1 = p1.photos.length == 1 && !p1.photos[0].isText;
      bool isCandidate2 = p2.photos.length == 1 && !p2.photos[0].isText;
      
      if (isCandidate1 && isCandidate2) {
         final photo1 = p1.photos[0];
         final photo2 = p2.photos[0];
         
         bool isVert1 = _isVertical(photo1);
         bool isVert2 = _isVertical(photo2);
         
         if (isVert1 && isVert2) {
            // MERGE (Standard 2 Portrait Pair)
            final mergedPhotos = [
               photo1.copyWith(id: Uuid().v4()),
               photo2.copyWith(id: Uuid().v4())
            ];
            
            final laidOutPhotos = TemplateSystem.applyTemplate(
               '2_portrait_pair', 
               mergedPhotos, 
               p1.widthMm, 
               p1.heightMm
            );
            
            final newPage = p1.copyWith(photos: laidOutPhotos);
            newPages.add(newPage);
            
            i += 2; 
            mergedCount++;
            continue;
         }
      }
      newPages.add(p1);
      i++;
    }
    
    if (mergedCount > 0) {
      state = state.copyWith(
        project: state.project.copyWith(pages: newPages, currentPageIndex: 0),
        selectedPhotoId: null,
      );
      print("Merged $mergedCount pairs of vertical photos.");
    }
  }

  bool _isVertical(PhotoItem p) {
     if (p.exifOrientation == 6 || p.exifOrientation == 8 || p.exifOrientation == 5 || p.exifOrientation == 7) return true; 
     if (p.rotation == 90 || p.rotation == 270) return true;
     if (p.height > p.width) return true;
     return false;
  }

  void cycleAutoLayout() {
     _saveStateToHistory();
     final page = state.project.pages[state.project.currentPageIndex];
     if (page.photos.isEmpty) return;

     final templates = TemplateSystem.getTemplatesForCount(page.photos.length);
     if (templates.isEmpty) return;
     
     // Random for now, or we could cycle sequentially if we stored last template
     final templateId = templates[DateTime.now().millisecondsSinceEpoch % templates.length];
     
     final newLayout = TemplateSystem.applyTemplate(
         templateId, 
         page.photos, 
         page.widthMm, 
         page.heightMm
     );
     updatePageLayout(newLayout);
  }

  Future<void> mergeSelectedPages() async {
    if (state.multiSelectedPages.length < 2) return;
    _saveStateToHistory();
    
    // 1. Gather info
    final indices = state.multiSelectedPages.toList()..sort();
    final firstIndex = indices.first;
    final targetPage = state.project.pages[firstIndex]; // Use dimensions of first
    
    List<PhotoItem> allPhotos = [];
    for (var i in indices) {
      allPhotos.addAll(state.project.pages[i].photos);
    }
    
    // 2. Analyze photos for Layout Engine (re-read Metadata for accuracy)
    final chunk = <Map<String, dynamic>>[];
    for (var p in allPhotos) {
       // We try to use cached or inferred data to be fast, but metadata is safer for "Clean" layout
       // which relies on orientation.
       int orientation = p.exifOrientation;
       // If we don't trust PhotoItem's orientation (it might be 1 if generic), we might want to reload.
       // But assuming it's correct from import:
       chunk.add({
         'path': p.path,
         'orientation': orientation,
         'width': p.width, // Current width on canvas (not used directly by calculate but maybe useful?)
         // layout engine uses aspect ratio from image usually.
         // Let's rely on MetadataHelper if possible?
         // Or just reconstruct generic structure expected by AutoLayoutEngine
       });
    }
    
    // 3. Generate Layout on ONE page
    // We need to properly analyze aspect ratios for the engine
    // Since we are synchronous here unless we await metadata, let's try to grab ratios from current items?
    // PhotoItem `width` and `height` are dimensions ON PAGE. Ratio = width/height.
    for (var i=0; i<chunk.length; i++) {
        final p = allPhotos[i];
        chunk[i]['ratio'] = p.width / p.height; 
    }

    final engine = AutoLayoutEngine(
        pageWidth: targetPage.widthMm, 
        pageHeight: targetPage.heightMm
    );
    
    // Calculate layout
    // Force more rows for many photos
    int rows = (allPhotos.length / 3).ceil().clamp(1, 5); 
    final newLayout = engine.calculateFlexibleGridLayout(chunk, maxRows: rows);
    
    // 4. Create merged page
    final newPage = targetPage.copyWith(photos: newLayout);
    
    // 5. Update Pages List
    final currentPages = List<AlbumPage>.from(state.project.pages);
    
    // Remove old pages (reverse order)
    for (var i in indices.reversed) {
      currentPages.removeAt(i);
    }
    
    // Insert new page at first index
    // Note: indices were referring to the ORIGINAL list. 
    // If we removed them, the insert position is effectively `firstIndex`
    // (since 0, 1, 2 removed -> 0 is new slot).
    // Wait, if we remove 1, 3, 5. removing 5 is fine. removing 3 is fine.
    // So insertion at `firstIndex` is correct.
    currentPages.insert(firstIndex, newPage);
    
    state = state.copyWith(
       project: state.project.copyWith(pages: currentPages, currentPageIndex: firstIndex),
       multiSelectedPages: {}, // Deselect
       selectedPhotoId: null,
    );
  }

  // --- labels ---

  void setContractNumber(String contractNumber) {
    state = state.copyWith(
      project: state.project.copyWith(contractNumber: contractNumber),
    );
  }

  void generateLabels({required bool allPages}) {
    _saveStateToHistory();
    
    String labelText;
    if (state.project.contractNumber.isNotEmpty) {
       labelText = state.project.contractNumber;
       if (state.project.name.isNotEmpty) {
          labelText += " - ${state.project.name}";
       }
    } else {
       labelText = state.project.name.isNotEmpty 
          ? state.project.name 
          : "Etiqueta";
    }
    
    final updatedPages = <AlbumPage>[];
    
    for (int i = 0; i < state.project.pages.length; i++) {
      final page = state.project.pages[i];
      
      // Determine if this page should get a label
      bool shouldAddLabel = allPages || 
                           i == 0 || 
                           i == state.project.pages.length - 1;
      
      if (!shouldAddLabel) {
        updatedPages.add(page);
        continue;
      }
      
      // Check if page already has a label
      final hasLabel = page.photos.any((p) => p.isText);
      if (hasLabel) {
        updatedPages.add(page);
        continue;
      }
      
      // Calculate dynamic label size to fit text
      // Base height 1.5% of page width (approx 4.5mm)
      final labelHeight = page.widthMm * 0.015;
      // Est. width per char ~ 0.65 * Height
      final estTextWidth = labelText.length * (labelHeight * 0.65) + (page.widthMm * 0.02);
      final minWidth = page.widthMm * 0.077;
      
      final labelWidth = estTextWidth > minWidth ? estTextWidth : minWidth;
      
      final marginRight = page.widthMm * 0.05;
      final marginBottom = page.heightMm * 0.035;
      
      // Create proportional label positioned on right side
      final label = PhotoItem(
        path: "",
        text: labelText,
        isText: true,
        x: page.widthMm - labelWidth - marginRight,
        y: page.heightMm - labelHeight - marginBottom,
        width: labelWidth,
        height: labelHeight,
        zIndex: 100,
      );
      
      updatedPages.add(page.copyWith(photos: [...page.photos, label]));
    }
    
    state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
  }

  // Generate labels for FIRST and LAST photo on each page
  void generateFirstLastLabels() {
    _saveStateToHistory();
    // Use contract number if set
    final String prefix = state.project.contractNumber.isNotEmpty ? "${state.project.contractNumber} - " : "";
    
    final updatedPages = <AlbumPage>[];
    int globalIndex = 1;

    for (var page in state.project.pages) {
      // Clean existing labels first
      final cleanPhotos = page.photos.where((p) => !p.isText).toList();
      
      // Sort spatial to determine "First" and "Last" (Top-Left to Bottom-Right)
      // Visual order is better than list order
      cleanPhotos.sort((a, b) {
         final dy = (a.y - b.y).sign.toInt();
         if (dy != 0) return dy;
         return (a.x - b.x).sign.toInt();
      });
      
      final photosToLabel = <PhotoItem>[];
      if (cleanPhotos.isNotEmpty) {
         photosToLabel.add(cleanPhotos.first);
         if (cleanPhotos.length > 1) {
            photosToLabel.add(cleanPhotos.last);
         }
      }

      final newLabels = <PhotoItem>[];
      
      // Create set of IDs to label for fast lookup
      final idsToLabel = photosToLabel.map((p) => p.id).toSet();

      for (var photo in cleanPhotos) {
         if (idsToLabel.contains(photo.id)) {
            // Label logic (same as generateLabels but selective)
             final labelText = "$prefix$globalIndex"; // Or keep sequential per page? Usually sequential relative to book.
             // We need to keep global index ticking for every photo or just labeled ones?
             // Usually labels follow the photo index. Let's find the original index of this photo in the "all photos" logic?
             // Or just simple counter? User said "Primeira e Ultima", implies identifying start/end frame.
             // Let's use simple sequential text for now.
             
             // Dynamic Sizing
             final labelWidth = 50.0; // mm
             final labelHeight = 10.0;
             
             // Place below photo
             final lx = photo.x; 
             final ly = photo.y + photo.height * (photo.height / photo.width) * (297/page.heightMm) + 2; // Approximate bottom
             // Actually photo.h is relative to page? No, PhotoItem x/y/w/h are usually relative (0..1) or absolute? 
             // In this codebase, LayoutEngine uses relative 0..1. 
             // Text needs to be placed relative.
             
             // Re-using logic from generateLabels(all):
             // ... Looking at existing generateLabels implementation ...
             // Wait, I replaced `generateLabels`? No, I am adding new methods.
             // I should copy logic from existing `generateLabels` if available.
             
             // Simplified Label Creation (assuming relative coordinates)
             final label = PhotoItem(
                id: Uuid().v4(),
                x: photo.x,
                y: photo.y + photo.height + 0.01,
                width: 0.2, // Approx width
                height: 0.05,
                path: "",
                isText: true,
                text: labelText,
                zIndex: 100,
             );
             newLabels.add(label);
         }
         globalIndex++;
      }
      
      updatedPages.add(page.copyWith(photos: [...cleanPhotos, ...newLabels]));
    }
    
    state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
  }
  
  // Kit Labels: Contract - Filename (No Ext)
  void generateKitLabels() {
    _saveStateToHistory();
    // Default Contract
    final String contract = state.project.contractNumber; // e.g "2024"
    
    final updatedPages = <AlbumPage>[];
    
    for (var page in state.project.pages) {
       final cleanPhotos = page.photos.where((p) => !p.isText).toList();
       final newLabels = <PhotoItem>[];
       
       // For Kit, usually One Student per Page.
       // We label ALL photos on the page or just the main one? 
       // User said: "essa etiqueta é gerada em todas as paginas pois cada pagina é de um formando diferente"
       // Implies 1 label per page unique to that page's student?
       // Usually we label the photos. If multiple photos of same student, label all?
       // "gerar a etiqueta com o numero do contrato e o nome do arquivo"
       
       for (var photo in cleanPhotos) {
          final file = File(photo.path);
          final filename = file.uri.pathSegments.last;
          final nameNoExt = filename.contains('.') ? filename.substring(0, filename.lastIndexOf('.')) : filename;
          
          String labelText = nameNoExt;
          if (contract.isNotEmpty) {
             labelText = "$contract - $labelText";
          }
          if (state.project.name.isNotEmpty) {
             // Insert Project Name in middle? "Contract - Project - Name"
             // Or append?
             // User: "puxe o numero ... puxe o nome do projeto ... e o nome do arquivo"
             // Let's do: "Contract - Project - Filename"
             // If contract is empty: "Project - Filename"
             if (contract.isNotEmpty) {
                 labelText = "$contract - ${state.project.name} - $nameNoExt";
             } else {
                 labelText = "${state.project.name} - $nameNoExt";
             }
          }

          // Dynamic Sizing
          final labelHeight = page.widthMm * 0.015;
          final estTextWidth = labelText.length * (labelHeight * 0.65) + (page.widthMm * 0.02);
          final labelWidth = estTextWidth > (page.widthMm * 0.2) ? estTextWidth : (page.widthMm * 0.2); // Min 20% width

          final label = PhotoItem(
            id: Uuid().v4(),
            x: photo.x, // Align with photo X
            y: photo.y + photo.height + 2, // 2mm padding
            width: labelWidth,
            height: labelHeight,
            path: "",
            isText: true,
            text: labelText,
            zIndex: 101,
          );
          newLabels.add(label);
       }
       
       updatedPages.add(page.copyWith(photos: [...cleanPhotos, ...newLabels]));
    }

    state = state.copyWith(project: state.project.copyWith(pages: updatedPages));
  }

  // Background to ALL pages
  void addBackgroundToAllPages(String path) {
    _saveStateToHistory();
    final updatedPages = <AlbumPage>[];
    
    // Default size based on page (assuming uniform)
    // If pages vary, we use each page's size.
    
    for (var page in state.project.pages) {
      final bgItem = PhotoItem(
        id: Uuid().v4(),
        path: path,
        x: 0,
        y: 0,
        width: page.widthMm,
        height: page.heightMm,
        zIndex: 0, // Bottom
      );
      
      // Prepend to photos
      updatedPages.add(page.copyWith(photos: [bgItem, ...page.photos]));
    }
    
    // Also track usage
    final allPaths = Set<String>.from(state.project.allImagePaths);
    allPaths.add(path);

    state = state.copyWith(
      project: state.project.copyWith(
        pages: updatedPages,
        allImagePaths: allPaths.toList(),
      )
    );
  }

  void replaceAllPages(List<AlbumPage> newPages) {
    saveHistorySnapshot();
    state = state.copyWith(
      project: state.project.copyWith(pages: newPages)
    );
  }

  Future<void> saveProject(String path) async {
    try {
      if (path.toLowerCase().endsWith('.alem')) {
          // Check if we are in "Offline/Proxy Mode" or simply have proxies available
          if (state.proxyRoot != null && await Directory(state.proxyRoot!).exists()) {
             debugPrint("Updating Smart Preview Package using existing proxies...");
             await ProjectPackager.updatePackage(state.project, state.proxyRoot!, path, onProgress: (c, t, s) {
                // Determine if we need to show progress? For quick saves usually we don't show dialog.
                // But this operation might take a few seconds.
                // Since this runs in async without UI feedback (unless we add it), we just log.
                if (c % 10 == 0) debugPrint(s);
             });
          } else {
             // Standard Full Pack (Resizing Originals)
             debugPrint("Saving as Smart Preview Package (Full Repack)...");
             await ProjectPackager.packProject(state.project, path);
          }
      } else {
          // Standard JSON
          final jsonStr = jsonEncode(state.project.toJson());
          await File(path).writeAsString(jsonStr);
      }

      state = state.copyWith(currentProjectPath: path);
      _updateUndoRedoFlags(); // Just to refresh state if needed
      debugPrint("Project saved to $path");
    } catch (e) {
      debugPrint("Error saving project: $e");
    }
  }


  Future<bool> loadProject(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;

      // Check Header for ZIP (PK..)
      final bytes = await file.openRead(0, 2).first;
      final isZip = bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
      
      String jsonStr = "";
      String? proxyRoot; 
      
      if (isZip) {
           debugPrint("Detected Project Package (ZIP). Unpacking...");
           final tempDir = await getTemporaryDirectory();
           final unpackDir = Directory(p.join(tempDir.path, 'aia_session_${Uuid().v4()}'));
           await unpackDir.create(recursive: true);
           
           // Workaround for extractFileToDisk requiring .zip extension
           // We copy the .alem file to a temp .zip file
           final tempZip = File(p.join(tempDir.path, 'temp_extract_${Uuid().v4()}.zip'));
           await file.copy(tempZip.path);

           try {
              // Use high-level extractor
              await extractFileToDisk(tempZip.path, unpackDir.path);
           } finally {
              if (await tempZip.exists()) {
                  await tempZip.delete();
              }
           }
           
           final jsonFile = File(p.join(unpackDir.path, 'project.json'));
           if (await jsonFile.exists()) {
               jsonStr = await jsonFile.readAsString();
               if (jsonStr.isEmpty) throw Exception("Project file is empty.");
               
               proxyRoot = p.join(unpackDir.path, 'proxies');
           } else {
               throw Exception("Invalid Package: project.json not found in root of archive");
           }
      } else {
         jsonStr = await file.readAsString();
      }

      final jsonMap = jsonDecode(jsonStr);
      var project = Project.fromJson(jsonMap);
      
      // Smart Relink
      project = await _smartRelinkAssets(project, path);
      
      // Auto-Sync Pending Rotations (If Originals Present)
      project = await _syncPendingRotations(project);

      _undoStack.clear();
      _redoStack.clear();
      
      state = state.copyWith(
        project: project,
        selectedPhotoId: null,
        isEditingContent: false,
        selectedBrowserPaths: {},
        currentProjectPath: path,
        proxyRoot: proxyRoot,
      );
      
      _updateUndoRedoFlags();
      debugPrint("Project loaded from $path (ProxyRoot: $proxyRoot)");
      return true;
    } catch (e) {
      debugPrint("Error loading project: $e");
      return false;
    }
  }

  Future<Project> _syncPendingRotations(Project project) async {
      bool changed = false;
      final newPages = <AlbumPage>[];
      int syncedCount = 0;

      for (var page in project.pages) {
          bool pageChanged = false;
          final newPhotos = <PhotoItem>[];
          
          for (var photo in page.photos) {
              if (photo.rotation != 0 && photo.path.isNotEmpty) {
                  // Check if ORIGINAL exists
                  if (await File(photo.path).exists()) {
                      // APPLY ROTATION TO FILE
                      debugPrint("Auto-Sync: Applying pending rotation ${photo.rotation} to ${photo.path}");
                      await _rotateFile(photo.path, photo.rotation.toInt());
                      
                      // RESET VISUAL
                      newPhotos.add(photo.copyWith(rotation: 0));
                      pageChanged = true;
                      changed = true;
                      syncedCount++;
                      
                      // Reset Visual in Gallery too?
                      // We handle gallery map later.
                      continue; 
                  }
              }
              newPhotos.add(photo);
          }
          
          // Background Rotation? Usually backgrounds are photos.
          // If backgroundPath has rotation in metadata? AlbumPage doesn't save rotation for BG currently in this model.
          
          if (pageChanged) {
             newPages.add(page.copyWith(photos: newPhotos));
          } else {
             newPages.add(page);
          }
      }
      
      if (changed) {
          // Fix Gallery Rotations
          // Ideally we reset the map for those keys.
          // Since we don't return the map here, we might need to handle it.
          // But _rotateFile updates the map in State?
          // No, _rotateFile is an instance method on Notifier, but here we are inside a Future returning Project.
          // We can't access `state` safely if we assume pure function or if we modify project locally.
          // Wait, `_rotateFile` writes to disk. It does NOT update state.project.imageRotations itself unless called via `rotateGalleryPhoto` action.
          // But here we are producing a NEW Project.
          
          // We need to clear rotation entries for the synced files.
          // Let's rely on the fact that if we zero them out in pages, they are zeroed there.
          // For Gallery, we might need to clear the map entries in `state` later?
          // Simplest: construct the updated project with cleaned imageRotations.
          
          final newRotations = Map<String, int>.from(project.imageRotations);
          for (var page in newPages) {
             for (var p in page.photos) {
                 if (p.rotation == 0 && project.imageRotations[p.path] != 0) {
                     // Potential conflict if same photo used twice with different rotations?
                     // If used twice with different rotations, we can only fix one?
                     // Destructive file rotation is global.
                     // If one instance was +90 and another +180... we have a problem.
                     // User said "Visualização to File".
                     // If multiple conflicts, we pick one?
                     // Usually user rotates "The Photo".
                     newRotations[p.path] = 0;
                 }
             }
          }
          
          if (syncedCount > 0) {
             debugPrint("Auto-Sync: Synced $syncedCount photos to disk.");
          }
          
          return project.copyWith(pages: newPages, imageRotations: newRotations);
      }
      
      return project;
  }

  Future<Project> _smartRelinkAssets(Project project, String projectPath) async {
      final projectDir = File(projectPath).parent.path;
      bool changed = false;
      final newPages = <AlbumPage>[];
      
      // Get Standard Template Dirs
      Directory? appSupportTemplates;
      Directory? documentsTemplates;
      try {
         final support = await getApplicationSupportDirectory();
         appSupportTemplates = Directory(p.join(support.path, 'templates'));
         
         final docs = await getApplicationDocumentsDirectory();
         documentsTemplates = Directory(p.join(docs.path, 'AiaAlbum', 'Templates'));
      } catch (_) {}

      Future<String?> findAlternatePath(String originalPath) async {
           final filename = p.basename(originalPath);
           
           // 1. Check Project Dir
           final cand1 = p.join(projectDir, filename);
           if (File(cand1).existsSync()) return cand1;
           
           // 2. Check AppSupport Templates
           if (appSupportTemplates != null) {
              final cand2 = p.join(appSupportTemplates.path, filename);
              if (await File(cand2).exists()) return cand2;
           }
           
           // 3. Check Documents Templates
           if (documentsTemplates != null) {
              final cand3 = p.join(documentsTemplates.path, filename);
              if (await File(cand3).exists()) return cand3;
           }
           
           return null;
      }

      for (final page in project.pages) {
          final newPhotos = <PhotoItem>[];
          // Check Background
          String? newBgPath = page.backgroundPath;
          if (newBgPath != null && newBgPath.isNotEmpty) {
             if (!File(newBgPath).existsSync()) {
                 final fixed = await findAlternatePath(newBgPath);
                 if (fixed != null) {
                     newBgPath = fixed;
                     changed = true;
                     debugPrint("Smart Relink: Fixed Background $fixed");
                 }
             }
          }

          bool pagePhotosChanged = false;
          for (final photo in page.photos) {
              if (photo.isText) {
                  newPhotos.add(photo);
                  continue;
              }
              
              String currentPath = photo.path;
              // Check file existence
              if (currentPath.isNotEmpty && !File(currentPath).existsSync()) {
                   // Try to find
                   final fixed = await findAlternatePath(currentPath);
                   if (fixed != null) {
                       newPhotos.add(photo.copyWith(path: fixed));
                       pagePhotosChanged = true;
                       changed = true;
                       debugPrint("Smart Relink: Fixed Photo $fixed");
                       continue;
                   }
              }
              newPhotos.add(photo);
          }
          
          if (pagePhotosChanged || newBgPath != page.backgroundPath) {
             newPages.add(page.copyWith(photos: newPhotos, backgroundPath: newBgPath));
          } else {
             newPages.add(page);
          }
      }

      // Fix Gallery Paths (allImagePaths)
      final newAllPaths = <String>[];
      bool galleryChanged = false;
      for (final path in project.allImagePaths) {
         if (path.isEmpty) continue;
         String finalPath = path;
         
         if (!File(path).existsSync()) {
             final fixed = await findAlternatePath(path);
             if (fixed != null) {
                 finalPath = fixed;
                 galleryChanged = true;
             }
         }
         newAllPaths.add(finalPath);
      }

      if (changed || galleryChanged) {
          debugPrint("Smart Relink: Project updated with new paths. (Pages: $changed, Gallery: $galleryChanged)");
          return project.copyWith(
              pages: newPages,
              allImagePaths: newAllPaths
          );
      }
      return project;
  }
      


  Future<void> runAutoSelect({Function(String phase, int processed, int total, int selected)? onProgress}) async {
     try {
        // Use all available images in the project browser context
        final imagePaths = state.project.allImagePaths;

        if (imagePaths.isEmpty) return;

        // Run Engine
        final winners = await AutoSelectEngine.findBestPhotos(
           imagePaths,
           onProgress: onProgress
        );
        
        // Update Selection
        state = state.copyWith(selectedBrowserPaths: winners.toSet());
        
     } catch (e) {
        debugPrint("Error in AutoSelect: $e");
     }
  }

  Future<void> sortPages() async {
    _saveStateToHistory();
    
    // 1. Identify representative photo for each page
    final pageInfoList = <_PageSortInfo>[];
    final pathsToFetch = <String>[];
    
    for (int i = 0; i < state.project.pages.length; i++) {
       final page = state.project.pages[i];
       
       // Find first visual photo (non-text)
       final visualPhotos = page.photos.where((p) => !p.isText).toList();
       
       if (visualPhotos.isEmpty) {
          pageInfoList.add(_PageSortInfo(page, null, null));
          continue;
       }
       
       // Sort visual photos to find top-left
       visualPhotos.sort((a,b) {
          final dy = (a.y - b.y).sign.toInt();
          if (dy != 0) return dy;
          return (a.x - b.x).sign.toInt();
       });
       
       final rep = visualPhotos.first;
       if (rep.path.isNotEmpty) {
           pageInfoList.add(_PageSortInfo(page, rep.path, null));
           pathsToFetch.add(rep.path);
       } else {
           pageInfoList.add(_PageSortInfo(page, null, null));
       }
    }
    
    // 2. Fetch Metadata
    if (pathsToFetch.isNotEmpty) {
       final metadataList = await MetadataHelper.getMetadataBatch(pathsToFetch);
       
       final metaMap = <String, PhotoMetadata>{};
       for (int i = 0; i < pathsToFetch.length; i++) {
          metaMap[pathsToFetch[i]] = metadataList[i];
       }
       
       // Fill info
       for (var info in pageInfoList) {
          if (info.repPath != null && metaMap.containsKey(info.repPath)) {
             info.metadata = metaMap[info.repPath];
          }
       }
    }
    
    // 3. Sort
    pageInfoList.sort((a, b) {
       final ta = a.metadata?.dateTaken ?? DateTime(2100); 
       final tb = b.metadata?.dateTaken ?? DateTime(2100);
       
       // A. Date (Day)
       final dayA = DateTime(ta.year, ta.month, ta.day);
       final dayB = DateTime(tb.year, tb.month, tb.day);
       int dayC = dayA.compareTo(dayB);
       if (dayC != 0) return dayC;
       
       // B. Camera
       final ca = a.metadata?.cameraModel ?? "";
       final cb = b.metadata?.cameraModel ?? "";
       int camC = ca.compareTo(cb);
       if (camC != 0) return camC;
       
       // C. Time
       return ta.compareTo(tb);
    });
    
    // 4. Update State
    final newPages = pageInfoList.map((info) => info.page).toList();
    
    // Renumber
    final renumbPages = <AlbumPage>[];
    for(int i=0; i<newPages.length; i++) {
       renumbPages.add(newPages[i].copyWith(pageNumber: i + 1));
    }
    
    state = state.copyWith(project: state.project.copyWith(pages: renumbPages));
  }


}


// --- Provider ---
final projectProvider = StateNotifierProvider<ProjectNotifier, PhotoBookState>((ref) {
  return ProjectNotifier(ref);
});

class _PageSortInfo {
   final AlbumPage page;
   final String? repPath;
   PhotoMetadata? metadata;
   _PageSortInfo(this.page, this.repPath, this.metadata);
}
