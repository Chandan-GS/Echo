import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/services/notification_ingest.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The native buffer as Dart sees it: rounds lent out until confirmed, a
/// round lent to one drainer kept from the next, and lent again after a
/// restart (BufferStoreTest covers the native side itself).
class _Buffer {
  final entries = <String, String>{};
  final lent = <String>{};
  final acked = <String>[];

  void add(String key, Map<String, dynamic> json) =>
      entries[key] = jsonEncode(json);

  Future<Map<String, String>> peek(int limit) async {
    final out = Map.fromEntries(
      entries.entries.where((e) => !lent.contains(e.key)).take(limit),
    );
    lent.addAll(out.keys);
    return out;
  }

  Future<void> ack(Iterable<String> keys) async {
    for (final k in keys) {
      entries.remove(k);
      lent.remove(k);
      acked.add(k);
    }
  }

  void restart() => lent.clear();

  Future<void> drain(
    Future<void> Function(List<Map<String, dynamic>>) save, {
    int limit = 3,
  }) => NotificationIngest.drainRounds(
    peek: () => peek(limit),
    ack: ack,
    save: save,
  );
}

Map<String, dynamic> _message(int i, {int? at}) => {
  'source': 'whatsapp',
  'sender': 'Asha',
  'content': 'message $i',
  'timestamp': at ?? DateTime.now().millisecondsSinceEpoch + i,
  'thread': 'whatsapp:asha',
};

void main() {
  group('draining in rounds', () {
    test('each round is confirmed once saved, and carries its key', () async {
      final buffer = _Buffer();
      for (var i = 0; i < 7; i++) {
        buffer.add('k$i', _message(i));
      }
      final saved = <String>[];
      await buffer.drain((items) async {
        saved.addAll(items.map((j) => j['captureKey'] as String));
      });
      expect(saved, [for (var i = 0; i < 7; i++) 'k$i']);
      expect(buffer.entries, isEmpty);
    });

    test(
      'killed mid-catch-up: only the unconfirmed round comes back',
      () async {
        final buffer = _Buffer();
        for (var i = 0; i < 6; i++) {
          buffer.add('k$i', _message(i));
        }
        var rounds = 0;
        await buffer.drain((items) async {
          // Isar went away during the second round.
          if (++rounds >= 2) throw StateError('closed');
        });
        expect(buffer.acked, ['k0', 'k1', 'k2']);
        expect(buffer.entries.keys, ['k3', 'k4', 'k5']);

        buffer.restart();
        final again = <String>[];
        await buffer.drain((items) async {
          again.addAll(items.map((j) => j['captureKey'] as String));
        });
        expect(again, ['k3', 'k4', 'k5']);
        expect(buffer.entries, isEmpty);
      },
    );

    test("one notification that won't save doesn't hold up the rest", () async {
      final buffer = _Buffer();
      for (var i = 0; i < 5; i++) {
        buffer.add('k$i', _message(i));
      }
      final saved = <String>[];
      await buffer.drain((items) async {
        if (items.any((j) => j['captureKey'] == 'k1')) {
          throw const FormatException('bad');
        }
        saved.addAll(items.map((j) => j['captureKey'] as String));
      });
      expect(saved, ['k0', 'k2', 'k3', 'k4']);
      expect(buffer.entries, isEmpty);
    });

    test('an unreadable entry is dropped, the rest saved', () async {
      final buffer = _Buffer()..add('k0', _message(0));
      buffer.entries['bad'] = '{"content": "cut sho';
      buffer.add('k2', _message(2));
      final saved = <String>[];
      await buffer.drain((items) async {
        saved.addAll(items.map((j) => j['captureKey'] as String));
      });
      expect(saved, ['k0', 'k2']);
      expect(buffer.entries, isEmpty);
    });

    test(
      'a notification arriving mid-drain is caught in a later round',
      () async {
        final buffer = _Buffer();
        for (var i = 0; i < 3; i++) {
          buffer.add('k$i', _message(i));
        }
        final saved = <String>[];
        await buffer.drain((items) async {
          if (saved.isEmpty) buffer.add('late', _message(9));
          saved.addAll(items.map((j) => j['captureKey'] as String));
        });
        expect(saved, ['k0', 'k1', 'k2', 'late']);
        expect(buffer.entries, isEmpty);
      },
    );

    test('two drainers at once share the backlog without overlap', () async {
      final buffer = _Buffer();
      for (var i = 0; i < 9; i++) {
        buffer.add('k$i', _message(i));
      }
      final app = <String>[], alarm = <String>[];
      Future<void> Function(List<Map<String, dynamic>>) into(List<String> to) =>
          (items) async {
            await Future<void>.delayed(Duration.zero);
            to.addAll(items.map((j) => j['captureKey'] as String));
          };
      await Future.wait([buffer.drain(into(app)), buffer.drain(into(alarm))]);
      expect({...app, ...alarm}, hasLength(9));
      expect(app.toSet().intersection(alarm.toSet()), isEmpty);
    });
  });

  group(
    'saving a round delivered again',
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
        dir = await Directory.systemTemp.createTemp('echo_drain_test');
        // IsarDataSource reuses the instance already open.
        isar = await Isar.open([RawDataSchema], directory: dir.path);
      });

      tearDown(() async {
        await isar.close(deleteFromDisk: true);
        await dir.delete(recursive: true);
      });

      Map<String, dynamic> keyed(int i, String key) =>
          _message(i)..['captureKey'] = key;

      test("doesn't save a notification twice", () async {
        final round = [keyed(0, 'k0'), keyed(1, 'k1'), keyed(2, 'k2')];
        expect(await NotificationIngest.ingestAll(round), 3);
        // The app died before confirming; the next drain brings them back,
        // with one that arrived since.
        final again = [
          keyed(0, 'k0'),
          keyed(1, 'k1'),
          keyed(2, 'k2'),
          keyed(3, 'k3'),
        ];
        expect(await NotificationIngest.ingestAll(again), 1);
        expect(await isar.rawDatas.count(), 4);
        final keys = await isar.rawDatas.where().captureKeyProperty().findAll();
        expect(keys.toSet(), {'k0', 'k1', 'k2', 'k3'});
      });

      test(
        'live notifications, which have no key, are saved as before',
        () async {
          final live = _message(0);
          await NotificationIngest.process(Map.of(live));
          await NotificationIngest.process(Map.of(live));
          expect(await isar.rawDatas.count(), 2);
        },
      );
    },
    skip: _isarLibrary() == null ? 'Isar core library not found' : false,
  );
}

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
