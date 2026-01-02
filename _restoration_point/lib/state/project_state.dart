import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/project_model.dart';

// --- State Definition ---
class PhotoBookState {
  final Project project;
  final bool canUndo;
  final bool canRedo;
  final String? selectedPhotoId;
  final bool isEditingContent;

  PhotoBookState({
    required this.project,
    this.canUndo = false,
    this.canRedo = false,
    this.selectedPhotoId,
    this.isEditingContent = false,
  });

  PhotoBookState copyWith({
    Project? project,
    bool? canUndo,
    bool? canRedo,
    String? selectedPhotoId,
    bool isEditingContent = false,
  }) {
    return PhotoBookState(
      project: project ?? this.project,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      selectedPhotoId: selectedPhotoId, // Nullable override needs care, simplify for now
      isEditingContent: isEditingContent,
    );
  }
}

// --- Notifier with Undo/Redo Logic ---
class ProjectNotifier extends StateNotifier<PhotoBookState> {
  // ...
  
  void setEditingContent(bool isEditing) {
     if (state.isEditingContent == isEditing) return;
     state = state.copyWith(isEditingContent: isEditing);
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
    state = state.copyWith(selectedPhotoId: photoId);
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
    _saveStateToHistory();
    // Logic: Locate current page, add photo.
    final pIdx = state.project.currentPageIndex;
    if (pIdx < 0 || pIdx >= state.project.pages.length) return;

    final currentPage = state.project.pages[pIdx];
    final updatedPhotos = [...currentPage.photos, photo];
    final updatedPage = currentPage.copyWith(photos: updatedPhotos);
    
    final updatedPages = List<AlbumPage>.from(state.project.pages);
    updatedPages[pIdx] = updatedPage;

    // Also track allImagePaths
    final allPaths = Set<String>.from(state.project.allImagePaths);
    allPaths.add(photo.path);

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
}

// --- Provider ---
final projectProvider = StateNotifierProvider<ProjectNotifier, PhotoBookState>((ref) {
  return ProjectNotifier();
});
