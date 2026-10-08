import 'dart:convert';

import 'package:project_echo/core/services/source_packages.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which apps Echo hears (Android), set in Vault → Apps Echo hears and in
/// onboarding. The native listener reads the same prefs value
/// (AppAccessRules.kt) and drops notifications from apps that are off.
class AppAccess {
  static const key = 'app_access';

  /// Whether an app nobody has decided on yet (e.g. installed later) is heard.
  final bool hearNewApps;

  /// Apps explicitly on / off; everything else follows [hearNewApps].
  final Set<String> on;
  final Set<String> off;

  const AppAccess({
    this.hearNewApps = true,
    this.on = const {},
    this.off = const {},
  });

  bool hears(String pkg) {
    if (off.contains(pkg)) return false;
    if (on.contains(pkg)) return true;
    return hearNewApps;
  }

  AppAccess withApps(Iterable<String> packages, bool hear) {
    final nextOn = {...on};
    final nextOff = {...off};
    for (final pkg in packages) {
      if (hear) {
        nextOff.remove(pkg);
        nextOn.add(pkg);
      } else {
        nextOn.remove(pkg);
        nextOff.add(pkg);
      }
    }
    return AppAccess(hearNewApps: hearNewApps, on: nextOn, off: nextOff);
  }

  /// Turning automatic hearing off keeps every [installed] app as it is now,
  /// so only apps installed later start off.
  AppAccess withHearNewApps(bool value, Iterable<String> installed) {
    if (value) return AppAccess(hearNewApps: true, on: on, off: off);
    return AppAccess(
      hearNewApps: false,
      on: {...on, ...installed.where((pkg) => !off.contains(pkg))},
      off: off,
    );
  }

  Map<String, dynamic> toJson() => {
    'hearNewApps': hearNewApps,
    'on': on.toList()..sort(),
    'off': off.toList()..sort(),
  };

  factory AppAccess.fromJson(String? raw) {
    try {
      final json = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      return AppAccess(
        hearNewApps: json['hearNewApps'] as bool? ?? true,
        on: Set<String>.from(json['on'] as List? ?? const []),
        off: Set<String>.from(json['off'] as List? ?? const []),
      );
    } catch (_) {
      return const AppAccess();
    }
  }

  static Future<AppAccess> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return AppAccess.fromJson(prefs.getString(key));
  }

  /// Whether the user has chosen anything yet (onboarding or the Vault page).
  static Future<bool> isChosen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(toJson()));
  }
}

/// The Vault categories kept out of briefings, Ask Echo and the to-do list:
/// the ones the user blocked, and the ones whose every app is switched off.
/// A switched-off app's signals stay in the Vault; they're just not context.
Set<String> excludedSources({
  required AppAccess access,
  required Map<String, Map<String, int>> sources,
  required Map<String, String> aliases,
  required Map<String, String> labels,
  Iterable<String> blocked = const [],
}) {
  final out = {...blocked};
  sources.forEach((source, packages) {
    if (packages.isNotEmpty && packages.keys.every((p) => !access.hears(p))) {
      out.add(displaySource(source, aliases));
    }
  });
  // Categories captured before packages were recorded, matched by app name.
  final recorded = sources.keys.map(SourcePackages.normalise).toSet();
  labels.forEach((pkg, label) {
    if (access.hears(pkg)) return;
    if (recorded.contains(SourcePackages.normalise(label))) return;
    out.add(displaySource(label, aliases));
  });
  return out;
}

/// [excludedSources], reading everything it needs from prefs. Safe in the
/// background briefing isolate (no platform channels).
Future<Set<String>> loadExcludedSources() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return excludedSources(
    access: AppAccess.fromJson(prefs.getString(AppAccess.key)),
    sources: SourcePackages.decode(prefs.getString(SourcePackages.key)),
    aliases: Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    ),
    labels: SourcePackages.decodeLabels(
      prefs.getString(SourcePackages.labelsKey),
    ),
    blocked: prefs.getStringList('vault_blocked_categories') ?? const [],
  );
}

/// [entries] minus the ones in [loadExcludedSources]' categories.
Future<List<RawData>> withoutExcludedSources(List<RawData> entries) async {
  final excluded = await loadExcludedSources();
  if (excluded.isEmpty) return entries;
  final prefs = await SharedPreferences.getInstance();
  final aliases = Map<String, String>.from(
    jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
  );
  return entries
      .where((e) => !excluded.contains(displaySource(e.source, aliases)))
      .toList();
}
