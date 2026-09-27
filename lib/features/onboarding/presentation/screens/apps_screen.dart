import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:project_echo/features/vault/data/app_access.dart';
import 'package:project_echo/features/vault/data/installed_apps.dart';
import 'package:project_echo/features/vault/presentation/widgets/app_access_widgets.dart';

/// Onboarding (Android): which apps Echo hears. The same choice as Vault →
/// Apps Echo hears, as a grid. Games, music, video and photo apps start off.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  static const _collapsedCount = 16;

  List<InstalledApp>? _apps;
  AppAccess _saved = const AppAccess();
  Set<String> _off = {};
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await InstalledApps.load();
    // Notification access was just granted, so what's in the shade right now
    // is the best guess at which apps matter; they lead the grid.
    final active = await InstalledApps.activePackages();
    final chosen = await AppAccess.isChosen();
    final saved = chosen ? await AppAccess.load() : const AppAccess();

    final rank = {for (final (i, pkg) in active.indexed) pkg: i};
    final ordered = [...apps]
      ..sort((a, b) {
        final ra = rank[a.package], rb = rank[b.package];
        if (ra != null || rb != null) return (ra ?? 1 << 30) - (rb ?? 1 << 30);
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    if (!mounted) return;
    setState(() {
      _apps = ordered;
      _saved = saved;
      _off = {
        for (final a in apps)
          if (chosen ? !saved.hears(a.package) : a.quietByDefault) a.package,
      };
    });
  }

  void _toggle(InstalledApp app) {
    setState(() {
      if (!_off.remove(app.package)) _off.add(app.package);
    });
  }

  void _toggleAll() {
    final apps = _apps ?? const [];
    setState(() {
      _off = _off.isEmpty ? {for (final a in apps) a.package} : {};
    });
  }

  Future<void> _continue() async {
    final apps = _apps ?? const [];
    await _saved
        .withApps(
          apps.map((a) => a.package).where((p) => !_off.contains(p)),
          true,
        )
        .withApps(_off, false)
        .save();
    if (mounted) context.read<OnBoardingCubit>().completeApps();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final apps = _apps;

    return OnboardingStepBody(
      title: 'Choose what Echo hears.',
      subtitle:
          'Tap an app to turn it off. Games, video and music start off. You '
          'can change this anytime from the Vault.',
      footer: EchoButton(
        text: 'Continue',
        showArrow: true,
        onPressed: apps == null ? null : _continue,
      ),
      child: apps == null
          ? const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : apps.isEmpty
          ? Text(
              "Couldn't list your apps. Echo will hear all of them for now; "
              'you can choose later from the Vault.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            )
          : _grid(apps),
    );
  }

  Widget _grid(List<InstalledApp> apps) {
    final colors = context.colors;
    final shown = _expanded ? apps : apps.take(_collapsedCount).toList();
    final on = apps.length - _off.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                '$on of ${apps.length} apps on',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            GestureDetector(
              onTap: _toggleAll,
              child: Text(
                _off.isEmpty ? 'Turn all off' : 'Turn all on',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryGreen,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 18,
            mainAxisExtent: 86,
          ),
          itemCount: shown.length,
          itemBuilder: (context, i) => AppTile(
            app: shown[i],
            on: !_off.contains(shown[i].package),
            onTap: () => _toggle(shown[i]),
          ),
        ),
        if (apps.length > _collapsedCount) ...[
          const SizedBox(height: 22),
          SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: OutlinedButton.styleFrom(
                backgroundColor: colors.surface,
                foregroundColor: colors.textPrimary,
                side: BorderSide(
                  color: colors.dividerColor.withValues(alpha: 0.8),
                ),
                shape: const StadiumBorder(),
              ),
              child: Text(
                _expanded ? 'Show fewer' : 'Show all ${apps.length} apps',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
