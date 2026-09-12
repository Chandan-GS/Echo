import 'package:flutter_tts/flutter_tts.dart';
import 'package:project_echo/features/onboarding/data/voice_preference.dart';

/// Discovers the English voices the current device can speak and maps an Echo
/// voice-slot × accent onto a concrete device speaker.
///
/// Each of the four voice slots takes a different device voice within the chosen
/// accent (by index over a stable, deduped, offline-preferred list), so the four
/// voices sound distinct. No gender logic — the voices are simply four different
/// speakers the device provides for that accent.
class VoiceCatalog {
  VoiceCatalog._();
  static final VoiceCatalog instance = VoiceCatalog._();

  /// Cached, normalized English voices: `{name, locale}`, offline "-local"
  /// variants only, excluding the generic `<locale>-language` alias.
  List<Map<String, String>>? _voices;

  Future<List<Map<String, String>>> _load(FlutterTts tts) async {
    if (_voices != null) return _voices!;
    try {
      final dynamic raw = await tts.getVoices;
      if (raw is List) {
        final all = raw
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
            .where((m) => (m['locale'] ?? '').toLowerCase().startsWith('en'))
            .toList();
        final local = all
            .where((m) => (m['name'] ?? '').toLowerCase().endsWith('-local'))
            .toList();
        _voices = local.isNotEmpty ? local : all;
      } else {
        _voices = const [];
      }
    } catch (_) {
      _voices = const [];
    }
    return _voices!;
  }

  /// Accents actually available on this device, in stable display order.
  Future<List<EchoAccent>> availableAccents(FlutterTts tts) async {
    final voices = await _load(tts);
    if (voices.isEmpty) return EchoAccent.values;
    final available = EchoAccent.values
        .where((a) => voices.any((v) => _localeMatches(v, a)))
        .toList();
    return available.isEmpty ? EchoAccent.values : available;
  }

  /// Resolves [pref] to a concrete device voice `{name, locale}`, or null when
  /// none exist (caller falls back to `setLanguage`).
  Future<Map<String, String>?> resolveVoice(
    FlutterTts tts,
    VoicePreference pref,
  ) async {
    final voices = await _load(tts);
    if (voices.isEmpty) return null;

    final inLocale = voices.where((v) => _localeMatches(v, pref.accent)).toList()
      ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    final pool = inLocale.isNotEmpty ? inLocale : voices;

    final pick = pool[pref.voice.voiceIndex % pool.length];
    final name = pick['name'];
    final locale = pick['locale'];
    if (name == null || locale == null) return null;
    return {'name': name, 'locale': locale};
  }

  bool _localeMatches(Map<String, String> v, EchoAccent accent) =>
      (v['locale'] ?? '').toLowerCase() == accent.localePrefix.toLowerCase();
}
