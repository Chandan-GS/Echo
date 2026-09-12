import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_progress.dart';

/// The persistent frame around every warm/light onboarding step.
///
/// This is mounted ONCE by `StartScreen` and stays alive across steps 1–6, so
/// the back affordance and the [OnboardingProgress] bar never tear down or
/// replay their entrance — the bar simply animates its fill as [step] changes,
/// and only the [body] beneath cross-fades between steps. That's what makes the
/// flow feel like one continuous surface instead of a stack of separate screens.
class OnboardingShell extends StatelessWidget {
  final int step;
  final VoidCallback? onBack;

  /// The per-step content, typically an [AnimatedSwitcher] of [OnboardingStepBody].
  final Widget body;

  const OnboardingShell({
    super.key,
    required this.step,
    required this.body,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    // AnimatedSwitcher so the back button fades in/out when a
                    // step gains/loses it, without the whole header re-mounting.
                    AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: onBack != null
                          ? _IosBackButton(
                              key: const ValueKey('back'),
                              onTap: onBack!,
                            )
                          : const SizedBox(
                              key: ValueKey('noback'), width: 44),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Center(child: OnboardingProgress(step: step)),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// The content of a single onboarding step: an editorial serif [title] (with an
/// optional [subtitle]), the step's [child], and a pinned [footer] (usually the
/// primary CTA). Rendered *inside* [OnboardingShell]'s
/// animated body region, so its staggered entrance replays on each step while
/// the surrounding chrome stays put.
class OnboardingStepBody extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget footer;

  /// When true (default) the [child] scrolls; set false for steps that manage
  /// their own Expanded/scroll internally.
  final bool scrollableBody;

  const OnboardingStepBody({
    super.key,
    required this.title,
    required this.child,
    required this.footer,
    this.subtitle,
    this.scrollableBody = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final titleBlock = Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(
            child: Text(
              title,
              style: GoogleFonts.oldStandardTt(
                fontSize: 37,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                height: 1.12,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: AppMotion.staggerDelay(2),
              child: Text(
                subtitle!,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final bodyContent = FadeSlideIn(
      delay: AppMotion.staggerDelay(3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: child,
      ),
    );

    final scrollBody = scrollableBody
        ? SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: bodyContent,
          )
        : bodyContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleBlock,
        Expanded(child: scrollBody),
        FadeSlideIn(
          delay: AppMotion.staggerDelay(4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: footer,
          ),
        ),
      ],
    );
  }
}

/// An iOS-style back affordance: a bare left-pointing chevron (no filled
/// circle), centered in a 44×44 tap target.
class _IosBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _IosBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 22,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
