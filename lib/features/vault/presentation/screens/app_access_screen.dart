import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/services/source_packages.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:project_echo/features/vault/data/installed_apps.dart';
import 'package:project_echo/features/vault/presentation/widgets/app_access_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vault → Apps Echo hears: a switch for every app on the phone. Apps that
/// are off aren't captured, and what they already sent stays out of the
/// briefing, Ask Echo and the to-do list (it's still in the Vault).
class AppAccessScreen extends StatefulWidget {
  const AppAccessScreen({super.key});

  @override
  State<AppAccessScreen> createState() => _AppAccessScreenState();
}

class _AppAccessScreenState extends State<AppAccessScreen> {
  List<InstalledApp>? _apps;
  AppAccess _access = const AppAccess();

  /// Package → notifications in the last 7 days.
  Map<String, int> _week = const {};

  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Listing the apps also saves their names, which the week counts use to
    // match categories captured before packages were recorded.
    final apps = await InstalledApps.load();
    final access = await AppAccess.load();
    final week = await _weekCounts();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _access = access;
      _week = week;
    });
  }

  /// This week's Vault signals per app: each category's count goes to the
  /// busiest app behind it.
  static Future<Map<String, int>> _weekCounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final sources = SourcePackages.decode(prefs.getString(SourcePackages.key));
    final labels = SourcePackages.decodeLabels(
      prefs.getString(SourcePackages.labelsKey),
    );
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );

    // Only the sources of this week's signals — not whole entries, whose
    // 384-float embeddings would make this slow on a full Vault.
    final since = DateTime.now().subtract(const Duration(days: 7));
    final isar = await IsarDataSource.instance;
    final recent = await isar.rawDatas
        .filter()
        .timestampGreaterThan(since)
        .sourceProperty()
        .findAll();
    final perCategory = <String, int>{};
    for (final source in recent) {
      final name = displaySource(source, aliases);
      perCategory[name] = (perCategory[name] ?? 0) + 1;
    }

    final perApp = <String, int>{};
    perCategory.forEach((category, n) {
      final packages = SourcePackages.forCategory(
        category,
        sources: sources,
        aliases: aliases,
        labels: labels,
      );
      if (packages.isEmpty) return;
      final busiest = packages.entries
          .reduce((a, b) => b.value > a.value ? b : a)
          .key;
      perApp[busiest] = (perApp[busiest] ?? 0) + n;
    });
    return perApp;
  }

  Future<void> _toggle(InstalledApp app) async {
    final hear = !_access.hears(app.package);
    setState(() => _access = _access.withApps([app.package], hear));
    await _access.save();
    // Turning an app back on also lifts a Vault block on its category, so
    // there's one switch per app, not two.
    if (hear) await _unblockCategoriesOf(app.package);
  }

  static Future<void> _unblockCategoriesOf(String package) async {
    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs.getStringList('vault_blocked_categories') ?? [];
    if (blocked.isEmpty) return;
    final sources = SourcePackages.decode(prefs.getString(SourcePackages.key));
    final labels = SourcePackages.decodeLabels(
      prefs.getString(SourcePackages.labelsKey),
    );
    final aliases = Map<String, String>.from(
      jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
    );
    final remaining = blocked.where((category) {
      final packages = SourcePackages.forCategory(
        category,
        sources: sources,
        aliases: aliases,
        labels: labels,
      );
      return !packages.containsKey(package);
    }).toList();
    if (remaining.length != blocked.length) {
      await prefs.setStringList('vault_blocked_categories', remaining);
    }
  }

  Future<void> _toggleNewApps() async {
    final apps = _apps ?? const [];
    setState(() {
      _access = _access.withHearNewApps(
        !_access.hearNewApps,
        apps.map((a) => a.package),
      );
    });
    await _access.save();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final apps = _apps;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: const EchoAppBar(title: ''),
      body: apps == null
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _list(apps),
    );
  }

  Widget _list(List<InstalledApp> apps) {
    final colors = context.colors;
    final q = _query.trim().toLowerCase();
    final matches = apps.where((a) => a.label.toLowerCase().contains(q));
    final heard = matches.where((a) => (_week[a.package] ?? 0) > 0).toList()
      ..sort((a, b) => _week[b.package]!.compareTo(_week[a.package]!));
    final quiet = matches.where((a) => (_week[a.package] ?? 0) == 0).toList();
    final hearing = apps.where((a) => _access.hears(a.package)).length;

    // Built lazily: a phone can have a hundred-odd apps, each with an icon
    // to fetch from Android.
    final children = <Widget>[
      FadeSlideIn(
        child: Text(
          'Apps Echo hears',
          style: GoogleFonts.oldStandardTt(
            fontSize: 37,
            fontWeight: FontWeight.w700,
            height: 1.12,
            color: colors.textPrimary,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Echo only reads notifications from apps that are on. Turning one '
        'off also keeps what it already sent out of your briefings and Ask '
        'Echo.',
        style: GoogleFonts.nunito(
          fontSize: 16,
          height: 1.45,
          color: colors.textSecondary,
        ),
      ),
      const SizedBox(height: 18),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Hearing '),
            TextSpan(
              text: '$hearing',
              style: TextStyle(
                color: colors.primaryGreen,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: ' of ${apps.length} apps'),
          ],
        ),
        style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 16),
      AppSearchField(onChanged: (v) => setState(() => _query = v)),
      if (heard.isNotEmpty) ...[
        const AppSectionHeader('Heard from this week'),
        for (final (i, app) in heard.indexed)
          AppAccessRow(
            app: app,
            on: _access.hears(app.package),
            count: _week[app.package] ?? 0,
            last: i == heard.length - 1,
            onTap: () => _toggle(app),
          ),
      ],
      if (quiet.isNotEmpty) ...[
        const AppSectionHeader(
          'Nothing yet',
          subtitle: 'Installed, but no notifications this week.',
        ),
        for (final (i, app) in quiet.indexed)
          AppAccessRow(
            app: app,
            on: _access.hears(app.package),
            count: 0,
            last: i == quiet.length - 1,
            onTap: () => _toggle(app),
          ),
      ],
      if (heard.isEmpty && quiet.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              apps.isEmpty ? 'No apps found.' : 'No app called that.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      const SizedBox(height: 28),
      NewAppsCard(on: _access.hearNewApps, onTap: _toggleNewApps),
    ];
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      itemCount: children.length,
      itemBuilder: (context, i) => children[i],
    );
  }
}
