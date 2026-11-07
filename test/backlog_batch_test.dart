import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/source_packages.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A catch-up writes each store once for the whole backlog; the result must
/// be what writing them one at a time would have stored.
void main() {
  final base = DateTime.now().subtract(const Duration(hours: 30));
  DateTime at(int minutes) => base.add(Duration(minutes: minutes));

  Future<Map<String, Object>> stored(Future<void> Function() write) async {
    SharedPreferences.setMockInitialValues({});
    await write();
    final prefs = await SharedPreferences.getInstance();
    return {for (final k in prefs.getKeys()) k: prefs.get(k)!};
  }

  test("the owner's own messages, at once or one by one", () async {
    final turns = [
      for (var i = 0; i < 12; i++)
        (thread: 'chat:${i % 3}', at: at(i * 7), text: 'reply $i'),
    ];
    final batched = await stored(() => ChatContextStore.recordMyTurns(turns));
    final oneByOne = await stored(() async {
      for (final t in turns) {
        await ChatContextStore.recordMyTurn(t.thread, t.at, t.text);
      }
    });
    expect(batched, oneByOne);
    expect(batched, isNotEmpty);
  });

  test('taps and swipes, at once or one by one', () async {
    final events = [
      for (var i = 0; i < 60; i++)
        (
          thread: 'chat:${i % 4}',
          action: ['opened', 'dismissed', 'read', 'ignored'][i % 4],
          at: at(i),
        ),
    ];
    final batched = await stored(
      () => ChatContextStore.recordEngagements(events),
    );
    final oneByOne = await stored(() async {
      for (final e in events) {
        await ChatContextStore.recordEngagement(e.thread, e.action, e.at);
      }
    });
    expect(batched, oneByOne);
  });

  test("the Vault's week, at once or one by one", () async {
    final signals = [
      for (var i = 0; i < 50; i++)
        (source: ['Whatsapp', 'Slack', 'Gmail'][i % 3], at: at(i * 40)),
    ];
    final batched = await stored(() => DailyStats.countAll(signals));
    final oneByOne = await stored(() async {
      for (final s in signals) {
        await DailyStats.count(s.source, s.at);
      }
    });
    expect(batched, oneByOne);
    expect(batched[DailyStats.key], isNotNull);
  });

  test("apps' packages, at once or one by one", () async {
    final seen = {
      'Whatsapp': {'com.whatsapp': 5, 'com.whatsapp.w4b': 2},
      'Slack': {'com.Slack': 3},
    };
    final batched = await stored(() => SourcePackages.rememberAll(seen));
    final oneByOne = await stored(() async {
      for (final source in seen.entries) {
        for (final package in source.value.entries) {
          for (var i = 0; i < package.value; i++) {
            await SourcePackages.remember(source.key, package.key);
          }
        }
      }
    });
    expect(batched, oneByOne);
  });

  test('names the owner is called, learned at once', () async {
    final batched = await stored(
      () => ChatContextStore.learnSelfNames(['Sam', ' ', 'Sam', 'Samuel']),
    );
    expect(batched['echo_self_names_v1'], ['Sam', 'Samuel']);
  });
}
