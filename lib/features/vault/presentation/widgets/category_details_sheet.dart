import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/vault/data/vault_icons.dart';
import 'package:project_echo/features/vault/presentation/cubit/vault_cubit.dart';
import 'package:project_echo/features/vault/presentation/widgets/notification_card_widget.dart';
import 'package:project_echo/features/vault/presentation/widgets/vault_utils.dart';

void showCategoryDetailsSheet(BuildContext context, String category) {
  // Ensure the cubit has this category selected before opening
  context.read<VaultCubit>().selectCategory(category);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _CategoryDetailsSheet(category: category, parentContext: context);
    },
  );
}

class _CategoryDetailsSheet extends StatelessWidget {
  final String category;
  final BuildContext parentContext;

  const _CategoryDetailsSheet({
    required this.category,
    required this.parentContext,
  });

  void _showDeleteConfirmation(BuildContext context) {
    _showBouncyDialog(
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
            style: GoogleFonts.nunito(color: context.colors.textPrimary),
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
                Navigator.of(context).pop();
                parentContext.read<VaultCubit>().deleteCategory(category);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Delete',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.bold,
                  color: context.colors.textInverse,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: category);
    _showBouncyDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: context.colors.surface,
          title: Text(
            'Rename Category',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'New category name',
              hintStyle: TextStyle(color: context.colors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: context.colors.dividerColor),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: context.colors.primaryGreen),
              ),
            ),
            autofocus: true,
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
                final newName = controller.text.trim();
                Navigator.of(dialogContext).pop();
                if (newName.isNotEmpty && newName != category) {
                  parentContext.read<VaultCubit>().renameCategory(
                    category,
                    newName,
                  );
                  Navigator.of(
                    context,
                  ).pop(); // close sheet to refresh with new name
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Save',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.bold,
                  color: context.colors.textInverse,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showBlockConfirmation(BuildContext context) {
    _showBouncyDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: context.colors.surface,
          title: Text(
            'Block Category',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          content: Text(
            'Are you sure you want to block $category? It will be hidden from your vault and ignored by Echo.',
            style: GoogleFonts.nunito(color: context.colors.textPrimary),
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
                Navigator.of(dialogContext).pop(); // Close dialog
                Navigator.of(context).pop(); // Close bottom sheet
                parentContext.read<VaultCubit>().toggleBlockCategory(category);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.textPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Block',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.bold,
                  color: context.colors.textInverse,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showIconPickerDialog(BuildContext context, IconData currentIcon) {
    _showBouncyDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: context.colors.surface,
          title: Text(
            'Choose Category Icon',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          content: SizedBox(
            width: 300,
            height: 280,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: curatedVaultIcons.length,
              itemBuilder: (context, index) {
                final icon = curatedVaultIcons[index];
                final isSelected = icon.codePoint == currentIcon.codePoint;

                return GestureDetector(
                  onTap: () {
                    parentContext.read<VaultCubit>().updateCategoryIcon(
                      category,
                      icon.codePoint,
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? context.colors.primaryGreen
                          : context.colors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? context.colors.primaryGreen
                            : context.colors.dividerColor.withValues(
                                alpha: 0.5,
                              ),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected
                          ? context.colors.textInverse
                          : context.colors.textPrimary,
                      size: 24,
                    ),
                  ),
                );
              },
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
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // We use the parentContext's BlocProvider to listen to VaultCubit
    return BlocBuilder<VaultCubit, VaultState>(
      bloc: parentContext.read<VaultCubit>(),
      builder: (context, state) {
        if (state is! VaultLoaded) {
          return const SizedBox.shrink();
        }

        final currentIcon = getCategoryIcon(category, state.categoryIcons);

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              // Drag handle
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: context.colors.dividerColor,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: context.colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _showIconPickerDialog(context, currentIcon),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.colors.primaryGreen,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          currentIcon,
                          size: 24,
                          color: context.colors.textInverse,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${state.displayedItems.length} signals',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Actions Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    _buildActionButton(
                      context: context,
                      icon: Icons.edit_rounded,
                      label: 'Rename',
                      onTap: () => _showRenameDialog(context),
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      context: context,
                      icon: Icons.block_rounded,
                      label: 'Block',
                      onTap: () => _showBlockConfirmation(context),
                      isWarning: true,
                    ),
                    const SizedBox(width: 12),
                    _buildActionButton(
                      context: context,
                      icon: Icons.delete_sweep_rounded,
                      label: 'Clear',
                      onTap: () => _showDeleteConfirmation(context),
                      isDanger: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Divider(
                color: context.colors.dividerColor,
                height: 1,
                thickness: 1,
              ),

              Expanded(
                child: state.displayedItems.isEmpty
                    ? Center(
                        child: Text(
                          'No signals here',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(24.0),
                        itemCount: state.displayedItems.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: NotificationCardWidget(
                              notification: state.displayedItems[index],
                            ),
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

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isWarning = false,
    bool isDanger = false,
  }) {
    // Use solid app colors for expressive Material 3 design without any alphas
    final Color bgColor = isDanger
        ? context.colors.buttonDark
        : (isWarning ? context.colors.buttonDark : context.colors.primaryGreen);

    final Color fgColor = isDanger
        ? context.colors.textInverse
        : (isWarning ? context.colors.textInverse : context.colors.textInverse);

    return Expanded(
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
          ),
          elevation: 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> _showBouncyDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) {
      return builder(context);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedValue = Curves.easeOutBack.transform(animation.value);
      return Transform.scale(scale: curvedValue, child: child);
    },
  );
}
