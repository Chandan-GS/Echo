import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/quiet/data/quiet_held.dart';
import 'package:project_echo/features/quiet/data/quiet_native.dart';
import 'package:project_echo/features/quiet/data/quiet_settings.dart';
import 'package:project_echo/features/quiet/presentation/widgets/quiet_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawData _row(
  String source, {
  bool isGroup = false,
  String sender = 'A',
  String content = 'x',
}) => RawData()
  ..source = source
  ..sender = sender
  ..content = content
  ..timestamp = DateTime(2026, 11, 8)
  ..isGroup = isGroup;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // QuietHours.kt's QuietSchedule keeps to these same cases.
  group('the window', () {
    const nine = QuietConfig(enabled: true); // 9 AM to 1 PM, Monday to Friday
    const night = QuietConfig(
      enabled: true,
      startMin: 22 * 60,
      endMin: 7 * 60,
      days: {1, 2, 3, 4, 5, 6, 7},
    );

    test('off by default, and off means no window', () {
      expect(const QuietConfig().enabled, isFalse);
      expect(
        const QuietConfig().activeWindow(DateTime(2026, 11, 9, 10)),
        isNull,
      );
    });

    test('inside and outside a daytime window', () {
      // 9 Nov 2026 is a Monday.
      final w = nine.activeWindow(DateTime(2026, 11, 9, 10));
      expect(w?.start, DateTime(2026, 11, 9, 9));
      expect(w?.end, DateTime(2026, 11, 9, 13));
      expect(nine.activeWindow(DateTime(2026, 11, 9, 8, 59)), isNull);
      expect(nine.activeWindow(DateTime(2026, 11, 9, 13)), isNull);
      expect(nine.activeWindow(DateTime(2026, 11, 9, 9)), isNotNull);
    });

    test('a day that is not chosen has no window', () {
      expect(nine.activeWindow(DateTime(2026, 11, 8, 10)), isNull); // Sunday
    });

    test('a window crossing midnight, on both sides of it', () {
      final before = night.activeWindow(DateTime(2026, 11, 9, 23));
      expect(before?.start, DateTime(2026, 11, 9, 22));
      expect(before?.end, DateTime(2026, 11, 10, 7));
      final after = night.activeWindow(DateTime(2026, 11, 10, 2));
      expect(after?.start, DateTime(2026, 11, 9, 22));
      expect(after?.end, DateTime(2026, 11, 10, 7));
      expect(night.activeWindow(DateTime(2026, 11, 10, 12)), isNull);
    });

    test('the morning after belongs to the day the window started', () {
      final mondayOnly = night.copyWith(days: {1});
      expect(mondayOnly.activeWindow(DateTime(2026, 11, 10, 3)), isNotNull);
      expect(mondayOnly.activeWindow(DateTime(2026, 11, 9, 3)), isNull);
      expect(mondayOnly.activeWindow(DateTime(2026, 11, 10, 23)), isNull);
    });

    test('crossing a month end', () {
      final w = night.activeWindow(DateTime(2026, 11, 30, 23));
      expect(w?.end, DateTime(2026, 12, 1, 7));
    });

    test('equal start and end is no window at all', () {
      final flat = nine.copyWith(startMin: 600, endMin: 600);
      expect(flat.activeWindow(DateTime(2026, 11, 9, 10)), isNull);
      expect(flat.nextWindow(DateTime(2026, 11, 9, 10)), isNull);
    });

    test('the next window skips days off', () {
      final next = nine.nextWindow(DateTime(2026, 11, 6, 14)); // Friday
      expect(next?.start, DateTime(2026, 11, 9, 9));
      expect(nine.copyWith(days: {}).nextWindow(DateTime(2026, 11, 6)), isNull);
    });
  });

  group('settings', () {
    test('survive a round trip', () {
      const c = QuietConfig(
        enabled: true,
        startMin: 1320,
        endMin: 420,
        days: {1, 7},
        custom: true,
        people: false,
        calendar: false,
        deliveries: true,
        through: ['Amma'],
      );
      final back = QuietConfig.fromJson(_encode(c));
      expect(back.enabled, isTrue);
      expect(back.startMin, 1320);
      expect(back.endMin, 420);
      expect(back.days, {1, 7});
      expect(back.custom, isTrue);
      expect(back.people, isFalse);
      expect(back.calendar, isFalse);
      expect(back.deliveries, isTrue);
      expect(back.through, ['Amma']);
    });

    test('unreadable settings are simply off', () {
      expect(QuietConfig.fromJson('{broken').enabled, isFalse);
      expect(QuietConfig.fromJson(null).enabled, isFalse);
    });

    test('saved settings load back', () async {
      SharedPreferences.setMockInitialValues({'user_name': 'Chandan GS'});
      await QuietSettings.save(const QuietConfig(enabled: true));
      final loaded = await QuietSettings.load();
      expect(loaded.enabled, isTrue);
      expect(loaded.names, contains('Chandan'));
    });
  });

  group('retention', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('an install from before the setting keeps a week', () async {
      expect(await RetentionSettings.days(), 7);
      expect(await RetentionSettings.keepSwiped(), isTrue);
    });

    test('only the offered choices stick', () async {
      await RetentionSettings.setDays(3);
      expect(await RetentionSettings.days(), 3);
      await RetentionSettings.setDays(30);
      expect(await RetentionSettings.days(), 7);
    });

    test('expiry', () {
      final now = DateTime(2026, 11, 8, 12);
      RawData at(int days, String text) =>
          _row('x', content: text)
            ..timestamp = now.subtract(Duration(days: days));
      expect(IsarDataSource.isExpired(at(2, 'hi'), now, 7), isFalse);
      expect(IsarDataSource.isExpired(at(8, 'hi'), now, 7), isTrue);
      expect(IsarDataSource.isExpired(at(2, 'hi'), now, 1), isTrue);
      expect(IsarDataSource.isExpired(at(200, 'hi'), now, 7), isTrue);
    });
  });

  group('held', () {
    test('groups by app, busiest first', () {
      final groups = QuietHeld.group([
        _row('Gmail'),
        _row('WhatsApp', isGroup: true),
        _row('WhatsApp', isGroup: true, sender: 'B'),
      ]);
      expect(groups.first.source, 'WhatsApp');
      expect(groups.first.count, 2);
      expect(groups.first.who, 'A, B');
    });

    test('splits into groups, deliveries and the rest', () {
      final split = QuietHeld.split([
        _row('WhatsApp', isGroup: true),
        _row('Swiggy'),
        _row('SMS', content: 'Your parcel is out for delivery'),
        _row('Gmail'),
      ]);
      expect(split.groups, 1);
      expect(split.deliveries, 2);
      expect(split.other, 1);
      expect(split.total, 4);
    });

    test('status from native, even broken', () {
      final s = QuietStatus.parse(
        '{"session":{"since":1000,"start":1000,"end":2000,"count":3,'
        '"groups":1,"through":["Neha"],"keys":[]},"blocked":true,"listening":true}',
      );
      expect(s.session?.count, 3);
      expect(s.session?.through, ['Neha']);
      expect(s.session?.closedAt, isNull);
      expect(s.lastDigest, isNull);
      expect(s.blocked, isTrue);
      expect(QuietStatus.parse('nope').listening, isFalse);
      expect(QuietStatus.parse(null).session, isNull);
    });

    test('clock text', () {
      expect(quietClockOf(9 * 60), '9 AM');
      expect(quietClockOf(13 * 60 + 30), '1:30 PM');
      expect(quietCountdown(const Duration(hours: 1, minutes: 19, seconds: 46)), '1:19:46');
      expect(quietCountdown(const Duration(seconds: -5)), '0:00:00');
    });
  });
}

String _encode(QuietConfig c) {
  final json = c.toJson();
  return '{"enabled":${json['enabled']},"startMin":${json['startMin']},'
      '"endMin":${json['endMin']},"days":${json['days']},"custom":${json['custom']},'
      '"people":${json['people']},"calendar":${json['calendar']},'
      '"deliveries":${json['deliveries']},"through":["Amma"],"names":[]}';
}
