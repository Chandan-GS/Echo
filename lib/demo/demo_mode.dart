import 'dart:io';
import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:project_echo/core/services/source_packages.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/todo/data/todo_item.dart';
import 'package:project_echo/features/todo/data/todo_store.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Echo Demo", the build used to film Echo: `--dart-define=ECHO_DEMO=true`
/// (and `ECHO_DEMO=1` in the environment, which gives Android its own app id
/// so it installs beside the real app). It starts every launch on the same
/// scripted day — a made-up Chandan's Saturday — built around the current
/// time, and never reads the device's notifications or calendar.
const bool kEchoDemo = bool.fromEnvironment('ECHO_DEMO');

/// The scripted day, relative to [now] so "now" always sits in the right
/// place on the day line and the evening's plans are still ahead.
class DemoDay {
  final DateTime now;
  DemoDay(this.now);

  DateTime get today => DateTime(now.year, now.month, now.day);
  DateTime get tomorrow => today.add(const Duration(days: 1));

  /// Dinner: the next half hour at least an hour and a quarter away, if
  /// that's still today; otherwise tomorrow evening.
  DateTime get dinner {
    final soon = now.add(const Duration(minutes: 75));
    final t = DateTime(
      soon.year,
      soon.month,
      soon.day,
      soon.hour,
      soon.minute <= 30 ? 30 : 0,
    ).add(Duration(hours: soon.minute <= 30 ? 0 : 1));
    return t.day == now.day && t.hour <= 22
        ? t
        : tomorrow.add(const Duration(hours: 20, minutes: 30));
  }

  bool get dinnerTonight => dinner.day == now.day;

  /// Something always still ahead tonight: calling Mom back at the next half
  /// hour that's at least 30 minutes away (null only in the last half hour
  /// of the day).
  DateTime? get call {
    final soon = now.add(const Duration(minutes: 30));
    final t = DateTime(
      soon.year,
      soon.month,
      soon.day,
      soon.hour,
      soon.minute <= 30 ? 30 : 0,
    ).add(Duration(hours: soon.minute <= 30 ? 0 : 1));
    return t.day == now.day ? t : null;
  }

  DateTime get review => tomorrow.add(const Duration(hours: 11));
  DateTime get settlement => tomorrow.add(const Duration(hours: 15));
  DateTime get arjunLands => tomorrow.add(const Duration(hours: 22));

  /// A time earlier today, [minutesAgo] before now but not before 7 AM.
  DateTime ago(int minutesAgo) {
    final t = now.subtract(Duration(minutes: minutesAgo));
    final earliest = today.add(const Duration(hours: 7));
    return t.isBefore(earliest)
        ? earliest.add(Duration(minutes: minutesAgo % 50))
        : t;
  }

  static String clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute == 0 ? '' : ':${t.minute.toString().padLeft(2, '0')}';
    return '$h$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String get dinnerWhen => dinnerTonight
      ? '${clock(dinner)} tonight'
      : 'tomorrow at ${clock(dinner)}';

