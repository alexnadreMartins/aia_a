import 'package:uuid/uuid.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../models/asset_model.dart';

class AssetLibraryState {
  final List<AssetCollection> collections;
  final bool isLoading;
  final Set<String> selectedAssetIds;

  AssetLibraryState({
    this.collections = const [],
    this.isLoading = false,
    this.selectedAssetIds = const {},
  });

  AssetLibraryState copyWith({
    List<AssetCollection>? collections,
    bool? isLoading,
    Set<String>? selectedAssetIds,
  }) => AssetLibraryState(
    collections: collections ?? this.collections,
    isLoading: isLoading ?? this.isLoading,
    selectedAssetIds: selectedAssetIds ?? this.selectedAssetIds,
  );
}

class AssetNotifier extends StateNotifier<AssetLibraryState> {
  AssetNotifier() : super(AssetLibraryState(isLoading: true)) {
    loadLibrary();
  }
  
  // Storage logic
  Future<File> _getStorageFile() async {
    final dir = await getApplicationSupportDirectory();
    final assetDir = Directory('${dir.path}/assets');
    if (!await assetDir.exists()) {
      await assetDir.create(recursive: true);
    }
    return File('${assetDir.path}/library_v1.json');
  }

  Future<void> loadLibrary() async {
    try {
      final file = await _getStorageFile();
      if (!await file.exists()) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final contents = await file.readAsString();
      final List<dynamic> json = jsonDecode(contents);
      final collections = json.map((c) => AssetCollection.fromJson(c)).toList();
      state = state.copyWith(collections: collections, isLoading: false);
    } catch (e) {
      debugPrint("Error loading asset library: $e");
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _saveLibrary() async {
    try {
      final file = await _getStorageFile();
      final json = state.collections.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint("Error saving asset library: $e");
    }
  }

  // Selection Logic
  void toggleSelection(String assetId) {
    final current = Set<String>.from(state.selectedAssetIds);
    if (current.contains(assetId)) {
      current.remove(assetId);
    } else {
      current.add(assetId);
    }
    state = state.copyWith(selectedAssetIds: current);
  }

  void selectSingle(String assetId) {
    state = state.copyWith(selectedAssetIds: {assetId});
  }

  void selectAll() {
    final allIds = state.collections.expand((c) => c.assets).map((a) => a.id).toSet();
    state = state.copyWith(selectedAssetIds: allIds);
  }

  void deselectAll() {
    state = state.copyWith(selectedAssetIds: {});
  }

  void selectRange(String fromId, String toId) {
    // Flatten all assets to find range
    final allAssets = state.collections.expand((c) => c.assets).toList();
    final fromIndex = allAssets.indexWhere((a) => a.id == fromId);
    final toIndex = allAssets.indexWhere((a) => a.id == toId);

    if (fromIndex == -1 || toIndex == -1) return;

    final start = fromIndex < toIndex ? fromIndex : toIndex;
    final end = fromIndex < toIndex ? toIndex : fromIndex;

    final rangeIds = allAssets.sublist(start, end + 1).map((a) => a.id).toSet();
    final current = Set<String>.from(state.selectedAssetIds);
    current.addAll(rangeIds);
    
    state = state.copyWith(selectedAssetIds: current);
  }

  // Collection Management
  void addCollection(String name) {
    state = state.copyWith(
      collections: [...state.collections, AssetCollection(name: name)],
    );
    _saveLibrary();
  }

  void removeCollection(String id) {
    state = state.copyWith(
      collections: state.collections.where((c) => c.id != id).toList(),
    );
    _saveLibrary();
  }

  Future<void> addAssetsToCollection(String collectionId, List<String> paths, AssetType type) async {
    state = state.copyWith(isLoading: true);
    
    final List<LibraryAsset> newAssets = [];
    for (var p in paths) {
      final name = p.split(Platform.pathSeparator).last;
      
      // Get File Date
      DateTime? fDate;
      try {
        fDate = await File(p).lastModified();
      } catch (e) {
        debugPrint("Error reading date for $p: $e");
      }

      double? hX, hY, hW, hH;
      if (type == AssetType.template) {
        final hole = await _detectHole(p);
        if (hole != null) {
          hX = hole.left;
          hY = hole.top;
          hW = hole.width;
          hH = hole.height;
        }
      }

      newAssets.add(LibraryAsset(
        path: p,
        name: name,
        type: type,
        holeX: hX,
        holeY: hY,
        holeW: hW,
        holeH: hH,
        fileDate: fDate,
      ));
    }

    state = state.copyWith(
      isLoading: false,
      collections: state.collections.map((c) {
        if (c.id == collectionId) {
          return c.copyWith(
            assets: [...c.assets, ...newAssets],
          );
        }
        return c;
      }).toList(),
    );
    _saveLibrary();
  }

  // Refreshes (or Creates) a standard collection with a fixed set of files.
  // Existing assets in this collection that are NOT in the new list might be kept or removed?
  // "Fixed templates" implies strict sync. Let's strict sync to ensure no stale files.
  Future<void> refreshStandardCollection(String collectionName, List<String> filePaths) async {
      // 0. Wait for Library Load to prevent duplicates
      int retries = 0;
      while (state.isLoading && retries < 50) { 
          await Future.delayed(const Duration(milliseconds: 100));
          retries++;
      }
  
      // 1. Find or Create Collection
      AssetCollection collection;
      bool isNew = false;
      
      try {
        collection = state.collections.firstWhere((c) => c.name == collectionName);
      } catch (e) {
        isNew = true;
        collection = AssetCollection(name: collectionName);
      }

      List<LibraryAsset> finalAssets = List.from(collection.assets);
      
      for (var path in filePaths) {
          // Check if already exists in this collection
          final exists = finalAssets.any((a) => a.path == path);
          
          if (!exists) {
             // Create New
             final name = path.split(Platform.pathSeparator).last;
             double? hX, hY, hW, hH;
             // Assume standard templates are templates
             final hole = await _detectHole(path);
             if (hole != null) {
               hX = hole.left;
               hY = hole.top;
               hW = hole.width;
               hH = hole.height;
             }
             
             finalAssets.add(LibraryAsset(
               id: Uuid().v4(),
               path: path,
               name: name,
               type: AssetType.template,
               holeX: hX, holeY: hY, holeW: hW, holeH: hH,
             ));
          }
      }
      
      final newCollection = collection.copyWith(assets: finalAssets);
      
      List<AssetCollection> newCollections;
      if (isNew) {
         newCollections = [...state.collections, newCollection];
      } else {
         newCollections = state.collections.map((c) => c.id == newCollection.id ? newCollection : c).toList();
      }
      
      state = state.copyWith(collections: newCollections);
      _saveLibrary();
  }

  Future<Rect?> _detectHole(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      int minX = image.width;
      int maxX = 0;
      int minY = image.height;
      int maxY = 0;
      bool found = false;

      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          if (pixel.a < 10) { // Nearly transparent
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            found = true;
          }
        }
      }

      if (!found) return null;

      return Rect.fromLTRB(
        minX / image.width, 
        minY / image.height, 
        maxX / image.width, 
        maxY / image.height
      );
    } catch (e) {
      debugPrint("Error detecting hole in $path: $e");
      return null;
    }
  }

  void removeAssetFromCollection(String collectionId, String assetId) {
    state = state.copyWith(
      collections: state.collections.map((c) {
        if (c.id == collectionId) {
          return c.copyWith(
            assets: c.assets.where((a) => a.id != assetId).toList(),
          );
        }
        return c;
      }).toList(),
    );
    _saveLibrary();
  }
}

final assetProvider = StateNotifierProvider<AssetNotifier, AssetLibraryState>((ref) {
  return AssetNotifier();
});
