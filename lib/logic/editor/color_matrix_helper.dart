import 'dart:math';
import 'package:image/image.dart' as img;

class ColorMatrixHelper {
  
  static List<double> brightnessInternal(double value) {
     // Matrix 5x4. stored as list of 20
     // value: -1 to 1 (add to RGB) works, but standard brightness is mult.
     // Let's assume 'value' is multiplier (0.5 to 1.5).
     // Wait, ColorMatrix 'brightness' usually adds offset. Exposure multiplies.
     // Let's implement 'Exposure' as mult, 'Brightness' as offset.
     
     // Identity
     return [
        1,0,0,0,0,
        0,1,0,0,0,
        0,0,1,0,0,
        0,0,0,1,0,
     ];
  }

  static List<double> getMatrix({
     required double exposure,   // mult (0 = x1, 1 = x2) -> NO, let's say -1..1 where 0 is x1.
     required double contrast,   // mult (1.0 = normal)
     required double brightness, // add (-1..1) -> Offset
     required double saturation, // mult (1.0 = normal)
     required double temperature,// -1..1 (Blue..Red)
     required double tint,       // -1..1 (Green..Magenta)
  }) {
     // Start Identity
     List<double> mat = [
        1,0,0,0,0,
        0,1,0,0,0,
        0,0,1,0,0,
        0,0,0,1,0,
     ];
     
     // 1. Exposure (Multiplier)
     // Val 0 -> 1.0. Val 1.0 -> 2.0. Val -1.0 -> 0.0 (Black)
     // Let's map -1..1 to 0..2
     double expMult = exposure + 1.0; 
     // Or simpler: e^val ? No linear is fine for UI.
     // Actually: Exposure 0.0 = 1.0 mult.
     double e = pow(2, exposure).toDouble(); // Photographic exposure stops
     mat = _multiply(mat, [
        e,0,0,0,0,
        0,e,0,0,0,
        0,0,e,0,0,
        0,0,0,1,0,
     ]);

     // 2. Contrast
     // Scale around 128 (0.5)
     double c = contrast;
     double t = (1.0 - c) / 2.0 * 255.0;
     mat = _multiply(mat, [
        c,0,0,0,t,
        0,c,0,0,t,
        0,0,c,0,t,
        0,0,0,1,0,
     ]);

     // 3. Brightness (Multiplier / Gain) - ALIGNED WITH SAVER
     // Previously this was Offset, causing mismatch with Saver (which uses Mult).
     // Now 1.05 means x1.05 RGB (Brighter but blacks stay black).
     double b = brightness; 
     mat = _multiply(mat, [
        b,0,0,0,0,
        0,b,0,0,0,
        0,0,b,0,0,
        0,0,0,1,0,
     ]);
     
     // 4. Saturation
     double s = saturation;
     double lumiR = 0.3086;
     double lumiG = 0.6094;
     double lumiB = 0.0820;
     
     double oneMinusS = 1.0 - s;
     
     mat = _multiply(mat, [
        (oneMinusS * lumiR) + s, (oneMinusS * lumiG), (oneMinusS * lumiB), 0, 0,
        (oneMinusS * lumiR), (oneMinusS * lumiG) + s, (oneMinusS * lumiB), 0, 0,
        (oneMinusS * lumiR), (oneMinusS * lumiG), (oneMinusS * lumiB) + s, 0, 0,
        0, 0, 0, 1, 0,
     ]);
     
     // 5. Temperature (Warm/Cool) & Tint
     // Temp > 0 -> Red/Yellow Boost, Blue Cut.
     // Temp < 0 -> Blue Boost, Red Cut.
     // Tint > 0 -> Magenta Boost, Green Cut.
     
     double r = 1.0;
     double g = 1.0;
     double bla = 1.0; // b var name conflict
     
     if (temperature > 0) {
        r += temperature * 0.2;
        bla -= temperature * 0.2;
     } else {
        r += temperature * 0.1; // Temp is negative
        bla -= temperature * 0.2; // -(-0.2) = +0.2
     }
     
     if (tint > 0) {
        g -= tint * 0.2;
        r += tint * 0.1;
        bla += tint * 0.1;
     } else {
        g -= tint * 0.2; // tint neg -> +green
     }

     mat = _multiply(mat, [
        r,0,0,0,0,
        0,g,0,0,0,
        0,0,bla,0,0,
        0,0,0,1,0,
     ]);
     
     return mat;
  }

