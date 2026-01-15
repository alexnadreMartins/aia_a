import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../state/project_state.dart';

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
    final file = File(path);
    
    // 1. Try Original
    if (file.existsSync()) {
       return Image.file(file, fit: fit, errorBuilder: (_,__,___) => errorBuilder ?? const SizedBox());
    }
    
    // 2. Try Proxy
    if (projectState.proxyRoot != null) {
       final filename = p.basename(path);
       final proxyFile = File(p.join(projectState.proxyRoot!, filename));
       if (proxyFile.existsSync()) {
          return Stack(
            fit: StackFit.expand,
            children: [
               Image.file(proxyFile, fit: fit, errorBuilder: (_,__,___) => errorBuilder ?? const SizedBox()),
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
          );
       }
    }
    
    // 3. Fallback (Red Error)
    return errorBuilder ?? Container(color: Colors.redAccent.withOpacity(0.3));
  }
}
