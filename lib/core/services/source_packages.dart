import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which Android apps post under each Vault source, counted at ingest.
///
/// Stored as `{source: {package: notifications}}`, keyed by the source as
/// saved before the user's renames, so a renamed or merged category still
/// finds its apps through the aliases.
class SourcePackages {
  SourcePackages._();

  static const key = 'vault_source_packages';

  /// Package → launcher name, saved whenever the installed apps are listed
  /// (see InstalledApps), so categories captured before packages were
  /// recorded can still be matched by name.
  static const labelsKey = 'app_labels';

  /// Called at ingest for every notification.
  static Future<void> remember(String source, String? packageName) async {
    if (packageName == null || packageName.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // the background alarm isolate writes here too
      final all = decode(prefs.getString(key));
      final counts = all.putIfAbsent(source, () => {});
      counts[packageName] = (counts[packageName] ?? 0) + 1;
      await prefs.setString(key, jsonEncode(all));
    } catch (_) {}
  }

  /// Packages behind [category] (a Vault display name), with how often each
  /// posted. Falls back to an installed app with the same name.
  static Map<String, int> forCategory(
    String category, {
    required Map<String, Map<String, int>> sources,
    required Map<String, String> aliases,
    required Map<String, String> labels,
  }) {
    final want = normalise(category);
    final totals = <String, int>{};
    sources.forEach((source, packages) {
      final shown = aliases[source] ?? source;
      if (normalise(source) != want && normalise(shown) != want) return;
      packages.forEach((pkg, n) => totals[pkg] = (totals[pkg] ?? 0) + n);
    });
    if (totals.isEmpty) {
      labels.forEach((pkg, label) {
        if (normalise(label) == want) totals[pkg] = 0;
      });
    }
    return totals;
  }

  /// [forCategory], reading everything it needs from prefs.
  static Future<Map<String, int>> load(String category) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return forCategory(
      category,
      sources: decode(prefs.getString(key)),
      aliases: Map<String, String>.from(
        jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
      ),
      labels: decodeLabels(prefs.getString(labelsKey)),
    );
  }

  static String normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Map<String, Map<String, int>> decode(String? raw) {
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

  static Map<String, String> decodeLabels(String? raw) {
    try {
      return Map<String, String>.from(jsonDecode(raw ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }
}
