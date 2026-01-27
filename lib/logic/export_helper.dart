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

    // Default to Project PPI or 300 if not set
    final targetDpi = project.ppi > 0 ? project.ppi : 300;

    for (int i = 0; i < pageKeys.length; i++) {
        // Validation loop range
        if (i >= project.pages.length) break;

        final key = pageKeys[i];
        final pageData = project.pages[i]; // Get dimensions from model (cm/mm)
        
        // Calculate required pixels for target DPI
        // widthMm / 25.4 * dpi = widthPixels
        final targetWidthPx = (pageData.widthMm / 25.4 * targetDpi).round();
        
        // Get current render size to calculate ratio
        final RenderRepaintBoundary? boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) {
            print("ExportHelper: Boundary not found for page ${i+1}");
            continue;
        }
        
        // Determine pixelRatio needed
        // currentWidth * ratio = targetWidthPx
        // ratio = targetWidthPx / currentWidth
        final currentWidth = boundary.size.width;
        final requiredRatio = targetWidthPx / currentWidth;
        
        debugPrint("Export Page ${i+1}: ${pageData.widthMm}mm @ $targetDpi DPI -> Target $targetWidthPx px | Screen Wid: $currentWidth -> Ratio: $requiredRatio");

        final imageBytes = await captureKeyToBytes(key, pixelRatio: requiredRatio);
        
        if (imageBytes != null) {
        final pageNum = (i + 1).toString().padLeft(2, '0');
                 
                 // Standard prefix: "Contract_ProjectName" or just "ProjectName"
                 String fileNamePrefix = project.name;
                 // Sanitize
                 fileNamePrefix = fileNamePrefix.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

                 if (project.contractNumber.isNotEmpty) {
                    fileNamePrefix = "${project.contractNumber}_$fileNamePrefix";
                 }
                 
                 final fileName = "${fileNamePrefix}_$pageNum.jpg";
                 final filePath = p.join(dir.path, fileName);
            
            // Save with explicit DPI metadata
            await saveAsHighResJpg(
                pngBytes: imageBytes, 
                path: filePath, 
                dpi: targetDpi
            );
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
      // For PDF, we usually want high quality but not insane DPI if mainly for viewing, 
      // but for print PDF we should respect 300 DPI.
      // Let's stick to a safe high ratio or 300 DPI equiv.
      
      // Re-use logic for consistent quality
      final pageData = project.pages[i];
      final targetDpi = 300;
      final targetWidthPx = (pageData.widthMm / 25.4 * targetDpi).round();
      final RenderRepaintBoundary? boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      double ratio = 3.0; // Fallback
      
      if (boundary != null) {
         ratio = targetWidthPx / boundary.size.width;
      }

      final imageBytes = await captureKeyToBytes(key, pixelRatio: ratio);
      
      if (imageBytes != null) {
        final image = pw.MemoryImage(imageBytes);
        
        // Use the project/page dimensions for PDF page sizing
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
      
      // Removed cap of 10.0 because it prevents high-res export from small on-screen widgets
      // We rely on Flutter to handle the texture size or fail if it's truly too big (e.g. > 16k)
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

    // 2. Encode to High Quality JPG (100)
    // We ignore the library's metadata support because it's proving unreliable for this user's context.
    List<int> jpgBytes = img.encodeJpg(image, quality: 100);
    
    // 3. Manually Patch JFIF Header (Nuclear Option)
    // This ensures Photoshop reads exactly what we want.
    try {
       jpgBytes = _setJfifDpi(Uint8List.fromList(jpgBytes), dpi);
    } catch (e) {
       debugPrint("Warning: Could not patch JFIF header: $e");
    }
    
    // 4. Save to file
    final file = File(path);
    await file.writeAsBytes(jpgBytes);
  }

  /// Patches the APP0 JFIF segment to enforce DPI
  static List<int> _setJfifDpi(Uint8List bytes, int dpi) {
     // Check for SOI (FF D8)
     if (bytes[0] != 0xFF || bytes[1] != 0xD8) return bytes;
     
     // Look for APP0 (FF E0)
     // Usually immediately after SOI, but sometimes there are other markers.
     int offset = 2;
     
     while (offset < bytes.length - 1) {
        if (bytes[offset] != 0xFF) break; // Invalid marker start
        
        int marker = bytes[offset + 1];
        int length = (bytes[offset + 2] << 8) | bytes[offset + 3];
        
        if (marker == 0xE0) {
           // Found APP0
           // Check for 'JFIF\0' signature at offset + 4
           // Structure: [FF E0] [LenHi LenLo] [J F I F 0] [Maj Min] [Units] [Xhi Xlo] [Yhi Ylo]
           // Indexes:   0  1     2     3       4 5 6 7 8    9   10      11     12 13    14 15
           // Relative to Offset:
           // +4,5,6,7,8 = JFIF\0
           // +11 = Units (1 = DPI)
           // +12,13 = X Density
           // +14,15 = Y Density
           
           if (bytes[offset + 4] == 0x4A && // J
               bytes[offset + 5] == 0x46 && // F
               bytes[offset + 6] == 0x49 && // I
               bytes[offset + 7] == 0x46 && // F
               bytes[offset + 8] == 0x00) { // \0
               
               // Set Units to 1 (Dots per Inch)
               bytes[offset + 11] = 1;
               
               // Set X Density
               bytes[offset + 12] = (dpi >> 8) & 0xFF;
               bytes[offset + 13] = dpi & 0xFF;

               // Set Y Density
               bytes[offset + 14] = (dpi >> 8) & 0xFF;
               bytes[offset + 15] = dpi & 0xFF;
               
               debugPrint("DPI Patched to $dpi in JFIF header");
               return bytes;
           }
        }
        
        // Move to next marker
        offset += 2 + length;
     }
     
     // If we are here, APP0 was not found. We could insert it, but img.encodeJpg usually adds it.
     return bytes; 
  }
}
