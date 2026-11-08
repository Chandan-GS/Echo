import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/features/people/presentation/widgets/people_parts.dart'
    show appLabel;
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/echo_segmented.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/ask/ask_parts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/screens/app_access_screen.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_details_sheet.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_pie_chart.dart';
import 'package:project_echo/features/vault/presentation/widgets/week_card.dart';

/// [counts] as the wheel draws them: real categories only, nothing excluded
/// or empty, busiest first so a slice keeps its colour as messages arrive.
Map<String, int> wheelCounts(Map<String, int> counts, Set<String> excluded) {
  final entries =
      counts.entries
          .where(
            (e) => e.key != 'All' && e.value > 0 && !excluded.contains(e.key),
          )
          .toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });
  return {for (final e in entries) e.key: e.value};
}

/// What Echo hears: how its signals sort into categories, the wheel first,
/// and which apps it reads.
class HearsScreen extends StatelessWidget {
  /// 0 for Categories, 1 for Apps.
  final int initialTab;

  const HearsScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => VaultCubit()..loadEntries(),
    child: _HearsView(initialTab: initialTab),
  );
}

class _HearsView extends StatefulWidget {
  final int initialTab;
  const _HearsView({required this.initialTab});

  @override
  State<_HearsView> createState() => _HearsViewState();
}

class _HearsViewState extends State<_HearsView> {
  static const _permissions = MethodChannel('project_echo/permissions');

  late int _tab = widget.initialTab;
  Set<String> _excluded = const {};
  String? _highlight;

  /// The app list is built the first time its tab is opened.
  late bool _appsOpened = widget.initialTab == 1;

  @override
  void initState() {
    super.initState();
    _loadExcluded();
  }

  Future<void> _loadExcluded() async {
    final excluded = await loadExcludedSources();
    if (mounted) setState(() => _excluded = excluded);
  }

  /// A switch on the Apps tab changed what the wheel may show.
  void _appsChanged() {
    context.read<VaultCubit>().reloadSettings();
    _loadExcluded();
  }

  void _selectTab(int tab) => setState(() {
    _tab = tab;
    if (tab == 1) _appsOpened = true;
  });

  Future<void> _openCategory(String category) async {
    HapticFeedback.selectionClick();
    setState(() => _highlight = category);
    await showCategoryDetailsSheet(context, category);
    if (mounted) setState(() => _highlight = null);
    _loadExcluded();
  }

  Future<void> _openAndroidSettings() async {
    try {
      await _permissions.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: const EchoAppBar(title: 'What Echo hears'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
            child: FadeSlideIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Echo only reads notifications from apps that are on. '
                    'Turning one off also keeps what it already sent out of '
                    'Today, History and Ask Echo.',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      height: 1.45,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  EchoSegmented(
                    labels: const ['Categories', 'Apps'],
                    selected: _tab,
                    onSelect: _selectTab,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _categories(context),
                if (_appsOpened)
                  AppAccessPanel(header: false, onChanged: _appsChanged)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categories(BuildContext context) {
    return BlocConsumer<VaultCubit, VaultState>(
      listener: (context, state) {
        if (state is VaultError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        if (state is! VaultLoaded) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (state.allItems.isEmpty) return _empty(context);
        final counts = wheelCounts(state.categoryCounts, _excluded);
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final side = box.maxWidth.clamp(0.0, 420.0);
                  return Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: CategoryPieChart(
                        categoryCounts: counts,
                        highlight: _highlight,
                        onCategorySelected: _openCategory,
                      ),
                    ),
                  );
                },
              ),
              if (counts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final (i, e) in counts.entries.indexed)
                      _LegendChip(
                        name: e.key,
                        count: e.value,
                        color: sliceColor(context, i, counts.length),
                        selected: _highlight == e.key,
                        onTap: () => _openCategory(e.key),
                      ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 12),
                child: Text(
                  'This week',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              const WeekCard(),
              if (state.blockedCategories.isNotEmpty) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showBlockedCategoriesSheet(context),
                    icon: Icon(
                      Symbols.block_rounded,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                    label: Text(
                      'Manage blocked (${state.blockedCategories.length})',
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        children: [
          const EchoMascot(state: EchoState.sleeping, size: 120),
          const SizedBox(height: 14),
          Text(
            'Nothing heard yet',
            style: GoogleFonts.oldStandardTt(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This fills in as notifications arrive. If it stays empty, check '
            'that Echo has notification access.',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 14.5,
              height: 1.45,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              AskPill(
                label: 'Choose apps',
                icon: Symbols.tune_rounded,
                filled: true,
                onTap: () => _selectTab(1),
              ),
              AskPill(
                label: 'Notification access',
                icon: Symbols.open_in_new_rounded,
                onTap: _openAndroidSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A category under the wheel: its colour, name and count. A tap lifts its
/// slice and opens it.
class _LegendChip extends StatelessWidget {
  final String name;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _LegendChip({
    required this.name,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressFeedback(
      scale: 0.95,
      child: Semantics(
        button: true,
        label: '${appLabel(name)}, $count ${count == 1 ? 'signal' : 'signals'}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
            constraints: const BoxConstraints(maxWidth: 220),
            decoration: BoxDecoration(
              color: selected ? context.selectionFill : c.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.dividerColor.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    appLabel(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? context.onSelection : c.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? context.onSelection : c.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
