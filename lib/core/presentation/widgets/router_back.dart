import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// System back for a screen that is the only page on go_router's stack (the
/// tabs, onboarding): while [onBack] is set, back runs it instead of closing
/// the app. A PopScope alone isn't enough, since go_router lets the app quit
/// when no Navigator can pop without asking it; the PopScope still tells
/// Android that Flutter handles back.
class RouterBack extends StatelessWidget {
  final VoidCallback? onBack;
  final Widget child;

  const RouterBack({super.key, required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    return BackButtonListener(
      onBackButtonPressed: () async {
        // A screen, sheet or dialog over this one closes first, as usual.
        if (onBack == null || GoRouter.of(context).canPop()) return false;
        onBack!();
        return true;
      },
      child: PopScope(canPop: onBack == null, child: child),
    );
  }
}
