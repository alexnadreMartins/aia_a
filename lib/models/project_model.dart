import 'dart:ui';
import 'package:uuid/uuid.dart';

enum PhotoSourceType { local, asset }

class PhotoItem {
  final String id;
  final String path;
  final String? text;
  final bool isText;
  final bool isTemplate;
  final bool isLocked;
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
    this.isTemplate = false,
    this.isLocked = false,
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
  }) : id = id ?? Uuid().v4();

  PhotoItem copyWith({
    String? id,
    String? path,
    String? text,
    bool? isText,
    bool? isTemplate,
    bool? isLocked,
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
      isTemplate: isTemplate ?? this.isTemplate,
      isLocked: isLocked ?? this.isLocked,
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
      'isTemplate': isTemplate,
      'isLocked': isLocked,
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
      isTemplate: json['isTemplate'] ?? false,
      isLocked: json['isLocked'] ?? false,
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
  final int pageNumber;
  final String? backgroundPath; // Optional path for page background image
  final String? label; // For production tagging (e.g. Contract Number)

  AlbumPage({
    String? id,
    required this.widthMm,
    required this.heightMm,
    this.backgroundColor = 0xFFFFFFFF, // White default
    this.pageNumber = 0,
    List<PhotoItem>? photos,
    this.backgroundPath,
    this.label,
  })  : id = id ?? Uuid().v4(),
        photos = photos ?? [];

  AlbumPage copyWith({
    String? id,
    double? widthMm,
    double? heightMm,
    int? backgroundColor,
    int? pageNumber,
    List<PhotoItem>? photos,
    String? backgroundPath,
    String? label,
  }) {
    return AlbumPage(
      id: id ?? this.id,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      pageNumber: pageNumber ?? this.pageNumber,
      photos: photos ?? this.photos.map((p) => p.copyWith()).toList(),
      backgroundPath: backgroundPath ?? this.backgroundPath,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'widthMm': widthMm,
      'heightMm': heightMm,
      'backgroundColor': backgroundColor,
      'pageNumber': pageNumber,
      'photos': photos.map((p) => p.toJson()).toList(),
      'backgroundPath': backgroundPath,
      'label': label,
    };
  }

  factory AlbumPage.fromJson(Map<String, dynamic> json) {
    return AlbumPage(
      id: json['id'],
      widthMm: (json['widthMm'] as num).toDouble(),
      heightMm: (json['heightMm'] as num).toDouble(),
      backgroundColor: json['backgroundColor'] as int,
      pageNumber: json['pageNumber'] as int? ?? 0,
      photos: (json['photos'] as List)
          .map((p) => PhotoItem.fromJson(p as Map<String, dynamic>))
          .toList(),
      backgroundPath: json['backgroundPath'],
      label: json['label'],
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
  final Map<String, int> cameraTimeOffsets; // Model_Serial -> Offset in Seconds
  final int currentPageIndex;
  final String? defaultBackgroundPath;
  
  // New Stats Fields
  final Map<String, int> sourcePhotoCounts; // e.g. "Canon 5D_123": 100
  final Map<String, int> usedPhotoCounts; // e.g. "Canon 5D_123": 50
  final int exportedCount; // NEW
  final Duration totalEditingTime;
  final Duration chronometerTime;
  final String lastUser;
  final String userCategory; // "Editor" or "Master"
  final String createdByCategory; // "Master" (if created via Batch), etc.
  final String company; // Company Name or ID

  Project({
    String? id,
    this.name = "New Project",
    this.contractNumber = "",
    List<AlbumPage>? pages,
    this.ppi = 300,
    List<String>? allImagePaths,
    Map<String, int>? imageRotations,
    Map<String, int>? cameraTimeOffsets,
    this.currentPageIndex = 0,
    this.defaultBackgroundPath,
    this.sourcePhotoCounts = const {},
    this.usedPhotoCounts = const {},
    this.exportedCount = 0, // NEW
    this.totalEditingTime = Duration.zero,
    this.chronometerTime = Duration.zero,
    this.lastUser = "Unknown",
    this.userCategory = "Editor",
    this.createdByCategory = "Editor",
    this.company = "Default",
  })  : id = id ?? Uuid().v4(),
        pages = pages ?? [],
        allImagePaths = allImagePaths ?? [],
        imageRotations = imageRotations ?? {},
        cameraTimeOffsets = cameraTimeOffsets ?? {};

  Project copyWith({
    String? id,
    String? name,
    String? contractNumber,
    List<AlbumPage>? pages,
    int? ppi,
    List<String>? allImagePaths,
    Map<String, int>? imageRotations,
    Map<String, int>? cameraTimeOffsets,
    int? currentPageIndex,
    String? defaultBackgroundPath,
    Map<String, int>? sourcePhotoCounts,
    Map<String, int>? usedPhotoCounts,
    int? exportedCount, // NEW
    Duration? totalEditingTime,
    Duration? chronometerTime,
    String? lastUser,
    String? userCategory,
    String? createdByCategory,
    String? company,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      contractNumber: contractNumber ?? this.contractNumber,
      pages: pages ?? this.pages, 
      ppi: ppi ?? this.ppi,
      allImagePaths: allImagePaths ?? this.allImagePaths,
      imageRotations: imageRotations ?? this.imageRotations,
      cameraTimeOffsets: cameraTimeOffsets ?? this.cameraTimeOffsets,
      currentPageIndex: currentPageIndex ?? this.currentPageIndex,
      defaultBackgroundPath: defaultBackgroundPath ?? this.defaultBackgroundPath,
      sourcePhotoCounts: sourcePhotoCounts ?? this.sourcePhotoCounts,
      usedPhotoCounts: usedPhotoCounts ?? this.usedPhotoCounts,
      exportedCount: exportedCount ?? this.exportedCount, // NEW
      totalEditingTime: totalEditingTime ?? this.totalEditingTime,
      chronometerTime: chronometerTime ?? this.chronometerTime,
      lastUser: lastUser ?? this.lastUser,
      userCategory: userCategory ?? this.userCategory,
      createdByCategory: createdByCategory ?? this.createdByCategory,
      company: company ?? this.company,
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
      'cameraTimeOffsets': cameraTimeOffsets,
      'currentPageIndex': currentPageIndex,
      'defaultBackgroundPath': defaultBackgroundPath,
      'sourcePhotoCounts': sourcePhotoCounts,
      'usedPhotoCounts': usedPhotoCounts,
      'exportedCount': exportedCount, // NEW
      'totalEditingTime': totalEditingTime.inSeconds,
      'chronometerTime': chronometerTime.inSeconds,
      'lastUser': lastUser,
      'userCategory': userCategory,
      'createdByCategory': createdByCategory,
      'company': company,
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
      cameraTimeOffsets: Map<String, int>.from(json['cameraTimeOffsets'] ?? {}),
      currentPageIndex: json['currentPageIndex'] as int? ?? 0,
      defaultBackgroundPath: json['defaultBackgroundPath'],
      sourcePhotoCounts: Map<String, int>.from(json['sourcePhotoCounts'] ?? {}),
      usedPhotoCounts: Map<String, int>.from(json['usedPhotoCounts'] ?? {}),
      exportedCount: json['exportedCount'] as int? ?? 0, // NEW
      totalEditingTime: Duration(seconds: json['totalEditingTime'] as int? ?? 0),
      chronometerTime: Duration(seconds: json['chronometerTime'] as int? ?? 0),
      lastUser: json['lastUser'] ?? "Unknown",
      userCategory: json['userCategory'] ?? "Editor",
      createdByCategory: json['createdByCategory'] ?? "Editor",
      company: json['company'] ?? "Default",
    );
  }
}
