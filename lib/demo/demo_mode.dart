import 'dart:io';
import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:project_echo/core/services/echo_server_service.dart';
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
/// scripted day — a made-up owner's day — built around the current
/// time, and never reads the device's notifications or calendar.
const bool kEchoDemo = bool.fromEnvironment('ECHO_DEMO');

/// The demo's theme: `--dart-define=ECHO_THEME=dark` for dark takes.
const String _theme = String.fromEnvironment(
  'ECHO_THEME',
  defaultValue: 'light',
);

/// The scripted day, relative to [now] so "now" always sits in the right
/// place on the day line and the evening's plans are still ahead.
class DemoDay {
  final DateTime now;
  DemoDay(this.now);

  DateTime get today => DateTime(now.year, now.month, now.day);
  DateTime get tomorrow => today.add(const Duration(days: 1));

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

  String get greeting => now.hour < 12
      ? 'Good morning'
      : now.hour < 17
      ? 'Good afternoon'
      : 'Good evening';

  /// The busy groups, and Echo's line on each.
  static const group = 'College gang';
  static const launch = '#launch';
  static const crit = 'Design crit';
  static const groupSummaries = {
    group:
        'The Coorg trip is on for Friday. Everyone pays Arjun by Monday, and '
        'Rohan asked if you’re driving with him.',
    launch:
        'Launch is still on for Tuesday. QA’s Android blocker is fixed, and '
        'Vikram needs your sign-off on the release notes before 5.',
    crit:
        'Riya’s landing page is ready for review. The team prefers the second '
        'hero, and wants your call by tomorrow.',
  };

