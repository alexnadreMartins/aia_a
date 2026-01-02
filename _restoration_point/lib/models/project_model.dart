import 'dart:ui';
import 'package:uuid/uuid.dart';

enum PhotoSourceType { local, asset }

class PhotoItem {
  final String id;
  final String path;
  double x;
  double y;
  double width;
  double height;
  double rotation;
  int zIndex;
  
  // Content Manipulation (Alignment/Scale inside frame)
  double contentX; // Alignment X (-1 to 1)
  double contentY; // Alignment Y (-1 to 1)
  double contentScale; // Zoom factor (>= 1.0)

  PhotoItem({
    String? id,
    required this.path,
    this.x = 0,
    this.y = 0,
    this.width = 100,
    this.height = 100,
    this.rotation = 0,
    this.zIndex = 0,
    this.contentX = 0,
    this.contentY = 0,
    this.contentScale = 1.0,
  }) : id = id ?? const Uuid().v4();

  PhotoItem copyWith({
    String? id,
    String? path,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
    double? contentX,
    double? contentY,
    double? contentScale,
  }) {
    return PhotoItem(
      id: id ?? this.id, 
      path: path ?? this.path,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      contentX: contentX ?? this.contentX,
      contentY: contentY ?? this.contentY,
      contentScale: contentScale ?? this.contentScale,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'zIndex': zIndex,
      'contentX': contentX,
      'contentY': contentY,
      'contentScale': contentScale,
    };
  }

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      id: json['id'],
      path: json['path'],
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      zIndex: json['zIndex'] as int,
      contentX: (json['contentX'] as num?)?.toDouble() ?? 0.0,
      contentY: (json['contentY'] as num?)?.toDouble() ?? 0.0,
      contentScale: (json['contentScale'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class AlbumPage {
  final String id;
  final double widthMm;
  final double heightMm;
  final int backgroundColor; // ARGB int
  final List<PhotoItem> photos;

  AlbumPage({
    String? id,
    required this.widthMm,
    required this.heightMm,
    this.backgroundColor = 0xFFFFFFFF, // White default
    List<PhotoItem>? photos,
  })  : id = id ?? const Uuid().v4(),
        photos = photos ?? [];

  AlbumPage copyWith({
    double? widthMm,
    double? heightMm,
    int? backgroundColor,
    List<PhotoItem>? photos,
  }) {
    return AlbumPage(
      id: id,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      photos: photos ?? this.photos.map((p) => p.copyWith()).toList(),
    );
  }
}

class Project {
  final String id;
  final String name;
  final List<AlbumPage> pages;
  final int ppi;
  final List<String> allImagePaths;
  final int currentPageIndex;

  Project({
    String? id,
    this.name = "New Project",
    List<AlbumPage>? pages,
    this.ppi = 300,
    List<String>? allImagePaths,
    this.currentPageIndex = 0,
  })  : id = id ?? const Uuid().v4(),
        pages = pages ?? [],
        allImagePaths = allImagePaths ?? [];

  Project copyWith({
    String? name,
    List<AlbumPage>? pages,
    int? ppi,
    List<String>? allImagePaths,
    int? currentPageIndex,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      pages: pages ?? this.pages, // Shallow copy of list logic handled in State
      ppi: ppi ?? this.ppi,
      allImagePaths: allImagePaths ?? this.allImagePaths,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
    );
  }
}
