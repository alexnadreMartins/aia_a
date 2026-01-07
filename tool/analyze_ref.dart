
import 'dart:io';
import 'package:image/image.dart' as img;

void main() async {
  final path = "/home/ale/.gemini/antigravity/brain/8fbec824-3181-43ba-b795-cd322a4b0b2a/uploaded_image_1767539017662.jpg";
  final bytes = await File(path).readAsBytes();
  final image = img.decodeImage(bytes)!;
  
  double totalLum = 0;
  double minLum = 1.0;
  double maxLum = 0.0;
  
  // Use same logic as app
  final thumb = img.copyResize(image, width: 256);
  
  for (final p in thumb) {
     final double lum = p.luminanceNormalized.toDouble();
     totalLum += lum;
     if (lum < minLum) minLum = lum;
     if (lum > maxLum) maxLum = lum;
  }
  
  final avgLum = totalLum / (thumb.width * thumb.height);
  
  print("Reference Stats:");
  print("Average Luminance: $avgLum");
  print("Min Luminance: $minLum");
  print("Max Luminance: $maxLum");
  print("Dynamic Range: ${maxLum - minLum}");
}