  /// source, sender, content, minutes ago
  List<(String, String, String, int)> get notifications => [
    ('WhatsApp', 'Rohan', 'Booked Toit for $dinnerWhen 🎉 you in?', 18),
    ('WhatsApp', 'Rohan', 'Wear something warm, we\'re on the terrace', 16),
    (
      'Slack',
      'Karan',
      'Can you send me the Q3 deck before the review tomorrow?',
      34,
    ),
    ('Slack', '#design', 'Neha: the design review moved to tomorrow 11 AM', 52),
    ('Calendar', 'Design review', 'Tomorrow, 11:00 AM · Google Meet', 55),
    (
      'WhatsApp',
      'Mom',
      'Did you pay the electricity bill? It\'s due tomorrow',
      70,
    ),
    (
      'WhatsApp',
      'Arjun',
      'Landing tomorrow at 10 PM, can you pick me up from the airport?',
      96,
    ),
    (
      'Gmail',
      'Razorpay',
      'Your settlement of ₹18,240 is scheduled for tomorrow',
      120,
    ),
    (
      'Gmail',
      'Anjali Rao',
      'Re: Offer letter — please sign and send it back by Friday',
      150,
    ),
    (
      'WhatsApp',
      'Flatmates',
      'Kabir: rent\'s due on the 1st, send your share when you can',
      175,
    ),
    ('Zomato', 'Zomato', 'Your order from Truffles is out for delivery', 200),
    ('Swiggy', 'Instamart', 'Groceries arriving in 9 minutes', 230),
    ('LinkedIn', 'LinkedIn', 'Ananya Rao viewed your profile', 260),
    ('Messages', 'AX-HDFCBK', 'Card ending 4411 used for ₹640 at Swiggy', 232),
    (
      'YouTube',
      'YouTube',
      'New from Veritasium: The Riddle That Seems Impossible',
      300,
    ),
    ('Slack', '#general', 'Priya: offsite photos are up in the drive 📸', 320),
    ('WhatsApp', 'Rohan', 'Also, did you see Mira\'s wedding invite?', 340),
    ('Gmail', 'Google Play Console', 'Your closed test has 12 testers', 380),
    ('Slack', 'Karan', 'Great work on the launch btw', 410),
    (
      'WhatsApp',
      'Mom',
      call == null
          ? 'Call me when you\'re free'
          : 'Call me at ${clock(call!)} tonight? Nothing urgent',
      45,
    ),
    ('Calendar', 'Gym', 'Today, 7:30 AM', 560),
  ];

  /// Categories → the real apps behind them, so their icons show.
  static const packages = {
    'Whatsapp': 'com.whatsapp',
    'Slack': 'com.Slack',
    'Calendar': 'com.google.android.calendar',
    'Gmail': 'com.google.android.gm',
    'Zomato': 'com.application.zomato',
    'Swiggy': 'in.swiggy.android',
    'Linkedin': 'com.linkedin.android',
    'Messages': 'com.google.android.apps.messaging',
    'Youtube': 'com.google.android.youtube',
  };

  String get briefing =>
      'Good evening, Chandan. Rohan has booked Toit for $dinnerWhen, on the '
      'terrace, so bring something warm. Tomorrow the design review moves to '
      '11 AM on Google Meet, and Karan wants the Q3 deck before then. Razorpay '
      'settles ₹18,240 tomorrow, and your mom says the electricity bill is due '
      'the same day. Arjun lands at 10 PM tomorrow and asked if you can pick '
      'him up from the airport. Anjali needs the offer letter signed by Friday.';
}

class DemoSeed {
  DemoSeed._();

