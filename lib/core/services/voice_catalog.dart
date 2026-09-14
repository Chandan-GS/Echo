import 'package:flutter/foundation.dart';
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

  /// macOS/iOS's AVSpeechSynthesizer mixes several categorically robotic-
  /// sounding voice *families* into the exact same locale pool as its normal
  /// narration voices — confirmed live: on a stock Mac, the en-US pool is
  /// Samantha (normal) plus EIGHT "Eloquence" voices (Eddy, Flo, Grandma,
  /// Grandpa, Reed, Rocko, Sandy, Shelley), so index-based selection almost
  /// always lands on one of the robotic ones. Rather than an incomplete
  /// name denylist, exclude by *identifier prefix* — Apple tags each voice's
  /// engine family right there (`com.apple.eloquence.*` is the legacy
  /// low-quality synthesis engine; `com.apple.speech.synthesis.voice.*` is
  /// the even older novelty engine — Zarvox, Bubbles, Bad News, etc). Only
  /// `com.apple.voice.*` (compact/super-compact/premium) are normal,
  /// pleasant narration voices.
  static const _excludedIdentifierPrefixes = [
    'com.apple.eloquence.',
    'com.apple.speech.synthesis.voice.',
  ];

  /// Drops the cached voice list so the next query re-reads from the device.
  /// Call this after the user has (potentially) installed a new system voice
  /// in System Settings, so a "Rescan" picks it up without an app relaunch.
  void invalidate() => _voices = null;

  Future<List<Map<String, String>>> _load(FlutterTts tts) async {
    if (_voices != null) return _voices!;
    try {
      final dynamic raw = await tts.getVoices;
      debugPrint('VoiceCatalog: raw device voices = $raw');
      if (raw is List) {
        final all = raw
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
            .where((m) => (m['locale'] ?? '').toLowerCase().startsWith('en'))
            .where((m) {
              final id = (m['identifier'] ?? '').toLowerCase();
              // No identifier at all (e.g. Android) — nothing to exclude by.
              if (id.isEmpty) return true;
              return !_excludedIdentifierPrefixes.any(id.startsWith);
            })
            .toList();
        final local = all
            .where((m) => (m['name'] ?? '').toLowerCase().endsWith('-local'))
            .toList();
        _voices = local.isNotEmpty ? local : all;
      } else {
        _voices = const [];
      }
    } catch (e) {
      debugPrint('VoiceCatalog: getVoices failed: $e');
      _voices = const [];
    }
    debugPrint('VoiceCatalog: usable English voices = $_voices');
    return _voices!;
  }

  /// Whether at least one genuinely natural (Enhanced/Premium tier) voice is
  /// installed — Apple ships every voice at "default" quality out of the box,
  /// so on a stock system this is false until the user downloads a better one
  /// via System Settings. Callers use this to decide whether to nudge the
  /// user toward installing one, rather than showing that hint unconditionally.
  Future<bool> hasHighQualityVoice(FlutterTts tts) async {
    final voices = await _load(tts);
    return voices.any((v) {
      final q = (v['quality'] ?? '').toLowerCase();
      return q == 'enhanced' || q == 'premium';
    });
  }

  /// All usable installed voices (already filtered to exclude the robotic
  /// families), sorted best-quality-first then alphabetically — used by
  /// desktop's direct voice picker, which shows the user exactly what's on
  /// their system rather than the phone's abstract slot × accent naming.
  Future<List<Map<String, String>>> listInstalledVoices(FlutterTts tts) async {
    final voices = await _load(tts);
    final sorted = [...voices];
    sorted.sort((a, b) {
      final q = _qualityRank(a).compareTo(_qualityRank(b));
      return q != 0 ? q : (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    return sorted;
  }

  int _qualityRank(Map<String, String> v) =>
      switch ((v['quality'] ?? '').toLowerCase()) {
        'premium' => 0,
        'enhanced' => 1,
        _ => 2,
      };

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

    // Apple ships every voice at "default" quality unless the user has
    // separately downloaded better ones via System Settings > Accessibility
    // > Spoken Content > System Voice (there they're labelled "Enhanced" /
    // "Premium" — genuinely natural neural voices, just not bundled by
    // default). If any are installed, prefer them over the default tier.
    int qualityRank(Map<String, String> v) => switch ((v['quality'] ?? '')
        .toLowerCase()) {
      'premium' => 0,
      'enhanced' => 1,
      _ => 2,
    };
    int byQualityThenName(Map<String, String> a, Map<String, String> b) {
      final q = qualityRank(a).compareTo(qualityRank(b));
      return q != 0 ? q : (a['name'] ?? '').compareTo(b['name'] ?? '');
    }

    final inLocale = voices.where((v) => _localeMatches(v, pref.accent)).toList()
      ..sort(byQualityThenName);
    // Stay strictly within the chosen accent, even if that means several
    // slots repeat the same voice — a mismatched accent (e.g. an Indian
    // voice under "American") is worse than fewer distinct voices. A stock
    // Mac often really does have just one good voice per English accent.
    final pool = inLocale.isNotEmpty ? inLocale : voices;

    final pick = pool[pref.voice.voiceIndex % pool.length];
    final name = pick['name'];
    final locale = pick['locale'];
    debugPrint(
      'VoiceCatalog: slot=${pref.voice.label} accent=${pref.accent.label} '
      '-> picked name="$name" locale="$locale" (pool size ${pool.length}, '
      'in-locale matches ${inLocale.length})',
    );
    if (name == null || locale == null) return null;
    return {'name': name, 'locale': locale};
  }

  // Normalizes both sides ("en_US" vs "en-US", case) before comparing — some
  // platforms/flutter_tts versions report locale with an underscore rather
  // than the hyphenated BCP-47 form our EchoAccent.localePrefix uses. Without
  // this, matches silently fail and every accent falls back to the full,
  // unfiltered voice pool (any English accent, not just the chosen one).
  bool _localeMatches(Map<String, String> v, EchoAccent accent) =>
      _normalizeLocale(v['locale']) == _normalizeLocale(accent.localePrefix);

  String _normalizeLocale(String? locale) =>
      (locale ?? '').toLowerCase().replaceAll('_', '-');
}
