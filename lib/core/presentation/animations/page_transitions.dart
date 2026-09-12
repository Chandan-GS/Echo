import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

/// go_router page that fades + gently slides the incoming screen up. Used for
/// the main forward navigations so screen changes feel like one continuous
/// surface rather than a hard platform cut.
CustomTransitionPage<T> fadeThroughPage<T>({
  required Widget child,
  LocalKey? key,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: AppMotion.medium,
    reverseTransitionDuration: AppMotion.fast,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
        reverseCurve: AppMotion.standard,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// go_router page that slides the incoming screen up from the bottom — for
/// modal-feeling destinations like the chat/"Ask AI" surface.
CustomTransitionPage<T> slideUpPage<T>({
  required Widget child,
  LocalKey? key,
}) {
  return CustomTransitionPage<T>(
    key: key,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.medium,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
        reverseCurve: AppMotion.standard,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}