  /// What Echo heard today: app, sender, message, minutes ago, and for chat
  /// messages the chat it came from (`chat`), the group's name (`group`)
  /// and, when it isn't the obvious one, who it was meant for (`to`).
  List<DemoMessage> get notifications => const [
    // People waiting on the owner, across their apps.
    DemoMessage(
      'WhatsApp',
      'Rohan',
      'Coorg on Friday? I’m driving, leaving early. You in?',
      12,
      chat: 'rohan',
    ),
    DemoMessage(
      'WhatsApp',
      'Rohan',
      'Homestay’s sorted btw',
      14,
      chat: 'rohan',
    ),
    DemoMessage(
      'Slack',
      'Vikram',
      'Can you sign off the release notes before 5?',
      20,
      chat: 'launch',
      group: launch,
      to: 'mentioned',
    ),
    DemoMessage(
      'WhatsApp',
      'Priya',
      'Landed! Thank you for the airport tips 🙌',
      25,
      chat: 'priya',
    ),
    DemoMessage(
      'Slack',
      'Karan',
      'Can you send me the deck before the review?',
      34,
      chat: 'karan',
    ),
    DemoMessage(
      'Teams',
      'Neha',
      'Demo moved to tomorrow evening. Can you send the deck by noon?',
      48,
      chat: 'neha',
    ),
    DemoMessage(
      'Slack',
      'Mahesh',
      'Still on for the testing session tomorrow?',
      60,
      chat: 'mahesh',
    ),
    DemoMessage(
      'WhatsApp',
      'Mom',
      'Did you pay the electricity bill? It’s due tomorrow',
      70,
      chat: 'mom',
    ),
    DemoMessage(
      'Telegram',
      'Kabir',
      'Can you share the Figma link for the landing page?',
      95,
      chat: 'kabir',
    ),
    DemoMessage(
      'LinkedIn',
      'Ananya Rao',
      'Hi! Open to a quick chat about the design lead role?',
      140,
      chat: 'ananya',
    ),
    // Slack #launch, busy all day.
    DemoMessage(
      'Slack',
      'Neha',
      'Launch is still on for Tuesday 🚀',
      28,
      chat: 'launch',
      group: launch,
    ),
    DemoMessage(
      'Slack',
      'Mahesh',
      'Fixed the Android blocker, PR is up',
      66,
      chat: 'launch',
      group: launch,
    ),
    DemoMessage(
      'Slack',
      'Riya',
      'Marketing wants the store screenshots by Monday',
      82,
      chat: 'launch',
      group: launch,
    ),
    DemoMessage(
      'Slack',
      'Vikram',
      'Release notes draft is in Notion',
      110,
      chat: 'launch',
      group: launch,
    ),
    DemoMessage(
      'Slack',
      'Neha',
      'QA found one blocker on Android',
      125,
      chat: 'launch',
      group: launch,
    ),
    DemoMessage(
      'Slack',
      'Karan',
      'Can we move standup to 10 tomorrow?',
      150,
      chat: 'launch',
      group: launch,
    ),
    DemoMessage(
      'Slack',
      'Neha',
      'Sure, moving it',
      148,
      chat: 'launch',
      group: launch,
    ),
    DemoMessage(
      'Slack',
      'Vikram',
      'Linear board is updated for the release',
      190,
      chat: 'launch',
      group: launch,
    ),
    // The college group.
    DemoMessage(
      'WhatsApp',
      'Riya',
      'Can we stop for breakfast on the way?',
      90,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Rohan',
      'Yes, at the usual place',
      86,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Rohan',
      'I’m driving, leaving early on Friday',
      130,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Kabir',
      'Fine, I’ll bring the speaker',
      160,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Riya',
      'Not me lol',
      170,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Kabir',
      'Who’s bringing the speaker?',
      180,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Arjun',
      'Everyone pays me by Monday for the booking 🙏',
      200,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Neel',
      'The one with the pool 😎',
      250,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Riya',
      'Which homestay??',
      260,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Arjun',
      'Coorg is ON',
      280,
      chat: 'college',
      group: group,
    ),
    DemoMessage(
      'WhatsApp',
      'Neel',
      'Homestay booked for Friday night!! 🎉',
      300,
      chat: 'college',
      group: group,
    ),
    // Teams design crit.
    DemoMessage(
      'Teams',
      'Riya',
      'Landing page is ready for review',
      100,
      chat: 'crit',
      group: crit,
    ),
    DemoMessage(
      'Teams',
      'Neha',
      'Second hero works better for me',
      104,
      chat: 'crit',
      group: crit,
    ),
    DemoMessage(
      'Teams',
      'Karan',
      'Agree, second one',
      108,
      chat: 'crit',
      group: crit,
    ),
    DemoMessage(
      'Teams',
      'Riya',
      'I’ll tidy the spacing tonight',
      115,
      chat: 'crit',
      group: crit,
    ),
    DemoMessage(
      'Teams',
      'Neha',
      'Let’s get a final call by tomorrow',
      120,
      chat: 'crit',
      group: crit,
    ),
    // Work, everywhere else.
    DemoMessage(
      'Calendar',
      'Design review',
      'Tomorrow, 11:00 AM · Google Meet',
      55,
    ),
    DemoMessage(
      'GitHub',
      'Mahesh',
      'Requested your review on “Fix sync on resume”',
      64,
    ),
    DemoMessage(
      'Jira',
      'Jira',
      'Assigned to you: Crash on login with Google',
      75,
    ),
    DemoMessage('Notion', 'Karan', 'Mentioned you in “Launch plan”', 112),
    DemoMessage(
      'Figma',
      'Riya',
      'Commented on “Landing page”: is this the final hero?',
      118,
    ),
    DemoMessage(
      'Linear',
      'Neha',
      'Moved “Onboarding polish” to In review',
      135,
    ),
    DemoMessage('Drive', 'Neha', 'Shared “Investor deck” with you', 145),
    DemoMessage(
      'Gmail',
      'Anjali Rao',
      'Re: Offer letter — please sign and send it back by Friday',
      150,
    ),
    DemoMessage('Outlook', 'Finance', 'Your expense report was approved', 210),
    DemoMessage('Zoom', 'Zoom', 'Standup starts in 10 minutes', 240),
    DemoMessage('Swiggy', 'Instamart', 'Your groceries are on the way', 230),
    DemoMessage('Messages', 'AX-HDFCBK', 'Your card was used at Swiggy', 232),
    DemoMessage(
      'YouTube',
      'YouTube',
      'New from Veritasium: The Riddle That Seems Impossible',
      310,
    ),
    DemoMessage('Calendar', 'Gym', 'Today, 7:30 AM', 560),
  ];

