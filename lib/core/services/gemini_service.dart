import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class GeminiService {
  static final GeminiService instance = GeminiService._internal();

  GeminiService._internal();

  Future<bool> validateKey(String apiKey) async {
    try {
      final cleanKey = apiKey.trim();
      if (cleanKey.isEmpty) return false;

      final dio = Dio();
      final response = await dio.get(
        'https://generativelanguage.googleapis.com/v1beta/models',
        queryParameters: {'key': cleanKey},
      );

      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint(
        'Gemini API Validation Error: ${e.response?.statusCode} - ${e.message}',
      );
      return false;
    } catch (e, stackTrace) {
      debugPrint('Gemini API Validation Error: $e');
      debugPrint('Stack Trace: $stackTrace');
      return false;
    }
  }

  Stream<GenerateContentResponse> generateStream(String apiKey, String prompt) {
    final cleanKey = apiKey.trim();

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: cleanKey,
      generationConfig: GenerationConfig(temperature: 0.3, topP: 0.9),
    );
    return model.generateContentStream([Content.text(prompt)]);
  }
}
