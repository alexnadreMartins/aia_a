
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
      Analise esta imagem para IMPRESSÃO FOTOGRÁFICA. Responda APENAS em JSON.
      INCLUA avaliação de SOMBRAS (pretos) e RUÍDO:
      {
          "qualidade_geral": "excelente|boa|regular|ruim",
          "exposicao": "subexposta|normal|superexposta",
          "contraste": "baixo|adequado|alto",
          "sombras": "bloqueadas|escuras|adequadas|lavadas",
          "nivel_ruido": "baixo|moderado|alto|muito_alto",
          "resumo": "resumo_breve"
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
             // Parse deep JSON structure
             if (data['candidates'] != null && 
                 (data['candidates'] as List).isNotEmpty &&
                 data['candidates'][0]['content'] != null) {
                 
                 final parts = data['candidates'][0]['content']['parts'] as List;
                 if (parts.isNotEmpty) {
                    final text = parts[0]['text'] as String;
                    return _calculateConservativeAdjustments(text);
                 }
             }
          } else {
             print("Gemini REST Error ($modelName): ${response.statusCode} - ${response.body}");
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

  static Map<String, double> _calculateConservativeAdjustments(String? text) {
     if (text == null) return {};
     try {
        final cleanText = text.replaceAll('```json', '').replaceAll('```', '').trim();
        final jsonMap = jsonDecode(cleanText);
        
        // Defaults (Printing Profile: Lighter Blacks, Safe Exposure)
        // User feedback: "Pretos muito fortes", needs more exposure/brightness.
        // Old Default 1.08 Contrast was crushing blacks.
        double exposure = 0.15; // Start with a mild boost
        double contrast = 1.0;  // Neutral contrast to keep shadows open
        double saturation = 1.05; 
        double brightness = 1.05; // Base brightness boost for printing
        
        double temperature = 0.0;
        double tint = 0.0;
        double sharpness = 0.05;
        double noiseReduction = 0.0;

        // 1. Exposure Logic
        final expStatus = jsonMap['exposicao']?.toString().toLowerCase();
        if (expStatus == 'subexposta') {
           exposure = 0.35; // Strong boost
        } else if (expStatus == 'superexposta') {
           exposure = -0.10; 
        }

        // 2. Contrast/Shadows Logic
        final contrastStatus = jsonMap['contraste']?.toString().toLowerCase();
        // Check for specific shadow info if available (prompt update needed below)
        final shadowStatus = jsonMap['sombras']?.toString().toLowerCase();
        
        if (contrastStatus == 'baixo') {
           contrast = 1.10; 
        } else if (contrastStatus == 'alto' || shadowStatus == 'bloqueadas' || shadowStatus == 'escuras') {
           // If high contrast or blocked shadows, keep contrast at minimum 1.0 (User Rule)
           contrast = 1.0; 
           brightness = 1.08; // Boost brightness further to lift shadows
        }

        // 3. Noise Logic
        final noiseStatus = jsonMap['nivel_ruido']?.toString().toLowerCase();
        if (noiseStatus == 'alto' || noiseStatus == 'muito_alto') {
           noiseReduction = 0.5; 
        } else if (noiseStatus == 'moderado') {
           noiseReduction = 0.3; 
        }
        
        // Return Map
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
        return {};
     }
  }
}
