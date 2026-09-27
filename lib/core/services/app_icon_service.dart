import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:project_echo/core/services/source_packages.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real launcher icons of other apps, for Vault categories and for the app
/// list in Apps Echo hears.
///
/// On Android they're drawn on demand. A computer can't read them, so the
/// phone sends each category's icon with its sync (see [storeSynced]).
/// Either way they're kept in memory for the session.
class AppIconService {
  AppIconService._();

  static const _channel = MethodChannel('project_echo/app_icons');

  /// Drawn once at ~48dp @3x and scaled down wherever it's shown.
  static const _sizePx = 144;

  static final Map<String, Uint8List?> _resolved = {};
  static final Map<String, Future<Uint8List?>> _pending = {};

  static bool get _desktop => Platform.isMacOS || Platform.isWindows;
  static bool get supported => Platform.isAndroid || _desktop;

  /// Category → base64 PNG, as last synced from the phone (desktop only).
  static const _syncedKey = 'synced_app_icons';

  static String _sourceKey(String source) =>
      'source:${source.trim().toLowerCase()}';
  static String _packageKey(String pkg) => 'package:$pkg';

  /// Whether [source]'s icon has been looked up, so a rebuild can paint it
  /// straight away instead of waiting a frame on the future.
  static bool isResolved(String source) =>
      !supported || _resolved.containsKey(_sourceKey(source));

  static Uint8List? cached(String source) => _resolved[_sourceKey(source)];

  static bool isPackageResolved(String pkg) =>
      !supported || _resolved.containsKey(_packageKey(pkg));

  static Uint8List? cachedPackage(String pkg) => _resolved[_packageKey(pkg)];

  /// PNG of the busiest app behind the Vault category [source], or null.
  static Future<Uint8List?> iconFor(String source) => _desktop
      ? _synced(source)
      : _lookUp(_sourceKey(source), () async {
          final packages = await SourcePackages.load(source);
          final busiest = packages.isEmpty
              ? null
              : packages.entries
                    .reduce((a, b) => b.value > a.value ? b : a)
                    .key;
          return {'package': busiest, 'label': source.trim()};
        });

  /// PNG of the app [pkg]'s icon, or null when it isn't installed.
  static Future<Uint8List?> iconForPackage(String pkg) => _desktop
      ? Future.value(null)
      : _lookUp(_packageKey(pkg), () async => {'package': pkg});

  /// Desktop: the icon the phone synced for [source], if any. A miss isn't
  /// cached — the phone may send it on its next sync.
  static Future<Uint8List?> _synced(String source) async {
    final key = _sourceKey(source);
    if (_resolved.containsKey(key)) return _resolved[key];
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = jsonDecode(prefs.getString(_syncedKey) ?? '{}') as Map;
      for (final e in map.entries) {
        if (_sourceKey(e.key as String) == key) {
          return _resolved[key] = base64Decode(e.value as String);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Desktop: keeps icons the phone sent, dropping cached lookups for them
  /// so a new icon shows.
  static Future<void> storeSynced(Map<String, dynamic> icons) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(_syncedKey) ?? '{}') as Map,
      );
    } catch (_) {
      map = {};
    }
    map.addAll(icons);
    await prefs.setString(_syncedKey, jsonEncode(map));
    for (final source in icons.keys) {
      _resolved.remove(_sourceKey(source));
    }
  }

  static Future<Uint8List?> _lookUp(
    String key,
    Future<Map<String, Object?>> Function() args,
  ) {
    if (!supported) return Future.value(null);
    if (_resolved.containsKey(key)) return Future.value(_resolved[key]);
    return _pending.putIfAbsent(key, () async {
      Uint8List? png;
      try {
        png = await _channel.invokeMethod<Uint8List>('icon', {
          ...await args(),
          'size': _sizePx,
        });
      } catch (_) {}
      _resolved[key] = png;
      _pending.remove(key);
      return png;
    });
  }

  /// Called at ingest for every notification: records the app behind
  /// [source], and lets a category that had no icon yet try again.
  static Future<void> remember(String source, String? packageName) async {
    if (!Platform.isAndroid || packageName == null || packageName.isEmpty) {
      return;
    }
    await SourcePackages.remember(source, packageName);
    final key = _sourceKey(source);
    if (_resolved.containsKey(key) && _resolved[key] == null) {
      _resolved.remove(key);
    }
  }
}
