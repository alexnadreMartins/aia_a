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

  AssetLibraryState({
    this.collections = const [],
    this.isLoading = false,
  });

  AssetLibraryState copyWith({
    List<AssetCollection>? collections,
    bool? isLoading,
  }) => AssetLibraryState(
    collections: collections ?? this.collections,
    isLoading: isLoading ?? this.isLoading,
  );
}

class AssetNotifier extends StateNotifier<AssetLibraryState> {
  AssetNotifier() : super(AssetLibraryState(isLoading: true)) {
    loadLibrary();
  }

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
          // Check alpha channel. In 'image' package 4.x, getAlpha might be needed or pixel value check.
          // For most formats, pixel.a is the alpha (0-255).
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

      // Return as logical 0-1 range for flexibility
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
