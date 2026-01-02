import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/project_model.dart';
import '../logic/template_system.dart';
import '../logic/metadata_helper.dart';
import '../logic/layout_engine.dart';

// --- State Definition ---
class PhotoBookState {
  final Project project;
  final bool canUndo;
  final bool canRedo;
  final String? selectedPhotoId;
  final bool isEditingContent;
  final Set<String> selectedBrowserPaths;
  final bool isProcessing;
  final bool isExporting; // NEW: Flag to hide UI elements during export
  final PhotoItem? clipboardPhoto;
  final double canvasScale;
  final String? currentProjectPath;

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

  Future<void> applyAutoLayout(List<String> paths) async {
    if (paths.isEmpty || state.isProcessing) return;
    
    state = state.copyWith(isProcessing: true);
    _saveStateToHistory();

    try {
      debugPrint("Starting Advanced Event Layout for ${paths.length} photos...");

      // 1. Fetch Metadata for all photos
      final metas = await MetadataHelper.getMetadataBatch(paths);
      final List<MapEntry<String, PhotoMetadata>> pathMeta = [];
      for (int i = 0; i < paths.length && i < metas.length; i++) {
        pathMeta.add(MapEntry(paths[i], metas[i]));
      }

      // 1.5 Apply manual rotation overrides & Calculate Ratios for Layout Engine
      final Map<String, int> overrides = state.project.imageRotations;
      final List<Map<String, dynamic>> photosWithRatios = [];

      for (int i = 0; i < pathMeta.length; i++) {
        final entry = pathMeta[i];
        final rotation = overrides[entry.key] ?? 0;
        final oldMeta = entry.value;
        
        bool isPortrait = oldMeta.isPortrait;
        if (rotation == 90 || rotation == 270) {
          isPortrait = !isPortrait;
        }
        
        // Logical Ratio (Width / Height)
        double ratio = isPortrait ? 0.66 : 1.5; 
        // We could get exact pixel dimensions if MetadataHelper provided it, 
        // for now we use common ratios which is safer than hardcoding 1.0.

        photosWithRatios.add({
          'path': entry.key,
          'ratio': ratio,
          'orientation': oldMeta.orientation,
          'date': oldMeta.dateTaken ?? DateTime(1970),
        });
      }

      // 2. Sort by date
      photosWithRatios.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

      final updatedPages = List<AlbumPage>.from(state.project.pages);
      
      if (updatedPages.length > 1) {
        // --- SMART ALLOCATION (Distribute into existing pages) ---
        int photoCount = photosWithRatios.length;
        int pageCount = updatedPages.length;
        int itemsPerPage = (photoCount / pageCount).ceil();
        
        final engine = AutoLayoutEngine(
          pageWidth: updatedPages[0].widthMm,
          pageHeight: updatedPages[0].heightMm,
          margin: 15, // Slightly larger margin for premium look
        );

        for (int i = 0; i < pageCount; i++) {
          int start = i * itemsPerPage;
          if (start >= photosWithRatios.length) break;
          int end = (start + itemsPerPage) < photosWithRatios.length ? (start + itemsPerPage) : photosWithRatios.length;
          
          final pagePhotos = photosWithRatios.sublist(start, end);
          final newLayout = engine.calculateFlexibleGridLayout(pagePhotos);
          updatedPages[i] = updatedPages[i].copyWith(photos: newLayout);
        }
      } else {
        // --- AUTO-GROWTH (Opening -> Individual -> Pairs) ---
        // This is the logic the user requested previously for "single page" start
        int startPageIndex = 0;
        
        // Group by day for the growth logic
        final Map<String, List<Map<String, dynamic>>> days = {};
        for (var p in photosWithRatios) {
          final dt = p['date'] as DateTime;
          final dayKey = "${dt.year}-${dt.month}-${dt.day}";
          days.putIfAbsent(dayKey, () => []).add(p);
        }

        final dayKeys = days.keys.toList()..sort();
        final engine = AutoLayoutEngine(
          pageWidth: updatedPages[0].widthMm,
          pageHeight: updatedPages[0].heightMm,
          margin: 10,
        );

        for (var dayKey in dayKeys) {
          final dayPhotos = days[dayKey]!;
          
          bool dayOpeningDone = false;
          int i = 0;
          
          while (i < dayPhotos.length) {
            final p1 = dayPhotos[i];
            final p1Ratio = p1['ratio'] as double;
            final isP1Portrait = p1Ratio < 0.9;
            final isLandscapeAlbum = updatedPages[0].widthMm > updatedPages[0].heightMm;

            // Rule 1: FIRST PORTRAIT OF THE DAY = EVENT OPENING (Right Side)
            if (!dayOpeningDone && isP1Portrait) {
              _applyLayoutByEngine(updatedPages, [p1], engine, startPageIndex++, forceEventOpening: true);
              dayOpeningDone = true;
              i += 1;
              continue;
            }

            if (i + 1 < dayPhotos.length) {
              final p2 = dayPhotos[i + 1];
              final p2Ratio = p2['ratio'] as double;
              final isP2Portrait = p2Ratio < 0.9;

              // Rule 2: NEVER MIX ORIENTATIONS
              if (isP1Portrait == isP2Portrait) {
                // Same orientation, can group
                if (isP1Portrait) {
                  // Pair of vertical
                  _applyLayoutByEngine(updatedPages, [p1, p2], engine, startPageIndex++, forceVerticalSplit: true);
                } else {
                  // Pair of horizontal
                  _applyLayoutByEngine(updatedPages, [p1, p2], engine, startPageIndex++);
                }
                i += 2;
              } else {
                // Mixed orientations! Must split to separate pages
                // Process p1 solo
                if (p1Ratio > 1.2 && isLandscapeAlbum) {
                   _applyLayoutByEngine(updatedPages, [p1], engine, startPageIndex++);
                } else {
                   _applyLayoutByEngine(updatedPages, [p1], engine, startPageIndex++);
                }
                i += 1;
                // p2 will be handled in next iteration
              }
            } else {
              // Solo remaining
              if (p1Ratio > 1.2 && isLandscapeAlbum) {
                 _applyLayoutByEngine(updatedPages, [p1], engine, startPageIndex++);
              } else {
                 _applyLayoutByEngine(updatedPages, [p1], engine, startPageIndex++);
              }
              i += 1;
            }
          }
        }
      }

      state = state.copyWith(
        project: state.project.copyWith(pages: updatedPages),
        selectedBrowserPaths: {},
        isProcessing: false,
      );
    } catch (e, stack) {
      debugPrint("Error in AI Auto Layout: $e \n $stack");
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
         id: const Uuid().v4(),
         path: p['path'] as String,
         exifOrientation: p['orientation'] ?? 1,
       )).toList(), pages[index].widthMm, pages[index].heightMm);
    } else if (forceVerticalSplit && chunk.length == 2) {
       newLayout = TemplateSystem.applyTemplate('2_full_vertical_split', chunk.map((p) => PhotoItem(
         id: const Uuid().v4(),
         path: p['path'] as String,
         exifOrientation: p['orientation'] ?? 1,
       )).toList(), pages[index].widthMm, pages[index].heightMm);
    } else if (chunk.length == 1 && (chunk[0]['ratio'] as double) > 1.2) {
       // Large Solo for landscape
       newLayout = TemplateSystem.applyTemplate('1_solo_horizontal_large', chunk.map((p) => PhotoItem(
         id: const Uuid().v4(),
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

  void reorderPage(int oldIndex, int newIndex) {
    _saveStateToHistory();
    final pages = List<AlbumPage>.from(state.project.pages);
    
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final page = pages.removeAt(oldIndex);
    pages.insert(newIndex, page);
    
    // Adjust current index if it was moved
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
         id: const Uuid().v4(),
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

  void cutPhoto(String photoId) {
    _saveStateToHistory();
    PhotoItem? target;
    final pIdx = state.project.currentPageIndex;
    final currentPage = state.project.pages[pIdx];
    
    try {
      target = currentPage.photos.firstWhere((p) => p.id == photoId);
    } catch (_) { return; }

    final updatedPhotos = currentPage.photos.where((p) => p.id != photoId).toList();
    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;

    state = state.copyWith(
      project: state.project.copyWith(pages: updatedPages),
      selectedPhotoId: null,
      clipboardPhoto: target.copyWith(id: const Uuid().v4()), // New ID for pasted instance
    );
  }

  void copyPhoto(String photoId) {
    PhotoItem? target;
    final pIdx = state.project.currentPageIndex;
    final currentPage = state.project.pages[pIdx];
    
    try {
      target = currentPage.photos.firstWhere((p) => p.id == photoId);
    } catch (_) { return; }

    state = state.copyWith(
      clipboardPhoto: target.copyWith(id: const Uuid().v4()),
    );
  }

  void pastePhoto(double? x, double? y) {
    if (state.clipboardPhoto == null) return;
    _saveStateToHistory();
    
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;

    final photo = state.clipboardPhoto!.copyWith(
      id: const Uuid().v4(), // Fresh ID for every paste
      x: x ?? 50,
      y: y ?? 50,
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
      // Reference: 20cm height x 30cm width page uses 2.5cm x 1cm label
      // Proportions: width = 12.5% of page width (2.5/20), height = 5% of page width (1/20)
      final labelWidth = page.widthMm * 0.125;  // 12.5% of page width
      final labelHeight = page.widthMm * 0.05;  // 5% of page width (maintains aspect ratio)
      final margin = page.widthMm * 0.075;      // 7.5% margin (1.5cm for 20cm page)
      
      // Create proportional label positioned on right side
      final label = PhotoItem(
        path: "",
        text: labelText,
        isText: true,
        x: page.widthMm - margin - labelWidth,
        y: page.heightMm - margin - labelHeight,
        width: labelWidth,
        height: labelHeight,
        zIndex: 100, // Always on top
      );
      
      updatedPages.add(page.copyWith(
        photos: [...page.photos, label],
      ));
    }
    
    state = state.copyWith(
      project: state.project.copyWith(pages: updatedPages),
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
}

// --- Provider ---
final projectProvider = StateNotifierProvider<ProjectNotifier, PhotoBookState>((ref) {
  return ProjectNotifier();
});
