import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/presentation/widgets/person_avatar.dart';
import 'package:project_echo/core/services/person_photos.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('project_echo/person_photos');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final vectors =
      (jsonDecode(
                File('test/fixtures/photo_key_vectors.json').readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  group('photoKey', () {
    test('matches the shared vectors', () {
      expect(vectors.length, greaterThan(10));
      for (final v in vectors) {
        expect(
          photoKey(v['name'] as String, v['source'] as String),
          v['key'],
          reason: '${v['name']} / ${v['source']}',
        );
      }
    });

    test('ignores spacing and case', () {
      expect(photoKey('  Rahul   Sharma ', 'WhatsApp'),
          photoKey('rahul sharma', 'Whatsapp'));
    });

    test('is empty for names that are not a single person', () {
      expect(photoKey('', 'WhatsApp'), isNull);
      expect(photoKey('   ', 'WhatsApp'), isNull);
      expect(photoKey('Rahul · College gang', 'WhatsApp'), isNull);
      expect(photoKey('Rahul', '  '), isNull);
    });

    test('does not lower beyond the shared range', () {
      // A Georgian capital and a Cherokee one: Dart and Android disagree.
      expect(normalisePhotoText('Ⴀ'), 'Ⴀ');
      expect(normalisePhotoText('Ꭰ'), 'Ꭰ');
      // Final sigma is not special.
      expect(normalisePhotoText('ΣΑΣ'), 'σασ');
    });
  });

  group('photoKeysFor', () {
    test('finds the source behind a renamed category', () {
      final keys = photoKeysFor('Rahul', 'Chats', {'Whatsapp': 'Chats'});
      expect(keys, [photoKey('Rahul', 'Whatsapp'), photoKey('Rahul', 'Chats')]);
    });

    test('finds every source merged into one', () {
      final keys = photoKeysFor('Rahul', 'Chats', {
        'Whatsapp': 'Chats',
        'Telegram': 'Chats',
        'Slack': 'Work',
      });
      expect(keys, [
        photoKey('Rahul', 'Telegram'),
        photoKey('Rahul', 'Whatsapp'),
        photoKey('Rahul', 'Chats'),
      ]);
    });

    test('is empty for an unusable name', () {
      expect(photoKeysFor('', 'Whatsapp', const {}), isEmpty);
    });
  });

  group('PersonPhotos', () {
    late List<MethodCall> calls;
    late Map<String, dynamic> Function(Map args) answer;

    setUp(() {
      PersonPhotos.debugReset();
      PersonPhotos.debugSupported = true;
      SharedPreferences.setMockInitialValues({});
      calls = [];
      answer = (_) => {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            if (call.method == 'resolveAll') {
              return answer(call.arguments as Map);
            }
            return true;
          });
    });

    tearDown(() {
      PersonPhotos.debugSupported = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    test('a person with no photo stays on initials and never calls', () async {
      final watched = PersonPhotos.watch('Rahul · College gang', 'Whatsapp');
      await settle();
      expect(watched.value, PersonPhoto.none);
      expect(calls, isEmpty);
    });

    test('a null source is initials', () async {
      final watched = PersonPhotos.watch('Rahul', null);
      await settle();
      expect(watched.value, PersonPhoto.none);
      expect(calls, isEmpty);
    });

    test('resolves many people in one batch', () async {
      answer = (args) => {
        for (final item in (args['items'] as List).cast<Map>())
          item['id'] as String: {
            'path': '/photos/${item['id']}.webp',
            'choice': 'auto',
            'hasDp': true,
          },
      };
      final a = PersonPhotos.watch('Rahul', 'Whatsapp');
      final b = PersonPhotos.watch('Priya', 'Whatsapp');
      final c = PersonPhotos.watch('rahul', 'WHATSAPP');
      expect(identical(a, c), isTrue);
      await settle();
      expect(calls.where((c) => c.method == 'resolveAll').length, 1);
      expect(a.value.path, isNotNull);
      expect(b.value.choice, PhotoChoice.auto);
    });

    test('a platform failure leaves initials', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(code: 'nope');
          });
      final watched = PersonPhotos.watch('Rahul', 'Whatsapp');
      await settle();
      expect(watched.value, PersonPhoto.none);
    });

    test('a change from the phone is picked up', () async {
      var path = '/photos/old.webp';
      answer = (args) => {
        for (final item in (args['items'] as List).cast<Map>())
          item['id'] as String: {
            'path': path,
            'choice': 'auto',
            'hasDp': true,
          },
      };
      final watched = PersonPhotos.watch('Rahul', 'Whatsapp');
      await settle();
      expect(watched.value.path, '/photos/old.webp');

      path = '/photos/new.webp';
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            _channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('changed', [photoKey('Rahul', 'Whatsapp')]),
            ),
            (_) {},
          );
      await settle();
      expect(watched.value.path, '/photos/new.webp');
    });

    test('a choice is sent under every key the person may have', () async {
      SharedPreferences.setMockInitialValues({
        'vault_category_aliases': '{"Whatsapp":"Chats"}',
      });
      await PersonPhotos.useInitials('Rahul', 'Chats');
      final call = calls.singleWhere((c) => c.method == 'useInitials');
      expect((call.arguments as Map)['keys'], [
        photoKey('Rahul', 'Whatsapp'),
        photoKey('Rahul', 'Chats'),
      ]);
    });

    testWidgets('a photo that cannot be read leaves the initial', (
      tester,
    ) async {
      answer = (args) => {
        for (final item in (args['items'] as List).cast<Map>())
          item['id'] as String: {
            'path': '/nowhere/gone.webp',
            'choice': 'auto',
            'hasDp': true,
          },
      };
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PersonAvatar(name: 'Rahul', size: 48)),
        ),
      );
      // No source, so no key: initials without asking the phone.
      expect(find.text('R'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: PersonAvatar(name: 'Rahul', size: 48, source: 'Whatsapp'),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.where((c) => c.method == 'resolveAll').length, 1);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('R'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('off the phone everything is a quiet no-op', () async {
      PersonPhotos.debugSupported = false;
      expect(PersonPhotos.watch('Rahul', 'Whatsapp').value, PersonPhoto.none);
      expect(await PersonPhotos.load('Rahul', 'Whatsapp'), PersonPhoto.none);
      expect(await PersonPhotos.useInitials('Rahul', 'Whatsapp'), isFalse);
      expect(await PersonPhotos.reset('Rahul', 'Whatsapp'), isFalse);
      expect(
        await PersonPhotos.choose('Rahul', 'Whatsapp'),
        PickOutcome.unavailable,
      );
      expect(calls, isEmpty);
    });
  });

  test('PersonPhoto reads the wire format', () {
    expect(
      PersonPhoto.fromWire(const {
        'path': '/a.webp',
        'choice': 'chosen',
        'hasDp': true,
      }),
      const PersonPhoto(
        path: '/a.webp',
        choice: PhotoChoice.chosen,
        hasDp: true,
      ),
    );
    expect(
      PersonPhoto.fromWire(const {'path': null, 'choice': 'initials'}),
      const PersonPhoto(choice: PhotoChoice.initials),
    );
  });
}
