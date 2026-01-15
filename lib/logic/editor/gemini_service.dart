
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class GeminiService {
  // Key (Replaced as needed)
  static const String _apiKey = "AIzaSyCO5TNHobpGqtrojFy5r5QnpSApCgCadpQ"; 
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  static Future<Map<String, double>> analyzeImage(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return {};

      // 1. Prepare Image
      final bytes = await file.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) return {};

      // Resize if too big
      img.Image processedImage = originalImage;
      if (originalImage.width > 1024 || originalImage.height > 1024) {
         processedImage = img.copyResize(originalImage, width: 1024);
      }
      
      final jpgBytes = img.encodeJpg(processedImage, quality: 80);
      final base64Image = base64Encode(jpgBytes);
      
      // 2. Models to try (REST String)
      // Trying 'gemini-2.0-flash-exp' as suggested, then falbacks
      final modelsToTry = [
        'gemini-2.0-flash-exp', 
        'gemini-1.5-flash', 
        'gemini-1.5-pro'
      ];
      
      final promptText = """
      Analise esta imagem para IMPRESSÃO FOTOGRÁFICA "FINE ART". Responda APENAS em JSON.
      
      CRÍTICO: EVITE "AQUECER" (ESQUENTAR) A IMAGEM.
      - A tendência deve ser NEUTRA ou LIG E IRAMENTE FRIA (Cool Bias).
      - Tint e Temperatura devem buscar o "BRANCO PURO", sem amarelados.
      
      PELE (VECTORSCOPE):
      - Correção CIRÚRGICA.
      - Se a pele estiver muito Laranja/Amarela -> RESFRIE (TEMP -).
      
      RETORNE:
      {
          "exposicao_correcao": "valor entre -0.5 e 0.5.",
          "contraste_sugerido": "valor entre 0.95 e 1.15.",
          "tint_pele": "valor entre -0.5 e 0.5. (Correção de Verde/Magenta)",
          "temp_pele": "valor entre -0.5 e 0.5. (PREFIRA VALORES NEGATIVOS SE TIVER DÚVIDA).",
          "sombras_bloqueadas": "true/false",
          "luzes_estouradas": "true/false"
      }
      """;

      for (final modelName in modelsToTry) {
        try {
          print("Gemini REST: Trying model $modelName...");
          final url = Uri.parse('$_baseUrl/$modelName:generateContent?key=$_apiKey');
          
          final requestBody = {
            'contents': [
              {
                'parts': [
                  {'text': promptText},
                  {
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': base64Image
                    }
                  }
                ]
              }
            ]
          };

          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          );
          
          if (response.statusCode == 200) {
             print("Gemini Response ($modelName): Success!");
             final data = jsonDecode(response.body);
             if (data['candidates'] != null && 
                 (data['candidates'] as List).isNotEmpty &&
                 data['candidates'][0]['content'] != null) {
                 
                 final parts = data['candidates'][0]['content']['parts'] as List;
                 if (parts.isNotEmpty) {
                    final text = parts[0]['text'] as String;
                    return _calculateCoolNeutralAdjustments(text);
                 }
             }
          }
        } catch (e) {
          print("Gemini Client Error ($modelName): $e");
        }
      }
      return {};

    } catch (e) {
      print("Gemini Service Error: $e");
      return {};
    }
  }

  static Map<String, double> _calculateCoolNeutralAdjustments(String? text) {
     if (text == null) return {};
     try {
        String cleanText = text.replaceAll('```json', '').replaceAll('```', '').trim();
        final startIndex = cleanText.indexOf('{');
        final endIndex = cleanText.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1) {
           cleanText = cleanText.substring(startIndex, endIndex + 1);
        }
        
        final jsonMap = jsonDecode(cleanText);
        
        double parseDouble(dynamic val, [double def = 0.0]) {
           if (val == null) return def;
           if (val is num) return val.toDouble();
           if (val is String) {
              return double.tryParse(val.replaceAll(',', '.')) ?? def;
           }
           return def;
        }

        // Defaults - User Preference (Soft & Bright)
        double exposure = 0.0;
        double contrast = 0.90; // Requested by User
        double saturation = 1.05; 
        double brightness = 1.05; // Requested by User
        double temperature = -0.05; 
        double tint = 0.0;
        double sharpness = 0.15; 
        double noiseReduction = 0.33;

        // 1. Exposure
        exposure = parseDouble(jsonMap['exposicao_correcao'], 0.0);
        
        // Combine AI contrast with User Baseline
        // If AI suggests 1.0 (Neutral), we use 0.9.
        // If AI suggests 1.1 (Contrast+), we use 1.0.
        double aiContrast = parseDouble(jsonMap['contraste_sugerido'], 1.0);
        contrast = 0.90 * aiContrast; 

        // Clamps
        if (exposure > 0.5) exposure = 0.5;
        if (exposure < -0.5) exposure = -0.5;
        if (contrast < 0.85) contrast = 0.85; // Allow softer
        if (contrast > 1.1) contrast = 1.1;   // restrict high contrast

        // 2. TONE LOGIC
        tint = parseDouble(jsonMap['tint_pele'], 0.0);
        temperature = parseDouble(jsonMap['temp_pele'], 0.0);
        
        if (temperature > 0.15) temperature = 0.15; 
        if (temperature < -0.5) temperature = -0.5; 

        if (tint > 0.4) tint = 0.4;
        if (tint < -0.4) tint = -0.4;

        // Recovery
        bool blackCrush = jsonMap['sombras_bloqueadas'].toString().toLowerCase() == 'true';
        bool whiteBlow = jsonMap['luzes_estouradas'].toString().toLowerCase() == 'true';
        
        if (blackCrush) {
           brightness += 0.05; // Add to existing 1.05
        }
        if (whiteBlow) {
           exposure -= 0.12;
        }

        // 3. Noise
        String noiseStatus = jsonMap['nivel_ruido']?.toString().toLowerCase() ?? "";
        if (noiseStatus.contains("alto")) {
           noiseReduction = 0.55;
        }

        return {
           'exposure': exposure,
           'contrast': contrast,
           'saturation': saturation,
           'temperature': temperature,
           'tint': tint,
           'sharpness': sharpness,
           'brightness': brightness,
           'noiseReduction': noiseReduction,
        };

     } catch (e) {
        print("JSON Parse Error: $e");
        return {
           'exposure': 0.05,
           'contrast': 1.0, 
           'saturation': 1.05,
           'sharpness': 0.1,
           'brightness': 1.02,
           'temperature': 0.0,
           'tint': 0.0,
        };
     }
  }
}
