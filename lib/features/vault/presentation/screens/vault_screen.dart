import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/widgets/notification_card_widget.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_pie_chart.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_details_sheet.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:project_echo/features/vault/presentation/screens/app_access_screen.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/vault/presentation/widgets/week_card.dart';
import 'package:project_echo/features/vault/presentation/widgets/vault_day_heading.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/header_icon_button.dart';

class VaultScreen extends StatelessWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => VaultCubit()..loadEntries(),
      child: const _VaultView(),
    );
  }
}

class _VaultView extends StatefulWidget {
  const _VaultView();

  @override
  State<_VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<_VaultView> {
  int _selectedTabIndex = 0; // 0 = All, 1 = Categories

  void _onTabSelected(int index) {
    if (_selectedTabIndex == index) return;
    setState(() => _selectedTabIndex = index);
    if (index == 0) {
      context.read<VaultCubit>().selectCategory('All');
    }
  }

  Widget _buildTabBar() {
    final tabs = ['All', 'Categories'];

    return Container(
      height: 68,
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.textInverse,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: context.colors.dividerColor.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final itemWidth = totalWidth / 2;
          final activeLeft = _selectedTabIndex * itemWidth;

          return Stack(
            children: [
              // Fluid sliding active capsule
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                left: activeLeft,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              // Tab Items Row
              Row(
                children: List.generate(tabs.length, (index) {
                  final title = tabs[index];
                  final isSelected = _selectedTabIndex == index;

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onTabSelected(index),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? context.colors.textInverse
                                : context.colors.textSecondary,
                          ),
                          child: Text(textAlign: TextAlign.center, title),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      // Lists scroll behind the phone's nav dock and pad their ends by
      // MediaQuery's bottom padding (see MainScaffold).
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              FadeSlideIn(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'The Vault',
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (Platform.isAndroid) _appAccessButton(context),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: BlocConsumer<VaultCubit, VaultState>(
                  listener: (context, state) {
                    if (state is VaultError) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(state.message),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  builder: (context, state) {
                    if (state is VaultInitial || state is VaultLoading) {
                      return const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    if (state is VaultLoaded) {
                      if (state.allItems.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const EchoMascot(
                                state: EchoState.sleeping,
                                size: 120,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No signals captured yet',
                                style: GoogleFonts.nunito(
                                  fontSize: 16,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return _SnappingVault(
                        // Categories gets the whole screen for the wheel.
                        collapsed: _selectedTabIndex == 1,
                        header: const WeekCard(),
                        tabs: _buildTabBar(),
                        body: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                          child: _selectedTabIndex == 0
                              ? _buildAllView(state)
                              : _buildCategoriesView(state, context),
                        ),
                      );
                    }

                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens Apps Echo hears; on return the Vault picks up any change to
  /// blocked categories made there.
  Widget _appAccessButton(BuildContext context) {
    return HeaderIconButton(
      icon: Symbols.tune_rounded,
      label: 'Apps Echo hears',
      onTap: () async {
        final vault = context.read<VaultCubit>();
        await Navigator.of(
          context,
          rootNavigator: true,
        ).push(bouncyRoute(const AppAccessScreen()));
        vault.reloadSettings();
      },
    );
  }

  /// Newest first, under a heading per day with that day's count.
  Widget _buildAllView(VaultLoaded state) {
    final items = state.displayedItems;
    final rows = <Object>[]; // a DateTime starts a day, then its notifications
    final perDay = <DateTime, int>{};
    for (final item in items) {
      final t = item.timestamp;
      final day = DateTime(t.year, t.month, t.day);
      if (rows.isEmpty || !perDay.containsKey(day)) rows.add(day);
      perDay[day] = (perDay[day] ?? 0) + 1;
      rows.add(item);
    }
    var cards = 0;
    return ListView.builder(
      key: const ValueKey('all_view'),
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        MediaQuery.paddingOf(context).bottom + 8,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is DateTime) {
          return VaultDayHeading(
            day: row,
            count: perDay[row]!,
            first: index == 0,
          );
        }
        // Cascade the first screenful on load; items scrolled into view
        // later just fade up immediately (no stale long delay).
        final n = cards++;
        return FadeSlideIn(
          delay: n < 8 ? AppMotion.staggerDelay(n) : Duration.zero,
          offsetY: 12,
          child: NotificationCardWidget(notification: row as RawData),
        );
      },
    );
  }

  Widget _buildCategoriesView(VaultLoaded state, BuildContext parentContext) {
    return Padding(
      key: const ValueKey('categories_view'),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: CategoryPieChart(
                categoryCounts: state.categoryCounts,
                onCategorySelected: (category) {
                  showCategoryDetailsSheet(parentContext, category);
                },
              ),
            ),
          ),
          if (state.blockedCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: TextButton.icon(
                onPressed: () =>
                    _showManageBlockedCategoriesDialog(parentContext, state),
                icon: Icon(
                  Symbols.block_rounded,
                  color: parentContext.colors.textSecondary,
                ),
                label: Text(
                  'Manage Blocked (${state.blockedCategories.length})',
                  style: GoogleFonts.nunito(
                    color: parentContext.colors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showManageBlockedCategoriesDialog(
    BuildContext parentContext,
    VaultLoaded state,
  ) {
    showModalBottomSheet(
      context: parentContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(parentContext).size.height * 0.6,
          decoration: BoxDecoration(
            color: parentContext.colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: parentContext.colors.dividerColor,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  'Blocked Categories',
                  style: GoogleFonts.oldStandardTt(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: parentContext.colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: BlocBuilder<VaultCubit, VaultState>(
                  bloc: parentContext.read<VaultCubit>(),
                  builder: (context, currentState) {
                    if (currentState is! VaultLoaded ||
                        currentState.blockedCategories.isEmpty) {
                      return Center(
                        child: Text(
                          'No blocked categories',
                          style: GoogleFonts.nunito(
                            color: parentContext.colors.textSecondary,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: currentState.blockedCategories.length,
                      itemBuilder: (context, index) {
                        final cat = currentState.blockedCategories[index];
                        return ListTile(
                          title: Text(
                            cat,
                            style: GoogleFonts.nunito(
                              color: parentContext.colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: () {
                              parentContext
                                  .read<VaultCubit>()
                                  .toggleBlockCategory(cat);
                            },
                            child: Text(
                              'Unblock',
                              style: GoogleFonts.nunito(
                                color: parentContext.colors.primaryGreen,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The week card over the tabs and what they show. The scroll never rests
/// in between: released part-way, it settles on whichever is nearer — the
/// full card, or the tabs pinned at the top with the list below.
class _SnappingVault extends StatefulWidget {
  final Widget header;
  final Widget tabs;
  final Widget body;

  /// Slides the card away (and back, if that's what hid it).
  final bool collapsed;

  const _SnappingVault({
    required this.header,
    required this.tabs,
    required this.body,
    this.collapsed = false,
  });

  @override
  State<_SnappingVault> createState() => _SnappingVaultState();
}

class _SnappingVaultState extends State<_SnappingVault> {
  final _outer = ScrollController();
  bool _snapping = false;

  /// Whether [collapsed] hid the card, so turning it off brings it back
  /// rather than undoing a scroll the user made.
  bool _hidByTab = false;

  @override
  void didUpdateWidget(covariant _SnappingVault oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed == oldWidget.collapsed || !_outer.hasClients) return;
    final max = _outer.position.maxScrollExtent;
    if (widget.collapsed) {
      _hidByTab = _outer.offset < max;
      if (_hidByTab) _slideTo(max);
    } else if (_hidByTab) {
      _hidByTab = false;
      _slideTo(0);
    }
  }

  Future<void> _slideTo(double offset) async {
    _snapping = true;
    await _outer.animateTo(
      offset,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
    _snapping = false;
  }

  @override
  void dispose() {
    _outer.dispose();
    super.dispose();
  }

  bool _onEnd(ScrollEndNotification _) {
    if (_snapping || !_outer.hasClients) return false;
    final p = _outer.position;
    if (p.pixels <= 0 || p.pixels >= p.maxScrollExtent) return false;
    final target = p.pixels < p.maxScrollExtent / 2 ? 0.0 : p.maxScrollExtent;
    _snapping = true;
    // After this frame: the scroll that just ended has fully let go.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_outer.hasClients) return;
      await _outer.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      _snapping = false;
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: _onEnd,
      child: NestedScrollView(
        controller: _outer,
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: widget.header,
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              color: context.colors.background,
              child: widget.tabs,
            ),
          ),
        ],
        body: widget.body,
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  final Color color;
  final Widget child;
  const _TabsHeader({required this.color, required this.child});

  static const _height = 68.0 + 18;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(
        color: color,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: child,
        ),
      );

  @override
  bool shouldRebuild(covariant _TabsHeader old) =>
      old.color != color || old.child != child;
}
