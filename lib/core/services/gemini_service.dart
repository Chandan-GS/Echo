import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:project_echo/core/services/remote_config_service.dart';

class GeminiService {
  static final GeminiService instance = GeminiService._internal();

  GeminiService._internal();

  Future<bool> validateKey(String apiKey) async {
    try {
      final cleanKey = apiKey.trim();
      if (cleanKey.isEmpty) return false;

      final dio = Dio(
        BaseOptions(
          // Bound the request so the validation spinner can never hang forever
          // on a stalled or offline network.
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
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

  /// [systemInstruction], when given, is sent as Gemini's real system
  /// instruction and [prompt] as the user turn — rather than one blob in the
  /// offline model's chat template, which Gemini just reads as extra text.
  Stream<GenerateContentResponse> generateStream(
    String apiKey,
    String prompt, {
    String? systemInstruction,
  }) {
    final cleanKey = apiKey.trim();

    final model = GenerativeModel(
      // Model name is remote-controlled (see RemoteConfigService) so it can be
      // swapped from config.json without shipping a new build.
      model: RemoteConfigService.instance.geminiModel,
      apiKey: cleanKey,
      generationConfig: GenerationConfig(temperature: 0.3, topP: 0.9),
      systemInstruction:
          systemInstruction == null ? null : Content.system(systemInstruction),
    );
    return model.generateContentStream([Content.text(prompt)]);
  }
}
