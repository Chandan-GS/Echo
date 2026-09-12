import 'package:flutter/animation.dart';

/// Central motion design tokens.
///
/// Keeping every duration and curve in one place is what makes the product feel
/// like one coherent, premium object rather than a set of independently-animated
/// screens. Reach for these instead of hardcoding `Duration`/`Curves` at call
/// sites.
class AppMotion {
  AppMotion._();

  // ── Durations ──────────────────────────────────────────────────────────────
  /// Micro-interactions: taps, small toggles, icon swaps.
  static const Duration fast = Duration(milliseconds: 180);

  /// The workhorse: content entrances, cross-fades, most transitions.
  static const Duration medium = Duration(milliseconds: 320);

  /// Larger, more deliberate moves: full-screen route transitions.
  static const Duration slow = Duration(milliseconds: 460);

  // ── Curves ───────────────────────────────────────────────────────────────
  /// Material 3 "emphasized decelerate" — fast in, gentle settle. The default
  /// for anything entering the screen; reads as expensive and controlled.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Symmetric ease for things that both enter and leave (cross-fades).
  static const Curve standard = Cubic(0.4, 0.0, 0.2, 1.0);

  /// A restrained overshoot for tactile feedback (press release, selection).
  static const Curve spring = Cubic(0.34, 1.3, 0.64, 1.0);

  // ── Stagger ─────────────────────────────────────────────────────────────
  /// Delay between successive items in a staggered list entrance.
  static const Duration stagger = Duration(milliseconds: 60);

  /// A sensible cap so long lists don't take forever to fully appear.
  static const int maxStaggerItems = 12;

  /// Stagger delay for the [index]th item, clamped so late items aren't
  /// penalised on long lists.
  static Duration staggerDelay(int index) {
    final clamped = index > maxStaggerItems ? maxStaggerItems : index;
    return stagger * clamped;
  }
}
