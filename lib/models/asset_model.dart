import 'dart:ui';
import 'package:uuid/uuid.dart';

enum AssetType {
  element, 
  template,
  background, // Background pattern/image
}

class LibraryAsset {
  final String id;
  final String path;
  final String name;
  final AssetType type;
  
  // Logical coordinates (0-1) for templates
  // Deprecated single hole fields - kep for compat or single hole simple logic
  final double? holeX;
  final double? holeY;
  final double? holeW;
  final double? holeH;
  final DateTime? fileDate;
  final int? width;
  final int? height;
  
  // New: Multiple holes support
  final List<Rect> holes;
  // Compatibility fields for main_window usage
  final String processedPath;
  final List<String> tags;

  LibraryAsset({
    String? id,
    required this.path,
    required this.name,
    this.type = AssetType.element,
    this.holeX,
    this.holeY,
    this.holeW,
    this.holeH,
    this.fileDate,
    this.width,
    this.height,
    List<Rect>? holes,
    this.processedPath = "",
    this.tags = const [],
  }) : id = id ?? Uuid().v4(),
       holes = holes ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'type': type.name,
    'holeX': holeX,
    'holeY': holeY,
    'holeW': holeW,
    'holeH': holeH,
    'fileDate': fileDate?.toIso8601String(),
    'width': width,
    'height': height,
    'holes': holes.map((h) => {'l': h.left, 't': h.top, 'w': h.width, 'h': h.height}).toList(),
  };

  factory LibraryAsset.fromJson(Map<String, dynamic> json) {
    // Parse holes
    List<Rect> parsedHoles = [];
    if (json['holes'] != null) {
      parsedHoles = (json['holes'] as List).map((h) {
         return Rect.fromLTWH(
           (h['l'] as num).toDouble(),
           (h['t'] as num).toDouble(),
           (h['w'] as num).toDouble(),
           (h['h'] as num).toDouble(),
         );
      }).toList();
    } else if (json['holeX'] != null) {
       // Migration: Single hole to list
       parsedHoles.add(Rect.fromLTWH(
          (json['holeX'] as num).toDouble(),
          (json['holeY'] as num).toDouble(),
          (json['holeW'] as num).toDouble(),
          (json['holeH'] as num).toDouble(),
       ));
    }

    return LibraryAsset(
      id: json['id'],
      path: json['path'],
      name: json['name'],
      type: AssetType.values.firstWhere((e) => e.name == json['type'], orElse: () => AssetType.element),
      holeX: json['holeX']?.toDouble(),
      holeY: json['holeY']?.toDouble(),
      holeW: json['holeW']?.toDouble(),
      holeH: json['holeH']?.toDouble(),
      fileDate: json['fileDate'] != null ? DateTime.parse(json['fileDate']) : null,
      width: json['width'],
      height: json['height'],
      holes: parsedHoles,
    );
  }
}

class AssetCollection {
  final String id;
  final String name;
  final List<LibraryAsset> assets;

  AssetCollection({
    String? id,
    required this.name,
    List<LibraryAsset>? assets,
  })  : id = id ?? Uuid().v4(),
        assets = assets ?? [];

  AssetCollection copyWith({
    String? name,
    List<LibraryAsset>? assets,
  }) => AssetCollection(
    id: id,
    name: name ?? this.name,
    assets: assets ?? this.assets,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'assets': assets.map((a) => a.toJson()).toList(),
  };

  factory AssetCollection.fromJson(Map<String, dynamic> json) => AssetCollection(
    id: json['id'],
    name: json['name'],
    assets: (json['assets'] as List).map((a) => LibraryAsset.fromJson(a)).toList(),
  );
}
