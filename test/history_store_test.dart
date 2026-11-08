import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/core/services/retention_settings.dart';
import 'package:project_echo/features/echo/data/datasources/isar_datasource.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:project_echo/features/history/data/history_store.dart';
import 'package:project_echo/features/history/data/opened_chats.dart';
import 'package:project_echo/features/history/presentation/widgets/history_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawData _row(
  String content, {
  String sender = 'Asha',
  String source = 'WhatsApp',
  DateTime? at,
  String? key,
  String? addressed,
}) => RawData()
  ..source = source
  ..sender = sender
  ..content = content
  ..timestamp = at ?? DateTime.now()
  ..noticeKey = key
  ..addressed = addressed;

void main() {
  group('tokens', () {
    test('lowercases, splits and drops repeats', () {
      expect(HistoryStore.tokens('  Parking  MAJESTIC parking '), [
        'parking',
        'majestic',
      ]);
      expect(HistoryStore.tokens('   '), isEmpty);
    });
  });

  group('days', () {
    test('groups by local day and remembers where each starts', () {
      final days = HistoryStore.daysOf([
        DateTime(2026, 11, 8, 12),
        DateTime(2026, 11, 8, 9),
        DateTime(2026, 11, 7, 23, 59),
        DateTime(2026, 11, 1),
      ]);
      expect([for (final d in days) d.count], [2, 1, 1]);
      expect([for (final d in days) d.firstIndex], [0, 2, 3]);
      expect(days.first.day, DateTime(2026, 11, 8));
    });

    test('labels follow the calendar across midnight and month ends', () {
      final now = DateTime(2026, 12, 1, 0, 5);
      expect(historyDayLabel(DateTime(2026, 12, 1), now), 'Today');
      expect(historyDayLabel(DateTime(2026, 11, 30), now), 'Yesterday');
      expect(historyDayLabel(DateTime(2026, 11, 26), now), 'Thursday');
      expect(historyDayLabel(DateTime(2026, 11, 20), now), '20 Nov');
    });
  });

  group('highlighting', () {
    const mark = TextStyle(fontSize: 1);
    String marked(List<TextSpan> spans) => spans
        .map((s) => s.style == mark ? '[${s.text}]' : s.text)
        .join();

    test('marks every match, ignoring case', () {
      expect(
        marked(highlightSpans('Parking at Majestic, PARKING B2', ['parking'], mark)),
        '[Parking] at Majestic, [PARKING] B2',
      );
    });

    test('copes with emoji, Hindi and regex characters', () {
      expect(
        marked(highlightSpans('कल मिलते हैं 😂 (a+b)', ['मिलते', '(a+b)'], mark)),
        'कल [मिलते] हैं 😂 [(a+b)]',
      );
      expect(marked(highlightSpans('plain', const [], mark)), 'plain');
    });
  });

  group('opened chats', () {
    test('reads what the listener wrote and survives junk', () {
      expect(OpenedChats.decode('{"com.whatsapp:1":1700}'), {
        'com.whatsapp:1': 1700,
      });
      expect(OpenedChats.decode('not json'), isEmpty);
      expect(OpenedChats.decode(null), isEmpty);
    });
  });

  group(
    'on a real database',
    () {
      late Directory dir;
      late Isar isar;
      final lib = _isarLibrary();

      setUpAll(() async {
        await Isar.initializeIsarCore(
          libraries: {Abi.current(): lib?.path ?? ''},
        );
      });

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        dir = await Directory.systemTemp.createTemp('echo_history_test');
        isar = await Isar.open([RawDataSchema], directory: dir.path);
      });

      tearDown(() async {
        await isar.close(deleteFromDisk: true);
        await dir.delete(recursive: true);
      });

      Future<void> put(List<RawData> rows) =>
          isar.writeTxn(() => isar.rawDatas.putAll(rows));

      HistoryChip chip(HistoryShape s, String id) =>
          s.chips.firstWhere((c) => c.id == id);

      test('counts follow the search and every chip filters', () async {
        await put([
          _row('Parking at Majestic is B2', addressed: 'direct'),
          _row('parking pass', sender: 'Rohan', addressed: 'group'),
          _row('Flat 60% off', source: 'Gmail', sender: 'Myntra')
            ..heldAt = DateTime.now(),
          _row('Water off Sunday')..swipedAt = DateTime.now(),
        ]);

        final all = await HistoryStore.shape(HistoryStore.all, '');
        expect(all.total, 4);
        expect(chip(all, HistoryStore.all).count, 4);
        expect(chip(all, HistoryStore.toYou).count, 1);
        expect(chip(all, HistoryStore.held).count, 1);
        expect(chip(all, HistoryStore.gone).count, 1);
        expect(chip(all, 'app:Whatsapp').count, 3);
        expect(chip(all, 'app:Gmail').count, 1);

        final search = await HistoryStore.shape(HistoryStore.all, 'PARKING');
        expect(search.total, 2);
        expect(chip(search, HistoryStore.toYou).count, 1);
        expect(chip(search, HistoryStore.held).count, 0);
        expect(chip(search, 'app:Gmail').count, 0);

        final app = await HistoryStore.shape('app:Gmail', '');
        expect(app.total, 1);
        final page = await HistoryStore.page('app:Gmail', '', 0);
        expect(page.single.sender, 'Myntra');
      });

      test('search needs every word, in any field', () async {
        await put([
          _row('the invoice', sender: 'Karan Mehta'),
          _row('the invoice', sender: 'Riya'),
        ]);
        final found = await HistoryStore.page('all', 'karan invoice', 0);
        expect(found.single.sender, 'Karan Mehta');
      });

      test('an excluded app never appears', () async {
        SharedPreferences.setMockInitialValues({
          'vault_blocked_categories': ['Gmail'],
        });
        await put([_row('a'), _row('b', source: 'Gmail')]);
        final shape = await HistoryStore.shape(HistoryStore.all, '');
        expect(shape.total, 1);
        expect(shape.chips.any((c) => c.source == 'Gmail'), isFalse);
        expect((await HistoryStore.page('all', '', 0)).single.source, 'WhatsApp');
      });

      test('pages are newest first, and days add up', () async {
        final at = DateTime(2026, 11, 8, 12);
        await put([
          for (var i = 0; i < 95; i++)
            _row('m$i', at: at.subtract(Duration(hours: i))),
        ]);
        final shape = await HistoryStore.shape(HistoryStore.all, '');
        expect(shape.days.fold<int>(0, (n, d) => n + d.count), 95);
        final p0 = await HistoryStore.page('all', '', 0);
        final p2 = await HistoryStore.page('all', '', 80);
        expect(p0.first.content, 'm0');
        expect(p0.length, HistoryStore.pageSize);
        expect(p2.length, 15);
        expect(p2.last.content, 'm94');
      });

      test('thousands of rows stay quick', () async {
        await put([
          for (var i = 0; i < 8000; i++)
            _row(
              'message number $i about the trip',
              at: DateTime(2026, 11, 1).add(Duration(minutes: i)),
              source: i.isEven ? 'WhatsApp' : 'Slack',
            ),
        ]);
        final sw = Stopwatch()..start();
        final shape = await HistoryStore.shape(HistoryStore.all, 'trip 79');
        final page = await HistoryStore.page('all', 'trip 79', 0);
        sw.stop();
        expect(shape.total, greaterThan(0));
        expect(page, isNotEmpty);
        expect(sw.elapsedMilliseconds, lessThan(1500));
      });

      group('leaving the shade', () {
        final at = DateTime(2026, 11, 8, 9);

        test('a swipe marks only what is still in the shade', () async {
          await put([
            _row('old', key: 'k')..removal = NoticeRemoval.app,
            _row('new', key: 'k'),
            _row('other', key: 'z'),
          ]);
          await HistoryStore.applyRemovals(isar, [
            ShadeRemoval('k', NoticeRemoval.swiped, at),
          ]);
          final rows = await isar.rawDatas.where().findAll();
          final byText = {for (final r in rows) r.content: r};
          expect(byText['old']!.swipedAt, isNull);
          expect(byText['new']!.swipedAt, at);
          expect(byText['new']!.removal, NoticeRemoval.swiped);
          expect(byText['other']!.removal, isNull);
        });

        test('an app taking it back is not a swipe', () async {
          await put([_row('a', key: 'k')]);
          await HistoryStore.applyRemovals(isar, [
            ShadeRemoval('k', NoticeRemoval.app, at),
          ]);
          final row = (await isar.rawDatas.where().findAll()).single;
          expect(row.swipedAt, isNull);
          expect(row.removal, NoticeRemoval.app);
        });

        test('a hold that did not take loses its mark', () async {
          await put([_row('a', key: 'k')..heldAt = at]);
          await HistoryStore.applyRemovals(isar, [
            ShadeRemoval('k', ShadeRemoval.notHeld, at),
          ]);
          final row = (await isar.rawDatas.where().findAll()).single;
          expect(row.heldAt, isNull);
          expect(row.removal, isNull);
        });

        test('with "keep what you swipe away" off, a swipe deletes', () async {
          await RetentionSettings.setKeepSwiped(false);
          await put([_row('a', key: 'k'), _row('b', key: 'y')]);
          await HistoryStore.applyRemovals(isar, [
            ShadeRemoval('k', NoticeRemoval.swiped, at),
          ]);
          final rows = await isar.rawDatas.where().findAll();
          expect(rows.single.content, 'b');
        });

        test('ingest saves first, so a swipe in the same round lands', () async {
          final time = DateTime.now().millisecondsSinceEpoch;
          await NotificationIngest.ingestAll([
            {
              'source': 'whatsapp',
              'sender': 'Asha',
              'content': 'hi',
              'timestamp': time,
              'noticeKey': 'k1',
              'heldAt': time,
            },
            {
              'kind': 'removal',
              'noticeKey': 'k1',
              'how': 'swiped',
              'timestamp': time + 5,
            },
          ]);
          final row = (await isar.rawDatas.where().findAll()).single;
          expect(row.noticeKey, 'k1');
          expect(row.heldAt, isNotNull);
          expect(row.swipedAt, isNotNull);
        });

        test('a removal alone, with nothing to save, is applied', () async {
          await put([_row('a', key: 'k')]);
          await NotificationIngest.ingestAll([
            {
              'kind': 'removal',
              'noticeKey': 'k',
              'how': 'opened',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            },
          ]);
          final row = (await isar.rawDatas.where().findAll()).single;
          expect(row.removal, NoticeRemoval.opened);
          expect(row.swipedAt, isNull);
        });
      });

      test('what the owner sent stays out of everything but History', () async {
        final to = _row('Can you?', sender: 'Karan')..thread = 't';
        await put([to]);
        await HistoryStore.recordSent(to, 'Sure', DateTime.now());
        final everything = await IsarDataSource.getAllEntries();
        expect(everything.single.content, 'Can you?');
        final page = await HistoryStore.page('all', '', 0);
        expect(page.length, 2);
        final line = page.firstWhere((r) => r.sent == true);
        expect(line.sender, 'You to Karan');
      });

      test('cleanup follows the setting and keeps what is still ahead', () async {
        final now = DateTime.now();
        final ahead = now.add(const Duration(days: 20));
        final d = '${ahead.day} ${_months[ahead.month - 1]}';
        await put([
          _row('two days ago', at: now.subtract(const Duration(days: 2))),
          _row('nine days ago', at: now.subtract(const Duration(days: 9))),
          _row('Goa trip on $d', at: now.subtract(const Duration(days: 9))),
        ]);
        await IsarDataSource.deleteOldNotifications();
        var left = (await isar.rawDatas.where().findAll()).map((r) => r.content);
        expect(left, containsAll(['two days ago', 'Goa trip on $d']));
        expect(left, isNot(contains('nine days ago')));

        await RetentionSettings.setDays(1);
        await IsarDataSource.deleteOldNotifications();
        left = (await isar.rawDatas.where().findAll()).map((r) => r.content);
        expect(left, ['Goa trip on $d']);
      });
    },
    skip: _isarLibrary() == null ? 'Isar core library not found' : false,
  );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Isar's native library for this computer, from isar_flutter_libs.
File? _isarLibrary() {
  final config = File('.dart_tool/package_config.json');
  if (!Platform.isMacOS || !config.existsSync()) return null;
  final packages = (jsonDecode(config.readAsStringSync()) as Map)['packages'];
  for (final p in packages as List) {
    if (p['name'] != 'isar_flutter_libs') continue;
    final root = config.uri.resolve('${p['rootUri']}/');
    final file = File.fromUri(root.resolve('macos/libisar.dylib'));
    return file.existsSync() ? file : null;
  }
  return null;
}
