import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/services/gemini_usage.dart';

/// Remotely-controlled runtime config (currently just the Gemini model name),
/// fetched from the hosted config.json so the cloud model can be swapped WITHOUT
/// shipping a new app build. Layers of safety:
///  - a compiled-in default (works offline / on first install),
///  - the last-good value cached in prefs (survives a transient fetch failure),
///  - a `min_build` gate so a remote model that needs a newer client than this
///    build is ignored (old installs keep their known-good model).
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const _configUrl = 'https://echo-mobileapp.vercel.app/config.json';
  static const _prefKey = 'cfg_gemini_model';
  static const _rpdKey = 'cfg_gemini_rpd';

  /// Always keep this a currently-valid model — it's the ultimate fallback.
  static const _defaultModel = 'gemini-3.5-flash-lite';

  String _geminiModel = _defaultModel;
  String get geminiModel => _geminiModel;

  /// Fetch remote config once at startup. Safe to fire-and-forget: on any
  /// failure it keeps the last-good cached value, or the bundled default.
  Future<void> load() async {
    await _fetch();
    final prefs = await SharedPreferences.getInstance();
    GeminiUsage.instance.configDailyLimit = prefs.getInt(_rpdKey);
    await GeminiUsage.instance.load(model: _geminiModel);
  }

  Future<void> _fetch() async {
    final prefs = await SharedPreferences.getInstance();
    // Seed from last-good cache first so a transient network failure never
    // regresses us to the compiled default.
    _geminiModel = prefs.getString(_prefKey) ?? _defaultModel;

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
      final res = await dio.get(_configUrl);
      final raw = res.data;
      final Map<String, dynamic> data = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : Map<String, dynamic>.from(raw as Map);

      final model = (data['gemini_model'] as String?)?.trim();
      // Optional: the model's free-tier requests per day, for the usage
      // meter. A user's own limit, once learned from Google, wins over it.
      final rpd = (data['gemini_rpd'] as num?)?.toInt();
      final minBuild = (data['min_build'] as num?)?.toInt() ?? 0;
      if (model == null || model.isEmpty) return;

      // Only adopt a remote model this client is new enough to support.
      final buildNumber =
          int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
      if (buildNumber < minBuild) {
        debugPrint(
          'RemoteConfig: build $buildNumber < min_build $minBuild — keeping $_geminiModel.',
        );
        return;
      }

      _geminiModel = model;
      await prefs.setString(_prefKey, model);
      if (rpd != null) {
        await prefs.setInt(_rpdKey, rpd);
      } else {
        await prefs.remove(_rpdKey);
      }
      debugPrint('RemoteConfig: gemini_model = $model');
    } catch (e) {
      debugPrint('RemoteConfig fetch failed, using $_geminiModel: $e');
    }
  }
}