  /// Categories → the real apps behind them, so their icons show.
  static const packages = {
    'Whatsapp': 'com.whatsapp',
    'Slack': 'com.Slack',
    'Teams': 'com.microsoft.teams',
    'Telegram': 'org.telegram.messenger',
    'Linkedin': 'com.linkedin.android',
    'Calendar': 'com.google.android.calendar',
    'Gmail': 'com.google.android.gm',
    'Outlook': 'com.microsoft.office.outlook',
    'Github': 'com.github.android',
    'Jira': 'com.atlassian.android.jira.core',
    'Notion': 'notion.id',
    'Figma': 'com.figma.mirror',
    'Linear': 'app.linear',
    'Drive': 'com.google.android.apps.docs',
    'Zoom': 'us.zoom.videomeetings',
    'Swiggy': 'in.swiggy.android',
    'Messages': 'com.google.android.apps.messaging',
    'Youtube': 'com.google.android.youtube',
  };

  static String packageOf(String source) =>
      packages[source[0].toUpperCase() + source.substring(1).toLowerCase()] ??
      source.toLowerCase();

  String get briefing =>
      '$greeting. Rohan is driving to Coorg on Friday and wants to '
      'know if you’re in. On Slack, Karan needs the deck before tomorrow’s '
      'review, and Vikram wants your sign-off on the release notes before 5. '
      'Neha moved the demo to tomorrow evening, and Mahesh asked for your '
      'review on GitHub. Priya landed safely. Your mom says the electricity '
      'bill is due tomorrow, and the college group has the trip sorted.';
}

/// One notification in the scripted day.
class DemoMessage {
  final String source;
  final String sender;
  final String content;
  final int ago;
  final String? chat;
  final String? group;
  final String? to;

  const DemoMessage(
    this.source,
    this.sender,
    this.content,
    this.ago, {
    this.chat,
    this.group,
    this.to,
  });

  RawData toRaw(DemoDay day) {
    final e = RawData()
      ..source = source
      ..sender = sender
      ..content = content
      ..timestamp = day.ago(ago);
    if (chat != null) {
      e
        ..thread = '${DemoDay.packageOf(source)}:$chat'
        ..threadTitle = group ?? sender
        ..isGroup = group != null
        ..addressed = to ?? (group != null ? 'group' : 'direct');
    }
    return e;
  }
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
    // No name: the film stays generic, so every greeting is just the greeting.
    await prefs.setString('user_name', '');
    await prefs.setBool('analytics_enabled', false);
    // Light unless the take asks for dark: --dart-define=ECHO_THEME=dark.
    await prefs.setInt('theme_mode', _theme == 'dark' ? 2 : 1);
    await prefs.setBool('is_offline_engine', false);
    await prefs.setStringList('briefing_times', ['07:00']);
    await prefs.setString(
      'first_launch_date',
      now.subtract(const Duration(days: 41)).toIso8601String(),
    );

    // The notifications Echo heard today.
    final entries = [for (final m in day.notifications) m.toRaw(day)];
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

    // The busy groups, already summed up, so no call is made for them.
    await prefs.setString(
      'home_group_summaries_v1',
      jsonEncode({
        for (final MapEntry(key: name, value: line)
            in DemoDay.groupSummaries.entries)
          name: {
            'x': line,
            'n': day.notifications.where((m) => m.group == name).length,
            't': now.millisecondsSinceEpoch,
          },
      }),
    );

    // The to-do list, already written from what people asked.
    await writeTodoList();

