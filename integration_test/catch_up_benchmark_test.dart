// How long Echo takes to catch up on two days of notifications missed while
// it was closed. Runs on a phone, in profile mode, as the separate test app
// (it clears that app's notifications and settings):
//
//   ECHO_DEMO=1 flutter drive --profile \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/catch_up_benchmark_test.dart
//
// Prints one "CATCH-UP" line per measurement.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/datasources/tflite_embedding_service.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _count = 500;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catching up on $_count notifications from two days', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final now = DateTime.now();
      final backlog = _backlog(now, _count);
      await _reset();
      // Load the model first: the first launch pays for that either way.
      await TfliteEmbeddingService.instance.getEmbedding('warm up');

      final caughtUp = Stopwatch()..start();
      final catchUp = _catchUp(backlog);

      // Ask Echo a question a moment after the app opens.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final asked = Stopwatch()..start();
      await TfliteEmbeddingService.instance.getEmbedding(
        'what is going on with the launch?',
      );
      asked.stop();

      await catchUp;
      caughtUp.stop();

      final everything = Stopwatch()..start();
      await _embedded();
      everything.stop();

      final isar = await IsarDataSource.instance;
      final stored = await isar.rawDatas.count();
      final unembedded = await isar.rawDatas.filter().embeddingIsNull().count();
      _report('notifications buffered', '$_count');
      _report('caught up (Ask and the briefing can run)', _ms(caughtUp));
      _report('a question asked mid-catch-up waited', _ms(asked));
      _report('then until every embedding is done', _ms(everything));
      _report('stored', '$stored ($unembedded without an embedding)');
    });
  });
}

/// What the app does with the buffer once it opens.
Future<void> _catchUp(List<Map<String, dynamic>> backlog) async {
  for (final item in backlog) {
    await NotificationIngest.process(item);
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits for any embedding still being made in the background.
Future<void> _embedded() async {}

Future<void> _reset() async {
  final isar = await IsarDataSource.instance;
  await isar.writeTxn(() => isar.rawDatas.clear());
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setString('user_name', 'Sam');
}

String _ms(Stopwatch s) => '${s.elapsedMilliseconds} ms';

void _report(String what, String value) {
  // ignore: avoid_print
  print('CATCH-UP | $what: $value');
}

/// [n] notifications as the listener buffers them, spread over the last two
/// days: chats one-to-one and in groups (with the owner's own replies and
/// taps), work apps, mail and promotions.
List<Map<String, dynamic>> _backlog(DateTime now, int n) {
  final r = math.Random(7);
  const people = ['Rohan', 'Priya', 'Vikram', 'Neha', 'Mahesh', 'Karan', 'Mom'];
  const groups = ['College gang', 'Family', 'Design crit', '#launch'];
  const said = [
    'Coorg on Friday? I\'m driving, leaving early. You in?',
    'Can you sign off the release notes before 5?',
    'Landed! Thank you for the airport tips',
    'Call me when you\'re free',
    'Launch is still on for Tuesday, QA signed off last night',
    'Can you send me the deck before the review tomorrow at 11?',
    'Dinner at 8:30?',
    'ok',
    'haha yes',
    'Who\'s bringing the speaker?',
    'Meeting moved to 3 PM today',
    'Did you see the new designs? The second hero is better',
  ];
  const promos = [
    '50% off on your next order, today only!',
    'Your OTP is 482913. Do not share it with anyone.',
    'Flash sale: up to 70% off',
    'Your order has been shipped',
  ];
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < n; i++) {
    final at = now
        .subtract(Duration(minutes: r.nextInt(48 * 60)))
        .millisecondsSinceEpoch;
    final roll = r.nextDouble();
    if (roll < 0.35) {
      final who = people[r.nextInt(people.length)];
      out.add({
        'source': 'WhatsApp',
        'packageName': 'com.whatsapp',
        'sender': who,
        'content': said[r.nextInt(said.length)],
        'timestamp': at,
        'thread': 'com.whatsapp:${who.hashCode.abs()}',
        'isGroup': false,
      });
    } else if (roll < 0.6) {
      final g = groups[r.nextInt(groups.length)];
      out.add({
        'source': g.startsWith('#') ? 'Slack' : 'WhatsApp',
        'packageName': g.startsWith('#') ? 'com.Slack' : 'com.whatsapp',
        'sender': people[r.nextInt(people.length)],
        'content': said[r.nextInt(said.length)],
        'timestamp': at,
        'thread': 'chat:${g.hashCode.abs()}',
        'threadTitle': g,
        'isGroup': true,
        'selfName': 'Sam',
      });
    } else if (roll < 0.66) {
      final g = groups[r.nextInt(groups.length)];
      out.add({
        'source': 'WhatsApp',
        'packageName': 'com.whatsapp',
        'sender': 'You',
        'content': 'sounds good, see you then',
        'timestamp': at,
        'thread': 'chat:${g.hashCode.abs()}',
        'fromMe': true,
      });
    } else if (roll < 0.72) {
      out.add({
        'kind': 'engagement',
        'action': r.nextBool() ? 'opened' : 'dismissed',
        'thread':
            'com.whatsapp:${people[r.nextInt(people.length)].hashCode.abs()}',
        'timestamp': at,
      });
    } else if (roll < 0.86) {
      out.add({
        'source': r.nextBool() ? 'Gmail' : 'Outlook',
        'packageName': 'com.google.android.gm',
        'sender': people[r.nextInt(people.length)],
        'content':
            'Re: Q4 planning — ${said[r.nextInt(said.length)]} '
            'Let me know by Thursday so we can lock the agenda.',
        'timestamp': at,
      });
    } else {
      out.add({
        'source': r.nextBool() ? 'Swiggy' : 'Amazon',
        'packageName': 'in.swiggy.android',
        'sender': r.nextBool() ? 'Swiggy' : 'Amazon',
        'content': promos[r.nextInt(promos.length)],
        'timestamp': at,
      });
    }
  }
  // The listener buffers them as they arrive.
  return out
    ..sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
}
