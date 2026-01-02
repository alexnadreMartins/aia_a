import 'dart:ui';
import 'package:uuid/uuid.dart';

enum PhotoSourceType { local, asset }

class PhotoItem {
  final String id;
  final String path;
  final String? text;
  final bool isText;
  double x;
  double y;
  double width;
  double height;
  double rotation;
  int zIndex;
  int exifOrientation;
  
  // Content Manipulation (Alignment/Scale inside frame)
  double contentX; // Alignment X (-1 to 1)
  double contentY; // Alignment Y (-1 to 1)
  double contentScale; // Zoom factor (>= 1.0)

  PhotoItem({
    String? id,
    required this.path,
    this.text,
    this.isText = false,
    this.x = 0,
    this.y = 0,
    this.width = 100,
    this.height = 100,
    this.rotation = 0,
    this.zIndex = 0,
    this.exifOrientation = 1,
    this.contentX = 0,
    this.contentY = 0,
    this.contentScale = 1.0,
  }) : id = id ?? const Uuid().v4();

  PhotoItem copyWith({
    String? id,
    String? path,
    String? text,
    bool? isText,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
    double? contentX,
    double? contentY,
    double? contentScale,
    int? exifOrientation,
  }) {
    return PhotoItem(
      id: id ?? this.id, 
      path: path ?? this.path,
      text: text ?? this.text,
      isText: isText ?? this.isText,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      exifOrientation: exifOrientation ?? this.exifOrientation,
      contentX: contentX ?? this.contentX,
      contentY: contentY ?? this.contentY,
      contentScale: contentScale ?? this.contentScale,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'text': text,
      'isText': isText,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'zIndex': zIndex,
      'contentX': contentX,
      'contentY': contentY,
      'contentScale': contentScale,
      'exifOrientation': exifOrientation,
    };
  }

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    return PhotoItem(
      id: json['id'],
      path: json['path'],
      text: json['text'],
      isText: json['isText'] ?? false,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      zIndex: json['zIndex'] as int,
      contentX: (json['contentX'] as num?)?.toDouble() ?? 0.0,
      contentY: (json['contentY'] as num?)?.toDouble() ?? 0.0,
      contentScale: (json['contentScale'] as num?)?.toDouble() ?? 1.0,
      exifOrientation: json['exifOrientation'] as int? ?? 1,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'widthMm': widthMm,
      'heightMm': heightMm,
      'backgroundColor': backgroundColor,
      'photos': photos.map((p) => p.toJson()).toList(),
    };
  }

  factory AlbumPage.fromJson(Map<String, dynamic> json) {
    return AlbumPage(
      id: json['id'],
      widthMm: (json['widthMm'] as num).toDouble(),
      heightMm: (json['heightMm'] as num).toDouble(),
      backgroundColor: json['backgroundColor'] as int,
      photos: (json['photos'] as List)
          .map((p) => PhotoItem.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Project {
  final String id;
  final String name; 
  final String contractNumber;
  final List<AlbumPage> pages;
  final int ppi;
  final List<String> allImagePaths;
  final Map<String, int> imageRotations; // path -> degrees (0, 90, 180, 270)
  final int currentPageIndex;

  Project({
    String? id,
    this.name = "New Project",
    this.contractNumber = "",
    List<AlbumPage>? pages,
    this.ppi = 300,
    List<String>? allImagePaths,
    Map<String, int>? imageRotations,
    this.currentPageIndex = 0,
  })  : id = id ?? const Uuid().v4(),
        pages = pages ?? [],
        allImagePaths = allImagePaths ?? [],
        imageRotations = imageRotations ?? {};

  Project copyWith({
    String? name,
    String? contractNumber,
    List<AlbumPage>? pages,
    int? ppi,
    List<String>? allImagePaths,
    Map<String, int>? imageRotations,
    int? currentPageIndex,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      contractNumber: contractNumber ?? this.contractNumber,
      pages: pages ?? this.pages, 
      ppi: ppi ?? this.ppi,
      allImagePaths: allImagePaths ?? this.allImagePaths,
      imageRotations: imageRotations ?? this.imageRotations,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contractNumber': contractNumber,
      'pages': pages.map((p) => p.toJson()).toList(),
      'ppi': ppi,
      'allImagePaths': allImagePaths,
      'imageRotations': imageRotations,
      'currentPageIndex': currentPageIndex,
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'] ?? "",
      contractNumber: json['contractNumber'] ?? "",
      pages: (json['pages'] as List)
          .map((p) => AlbumPage.fromJson(p as Map<String, dynamic>))
          .toList(),
      ppi: json['ppi'] as int? ?? 300,
      allImagePaths: List<String>.from(json['allImagePaths'] ?? []),
      imageRotations: Map<String, int>.from(json['imageRotations'] ?? {}),
      currentPageIndex: json['currentPageIndex'] as int? ?? 0,
    );
  }
}
