import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../state/project_state.dart';
import '../../logic/cache_provider.dart';

class SmartImage extends ConsumerWidget {
  final String path;
  final BoxFit fit;
  final Widget? errorBuilder;

  const SmartImage({
    super.key, 
    required this.path, 
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path.isEmpty) return const SizedBox();

    final projectState = ref.watch(projectProvider);
    final version = ref.watch(imageVersionProvider(path));
    final file = File(path);
    
    // 3. Apply Local Rotation
    final rotation = projectState.project.imageRotations[path] ?? 0;
    
    Widget wrapRotation(Widget child) {
       if (rotation == 0) return child;
       return RotatedBox(
         quarterTurns: (rotation / 90).round(),
         child: child,
       );
    }

    // 1. Try Original
    if (file.existsSync()) {
       return wrapRotation(Image.file(
         file, 
         key: ValueKey('${path}_$version'), // Rebuild widget
         fit: fit, 
         errorBuilder: (_,__,___) => errorBuilder ?? const SizedBox()
       ));
    }
    
    // 2. Try Proxy
    if (projectState.proxyRoot != null) {
       final filename = p.basename(path);
       final proxyPath = p.join(projectState.proxyRoot!, filename);
       final proxyFile = File(proxyPath);
       if (proxyFile.existsSync()) {
          final pVersion = ref.watch(imageVersionProvider(proxyPath));
          return wrapRotation(Stack(
            fit: StackFit.expand,
            children: [
               Image.file(
                 proxyFile, 
                 key: ValueKey('${proxyPath}_$pVersion'),
                 fit: fit, 
                 errorBuilder: (_,__,___) => errorBuilder ?? const SizedBox()
               ),
               // Mini Cloud Icon for Thumbnails
               Positioned(
                 top: 1, right: 1,
                 child: Container(
                   padding: const EdgeInsets.all(1),
                   color: Colors.black54,
                   child: const Icon(Icons.cloud_off, color: Colors.white, size: 10),
                 ),
               )
            ],
          ));
       }
    }
    
    // 3. Fallback (Red Error)
    return errorBuilder ?? Container(color: Colors.redAccent.withOpacity(0.3));
  }
}
