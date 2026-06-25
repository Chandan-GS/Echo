import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/widgets/notification_card_widget.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_pie_chart.dart';
import 'package:project_echo/features/vault/presentation/widgets/category_details_sheet.dart';

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                'The Vault',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.15,
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
                          child: Text(
                            'No signals captured yet',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Custom sliding tab bar
                          _buildTabBar(),
                          const SizedBox(height: 24),

                          // Content View
                          Expanded(
                            child: AnimatedSwitcher(
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
                          ),
                        ],
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

  Widget _buildAllView(VaultLoaded state) {
    return Column(
      key: const ValueKey('all_view'),
      children: [
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            itemCount: state.displayedItems.length,
            itemBuilder: (context, index) {
              return NotificationCardWidget(
                notification: state.displayedItems[index],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesView(VaultLoaded state, BuildContext parentContext) {
    return Column(
      key: const ValueKey('categories_view'),
      children: [
        Expanded(
          child: Container(
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
                Icons.block,
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

  void _showDeleteConfirmation(BuildContext context, String category) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: context.colors.surface,
          title: Text(
            'Delete Category',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          content: Text(
            'Are you sure you want to delete all notifications for $category?',
            style: GoogleFonts.nunito(
              color: context.colors.textPrimary.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.bold,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<VaultCubit>().deleteCategory(category);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Delete',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
