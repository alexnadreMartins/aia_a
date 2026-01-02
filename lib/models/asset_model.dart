import 'package:uuid/uuid.dart';

enum AssetType { element, template }

class LibraryAsset {
  final String id;
  final String path;
  final String name;
  final AssetType type;
  
  // Logical coordinates (0-1) for templates
  final double? holeX;
  final double? holeY;
  final double? holeW;
  final double? holeH;

  LibraryAsset({
    String? id,
    required this.path,
    required this.name,
    this.type = AssetType.element,
    this.holeX,
    this.holeY,
    this.holeW,
    this.holeH,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'name': name,
    'type': type.name,
    'holeX': holeX,
    'holeY': holeY,
    'holeW': holeW,
    'holeH': holeH,
  };

  factory LibraryAsset.fromJson(Map<String, dynamic> json) => LibraryAsset(
    id: json['id'],
    path: json['path'],
    name: json['name'],
    type: AssetType.values.firstWhere((e) => e.name == json['type'], orElse: () => AssetType.element),
    holeX: json['holeX']?.toDouble(),
    holeY: json['holeY']?.toDouble(),
    holeW: json['holeW']?.toDouble(),
    holeH: json['holeH']?.toDouble(),
  );
}

class AssetCollection {
  final String id;
  final String name;
  final List<LibraryAsset> assets;

  AssetCollection({
    String? id,
    required this.name,
    List<LibraryAsset>? assets,
  })  : id = id ?? const Uuid().v4(),
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
