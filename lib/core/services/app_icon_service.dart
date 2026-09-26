import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The real launcher icon of the app behind each Vault category (Android only).
///
/// Ingest records which packages post under each source; the icon itself is
/// drawn by Android on demand and kept in memory for the session.
class AppIconService {
  AppIconService._();

  static const _channel = MethodChannel('project_echo/app_icons');

  /// Source (as saved at ingest, before aliases) → {package: notifications}.
  static const _packagesKey = 'vault_source_packages';

  /// Drawn once at ~48dp @3x and scaled down wherever it's shown.
  static const _sizePx = 144;

  static final Map<String, Uint8List?> _resolved = {};
  static final Map<String, Future<Uint8List?>> _pending = {};

  static bool get supported => Platform.isAndroid;

  static String _key(String source) => source.trim().toLowerCase();

  /// Whether [source]'s icon has been looked up, so a rebuild can paint it
  /// straight away instead of waiting a frame on the future.
  static bool isResolved(String source) =>
      !supported || _resolved.containsKey(_key(source));

  static Uint8List? cached(String source) => _resolved[_key(source)];

  /// PNG bytes of [source]'s app icon, or null when there isn't one to show.
  static Future<Uint8List?> iconFor(String source) {
    if (!supported) return Future.value(null);
    final key = _key(source);
    if (_resolved.containsKey(key)) return Future.value(_resolved[key]);
    return _pending.putIfAbsent(key, () async {
      Uint8List? png;
      try {
        png = await _channel.invokeMethod<Uint8List>('icon', {
          'package': await _packageFor(source),
          'label': source.trim(),
          'size': _sizePx,
        });
      } catch (_) {}
      _resolved[key] = png;
      _pending.remove(key);
      return png;
    });
  }

  /// Called at ingest for every notification: counts [packageName] under
  /// [source] so a category merging several apps shows its busiest one.
  static Future<void> remember(String source, String? packageName) async {
    if (!supported || packageName == null || packageName.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // the background alarm isolate writes here too
      final all = _decode(prefs.getString(_packagesKey));
      final counts = all.putIfAbsent(source, () => {});
      counts[packageName] = (counts[packageName] ?? 0) + 1;
      await prefs.setString(_packagesKey, jsonEncode(all));
      // A category that had no icon yet may have one now.
      final key = _key(source);
      if (_resolved.containsKey(key) && _resolved[key] == null) {
        _resolved.remove(key);
      }
    } catch (_) {}
  }

  static Future<String?> _packageFor(String category) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    final want = _key(category);
    final totals = <String, int>{};
    _decode(prefs.getString(_packagesKey)).forEach((source, packages) {
      final shown = aliases[source] ?? source;
      if (_key(source) != want && _key(shown) != want) return;
      packages.forEach((pkg, n) => totals[pkg] = (totals[pkg] ?? 0) + n);
    });
    if (totals.isEmpty) return null;
    return totals.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static Map<String, Map<String, int>> _decode(String? raw) {
    try {
      final map = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      return map.map(
        (source, packages) => MapEntry(
          source,
          Map<String, int>.from(packages as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return {};
    }
  }
}
