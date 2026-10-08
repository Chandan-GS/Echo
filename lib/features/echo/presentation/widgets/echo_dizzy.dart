import 'dart:math' as math;

/// Echo's dizzy spell after the phone is shaken: he squashes and stretches
/// like shaken jelly, his eyes flutter and three stars circle his head, then
/// he steadies with a slow double blink and a quick shake of the head.
///
/// Every [EchoMascot] on screen reads this, so the Echo in the nav dock and
/// any other Echo get dizzy together.
class EchoDizzy {
  EchoDizzy._();
  static final EchoDizzy instance = EchoDizzy._();

  DateTime? _start;
  double _power = 0;

  /// [power] is how hard the shake was, 0..1 (a gentle shake is about 0.4).
  void trigger(double power, {DateTime? now}) {
    final at = now ?? DateTime.now();
    // Shaking again while dizzy tops the spell up instead of restarting it.
    _power = math.max(power.clamp(0.0, 1.0), level(at));
    _start = at;
  }

  double get _hold => 0.5 + 0.9 * _power;
  double get _fade => 1.4 + 1.2 * _power;

  double _seconds(DateTime now) => _start == null
      ? double.infinity
      : now.difference(_start!).inMilliseconds / 1000;

  /// How dizzy he is right now, 0 (not at all) to the shake's power.
  double level(DateTime now) {
    final t = _seconds(now);
    if (t.isInfinite || t < 0) return 0;
    final rise = (t / 0.18).clamp(0.0, 1.0);
    final left = t < _hold
        ? 1.0
        : 1 - _smooth(((t - _hold) / _fade).clamp(0.0, 1.0));
    return _power * rise * left;
  }

  /// The coming-round: [blink] 1 is open (it dips twice), [shake] is a
  /// quick side-to-side of the head, -1..1.
  ({double blink, double shake}) recovery(DateTime now) {
    final t = _seconds(now);
    if (t.isInfinite) return (blink: 1.0, shake: 0.0);
    final r = t - (_hold + _fade) + 0.35;
    var blink = 1.0;
    for (final at in const [0.0, 0.42]) {
      final d = (r - at) / 0.26;
      if (d >= 0 && d < 1) {
        blink = math.min(blink, 1 - (d < 0.5 ? d / 0.5 : (1 - d) / 0.5) * 0.95);
      }
    }
    final s = r - 0.9;
    final shake = s > 0 && s < 0.55 ? math.sin(s * 34) * (1 - s / 0.55) : 0.0;
    return (blink: blink, shake: shake);
  }

  /// Whether anything is still playing (the spell or the coming-round).
  bool active(DateTime now) => _seconds(now) < _hold + _fade + 1.6;

  static double _smooth(double x) => x * x * (3 - 2 * x);
}

/// Spots a deliberate shake in the phone's linear acceleration (gravity
/// already removed): a few strong jolts in quick succession. Walking, a
/// bumpy ride or setting the phone down don't reach it.
class ShakeDetector {
  /// A jolt is acceleration above this, in m/s².
  final double threshold;

  /// How many jolts, within [window], make a shake.
  final int jolts;
  final Duration window;

  /// No second shake this soon after the last one.
  final Duration cooldown;

  ShakeDetector({
    this.threshold = 14,
    this.jolts = 3,
    this.window = const Duration(milliseconds: 1100),
    this.cooldown = const Duration(seconds: 4),
  });

  final List<DateTime> _hits = [];
  double _peak = 0;
  DateTime? _lastShake;

  /// Feeds one sample; returns the shake's strength (0..1) when one
  /// completes, otherwise null.
  double? add(double x, double y, double z, DateTime at) {
    final g = math.sqrt(x * x + y * y + z * z);
    if (_lastShake != null && at.difference(_lastShake!) < cooldown) {
      return null;
    }
    _hits.removeWhere((h) => at.difference(h) > window);
    if (g < threshold) return null;
    // One jolt spans several samples; count it once.
    if (_hits.isNotEmpty && at.difference(_hits.last).inMilliseconds < 90) {
      _peak = math.max(_peak, g);
      return null;
    }
    if (_hits.isEmpty) _peak = 0;
    _hits.add(at);
    _peak = math.max(_peak, g);
    if (_hits.length < jolts) return null;
    _hits.clear();
    _lastShake = at;
    return ((_peak - threshold) / (threshold * 1.5)).clamp(0.0, 1.0);
  }
}

/// A shake's strength (0..1) as the spell's power: always close to the
/// gentle wobble chosen in the mock (0.4), a little more for a hard shake.
double dizzyPowerFor(double strength) => 0.3 + 0.2 * strength;
