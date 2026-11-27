import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:project_echo/features/vault/data/daily_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _message(int i, {String? key}) => {
  'source': 'whatsapp',
  'sender': 'Asha',
  'content': 'message $i',
  'timestamp': DateTime.now().millisecondsSinceEpoch + i,
  'thread': 'whatsapp:asha',
  'captureKey': ?key,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('live batches', () {
    test('what arrives during a save goes in the next batch, together', () async {
      final batches = <List<int>>[];
      final gate = Completer<void>();
      var saving = 0;
      var overlapped = false;
      final live = LiveBatches<int>((batch) async {
        if (++saving > 1) overlapped = true;
        batches.add(batch);
        if (batches.length == 1) await gate.future;
        saving--;
      });
      final first = live.add(1);
      final second = live.add(2);
      live.add(3);
      gate.complete();
      await Future.wait([first, second]);
      expect(batches, [
        [1],
        [2, 3],
      ]);
      expect(overlapped, isFalse);
    });

    test('a batch that fails doesn’t stop the next', () async {
      final saved = <int>[];
      final live = LiveBatches<int>((batch) async {
        if (batch.contains(1)) throw StateError('Isar closed');
        saved.addAll(batch);
      });
      await live.add(1);
      await live.add(2);
      expect(saved, [2]);
    });
  });

  group('calendar sync', () {
    final from = DateTime(2026, 11, 26);
    Map<String, dynamic> event(String title, DateTime at, String content) => {
      'source': 'Calendar',
      'sender': title,
      'content': content,
      'timestamp': at.millisecondsSinceEpoch,
    };
    String key(String title, DateTime at) =>
        NotificationIngest.calendarKey(title, at.millisecondsSinceEpoch);

    test('a moved event replaces its old time; a deleted one goes', () {
      final standup = DateTime(2026, 11, 26, 9);
      final moved = DateTime(2026, 11, 26, 11);
      final review = DateTime(2026, 11, 27, 15);
      final fetched = {
        key('Standup', moved): event('Standup', moved, '11:00 AM'),
      };
      final changes = NotificationIngest.reconcileCalendar(
        stored: [
          (id: 1, key: key('Standup', standup), at: standup, content: '9'),
          (id: 2, key: key('Review', review), at: review, content: '3'),
        ],
        fetched: fetched,
        from: from,
      );
      expect(changes.gone, [1, 2]);
      expect(changes.changed, isEmpty);
      expect(changes.fresh.single['sender'], 'Standup');
      expect(changes.fresh.single['timestamp'], moved.millisecondsSinceEpoch);
    });

    test('changed details are updated in place, the same ones left', () {
      final at = DateTime(2026, 11, 26, 9);
      final lunch = DateTime(2026, 11, 26, 13);
      final changes = NotificationIngest.reconcileCalendar(
        stored: [
          (id: 1, key: key('Standup', at), at: at, content: '9:00 - 9:15'),
          (id: 2, key: key('Lunch', lunch), at: lunch, content: 'All day'),
        ],
        fetched: {
          key('Standup', at): event('Standup', at, '9:00 - 9:30'),
          key('Lunch', lunch): event('Lunch', lunch, 'All day'),
        },
        from: from,
      );
      expect(changes.gone, isEmpty);
      expect(changes.fresh, isEmpty);
      expect(changes.changed.single, (id: 1, content: '9:00 - 9:30'));
    });

    test('yesterday’s events are history; repeats of one go', () {
      final yesterday = DateTime(2026, 11, 25, 9);
      final at = DateTime(2026, 11, 26, 9);
      final changes = NotificationIngest.reconcileCalendar(
        stored: [
          (id: 1, key: key('Old', yesterday), at: yesterday, content: ''),
          (id: 2, key: key('Standup', at), at: at, content: 'x'),
          (id: 3, key: key('Standup', at), at: at, content: 'x'),
        ],
        fetched: {key('Standup', at): event('Standup', at, 'x')},
        from: from,
      );
      expect(changes.gone, [3]);
      expect(changes.fresh, isEmpty);
    });

    test('an event under way since yesterday isn’t added again', () {
      final began = DateTime(2026, 11, 25, 22);
      final changes = NotificationIngest.reconcileCalendar(
        stored: [(id: 1, key: key('Flight', began), at: began, content: 'x')],
        fetched: {key('Flight', began): event('Flight', began, 'x')},
        from: from,
      );
      expect(changes.gone, isEmpty);
      expect(changes.fresh, isEmpty);
    });
  });

  group(
    'live and buffered copies',
    () {
      late Directory dir;
      late Isar isar;
      final acked = <String>[];
      final lib = _isarLibrary();

      setUpAll(() async {
        await Isar.initializeIsarCore(
          libraries: {Abi.current(): lib?.path ?? ''},
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('echo_native'), (
              call,
            ) async {
              if (call.method == 'ackBuffer') {
                acked.addAll(
                  List<String>.from((call.arguments as Map)['keys'] as List),
                );
              }
              return null;
            });
      });

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        NotificationIngest.forgetRecentKeys();
        acked.clear();
        dir = await Directory.systemTemp.createTemp('echo_live_test');
        isar = await Isar.open([RawDataSchema], directory: dir.path);
      });

      tearDown(() async {
        await isar.close(deleteFromDisk: true);
        await dir.delete(recursive: true);
      });

      Future<int> countedToday() async {
        final prefs = await SharedPreferences.getInstance();
        final store = jsonDecode(prefs.getString(DailyStats.key) ?? '{}');
        final today = DayStats.fromJson(
          DateTime.now(),
          store[DailyStats.dateKey(DateTime.now())],
        );
        return today.total;
      }

      test(
        'saved live, confirmed to the buffer, and the drained copy skipped',
        () async {
          final live = _message(0, key: 'live-1');
          await NotificationIngest.process(Map.of(live));
          expect(acked, ['live-1']);
          // The drain reached the buffered copy before the confirmation.
          expect(await NotificationIngest.ingestAll([Map.of(live)]), 0);
          expect(await isar.rawDatas.count(), 1);
          expect(await countedToday(), 1);
        },
      );

      test('counted once even when this engine has forgotten it', () async {
        final live = _message(0, key: 'live-2');
        await NotificationIngest.process(Map.of(live));
        // Saved by an engine that has since restarted.
        NotificationIngest.forgetRecentKeys();
        expect(await NotificationIngest.ingestAll([Map.of(live)]), 0);
        expect(await countedToday(), 1);
      });

      test('saves started together lose no counts', () async {
        await Future.wait([
          for (var i = 0; i < 6; i++)
            NotificationIngest.ingestAll([_message(i, key: 'p$i')]),
        ]);
        expect(await isar.rawDatas.count(), 6);
        expect(await countedToday(), 6);
      });
    },
    skip: _isarLibrary() == null ? 'Isar core library not found' : false,
  );
}

/// Isar's native library for this computer, from isar_community_flutter_libs.
File? _isarLibrary() {
  final config = File('.dart_tool/package_config.json');
  if (!Platform.isMacOS || !config.existsSync()) return null;
  final packages = (jsonDecode(config.readAsStringSync()) as Map)['packages'];
  for (final p in packages as List) {
    if (p['name'] != 'isar_community_flutter_libs') continue;
    final root = config.uri.resolve('${p['rootUri']}/');
    final file = File.fromUri(root.resolve('macos/libisar.dylib'));
    return file.existsSync() ? file : null;
  }
  return null;
}
