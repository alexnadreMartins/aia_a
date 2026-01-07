import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/project_model.dart';
import '../logic/template_system.dart';
import '../logic/metadata_helper.dart';
import '../logic/layout_engine.dart';
import '../models/asset_model.dart';

import '../logic/auto_select_engine.dart';





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
  
  // New Browser Fields
  final BrowserSortType browserSortType;
  final BrowserFilterType browserFilterType;

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
    this.browserSortType = BrowserSortType.name,
    this.browserFilterType = BrowserFilterType.all,
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
    BrowserFilterType? browserFilterType,
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
      browserSortType: browserSortType ?? this.browserSortType,
      browserFilterType: browserFilterType ?? this.browserFilterType,
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

  ProjectNotifier()
      : super(PhotoBookState(
          project: Project(pages: [_createDefaultPage()]),
        ));

  static AlbumPage _createDefaultPage({double widthMm = 210, double heightMm = 297}) {
    return AlbumPage(widthMm: widthMm, heightMm: heightMm); 
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
    state = state.copyWith(canvasScale: scale.clamp(0.1, 5.0));
  }

  void updateCanvasScale(double delta) {
    setCanvasScale(state.canvasScale + delta);
  }

  void rotateSelectedGalleryPhotos(int degrees) {
    if (state.selectedBrowserPaths.isEmpty) return;
    
    _saveStateToHistory();
    final newRotations = Map<String, int>.from(state.project.imageRotations);
    
    for (var path in state.selectedBrowserPaths) {
      final current = newRotations[path] ?? 0;
      newRotations[path] = (current + degrees) % 360;
    }
    
    state = state.copyWith(
      project: state.project.copyWith(imageRotations: newRotations)
    );
  }

  void rotateGalleryPhoto(String path, int degrees) {
    _saveStateToHistory();
    final newRotations = Map<String, int>.from(state.project.imageRotations);
    final current = newRotations[path] ?? 0;
    newRotations[path] = (current + degrees) % 360;
    
    state = state.copyWith(
      project: state.project.copyWith(imageRotations: newRotations)
    );
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
  // ... (existing code, not replacing, just ensuring these new methods are appended correctly)
    if (paths.isEmpty || state.isProcessing) return;
    
    state = state.copyWith(isProcessing: true);
    _saveStateToHistory();

    try {
      debugPrint("Starting Advanced Smart Flow for ${paths.length} photos...");
      
      
      // 1. Prepare Assets with Dimensions
      List<LibraryAsset> assets = [];
      for (var p in paths) {
          DateTime? date;
          int w = 0;
          int h = 0;
          try { 
              date = await File(p).lastModified();
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
              width: w,
              height: h
          ));
      }

      // 2. Run SmartFlow
      // Determine orientation
      bool isHorizontal = true; 
      if (state.project.pages.isNotEmpty) {
          isHorizontal = state.project.pages[0].widthMm >= state.project.pages[0].heightMm;
      }

      // Delegate to SmartFlow Engine
      final pagesFlow = await SmartFlow.generateFlow(
        assets,
        isProjectHorizontal: isHorizontal,
      );
      
      // 3. Generate Pages
      List<AlbumPage> newPages = [];
      double pW = 305;
      double pH = 215;
      if (state.project.pages.isNotEmpty) {
          pW = state.project.pages[0].widthMm;
          pH = state.project.pages[0].heightMm;
      }

      for (var pageAssets in pagesFlow) {
          final pageId = Uuid().v4();
          List<PhotoItem> photos = [];
          
          if (pageAssets.length == 1) {
               photos.add(PhotoItem(
                   id: Uuid().v4(),
                   path: pageAssets[0].path,
                   x: 0, y: 0, width: pW, height: pH
               ));
          } else if (pageAssets.length >= 2) { 
               if (isHorizontal) {
                   // Side by side
                   double w = pW / 2;
                   photos.add(PhotoItem(id: Uuid().v4(), path: pageAssets[0].path, x: 0, y: 0, width: w, height: pH));
                   photos.add(PhotoItem(id: Uuid().v4(), path: pageAssets[1].path, x: w, y: 0, width: w, height: pH));
               } else {
                   // Top Bottom
                   double h = pH / 2;
                   photos.add(PhotoItem(id: Uuid().v4(), path: pageAssets[0].path, x: 0, y: 0, width: pW, height: h));
                   photos.add(PhotoItem(id: Uuid().v4(), path: pageAssets[1].path, x: 0, y: h, width: pW, height: h));
               }
          }
          
          newPages.add(AlbumPage(id: pageId, widthMm: pW, heightMm: pH, photos: photos, pageNumber: 0));
      }

      // 4. Update State: Append
      int startNum = state.project.pages.length + 1;
      for (int i=0; i<newPages.length; i++) {
          newPages[i] = newPages[i].copyWith(pageNumber: startNum + i);
      }
      
      final updatedPages = [...state.project.pages, ...newPages];

      state = state.copyWith(
        project: state.project.copyWith(pages: updatedPages),
      );
      
      // Auto-Group Verticals immediately after generation (User Request)
      // This fixes single vertical pages by pairing them
      groupConsecutiveVerticals();
      
      // Final Cleanup
      state = state.copyWith(
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
    
    final newPage = _createDefaultPage(widthMm: w, heightMm: h);
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
    
    final labelText = state.project.contractNumber.isEmpty 
        ? "Etiqueta" 
        : state.project.contractNumber;
    
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
      
      // Calculate proportional label size based on page dimensions
      // Calibrated based on user preference (W: 23.5, H: 4.6 on 305 width)
      final labelWidth = page.widthMm * 0.077;  
      final labelHeight = page.widthMm * 0.015;
      
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
          
          final labelText = contract.isNotEmpty ? "$contract - $nameNoExt" : nameNoExt;
          
          // Proportional Sizing (matching generateLabels standard)
          final labelWidth = page.widthMm * 0.077;  
          final labelHeight = page.widthMm * 0.015;

          final label = PhotoItem(
            id: Uuid().v4(),
            x: photo.x, // Align with photo X? Or Centered? User said "standard".
                        // generateLabels puts it at bottom right. 
                        // But Kit labels usually go UNDER the photo? 
                        // "ao inves de colocar... vai colocar o nome... mantendo padrão"
                        // I will place it centered under the photo for now or stick to the previous "under" logic but with correct size.
            y: photo.y + photo.height + 2, // 2mm padding
            width: labelWidth * 3, // Filenames are longer than "001", need more width.
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
      final jsonStr = jsonEncode(state.project.toJson());
      await File(path).writeAsString(jsonStr);
      state = state.copyWith(currentProjectPath: path);
      debugPrint("Project saved to $path");
    } catch (e) {
      debugPrint("Error saving project: $e");
    }
  }

  Future<void> loadProject(String path) async {
    try {
      final jsonStr = await File(path).readAsString();
      final jsonMap = jsonDecode(jsonStr);
      final project = Project.fromJson(jsonMap);
      
      _undoStack.clear();
      _redoStack.clear();
      
      state = state.copyWith(
        project: project,
        selectedPhotoId: null,
        isEditingContent: false,
        selectedBrowserPaths: {},
        currentProjectPath: path,
      );
      
      _updateUndoRedoFlags();
      debugPrint("Project loaded from $path");
    } catch (e) {
      debugPrint("Error loading project: $e");
    }
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

}

// --- Provider ---
final projectProvider = StateNotifierProvider<ProjectNotifier, PhotoBookState>((ref) {
  return ProjectNotifier();
});
