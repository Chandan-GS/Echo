import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/echo_says.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_dizzy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ShakeDetector', () {
    final t0 = DateTime(2026, 9, 27, 12);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('three strong jolts in a second make a shake', () {
      final d = ShakeDetector();
      expect(d.add(20, 0, 0, at(0)), isNull);
      expect(d.add(-22, 0, 0, at(250)), isNull);
      final strength = d.add(25, 0, 0, at(500));
      expect(strength, isNotNull);
      expect(strength, inInclusiveRange(0, 1));
    });

    test('walking-level movement never does', () {
      final d = ShakeDetector();
      for (var i = 0; i < 40; i++) {
        expect(d.add(6, 4, 3, at(i * 100)), isNull);
      }
    });

    test('jolts spread too far apart do not add up', () {
      final d = ShakeDetector();
      expect(d.add(20, 0, 0, at(0)), isNull);
      expect(d.add(20, 0, 0, at(1500)), isNull);
      expect(d.add(20, 0, 0, at(3000)), isNull);
    });

    test('one jolt spanning several samples counts once', () {
      final d = ShakeDetector();
      expect(d.add(20, 0, 0, at(0)), isNull);
      expect(d.add(21, 0, 0, at(20)), isNull);
      expect(d.add(22, 0, 0, at(40)), isNull);
      expect(d.add(20, 0, 0, at(300)), isNull);
    });

    test('rests for a few seconds after a shake', () {
      final d = ShakeDetector();
      d.add(20, 0, 0, at(0));
      d.add(20, 0, 0, at(200));
      expect(d.add(20, 0, 0, at(400)), isNotNull);
      d.add(20, 0, 0, at(900));
      d.add(20, 0, 0, at(1100));
      expect(d.add(20, 0, 0, at(1300)), isNull);
    });
  });

  group('EchoDizzy', () {
    test('rises, holds, fades, then blinks and shakes it off', () {
      final dizzy = EchoDizzy.instance;
      final t0 = DateTime(2026, 9, 27, 12);
      DateTime at(double s) =>
          t0.add(Duration(milliseconds: (s * 1000).round()));
      dizzy.trigger(0.4, now: t0);
      expect(dizzy.level(at(0.5)), closeTo(0.4, 1e-9));
      expect(dizzy.level(at(1.5)), lessThan(0.4));
      expect(dizzy.level(at(3.0)), lessThan(0.05));
      // Hold 0.86 s + fade 1.88 s = 2.74 s; blinks start 0.35 s before.
      expect(dizzy.recovery(at(2.5)).blink, lessThan(1));
      expect(dizzy.recovery(at(3.5)).shake.abs(), greaterThan(0.1));
      expect(dizzy.active(at(5)), isFalse);
    });

    test('a gentle shake stays gentle', () {
      expect(dizzyPowerFor(0), closeTo(0.3, 1e-9));
      expect(dizzyPowerFor(1), closeTo(0.5, 1e-9));
    });
  });

  group('EchoSays', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      EchoSays.instance.reset();
    });

    test('keeps a quiet gap between ambient lines', () async {
      final says = EchoSays.instance;
      final t = DateTime(2026, 9, 27, 12);
      expect(await says.say(const EchoLine('a'), now: t), isTrue);
      expect(
        await says.say(
          const EchoLine('b'),
          now: t.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(
        await says.say(
          const EchoLine('c', ambient: false),
          now: t.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(
        await says.say(
          const EchoLine('d'),
          now: t.add(const Duration(minutes: 4)),
        ),
        isTrue,
      );
      says.reset();
    });

    test('says a once-a-day line only once a day', () async {
      final says = EchoSays.instance;
      final t = DateTime(2026, 9, 27, 8);
      const morning = EchoLine('Morning!', onceKey: 'morning', ambient: false);
      expect(await says.say(morning, now: t), isTrue);
      expect(
        await says.say(morning, now: t.add(const Duration(hours: 1))),
        isFalse,
      );
      expect(
        await says.say(morning, now: t.add(const Duration(days: 1))),
        isTrue,
      );
      says.reset();
    });

    test('stays quiet while typing, and steps aside for scrolling', () async {
      final says = EchoSays.instance;
      says.setQuiet(true);
      expect(await says.say(const EchoLine('x', ambient: false)), isFalse);
      says.setQuiet(false);
      expect(await says.say(const EchoLine('y')), isTrue);
      says.scrolled();
      expect(says.current.value, isNull);
      says.reset();
    });
  });
}
