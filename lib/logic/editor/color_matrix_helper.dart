import 'dart:math';

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
}
