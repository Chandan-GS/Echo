import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
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
  ///
  /// Every call is counted in [GeminiUsage]. When Gemini is overloaded before
  /// replying, it retries once; other failures surface as [GeminiFailure].
  Stream<GenerateContentResponse> generateStream(
    String apiKey,
    String prompt, {
    String? systemInstruction,
  }) async* {
    final name = RemoteConfigService.instance.geminiModel;
    final model = GenerativeModel(
      // Model name is remote-controlled (see RemoteConfigService) so it can be
      // swapped from config.json without shipping a new build.
      model: name,
      apiKey: apiKey.trim(),
      generationConfig: GenerationConfig(temperature: 0.3, topP: 0.9),
      systemInstruction: systemInstruction == null
          ? null
          : Content.system(systemInstruction),
    );
    for (var attempt = 0; ; attempt++) {
      var replied = false;
      var tokens = 0;
      try {
        await for (final r in model.generateContentStream([
          Content.text(prompt),
        ])) {
          replied = true;
          tokens = r.usageMetadata?.totalTokenCount ?? tokens;
          yield r;
        }
        await GeminiUsage.instance.recordCall(model: name, tokens: tokens);
        return;
      } catch (e) {
        final hit = await GeminiUsage.instance.recordError(e, model: name);
        if (!replied && attempt == 0 && isOverloaded(errorText(e))) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        throw GeminiFailure(e, hit);
      }
    }
  }

  /// A single, non-streamed reply constrained to JSON — for small structured
  /// jobs like the to-do list, where only the finished object is useful.
  Future<String> generateJson(
    String apiKey,
    String prompt, {
    required String systemInstruction,
  }) async {
    final name = RemoteConfigService.instance.geminiModel;
    final model = GenerativeModel(
      model: name,
      apiKey: apiKey.trim(),
      generationConfig: GenerationConfig(
        temperature: 0.2,
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(systemInstruction),
    );
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await model.generateContent([Content.text(prompt)]);
        await GeminiUsage.instance.recordCall(
          model: name,
          tokens: response.usageMetadata?.totalTokenCount ?? 0,
        );
        return response.text ?? '';
      } catch (e) {
        final hit = await GeminiUsage.instance.recordError(e, model: name);
        if (attempt == 0 && isOverloaded(errorText(e))) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        throw GeminiFailure(e, hit);
      }
    }
  }
}

/// A failed Gemini call, with what to tell the user.
class GeminiFailure implements Exception {
  final Object cause;

  /// The limit that was hit, when it was one.
  final GeminiLimitHit? hit;

  const GeminiFailure(this.cause, this.hit);

  String get message => friendlyGeminiError(cause, hit: hit);

  @override
  String toString() => message;
}
