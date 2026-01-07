
import 'dart:io';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

class NativeAutoEnhance {
  static Future<Map<String, double>> analyze(String path) async {
     try {
       final bytes = await File(path).readAsBytes();
       // Decode only header if possible? No, we need pixels.
       // Decode resize?
       final image = await img.decodeImage(bytes);
       if (image == null) return {};
       return computeStats(image);
     } catch (e) {
       print("NativeAuto Error: $e");
       return {};
     }
  }

  /// Analyzes the image locally and returns immediate adjustment values.
  static Map<String, double> computeStats(img.Image image) {
    // 1. Resize for speed (analyze a thumbnail)
    final thumb = img.copyResize(image, width: 256);
    
    // Stats
    double totalLum = 0;
    double minLum = 1.0;
    double maxLum = 0.0;
    
    // Histogram for simple levels
    // We can just iterate pixels to find approximate percentiles
    
    for (final p in thumb) {
       final double lum = p.luminanceNormalized.toDouble();
       totalLum += lum;
       if (lum < minLum) minLum = lum;
       if (lum > maxLum) maxLum = lum;
    }
    
    final avgLum = totalLum / (thumb.width * thumb.height);
    
    // --- Smart Gate (Calibrated to Reference: Avg 0.25, Max 1.0) ---
    
    // --- Smart Gate (Calibrated to Reference: Avg 0.25, Max 1.0) ---
    
    // Check if image is already "Ideal" (Good dynamic range, appropriate darkness for robes)
    bool isWellExposed = (avgLum > 0.23 && maxLum > 0.90);
    
    double exposure = 0.0;
    double brightness = 1.0;
    double contrast = 1.05; // Base contrast
    
    if (isWellExposed) {
       // "Ideal" Profile: Minimal touches
       exposure = 0.0;
       brightness = 1.0;
       contrast = 1.05;
    } else {
       // Needs Correction
       
       // 1. Exposure Calculation with Protection
       // Calculate how much we WANT to add
       double targetExposure = 0.35 - avgLum; 
       
       // HIGHLIGHT PROTECTION (Critical for Skin):
       // Calculate how much space we actually HAVE before clipping white
       // If Max is 0.9, we only have 0.1 space. We can push maybe 0.15 (soft clip) but not 0.4
       double headroom = 1.0 - maxLum;
       double safeExposure = headroom + 0.1; // Allow slight pushing into highlight compression
       
       exposure = targetExposure.clamp(0.0, 0.4);
       // Cap exposure to safe limits to prevent skin blowout
       if (exposure > safeExposure) exposure = safeExposure;

       // 2. Dark Background Detection (Prevent "Washed Out" look)
       // If Avg is low (0.1) but Max is High (0.8+), it's likely a dark background scene.
       // Pushing brightness here destroys the blacks.
       bool isHighContrastDark = (avgLum < 0.2 && maxLum > 0.7);
       
       if (isHighContrastDark) {
          // It's a dark background photo. Be gentle.
          brightness = 1.02; // Very slight boost only
          exposure = exposure * 0.7; // Reduce exposure boost by 30%
          contrast = 1.15; // increased contrast to keep blacks black
       } else {
          // Standard underexposed photo (flat)
          brightness = 1.05;
          
          // 3. Contrast: Stretch if flat
          final range = maxLum - minLum;
          if (range < 0.7) {
             contrast = 1.1 + (0.7 - range); 
          }
       }
       
       contrast = contrast.clamp(1.0, 1.3);
    }
    
    // 4. Saturation: 
    double saturation = 1.1; 
    
    // 4. Sharpness: Always good to have a tiny bit
    double sharpness = 0.1;

    return {
      'exposure': exposure,
      'contrast': contrast,
      'saturation': saturation,
      'sharpness': sharpness,
      'brightness': brightness, 
      'temperature': 0.0,
      'tint': 0.0,
    };
  }
}
