import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/project_model.dart';
import 'package:uuid/uuid.dart';

class ProjectPackager {
  
  static Future<void> packProject(Project project, String outputPath, {Function(int current, int total, String status)? onProgress}) async {
    final tempDir = await getTemporaryDirectory();
    final packId = Uuid().v4();
    final workDir = Directory(p.join(tempDir.path, 'aia_pack_$packId'));
    await workDir.create(recursive: true);

    try {
      final proxiesDir = Directory(p.join(workDir.path, 'proxies'));
      await proxiesDir.create();

      final allPaths = project.allImagePaths;
      int processed = 0;
      int total = allPaths.length;

      // 1. Process Images in Parallel Batches
      // Batch size of 4-6 is usually optimal for mobile/desktop to avoid OOM but maximize CPU
      const int batchSize = 4;
      
      for (int i = 0; i < allPaths.length; i += batchSize) {
         final end = (i + batchSize < allPaths.length) ? i + batchSize : allPaths.length;
         final batch = allPaths.sublist(i, end);
         
         final futures = batch.map((path) async {
            final filename = p.basename(path);
            final destPath = p.join(proxiesDir.path, filename);
            
            // Check if source exists
            if (await File(path).exists()) {
               try {
                 // Offload heavy lifting to Isolate
                 await _processImageIsolate(path, destPath);
               } catch (e) {
                 print("Error packing image $path: $e");
               }
            }
         });
         
         await Future.wait(futures);
         
         processed += batch.length;
         if (onProgress != null) onProgress(processed, total, "Compactando: $processed/$total");
      }

      // 2. Save Project JSON
      final jsonFile = File(p.join(workDir.path, 'project.json'));
      await jsonFile.writeAsString(jsonEncode(project.toJson()));
      
      if (onProgress != null) onProgress(total, total, "Gerando Arquivo Final...");
      await Future.delayed(Duration.zero);

      // 3. Create Archive In-Memory (Robust against stream issues)
      final archive = Archive();

      // Add Files
      final files = workDir.listSync(recursive: true);
      for (var file in files) {
         if (file is File) {
            final relPath = p.relative(file.path, from: workDir.path).replaceAll(r'\', '/');
            final bytes = await file.readAsBytes();
            final af = ArchiveFile(relPath, bytes.length, bytes);
            archive.addFile(af);
         }
      }

      // Encode
      final encoder = ZipEncoder();
      final encodedBytes = encoder.encode(archive);
      if (encodedBytes == null) throw Exception("Failed to encode zip file");

      // Write
      final outFile = File(outputPath);
      await outFile.writeAsBytes(encodedBytes);

    } catch (e) {
      print("Zip Failure: $e");
      rethrow;
    } finally {
      // Cleanup
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    }
  }

  // Standalone function for Isolate
  static Future<void> _processImageIsolate(String srcPath, String destPath) async {
     await Isolate.run(() async {
        final file = File(srcPath);
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        
        if (image != null) {
           // Resize to max 2048
           img.Image resized = image;
           if (image.width > 2048 || image.height > 2048) {
               resized = img.copyResize(image, width: image.width > image.height ? 2048 : null, height: image.height >= image.width ? 2048 : null);
           }
           
           // Encode as JPG
           final encoded = img.encodeJpg(resized, quality: 80);
           await File(destPath).writeAsBytes(encoded);
        }
     });
  }

  static Future<void> updatePackage(Project project, String proxySource, String outputPath, {Function(int current, int total, String status)? onProgress}) async {
    final tempDir = await getTemporaryDirectory();
    final packId = Uuid().v4();
    final workDir = Directory(p.join(tempDir.path, 'aia_update_$packId'));
    await workDir.create(recursive: true);

    try {
      // 1. Prepare Content
      final proxiesDir = Directory(p.join(workDir.path, 'proxies'));
      await proxiesDir.create();

      // Copy existing proxies
      final sourceDir = Directory(proxySource);
      if (await sourceDir.exists()) {
         final files = sourceDir.listSync();
         int i = 0;
         for (var f in files) {
           if (f is File) {
              if (onProgress != null && i % 5 == 0) onProgress(i, files.length, "Empacotando Proxy: ${p.basename(f.path)}");
              await f.copy(p.join(proxiesDir.path, p.basename(f.path)));
           }
           i++;
         }
      }

      // 2. Save new Project JSON
      final jsonFile = File(p.join(workDir.path, 'project.json'));
      await jsonFile.writeAsString(jsonEncode(project.toJson()));

      if (onProgress != null) onProgress(0,0, "Finalizando Pacote...");
      await Future.delayed(Duration.zero);

      // 3. Zip It (In-Memory)
      final archive = Archive();
      final content = workDir.listSync(recursive: true);
      for (var file in content) {
         if (file is File) {
            final relPath = p.relative(file.path, from: workDir.path).replaceAll(r'\', '/');
            final bytes = await file.readAsBytes();
            final af = ArchiveFile(relPath, bytes.length, bytes);
            archive.addFile(af);
         }
      }

      final encoder = ZipEncoder();
      final encodedBytes = encoder.encode(archive);
      if (encodedBytes == null) throw Exception("Failed to encode zip");

      final outFile = File(outputPath);
      await outFile.writeAsBytes(encodedBytes);

    } catch (e) {
      print("Update Package Failure: $e");
      rethrow;
    } finally {
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
    }
  }
}
