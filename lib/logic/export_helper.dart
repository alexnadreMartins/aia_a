import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import '../models/project_model.dart';

class ExportHelper {
  /// Exports each page as a JPG image in the specified directory.
  static Future<void> exportToJpg({
    required Project project,
    required List<GlobalKey> pageKeys,
    required String directoryPath,
  }) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    for (int i = 0; i < pageKeys.length; i++) {
      final key = pageKeys[i];
      final imageBytes = await captureKeyToBytes(key);
      if (imageBytes != null) {
        final fileName = 'page_${i + 1}.jpg';
        final file = File(p.join(directoryPath, fileName));
        await file.writeAsBytes(imageBytes);
      }
    }
  }

  /// Exports all pages into a single PDF file.
  static Future<void> exportToPdf({
    required Project project,
    required List<GlobalKey> pageKeys,
    required String pdfPath,
  }) async {
    final pdf = pw.Document();

    for (int i = 0; i < pageKeys.length; i++) {
      final key = pageKeys[i];
      final imageBytes = await captureKeyToBytes(key);
      if (imageBytes != null) {
        final image = pw.MemoryImage(imageBytes);
        
        // Use the project/page dimensions for PDF page sizing
        final pageData = project.pages[i];
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(
              pageData.widthMm * PdfPageFormat.mm,
              pageData.heightMm * PdfPageFormat.mm,
              marginAll: 0,
            ),
            build: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(image, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
      }
    }

    final file = File(pdfPath);
    await file.writeAsBytes(await pdf.save());
  }

  static Future<Uint8List?> captureKeyToBytes(GlobalKey key, {double pixelRatio = 3.0}) async {
    try {
      final RenderRepaintBoundary? boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
          debugPrint("ExportHelper: Boundary not found for key");
          return null;
      }
      
      debugPrint("ExportHelper: Boundary Size: ${boundary.size} | PixelRatio: $pixelRatio");

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("Error capturing page: $e");
      return null;
    }
  }

  /// Converts raw PNG bytes from Flutter to a JPG with explicit DPI metadata.
  static Future<void> saveAsHighResJpg({
    required Uint8List pngBytes,
    required String path,
    required int dpi,
  }) async {
    // 1. Decode the Flutter-captured PNG
    final image = img.decodeImage(pngBytes);
    if (image == null) return;

    // 2. Inject EXIF DPI Metadata
    if (image.exif.imageIfd.xResolution == null) {
        image.exif.imageIfd.xResolution = img.IfdValueRational(dpi, 1);
        image.exif.imageIfd.yResolution = img.IfdValueRational(dpi, 1);
        image.exif.imageIfd.resolutionUnit = 2; // Inches
    }

    // 3. Encode to High Quality JPG (100)
    final jpgBytes = img.encodeJpg(image, quality: 100);
    
    // 4. Save to file
    final file = File(path);
    await file.writeAsBytes(jpgBytes);
  }
}
