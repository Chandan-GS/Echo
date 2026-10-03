import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/desktop/presentation/vault/vault_filter.dart';
import 'package:project_echo/features/desktop/presentation/vault/vault_table_parts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The desktop Vault: everything Echo heard on the phone as one table you
/// search and filter, with an entry's whole message in a panel beside it.
/// Reloads whenever the phone syncs.
class DesktopVaultTable extends StatefulWidget {
  /// Hands a question to Ask Echo ("What else did Neha say?").
  final void Function(String question)? onAsk;

  const DesktopVaultTable({super.key, this.onAsk});

  @override
  State<DesktopVaultTable> createState() => DesktopVaultTableState();
}

/// Public so the shell can reach [focusSearch] through a GlobalKey.
class DesktopVaultTableState extends State<DesktopVaultTable> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _tableFocus = FocusNode();
  final _scroll = ScrollController();

  /// Null until the first load.
  List<VaultItem>? _items;
  List<(String, RawData)> _apps = const [];
  List<VaultLine> _lines = const [];
  int? _thisWeek;
  VaultQuery _query = const VaultQuery();
  VaultItem? _open;

  /// Counts loads, so a slow one can't overwrite a newer one.
  int _loads = 0;

  /// App chips shown before the rest go under "More".
  static const _visibleApps = 5;

  @override
  void initState() {
    super.initState();
    EchoServerService.instance.syncTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    EchoServerService.instance.syncTick.removeListener(_load);
    _search.dispose();
    _searchFocus.dispose();
    _tableFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Puts the cursor in the search field, its text selected to type over.
  void focusSearch() {
    _searchFocus.requestFocus();
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
  }

  Future<void> _load() async {
    final load = ++_loads;
    List<RawData> entries;
    Map<String, String> aliases;
    List<String> blocked;
    try {
      entries = await IsarDataSource.getAllEntries();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      aliases = Map<String, String>.from(
        jsonDecode(prefs.getString('vault_category_aliases') ?? '{}'),
      );
      blocked = prefs.getStringList('vault_blocked_categories') ?? const [];
    } catch (e) {
      debugPrint('Desktop Vault failed to load: $e');
      if (mounted && _items == null) setState(() => _items = const []);
      return;
    }
    int? week;
    try {
      final days = await DailyStats.week(DateTime.now());
      week = days.fold<int>(0, (sum, d) => sum + d.total);
    } catch (_) {}
    if (!mounted || load != _loads) return;

    final items = [for (final e in entries) VaultItem(e, aliases: aliases)];
    final apps = vaultApps(items, blocked: blocked);
    setState(() {
      _items = items;
      _apps = apps;
      _thisWeek = week ?? _thisWeek;
      if (_query.app != null && !apps.any((a) => a.$1 == _query.app)) {
        _query = _query.copyWith(app: () => null);
      }
      _open = _open == null ? null : _sameAs(_open!, items);
      _lines = vaultLines(items, _query, DateTime.now());
    });
  }

  /// [open] in a fresh load: a sync replaces every entry, so it's matched
  /// by who, when and what rather than by id.
  static VaultItem? _sameAs(VaultItem open, List<VaultItem> items) {
    final a = open.entry;
    for (final item in items) {
      final b = item.entry;
      if (b.timestamp == a.timestamp &&
          b.sender == a.sender &&
          b.content == a.content) {
        return item;
      }
    }
    return null;
  }

  void _filter(VaultQuery query) {
    setState(() {
      _query = query;
      _lines = vaultLines(_items ?? const [], query, DateTime.now());
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _select(VaultItem item) {
    _tableFocus.requestFocus();
    setState(() => _open = item);
  }

  /// Esc closes the panel, then clears the search, then leaves it.
  void _escape() {
    if (_open != null) {
      setState(() => _open = null);
    } else if (_search.text.isNotEmpty) {
      _search.clear();
      _filter(_query.copyWith(text: ''));
    } else {
      _searchFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.background,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
        child: Focus(
          focusNode: _tableFocus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              _filters(context),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _table(context)),
                    _panel(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    final week = _thisWeek == null
        ? ''
        : ' ${groupedCount(_thisWeek!)} this week.';
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The Vault',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Everything Echo heard on your phone, searchable.$week',
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final c = context.colors;
    final q = _query;
    // The busiest apps as chips; the rest, unless one is picked, under More.
    final shown = <(String, RawData)>[];
    final more = <(String, RawData)>[];
    for (final (i, app) in _apps.indexed) {
      (i < _visibleApps || app.$1 == q.app ? shown : more).add(app);
    }
    Widget day(String label, VaultDay value) => VaultChip(
      label: label,
      selected: q.day == value,
      onTap: () =>
          _filter(q.copyWith(day: q.day == value ? VaultDay.any : value)),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.dividerColor)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _searchField(context),
          VaultChip(
            label: 'All apps',
            selected: q.app == null,
            onTap: () => _filter(q.copyWith(app: () => null)),
          ),
          for (final (app, sample) in shown)
            VaultChip(
              label: app,
              selected: q.app == app,
              leading: SourceBadge(sample, size: 18),
              onTap: () =>
                  _filter(q.copyWith(app: () => q.app == app ? null : app)),
            ),
          if (more.isNotEmpty) _moreApps(context, more),
          const VaultChipDivider(),
          VaultChip(
            label: 'For you only',
            selected: q.forYouOnly,
            onTap: () => _filter(q.copyWith(forYouOnly: !q.forYouOnly)),
          ),
          const VaultChipDivider(),
          day('Today', VaultDay.today),
          day('Yesterday', VaultDay.yesterday),
          day('This week', VaultDay.week),
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );
    return SizedBox(
      width: 320,
      height: 38,
      child: TextField(
        controller: _search,
        focusNode: _searchFocus,
        onChanged: (text) => _filter(_query.copyWith(text: text)),
        cursorColor: c.primaryGreen,
        style: GoogleFonts.nunito(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.surface,
          hintText: 'Search, or ask “what did Neha say about the demo”',
          hintMaxLines: 1,
          hintStyle: GoogleFonts.nunito(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: c.textSecondary,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: Icon(
            Symbols.search_rounded,
            size: 20,
            color: c.textSecondary,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  onPressed: () {
                    _search.clear();
                    _filter(_query.copyWith(text: ''));
                  },
                  icon: Icon(
                    Symbols.close_rounded,
                    size: 18,
                    color: c.textSecondary,
                  ),
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 36),
          enabledBorder: border(c.dividerColor),
          focusedBorder: border(c.primaryGreen, 1.5),
        ),
      ),
    );
  }

  Widget _moreApps(BuildContext context, List<(String, RawData)> apps) {
    final c = context.colors;
    return PopupMenuButton<String>(
      tooltip: '',
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.dividerColor),
      ),
      onSelected: (app) => _filter(_query.copyWith(app: () => app)),
      itemBuilder: (context) => [
        for (final (app, sample) in apps)
          PopupMenuItem(
            value: app,
            height: 40,
            child: Row(
              children: [
                SourceBadge(sample, size: 20),
                const SizedBox(width: 10),
                Text(
                  app,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: const VaultChip(
        label: 'More',
        selected: false,
        trailingIcon: Symbols.expand_more_rounded,
      ),
    );
  }

  Widget _table(BuildContext context) {
    final items = _items;
    if (items == null) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final now = DateTime.now();
    final lines = _lines;
    final shortcut = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘K'
        : 'Ctrl+K';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VaultColumnHeadings(),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            itemCount: lines.isEmpty ? 1 : lines.length,
            itemBuilder: (context, i) {
              if (lines.isEmpty) {
                return VaultNote(
                  items.isEmpty
                      ? 'Nothing from your phone yet.'
                      : 'Nothing matches. Press $shortcut to ask Echo instead.',
                );
              }
              return switch (lines[i]) {
                VaultDayLine line => VaultDayRow(line, now: now),
                VaultEntryLine(:final item) => VaultEntryRow(
                  item: item,
                  selected: identical(item, _open),
                  onTap: () => _select(item),
                ),
              };
            },
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final open = _open;
    return AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.emphasized,
      switchOutCurve: AppMotion.standard,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axis: Axis.horizontal,
        alignment: Alignment.centerLeft,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: open == null
          ? const SizedBox.shrink(key: ValueKey('closed'))
          : VaultDetailPanel(
              key: const ValueKey('open'),
              item: open,
              now: DateTime.now(),
              onClose: () => setState(() => _open = null),
              onAsk: widget.onAsk == null
                  ? null
                  : () => widget.onAsk!('What else did ${open.who} say?'),
              onOpenOnPhone: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opens on your phone')),
              ),
            ),
    );
  }
}