    // Replies sent through Echo this week, for Profile.
    await prefs.setString(
      'echo_replies_sent_v1',
      jsonEncode([
        for (var i = 0; i < 26; i++)
          day.today
              .subtract(Duration(days: i % 6 + 1, hours: (i * 5) % 9))
              .add(const Duration(hours: 18))
              .millisecondsSinceEpoch,
      ]),
    );

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

    // On the phone, paired with a desktop (shown as such in Settings).
    if (Platform.isAndroid) {
      await prefs.setString('desktop_engine_host', '192.168.1.20');
      await prefs.setString('desktop_engine_name', 'Desktop');
    }

    // On a computer the Echo Engine is on, and the phone synced a moment ago.
    if (Platform.isMacOS || Platform.isWindows) {
      await prefs.setBool('run_desktop_engine_here', true);
      await prefs.setInt(
        EchoServerService.lastPhoneSyncKey,
        now.subtract(const Duration(seconds: 40)).millisecondsSinceEpoch,
      );
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

    final items = [
      item(
        'Sign off the release notes',
        day.today,
        '5 PM',
        'Vikram',
        mentioning: 'sign off',
      ),
      item('Send Karan the deck', day.today, null, 'Karan', mentioning: 'deck'),
      item(
        'Tell Rohan if you’re in for Friday',
        day.today,
        null,
        'Rohan',
        mentioning: 'Coorg',
      ),
      item(
        'Review Mahesh’s pull request',
        day.today,
        null,
        'Mahesh',
        mentioning: 'review on',
      ),
      item(
        'Share the Figma link with Kabir',
        day.today,
        null,
        'Kabir',
        mentioning: 'Figma',
      ),
      item('Pay the electricity bill', day.tomorrow, null, 'Mom'),
      item(
        'Send Neha the deck',
        day.tomorrow,
        '12 PM',
        'Neha',
        mentioning: 'noon',
      ),
      item(
        'Design review on Google Meet',
        day.tomorrow,
        '11 AM',
        'Design review',
      ),
      item(
        'Testing session with Mahesh',
        day.tomorrow,
        '6 PM',
        'Mahesh',
        mentioning: 'testing',
      ),
      item(
        'Pay Arjun for the trip',
        day.tomorrow,
        null,
        'Arjun',
        mentioning: 'pays',
      ),
      item(
        'Reply to Ananya about the design role',
        day.tomorrow,
        null,
        'Ananya Rao',
      ),
      item(
        'Sign and return the offer letter',
        day.tomorrow,
        null,
        'Anjali Rao',
      ),
      item('Order groceries', day.today, null, 'Instamart', done: true),
    ];
    // The week so far: things already done on earlier days, for Profile.
    const earlier = [
      ('Book the dentist', 'Calendar', 'Dentist', 6),
      ('Renew the car insurance', 'Gmail', 'Acko', 5),
      ('Send the invoice', 'Slack', 'Karan', 5),
      ('Review the onboarding copy', 'Notion', 'Neha', 4),
      ('Fix the login crash', 'Jira', 'Jira', 3),
      ('Call the plumber', 'WhatsApp', 'Mom', 3),
      ('Pay the rent', 'WhatsApp', 'Kabir', 2),
      ('Share the offsite photos', 'Slack', 'Priya', 2),
      ('Merge the sync fix', 'GitHub', 'Mahesh', 1),
      ('Book cabs for the airport', 'WhatsApp', 'Arjun', 1),
      ('Reply to the recruiter', 'LinkedIn', 'Ananya Rao', 1),
    ];
    for (final (title, app, who, daysAgo) in earlier) {
      final on = day.today.subtract(Duration(days: daysAgo));
      items.add(
        TodoItem(
          id: id++,
          title: title,
          day: on,
          time: null,
          sort: TodoItem.noTimeSort,
          sender: who,
          app: app,
          sourceText: title,
          sourceKey: '$who|${on.millisecondsSinceEpoch}',
          created: on,
          done: true,
          doneAt: on.add(Duration(hours: 11 + daysAgo)),
        ),
      );
    }
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
    final String text;
    final List<(String, String?)> from;
    if (q.contains('launch') || q.contains('slack') || q.contains('work')) {
      text =
          'Launch is still on for Tuesday [1]. Mahesh fixed the Android blocker '
          'and his PR is waiting for your review [2], and Vikram needs your '
          'sign-off on the release notes before 5 [3].';
      from = [
        ('Neha', 'Tuesday'),
        ('Mahesh', 'review on'),
        ('Vikram', 'sign off'),
      ];
    } else if (q.contains('college') ||
        q.contains('group') ||
        q.contains('catch me up')) {
      text =
          'The Coorg trip is on for Friday [1]. Everyone pays Arjun by Monday '
          'for the homestay [2], and Rohan’s driving, leaving early [3].';
      from = [('Neel', 'booked'), ('Arjun', 'pays'), ('Rohan', 'driving')];
    } else if (q.contains('friday') ||
        q.contains('rohan') ||
        q.contains('coorg')) {
      text =
          'Rohan’s driving to Coorg on Friday and leaving early [1]. He asked '
          'if you’re in, and the group has everyone paying Arjun by Monday [2].';
      from = [('Rohan', 'Coorg on Friday'), ('Arjun', 'pays')];
    } else if (q.contains('urgent')) {
      text =
          'Two things before tomorrow: the deck for Karan ahead of the review '
          '[1], and the electricity bill, which is due tomorrow [2].';
      from = [('Karan', null), ('Mom', null)];
    } else if (q.contains('tomorrow')) {
      text =
          'The design review at 11 AM on Google Meet [1], Neha’s demo in the '
          'evening, with the deck due by noon [2], and the testing session '
          'with Mahesh [3].';
      from = [('Design review', null), ('Neha', null), ('Mahesh', null)];
    } else {
      text =
          'Rohan wants to know if you’re in for Coorg on Friday [1], Karan '
          'needs the deck before the review [2], and your mom reminded you '
          'about the electricity bill [3].';
      from = [('Rohan', 'Coorg on Friday'), ('Karan', null), ('Mom', null)];
    }
    final isar = await IsarDataSource.instance;
    final all = await isar.rawDatas.where().findAll();
    final sources = [
      for (final (who, says) in from)
        ...all
            .where(
              (e) =>
                  e.sender == who && (says == null || e.content.contains(says)),
            )
            .take(1),
    ];
    return (text, sources);
  }