  static List<double> _multiply(List<double> a, List<double> b) {
    List<double> result = List.filled(20, 0.0);

    for (int y = 0; y < 4; y++) {
      for (int x = 0; x < 5; x++) {
        double sum = 0.0;
        for (int i = 0; i < 4; i++) {
          sum += a[y * 5 + i] * b[i * 5 + x];
        }
        if (x == 4) {
           sum += a[y * 5 + 4];
        }
        result[y * 5 + x] = sum;
      }
    }
    return result;
  }
  static img.Image applyColorMatrix(img.Image src, List<double> matrix) {
    // Standard 5x4 Matrix:
    // [ a, b, c, d, e,
    //   f, g, h, i, j,
    //   k, l, m, n, o,
    //   p, q, r, s, t ]
    //
    // R' = a*R + b*G + c*B + d*A + e
    // G' = f*R + g*G + h*B + i*A + j
    // ...
    // Note: Our matrix might be 20 items flat list.

    if (matrix.length != 20) return src;

    // Pre-calculate constants for speed if possible, but local vars are fine.
    final m = matrix;

    // Use loop
    for (var pixel in src) {
       // Normalize 0-255 to 0-255 (or 0-1 depending on logic? Our matrix logic assumed 0-255 or RGB input?)
       // ColorMatrixHelper.getMatrix assumed "value: -1 to 1 (add to RGB)".
       // Wait, `getMatrix` logic:
       //   Contrast: (1.0 - c) / 2.0 * 255.0 -> This implies the offsets (e, j, o) are in 0..255 space.
       //   Exposure: Mult.
       //   So input R,G,B should be 0..255.
       
       double r = pixel.r.toDouble();
       double g = pixel.g.toDouble();
       double b = pixel.b.toDouble();
       double a = pixel.a.toDouble();

       double newR = (m[0]*r) + (m[1]*g) + (m[2]*b) + (m[3]*a) + m[4]; // + offset
       double newG = (m[5]*r) + (m[6]*g) + (m[7]*b) + (m[8]*a) + m[9];
       double newB = (m[10]*r) + (m[11]*g) + (m[12]*b) + (m[13]*a) + m[14];
       double newA = (m[15]*r) + (m[16]*g) + (m[17]*b) + (m[18]*a) + m[19];

       // Clamp
       pixel.r = max(0, min(255, newR));
       pixel.g = max(0, min(255, newG));
       pixel.b = max(0, min(255, newB));
       pixel.a = max(0, min(255, newA));
    }
    
    return src;
  }

  /// Align histogram between 5 and 252 (Levels)
  static img.Image autoLevel(img.Image src) {
     int minL = 255;
     int maxL = 0;
     
     // 1. Find Min/Max Luminance
     var p = src.getPixel(0, 0);
     for (var pixel in src) {
        // Simple luminance approx
        int lum = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        if (lum < minL) minL = lum;
        if (lum > maxL) maxL = lum;
     }

     // Avoid divide by zero if plain image
     if (maxL <= minL) return src;

     // Target Range
     const int targetMin = 5;
     const int targetMax = 252;
     
     // Stretch Factor
     // formula: New = (Old - MinL) * (TMax - TMin) / (MaxL - MinL) + TMin
     double scale = (targetMax - targetMin) / (maxL - minL);

     for (var pixel in src) {
        pixel.r = _levelPixel(pixel.r, minL, scale, targetMin);
        pixel.g = _levelPixel(pixel.g, minL, scale, targetMin);
        pixel.b = _levelPixel(pixel.b, minL, scale, targetMin);
     }
     return src;
  }

  static num _levelPixel(num val, int minL, double scale, int targetMin) {
     double v = (val - minL) * scale + targetMin;
     return max(0, min(255, v));
  }
}
