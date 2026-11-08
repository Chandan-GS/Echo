import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:project_echo/core/services/source_packages.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _whitespace = RegExp(
  '[\\t-\\r \\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]+',
);

/// Trimmed, whitespace collapsed, lowercased. Must stay the same as
/// PhotoRules.normalise in PersonPhotos.kt. Only Latin, Greek and Cyrillic
/// capitals are lowered: Dart and Android's case tables differ elsewhere, and
/// a mismatch here would lose someone's picture.
String normalisePhotoText(String s) {
  var text = s.replaceAll(_whitespace, ' ');
  if (text.startsWith(' ')) text = text.substring(1);
  if (text.endsWith(' ')) text = text.substring(0, text.length - 1);
  final out = StringBuffer();
  for (final r in text.runes) {
    out.writeCharCode(
      _lowered(r) ? String.fromCharCode(r).toLowerCase().runes.first : r,
    );
  }
  return out.toString();
}

bool _lowered(int r) =>
    (r >= 0x41 && r <= 0x24F) ||
    (r >= 0x391 && r <= 0x3A9) ||
    (r >= 0x400 && r <= 0x42F);

/// The name a profile picture is filed under on the phone, or null when
/// [name] can't name one person: empty, or a "Sender · Group" line.
///
/// Must stay the same as PhotoRules.photoKey in PersonPhotos.kt; both are
/// pinned to test/fixtures/photo_key_vectors.json. FNV-1a over UTF-8, as 16
/// hex digits.
String? photoKey(String name, String source) {
  final n = normalisePhotoText(name);
  final s = normalisePhotoText(source);
  if (n.isEmpty || s.isEmpty || n.contains(' · ')) return null;
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode('$s\u0000$n')) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  final high = (hash >>> 32).toRadixString(16).padLeft(8, '0');
  final low = (hash & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}

/// Every key [name] may be filed under. The listener files a picture under
/// the app's own source, but [source] may be the category the owner renamed
/// or merged it into, so the sources behind that name come first.
List<String> photoKeysFor(
  String name,
  String source,
  Map<String, String> aliases,
) {
  final want = normalisePhotoText(source);
  final behind =
      aliases.entries
          .where((e) => normalisePhotoText(e.value) == want)
          .map((e) => e.key)
          .toList()
        ..sort();
  final keys = <String>[];
  for (final s in [...behind, source]) {
    final key = photoKey(name, s);
    if (key != null && !keys.contains(key)) keys.add(key);
  }
  return keys;
}

enum PhotoChoice { auto, chosen, initials }

/// What to show for someone: the file, if any, and why.
@immutable
class PersonPhoto {
  /// A file in the app's private storage. Null means initials.
  final String? path;
  final PhotoChoice choice;

  /// Whether a notification's picture is on file, chosen over or not.
  final bool hasDp;

  const PersonPhoto({
    this.path,
    this.choice = PhotoChoice.auto,
    this.hasDp = false,
  });

  static const none = PersonPhoto();