  /// Replaces everything with the scripted day. Runs on every cold start of
  /// the demo build, so each take begins the same way.
  static Future<void> seed() async {
    if (!kEchoDemo) return;
    final day = DemoDay(DateTime.now());
    final now = day.now;
    final prefs = await SharedPreferences.getInstance();
    // App icons given to the desktop demo (it can't read the phone's) survive
    // the reset.
    final icons = prefs.getString('synced_app_icons');
    await prefs.clear();
    if (icons != null) await prefs.setString('synced_app_icons', icons);

    // Who, and how the app is set up.
    await prefs.setBool('onboarding_finished', true);
    await prefs.setString('user_name', 'Chandan');
    await prefs.setBool('analytics_enabled', false);
    await prefs.setInt('theme_mode', 2); // dark
    await prefs.setBool('is_offline_engine', false);
    await prefs.setStringList('briefing_times', ['07:00']);
    await prefs.setString(
      'first_launch_date',
      now.subtract(const Duration(days: 41)).toIso8601String(),
    );

    // The notifications Echo heard today.
    final entries = [
      for (final (source, sender, content, ago) in day.notifications)
        RawData()
          ..source = source
          ..sender = sender
          ..content = content
          ..timestamp = day.ago(ago),
    ];
    final isar = await IsarDataSource.instance;
    await isar.writeTxn(() async {
      await isar.rawDatas.clear();
      await isar.rawDatas.putAll(entries);
    });
    await prefs.setString(
      SourcePackages.key,
      jsonEncode({
        for (final e in DemoDay.packages.entries) e.key: {e.value: 20},
      }),
    );

    // This morning's briefing, made at 7:02.
    await prefs.setString('cached_briefing_date', dayKey(now));
    await prefs.setString(
      'cached_briefing_time',
      day.today.add(const Duration(hours: 7, minutes: 2)).toIso8601String(),
    );
    await prefs.setString('cached_briefing_text', day.briefing);

    // No to-do list yet: making it is part of the film (see [writeTodoList]).

    // A week of numbers for the Vault, and a streak.
    await prefs.setString(DailyStats.key, jsonEncode(_week(day)));
    final heard = [
      for (var i = 6; i >= 0; i--)
        if (i != 3) dayKey(day.today.subtract(Duration(days: i))),
    ];
    await prefs.setString('streak_heard_csv', heard.join(','));
    await prefs.setString('streak_last_heard_date', dayKey(day.today));
    await prefs.setInt('streak_current', 3);
    await prefs.setInt('streak_longest', 12);
    await prefs.setInt('briefings_heard_total', 34);

    // On a computer there's nothing to tap, so the list is already made, and
    // the Echo Engine is on (as when the phone hands its thinking over).
    if (Platform.isMacOS || Platform.isWindows) {
      await writeTodoList();
      await prefs.setBool('run_desktop_engine_here', true);
    }
  }

  /// The scripted to-do list, as "Make a to-do list" writes it in the demo.
  static Future<void> writeTodoList() async {
    final day = DemoDay(DateTime.now());
    final now = day.now;
    final isar = await IsarDataSource.instance;
    final entries = await isar.rawDatas.where().findAll();
    RawData source(String sender, [String? mentioning]) => entries.firstWhere(
      (e) =>
          e.sender == sender &&
          (mentioning == null || e.content.contains(mentioning)),
    );
    var id = 1;
    TodoItem item(
      String title,
      DateTime on,
      String? time,
      String sender, {
      bool done = false,
      String? mentioning,
    }) {
      final e = source(sender, mentioning);
      final at = time == null ? null : _startOf(time, on);
      return TodoItem(
        id: id++,
        title: title,
        day: DateTime(on.year, on.month, on.day),
        time: time,
        sort: at == null ? TodoItem.noTimeSort : at.hour * 60 + at.minute,
        sender: e.sender,
        app: e.source,
        sourceText: e.content,
        sourceKey: '${e.sender}|${e.timestamp.millisecondsSinceEpoch}',
        done: done,
        doneAt: done ? day.ago(40) : null,
        created: now.subtract(const Duration(seconds: 1)),
      );
    }

    final dinnerDay = day.dinnerTonight ? day.today : day.tomorrow;
    final items = [
      item(
        'Dinner with Rohan at Toit',
        dinnerDay,
        DemoDay.clock(day.dinner),
        'Rohan',
      ),
      item('Send Karan the Q3 deck', day.today, null, 'Karan'),
      item(
        'Call Mom back',
        day.today,
        day.call == null ? null : DemoDay.clock(day.call!),
        'Mom',
        mentioning: 'Call me',
      ),
      item('Order groceries', day.today, null, 'Instamart', done: true),
      item('Send Kabir your share of the rent', day.today, null, 'Flatmates'),
      item(
        'Design review on Google Meet',
        day.tomorrow,
        '11 AM',
        'Design review',
      ),
      item(
        'Pay the electricity bill',
        day.tomorrow,
        null,
        'Mom',
        mentioning: 'electricity',
      ),
      item(
        'Sign and return the offer letter',
        day.tomorrow,
        null,
        'Anjali Rao',
      ),
      item('Pick Arjun up from the airport', day.tomorrow, '10 PM', 'Arjun'),
    ];
    await TodoStore().save(
      items,
      TodoMeta(madeAt: now, updatedAt: now, nextId: id),
    );
  }

