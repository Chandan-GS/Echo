import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/nav_dock.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/history/data/history_store.dart';
import 'package:project_echo/features/history/presentation/widgets/history_item_sheet.dart';
import 'package:project_echo/features/history/presentation/widgets/history_parts.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;

/// Every notification Echo heard: searchable as you type, filterable, with
/// what was swiped away on a shelf of its own.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  static const _permissions = MethodChannel('project_echo/permissions');

  final _search = TextEditingController();
  final _focus = FocusNode();

  String _chip = HistoryStore.all;
  String _text = '';
  HistoryShape _shape = HistoryShape.empty;
  List<RawData> _shelf = const [];
  int _days = RetentionSettings.defaultDays;
  bool _loaded = false;
  bool _listening = true;

  /// Pages of messages read so far, by page number.
  Map<int, List<RawData>> _pages = {};
  final _loadingPages = <int>{};
  int _lastPage = 0;

  /// Bumped by every new load, so a slower, older one can't overwrite it.
  int _generation = 0;

  Timer? _debounce;
  Timer? _midnight;
  StreamSubscription<void>? _changes;
  Timer? _changeDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _load();
    _watch();
    _scheduleMidnight();
    _checkListening();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _midnight?.cancel();
    _changeDebounce?.cancel();
    _changes?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkListening();
    _load(keepPages: true);
    _scheduleMidnight();
  }

  Future<void> _watch() async {
    try {
      final isar = await IsarDataSource.instance;
      if (!mounted) return;
      _changes = isar.rawDatas.watchLazy().listen((_) {
        _changeDebounce?.cancel();
        _changeDebounce = Timer(
          const Duration(milliseconds: 500),
          () => _load(keepPages: true),
        );
      });
    } catch (e) {
      debugPrint('History could not watch for changes: $e');
    }
  }

  /// "Today" changes at midnight, whether or not anything new arrives.
  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _load(keepPages: true);
      _scheduleMidnight();
    });
  }

  Future<void> _checkListening() async {
    bool? allowed;
    try {
      allowed = await _permissions.invokeMethod<bool>(
        'checkNotificationPermission',
      );
    } catch (_) {
      allowed = true; // desktop builds have no such thing to ask
    }
    if (mounted) setState(() => _listening = allowed ?? true);
  }

  void _onSearchChanged() {
    final value = _search.text;
    if (value == _text) return;
    setState(() => _text = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), _load);
  }

  void _selectChip(String id) {
    if (id == _chip) return;
    setState(() => _chip = id);
    _load();
  }

  /// Reads the list's shape and its first page. With [keepPages] what's on
  /// screen is re-read and swapped in at once, so a new notification arriving
  /// doesn't blank the list.
  Future<void> _load({bool keepPages = false}) async {
    final generation = ++_generation;
    final chip = _chip;
    final text = _text;
    try {
      final now = DateTime.now();
      final shape = await HistoryStore.shape(chip, text);
      final shelf = await HistoryStore.recentlySwiped(now);
      final days = await RetentionSettings.days();
      final wanted = keepPages
          ? {for (var p = _lastPage - 2; p <= _lastPage + 2; p++) p}
                .where((p) => p >= 0)
                .toSet()
          : {0};
      final pages = <int, List<RawData>>{};
      for (final p in wanted) {
        if (p * HistoryStore.pageSize >= shape.total && p != 0) continue;
        pages[p] = await HistoryStore.page(
          chip,
          text,
          p * HistoryStore.pageSize,
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _shape = shape;
        _shelf = shelf;
        _days = days;
        _pages = pages;
        _loadingPages.clear();
        _loaded = true;
      });
    } catch (e) {
      debugPrint('Loading history failed: $e');
      if (mounted && generation == _generation) {
        setState(() => _loaded = true);
      }
    }
  }

  RawData? _itemAt(int index) {
    final page = index ~/ HistoryStore.pageSize;
    _lastPage = page;
    final rows = _pages[page];
    if (rows == null) {
      _loadPage(page);
      return null;
    }
    final at = index % HistoryStore.pageSize;
    return at < rows.length ? rows[at] : null;
  }

  Future<void> _loadPage(int page) async {
    if (!_loadingPages.add(page)) return;
    final generation = _generation;
    try {
      final rows = await HistoryStore.page(
        _chip,
        _text,
        page * HistoryStore.pageSize,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _pages[page] = rows);
    } catch (e) {
      debugPrint('Loading a page of history failed: $e');
    } finally {
      _loadingPages.remove(page);
    }
  }

  String get _keepText => _days == 1 ? '1 day' : '$_days days';

  void _ask(String question) =>
      context.push('/echo/chat', extra: question);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final words = HistoryStore.tokens(_text);
    final raw = _text.trim();
    final now = DateTime.now();
    final showShelf =
        words.isEmpty && _chip == HistoryStore.all && _shelf.isNotEmpty;
    final days = _shape.days;
    final rowCount = _shape.total + days.length;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focus.unfocus(),
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              SliverToBoxAdapter(
                child: FadeSlideIn(
                  delay: AppMotion.stagger * 2,
                  child: _searchBox(context, raw),
                ),
              ),
              SliverToBoxAdapter(child: _chips(context)),
              SliverToBoxAdapter(child: _askRow(context, raw)),
              if (showShelf) SliverToBoxAdapter(child: _shelfView(context, now)),
              if (!_listening && !_shape.anything)
                SliverToBoxAdapter(child: _noListener(context))
              else if (_loaded && _shape.total == 0)
                SliverToBoxAdapter(child: _empty(context, raw))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList.builder(
                    itemCount: rowCount,
                    itemBuilder: (context, index) =>
                        _row(context, index, days, words, now),
                  ),
                ),
              SliverToBoxAdapter(child: _footer(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    int index,
    List<HistoryDay> days,
    List<String> words,
    DateTime now,
  ) {
    // Each day's heading sits before its messages; walk to the one this is.
    var headersBefore = 0;
    for (final day in days) {
      final headerAt = day.firstIndex + headersBefore;
      if (index == headerAt) return _dayHeading(context, day, now);
      if (index < headerAt) break;
      headersBefore++;
    }
    final item = _itemAt(index - headersBefore);
    if (item == null) return const SizedBox(height: 112);
    return HistoryCard(
      key: ValueKey(item.id),
      entry: item,
      words: words,
      onTap: () => showHistoryItemSheet(context, item),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'History',
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(fontSize: 44, height: 1),
            ),
            const SizedBox(height: 10),
            Text(
              'Everything Echo heard, kept for $_keepText on this phone.',
              style: GoogleFonts.nunito(
                fontSize: 14.5,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBox(BuildContext context, String raw) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, _) => AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: _focus.hasFocus
                  ? c.primaryGreen
                  : c.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(Symbols.search_rounded, size: 21, color: c.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _search,
                  focusNode: _focus,
                  cursorColor: c.primaryGreen,
                  textInputAction: TextInputAction.search,
                  style: GoogleFonts.nunito(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search everything you were sent',
                    hintStyle: GoogleFonts.nunito(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: c.textSecondary,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              if (raw.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: () {
                    _search.clear();
                    _focus.requestFocus();
                  },
                  icon: Icon(
                    Symbols.close_rounded,
                    size: 20,
                    color: c.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chips(BuildContext context) => FadeSlideIn(
    delay: AppMotion.stagger * 3,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
      child: Row(
        children: [
          for (final chip in _shape.chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                chip: chip,
                on: chip.id == _chip,
                onTap: () => _selectChip(chip.id),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _askRow(BuildContext context, String raw) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: PressFeedback(
        scale: 0.98,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _ask(raw.isEmpty ? 'What did I miss this week?' : raw),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                c.primaryGreen.withValues(alpha: 0.1),
                c.surface,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.primaryGreen.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                const EchoMascot(
                  state: EchoState.idle,
                  size: 40,
                  showRings: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        raw.isEmpty
                            ? 'Ask Echo about your history'
                            : 'Ask Echo about “$raw”',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        raw.isEmpty
                            ? 'Like “What did I miss this week?”'
                            : 'An answer with the messages it came from',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.arrow_upward_rounded,
                    size: 19,
                    color: c.textInverse,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shelfView(BuildContext context, DateTime now) {
    final c = context.colors;
    final today = DateTime(now.year, now.month, now.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Recently swiped away',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 22,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_shelf.length} in the last day',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in _shelf)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _SwipedCard(
                      entry: item,
                      today: today,
                      onTap: () => showHistoryItemSheet(context, item),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayHeading(BuildContext context, HistoryDay day, DateTime now) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              historyDayLabel(day.day, now),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 22,
                height: 1.1,
              ),
            ),
          ),
          Text(
            '${day.count} ${day.count == 1 ? 'notification' : 'notifications'}',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: c.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String raw) {
    final c = context.colors;
    final searching = raw.isNotEmpty;
    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 40, 44, 10),
        child: Column(
          children: [
            const EchoMascot(
              state: EchoState.thinking,
              size: 84,
              showRings: false,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'Nothing matches “$raw”' : 'Nothing here yet',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.displayMedium?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Echo can still answer a question about it, from everything it heard.'
                  : _shape.anything
                  ? 'Nothing in this filter in the last $_keepText.'
                  : "When notifications arrive, they'll be kept here for $_keepText.",
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
            if (searching) ...[
              const SizedBox(height: 14),
              _ActionPill(
                icon: Symbols.auto_awesome_rounded,
                label: 'Ask Echo instead',
                onTap: () => _ask(raw),
              ),
            ] else if (_chip != HistoryStore.all) ...[
              const SizedBox(height: 14),
              _ActionPill(
                icon: Symbols.inbox_rounded,
                label: 'Show everything',
                onTap: () => _selectChip(HistoryStore.all),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noListener(BuildContext context) {
    final c = context.colors;
    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 40, 44, 10),
        child: Column(
          children: [
            const EchoMascot(
              state: EchoState.sleeping,
              size: 84,
              showRings: false,
            ),
            const SizedBox(height: 12),
            Text(
              "Echo can't hear your notifications",
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.displayMedium?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(
              'Allow notification access and everything you get will be kept here, on this phone.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                height: 1.45,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            _ActionPill(
              icon: Symbols.notifications_active_rounded,
              label: 'Allow access',
              onTap: () => _permissions
                  .invokeMethod<void>('requestNotificationPermission')
                  .catchError((Object _) {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        top: 18,
        bottom: MediaQuery.paddingOf(context).bottom + kNavDockHeight + 32,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Symbols.lock_rounded, size: 16, fill: 1, color: c.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Kept $_keepText, only on this phone',
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final HistoryChip chip;
  final bool on;
  final VoidCallback onTap;
  const _Chip({required this.chip, required this.on, required this.onTap});

  IconData? get _icon => switch (chip.id) {
    HistoryStore.toYou => Symbols.alternate_email_rounded,
    HistoryStore.held => Symbols.bedtime_rounded,
    HistoryStore.gone => Symbols.swipe_left_rounded,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = on ? c.textInverse : c.textPrimary;
    return PressFeedback(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: on ? c.textPrimary : c.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: on
                  ? Colors.transparent
                  : c.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chip.source != null) ...[
                HistoryAppIcon(source: chip.source!),
                const SizedBox(width: 6),
              ] else if (_icon != null) ...[
                Icon(
                  _icon,
                  size: 18,
                  color: fg,
                  fill: chip.id == HistoryStore.held ? 1 : 0,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                appLabel(chip.label),
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(width: 6),
              Opacity(
                opacity: chip.count == 0 ? 0.45 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: on ? c.primaryGreen : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${chip.count}',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: on ? c.textInverse : c.primaryGreen,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipedCard extends StatelessWidget {
  final RawData entry;
  final DateTime today;
  final VoidCallback onTap;
  const _SwipedCard({
    required this.entry,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = entry.swipedAt ?? entry.timestamp;
    final sameDay = DateTime(at.year, at.month, at.day) == today;
    return PressFeedback(
      scale: 0.97,
      haptic: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 208,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: c.textPrimary.withValues(alpha: 0.22),
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  HistoryAppIcon(source: entry.source, size: 16),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      appLabel(entry.source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.primaryGreen,
                      ),
                    ),
                  ),
                  Icon(
                    Symbols.swipe_left_rounded,
                    size: 16,
                    color: c.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Text(
                  entry.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    height: 1.35,
                    color: c.textPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Swiped away ${sameDay ? '' : 'yesterday '}at ${clockTime(at)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.nunito(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: context.selectionFill,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: context.onSelection),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.onSelection,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