  factory PersonPhoto.fromWire(Map<Object?, Object?> wire) => PersonPhoto(
    path: wire['path'] as String?,
    choice: switch (wire['choice']) {
      'chosen' => PhotoChoice.chosen,
      'initials' => PhotoChoice.initials,
      _ => PhotoChoice.auto,
    },
    hasDp: wire['hasDp'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is PersonPhoto &&
      other.path == path &&
      other.choice == choice &&
      other.hasDp == hasDp;

  @override
  int get hashCode => Object.hash(path, choice, hasDp);
}

class _Slot extends ValueNotifier<PersonPhoto> {
  final String name;
  final String source;
  List<String> keys = const [];
  DateTime? resolvedAt;

  _Slot(this.name, this.source) : super(PersonPhoto.none);
}

/// How picking a photo went, for the sheet to say so.
enum PickOutcome { ok, cancel, unreadable, busy, unavailable }

/// Profile pictures for people and groups: what the notifications carry, or
/// what the owner chose instead. Only ever on the phone; nothing here is part
/// of phone-to-desktop sync, and on a computer everyone gets initials.
///
/// Native side: PersonPhotos.kt.
class PersonPhotos {
  PersonPhotos._();

  static const _channel = MethodChannel('project_echo/person_photos');

  /// A re-check on rebuild after this long catches a rename of the app's
  /// category. New pictures don't wait for it: the phone announces them.
  static const _stale = Duration(minutes: 10);
  static const _aliasesFresh = Duration(seconds: 30);

  /// Sent to the phone at a time so a first paint of a long list stays cheap.
  static const _batch = 64;

  static final Map<String, _Slot> _slots = {};
  static final Set<String> _queued = {};
  static final ValueNotifier<PersonPhoto> _nothing = ValueNotifier(
    PersonPhoto.none,
  );
  static final Map<String, Set<int>> _painted = {};

  static bool _flushing = false;
  static bool _listening = false;
  static Map<String, String> _aliases = const {};
  static DateTime? _aliasesAt;

  @visibleForTesting
  static bool? debugSupported;

  static bool get supported => debugSupported ?? Platform.isAndroid;

  /// [name]'s photo as it's known, updating when it changes. Safe in build:
  /// asking the phone happens later, and a person with no key is initials.
  static ValueListenable<PersonPhoto> watch(String name, String? source) {
    if (!supported || source == null || photoKey(name, source) == null) {
      return _nothing;
    }
    final id = '${normalisePhotoText(source)}\u0000${normalisePhotoText(name)}';
    final slot = _slots.putIfAbsent(id, () => _Slot(name, source));
    final at = slot.resolvedAt;
    if (at == null || DateTime.now().difference(at) > _stale) _enqueue(id);
    return slot;
  }

  /// An image provider for [path], decoded no larger than [cacheWidth] pixels.
  static ImageProvider providerFor(String path, int cacheWidth) {
    (_painted[path] ??= {}).add(cacheWidth);
    return ResizeImage(FileImage(File(path)), width: cacheWidth);
  }

  static void _evict(String path) {
    final widths = _painted.remove(path);
    if (widths == null) return;
    final file = FileImage(File(path));
    for (final width in widths) {
      unawaited(ResizeImage(file, width: width).evict());
    }
  }

  static void _enqueue(String id) {
    _queued.add(id);
    _listen();
    if (_flushing) return;
    _flushing = true;
    // After this frame's widgets have all asked, in one go.
    Timer(Duration.zero, _flush);
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'changed') return;
      final keys = Set<String>.from(call.arguments as List);
      _slots.forEach((id, slot) {
        if (slot.keys.any(keys.contains)) _enqueue(id);
      });
    });
  }

  static Future<void> _flush() async {
    try {
      final aliases = await _loadAliases();
      while (_queued.isNotEmpty) {
        final ids = _queued.take(_batch).toList();
        _queued.removeAll(ids);
        final items = [
          for (final id in ids)
            {
              'id': id,
              'keys': _slots[id]!.keys = photoKeysFor(
                _slots[id]!.name,
                _slots[id]!.source,
                aliases,
              ),
            },
        ];
        final answers = await _channel.invokeMapMethod<String, Object?>(
          'resolveAll',
          {'items': items},
        );
        final now = DateTime.now();
        for (final id in ids) {
          final slot = _slots[id]!;
          slot.resolvedAt = now;
          final wire = answers?[id];
          if (wire is Map) _apply(slot, PersonPhoto.fromWire(wire));
        }
      }
    } catch (e) {
      // Initials stay up. The next rebuild after [_stale], or the next
      // announced change, asks again.
      debugPrint('PersonPhotos: $e');
      _queued.clear();
    } finally {
      _flushing = false;
      if (_queued.isNotEmpty) {
        _flushing = true;
        Timer(Duration.zero, _flush);
      }
    }
  }

  static void _apply(_Slot slot, PersonPhoto next) {
    final before = slot.value.path;
    if (before != null && before != next.path) _evict(before);
    slot.value = next;
  }

  static Future<Map<String, String>> _loadAliases() async {
    final at = _aliasesAt;
    if (at != null && DateTime.now().difference(at) < _aliasesFresh) {
      return _aliases;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _aliases = Map<String, String>.from(
        jsonDecode(prefs.getString('vault_category_aliases') ?? '{}') as Map,
      );
    } catch (_) {
      _aliases = const {};
    }
    _aliasesAt = DateTime.now();
    return _aliases;
  }

  /// What [name] shows right now, asked fresh, for the sheet.
  static Future<PersonPhoto> load(String name, String source) async {
    if (!supported) return PersonPhoto.none;
    final keys = photoKeysFor(name, source, await _loadAliases());
    if (keys.isEmpty) return PersonPhoto.none;
    try {
      final answers = await _channel.invokeMapMethod<String, Object?>(
        'resolveAll',
        {
          'items': [
            {'id': 'sheet', 'keys': keys},
          ],
        },
      );
      final wire = answers?['sheet'];
      return wire is Map ? PersonPhoto.fromWire(wire) : PersonPhoto.none;
    } catch (_) {
      return PersonPhoto.none;
    }
  }

  /// Opens the system photo picker and keeps a copy of what's picked. Needs
  /// no permission; the phone copies and shrinks it before answering.
  static Future<PickOutcome> choose(String name, String source) async {
    if (!supported) return PickOutcome.unavailable;
    final keys = photoKeysFor(name, source, await _loadAliases());
    if (keys.isEmpty) return PickOutcome.unreadable;
    try {
      final outcome = await _channel.invokeMethod<String>('choose', {
        'keys': keys,
        'package': await _packageFor(source),
      });
      return PickOutcome.values.firstWhere(
        (o) => o.name == outcome,
        orElse: () => PickOutcome.unreadable,
      );
    } catch (_) {
      return PickOutcome.unavailable;
    }
  }

  /// Keeps [name] on initials, whatever the notifications carry.
  static Future<bool> useInitials(String name, String source) async {
    if (!supported) return false;
    final keys = photoKeysFor(name, source, await _loadAliases());
    if (keys.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('useInitials', {
            'keys': keys,
            'package': await _packageFor(source),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Forgets the owner's choice, so the notification's picture shows again.
  static Future<bool> reset(String name, String source) async {
    if (!supported) return false;
    final keys = photoKeysFor(name, source, await _loadAliases());
    if (keys.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('reset', {'keys': keys}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// The busiest app behind [source], so a choice is deleted with that app
  /// if it's ever switched off.
  static Future<String?> _packageFor(String source) async {
    try {
      final packages = await SourcePackages.load(source);
      if (packages.isEmpty) return null;
      return packages.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void debugReset() {
    _slots.clear();
    _queued.clear();
    _painted.clear();
    _flushing = false;
    _listening = false;
    _aliases = const {};
    _aliasesAt = null;
  }
}
