import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';

class StandardTemplateInitializer {
  static const String _templateAssetPrefix = 'assets/templates/';
  static const String _targetDirName = 'templates';

  /// Scans bundled assets, finds templates, copies them to AppData,
  /// and returns the list of local file paths.
  static Future<List<String>> initializeStandardTemplates() async {
    List<String> localPaths = [];
    
    try {
      // 1. Get where we should store bundled templates
      final appDir = await getApplicationSupportDirectory();
      final targetDir = Directory(p.join(appDir.path, _targetDirName));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // 2. Scan Asset Manifest (Bundled)
      try {
        final manifestContent = await rootBundle.loadString('AssetManifest.json');
        final Map<String, dynamic> manifestMap = json.decode(manifestContent);
        final templateAssets = manifestMap.keys
            .where((key) => key.startsWith(_templateAssetPrefix))
            .where((key) {
              final ext = p.extension(key).toLowerCase();
              return ext == '.png' || ext == '.jpg' || ext == '.jpeg';
            })
            .toList();

        for (final assetPath in templateAssets) {
          final filename = p.basename(assetPath);
          final targetFile = File(p.join(targetDir.path, filename));
          final byteData = await rootBundle.load(assetPath);
          await targetFile.writeAsBytes(byteData.buffer.asUint8List());
          localPaths.add(targetFile.path);
        }
      } catch (e) {
         print("Error scanning bundle: $e");
      }
      
      // 3. Scan User Documents Folder (External)
      try {
         final docsDir = await getApplicationDocumentsDirectory();
         final extDir = Directory(p.join(docsDir.path, 'AiaAlbum', 'Templates'));
         
         if (!await extDir.exists()) {
            await extDir.create(recursive: true);
            // Optional: Create a README there?
            final readme = File(p.join(extDir.path, 'LEIA-ME.txt'));
            await readme.writeAsString("Coloque seus templates (1.png, 2.png, ...) aqui para serem detectados automaticamente.");
         }
         
         final extFiles = extDir.listSync().whereType<File>().where((f) {
             final ext = p.extension(f.path).toLowerCase();
             return ext == '.png' || ext == '.jpg' || ext == '.jpeg';
         }).toList();
         
         for (var f in extFiles) {
            // Avoid duplicates if same filename exists in bundle?
            // Or just add them.
            localPaths.add(f.path);
         }
         
         print("Found ${extFiles.length} external templates in ${extDir.path}");
         
      } catch (e) {
         print("Error scanning external templates: $e");
      }
      
      return localPaths;

    } catch (e) {
      print("Error initializing standard templates: $e");
      return localPaths;
    }
  }
}
