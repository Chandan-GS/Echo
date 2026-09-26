import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/vault/data/installed_apps.dart';
import 'package:project_echo/features/vault/presentation/widgets/source_icon.dart';

/// Pieces shared by Vault → Apps Echo hears and the onboarding step.

/// An app's real icon; greyed and faded while Echo doesn't hear it.
class AppIconDisc extends StatelessWidget {
  final InstalledApp app;
  final double size;
  final bool on;

  const AppIconDisc({
    super.key,
    required this.app,
    required this.size,
    this.on = true,
  });

  static const _greyscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final icon = SourceIcon.app(
      packageName: app.package,
      size: size,
      fallback: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.dividerColor,
          shape: BoxShape.circle,
        ),
        child: Text(
          app.label.isEmpty ? '?' : app.label.characters.first.toUpperCase(),
          style: GoogleFonts.nunito(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: on ? 1 : 0.4,
      child: on ? icon : ColorFiltered(colorFilter: _greyscale, child: icon),
    );
  }
}

class AppSearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const AppSearchField({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.dividerColor.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.nunito(
                fontSize: 15,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Search apps',
                hintStyle: GoogleFonts.nunito(
                  fontSize: 15,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const AppSectionHeader(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One app with its switch; the whole row toggles.
class AppAccessRow extends StatelessWidget {
  final InstalledApp app;
  final bool on;

  /// Notifications this week; 0 shows just On / Off.
  final int count;
  final bool last;
  final VoidCallback onTap;

  const AppAccessRow({
    super.key,
    required this.app,
    required this.on,
    required this.count,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final String sub;
    if (count > 0) {
      sub =
          '$count signal${count == 1 ? '' : 's'}'
          '${on ? '' : ' · left out of briefings'}';
    } else {
      sub = on ? 'On' : 'Off';
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: colors.dividerColor)),
        ),
        child: Row(
          children: [
            AppIconDisc(app: app, size: 38, on: on),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: on ? colors.textPrimary : colors.textSecondary,
                    ),
                  ),
                  Text(
                    sub,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: on, onChanged: (_) => onTap()),
          ],
        ),
      ),
    );
  }
}

/// "Hear new apps automatically", at the foot of the list.
class NewAppsCard extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const NewAppsCard({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.dividerColor.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hear new apps automatically',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'When an app you install sends its first notification. '
                      'Off means new apps stay off until you turn them on '
                      'here.',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Switch(value: on, onChanged: (_) => onTap()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Onboarding's grid tile: the app's icon with a check while it's on.
class AppTile extends StatelessWidget {
  final InstalledApp app;
  final bool on;
  final VoidCallback onTap;

  const AppTile({
    super.key,
    required this.app,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      toggled: on,
      label: app.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppIconDisc(app: app, size: 56, on: on),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: AnimatedScale(
                    scale: on ? 1 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.spring,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: colors.primaryGreen,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.background,
                          width: 2.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                color: on ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