  /// Six earlier days of counts (today comes from the notifications above).
  static Map<String, dynamic> _week(DemoDay day) {
    const shape = [
      1,
      0,
      0,
      0,
      0,
      1,
      3,
      8,
      13,
      17,
      12,
      9,
      8,
      10,
      7,
      6,
      9,
      12,
      10,
      8,
      7,
      5,
      3,
      2,
    ];
    const scale = [0.2, 0.27, 0.3, 0.24, 0.32, 0.26];
    const apps = [
      {'Whatsapp': 12, 'Swiggy': 4, 'Slack': 3},
      {'Slack': 13, 'Whatsapp': 11, 'Gmail': 6},
      {'Slack': 15, 'Whatsapp': 12, 'Gmail': 7},
      {'Whatsapp': 11, 'Slack': 9, 'Gmail': 5},
      {'Slack': 16, 'Whatsapp': 13, 'Calendar': 4},
      {'Whatsapp': 13, 'Slack': 10, 'Gmail': 6},
    ];
    return {
      for (var i = 0; i < 6; i++)
        DailyStats.dateKey(day.today.subtract(Duration(days: 6 - i))): {
          'h': [
            for (var h = 0; h < 24; h++)
              ((shape[h] * scale[i]) + ((h * 7 + i * 3) % 5) - 2).round().clamp(
                0,
                99,
              ),
          ],
          'a': apps[i],
        },
    };
  }

  static DateTime? _startOf(String time, DateTime day) {
    final m = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',
      caseSensitive: false,
    ).firstMatch(time.trim());
    if (m == null) return null;
    var hour = int.parse(m.group(1)!) % 12;
    if (m.group(3)!.toUpperCase() == 'PM') hour += 12;
    return DateTime(
      day.year,
      day.month,
      day.day,
      hour,
      int.parse(m.group(2) ?? '0'),
    );
  }
}

/// Ask Echo's answers in the demo: scripted, so every take reads the same,
/// with the notifications they came from as sources.
class DemoAsk {
  DemoAsk._();

  static Future<(String, List<RawData>)> answer(String question) async {
    final q = question.toLowerCase();
    final day = DemoDay(DateTime.now());
    final String text;
    final List<String> from;
    if (q.contains('miss')) {
      text =
          'Rohan booked Toit for ${day.dinnerWhen}. Karan asked for the Q3 deck '
          'before tomorrow\'s 11 AM review, and your mom reminded you the '
          'electricity bill is due tomorrow.';
      from = ['Rohan', 'Karan', 'Mom'];
    } else if (q.contains('urgent')) {
      text =
          'Two things before tomorrow: the Q3 deck for Karan ahead of the '
          '11 AM review, and the electricity bill, which is due tomorrow.';
      from = ['Karan', 'Mom'];
    } else if (q.contains('tomorrow')) {
      text =
          'The design review at 11 AM on Google Meet, Razorpay settling '
          '₹18,240, and Arjun landing at 10 PM. He asked if you can pick him '
          'up from the airport.';
      from = ['Design review', 'Razorpay', 'Arjun'];
    } else if (q.contains('reply')) {
      text =
          'Arjun is waiting to hear about the airport pickup, and Anjali '
          'needs the offer letter signed by Friday.';
      from = ['Arjun', 'Anjali Rao'];
    } else {
      text =
          'Rohan booked a table at Toit for ${day.dinnerWhen}, on the terrace, '
          'and asked if you\'re in. He says to bring something warm.';
      from = ['Rohan'];
    }
    final isar = await IsarDataSource.instance;
    final all = await isar.rawDatas.where().findAll();
    final sources = [
      for (final who in from) ...all.where((e) => e.sender == who).take(1),
    ];
    return (text, sources);
  }
}
