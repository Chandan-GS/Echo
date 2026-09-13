import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

/// The shared "pop" motion for every screen entrance: the incoming screen
/// springs up from a slightly smaller size with an easeOutBack overshoot while
/// fading in — the same bouncy feel as the chat bubbles in Ask Echo. Scale and
/// slide ride the overshooting curve (they tolerate values past 1); opacity
/// rides a plain easeOut so it never leaves the [0,1] range.
Widget _pop(
  Animation<double> animation,
  Widget child, {
  double scaleFrom = 0.90,
  Offset slideFrom = Offset.zero,
}) {
  final spring = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );
  final fade = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  Widget content = ScaleTransition(
    scale: Tween<double>(begin: scaleFrom, end: 1.0).animate(spring),
    child: FadeTransition(opacity: fade, child: child),
  );
  if (slideFrom != Offset.zero) {
    content = SlideTransition(
      position: Tween<Offset>(begin: slideFrom, end: Offset.zero).animate(spring),
      child: content,
    );
  }
  return content;
}

/// go_router page: the incoming screen bounces + fades in. Used for the main
/// forward navigations.
CustomTransitionPage<T> fadeThroughPage<T>({
  required Widget child,
  LocalKey? key,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.medium,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _pop(animation, child),
  );
}

/// go_router page for modal-feeling destinations (the chat / "Ask Echo"
/// surface): springs up from the bottom with a bouncy overshoot.
CustomTransitionPage<T> slideUpPage<T>({
  required Widget child,
  LocalKey? key,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.medium,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _pop(animation, child, scaleFrom: 0.96, slideFrom: const Offset(0, 0.08)),
  );
}

/// Imperative equivalent of [fadeThroughPage] for `Navigator.push` — gives the
/// same bouncy pop to screens pushed outside go_router (briefing, celebration,
/// previews, etc.).
PageRoute<T> bouncyRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.medium,
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _pop(animation, child),
  );
}