  /// "Draft a reply to Rohan": who it's to, and what Echo writes.
  static Future<(RawData, String)?> draft(String question) async {
    final m = RegExp(
      r'repl(?:y|ies) to (\w+)',
      caseSensitive: false,
    ).firstMatch(question);
    if (m == null) return null;
    final name = m.group(1)!.toLowerCase();
    final isar = await IsarDataSource.instance;
    final all = await isar.rawDatas.where().findAll()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final theirs = all.where((e) => e.sender.toLowerCase() == name);
    final to =
        theirs.where((e) => !e.isGroup).firstOrNull ??
        theirs.where((e) => e.addressed == 'mentioned').firstOrNull;
    if (to == null) return null;
    final text = switch (name) {
      'rohan' => 'I’m in! Happy to split fuel. See you early 🚗',
      'karan' => 'Sending it over in a bit, before the review.',
      'mom' => 'Paying it tonight, don’t worry 🙂',
      'priya' => 'So glad you landed safe! 🙌',
      'vikram' => 'Reading them now, you’ll have my sign-off by 4.',
      'neha' => 'Works for me. I’ll send the deck before noon.',
      'mahesh' => 'Yes, see you at the testing session tomorrow!',
      'kabir' => 'Here you go, sharing the Figma link now.',
      _ => 'Will get back to you soon!',
    };
    return (to, text);
  }
}
