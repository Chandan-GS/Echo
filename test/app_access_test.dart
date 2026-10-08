import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/source_packages.dart';
import 'package:project_echo/features/vault/data/app_access.dart';

void main() {
  group('AppAccess', () {
    test('explicit choices win; everything else follows hearNewApps', () {
      const access = AppAccess(on: {'a'}, off: {'b'});
      expect(access.hears('a'), isTrue);
      expect(access.hears('b'), isFalse);
      expect(access.hears('new'), isTrue);

      const strict = AppAccess(hearNewApps: false, on: {'a'});
      expect(strict.hears('a'), isTrue);
      expect(strict.hears('new'), isFalse);
    });

    test('withApps moves packages between on and off', () {
      final access = const AppAccess(on: {'a'}).withApps(['a', 'b'], false);
      expect(access.off, {'a', 'b'});
      expect(access.on, isEmpty);
      expect(access.withApps(['a'], true).hears('a'), isTrue);
    });

    test('turning new apps off keeps installed apps as they were', () {
      final access = const AppAccess(
        off: {'games'},
      ).withHearNewApps(false, ['chat', 'mail', 'games']);
      expect(access.hears('chat'), isTrue);
      expect(access.hears('mail'), isTrue);
      expect(access.hears('games'), isFalse);
      expect(access.hears('installed.later'), isFalse);
    });

    test('round-trips through JSON', () {
      const access = AppAccess(hearNewApps: false, on: {'a'}, off: {'b'});
      final back = AppAccess.fromJson(
        '{"hearNewApps":false,"on":["a"],"off":["b"]}',
      );
      expect(back.toJson(), access.toJson());
      expect(AppAccess.fromJson('not json').hearNewApps, isTrue);
    });
  });

  group('excludedSources', () {
    const sources = {
      'Whatsapp': {'com.whatsapp': 40},
      'Android': {'com.linkedin.android': 5, 'in.swiggy.android': 3},
    };

    test('a category is left out only when all of its apps are off', () {
      final one = excludedSources(
        access: const AppAccess(off: {'com.linkedin.android'}),
        sources: sources,
        aliases: const {},
        labels: const {},
      );
      expect(one, isNot(contains('Android')));

      final both = excludedSources(
        access: const AppAccess(
          off: {'com.linkedin.android', 'in.swiggy.android'},
        ),
        sources: sources,
        aliases: const {},
        labels: const {},
      );
      expect(both, contains('Android'));
    });

    test('uses the renamed category name', () {
      final out = excludedSources(
        access: const AppAccess(off: {'com.whatsapp'}),
        sources: sources,
        aliases: const {'Whatsapp': 'Chats'},
        labels: const {},
      );
      expect(out, {'Chats'});
    });

    test('matches older categories by app name, and keeps blocked ones', () {
      final out = excludedSources(
        access: const AppAccess(off: {'com.slack'}),
        sources: sources,
        aliases: const {},
        labels: const {'com.slack': 'Slack', 'com.whatsapp': 'WhatsApp'},
        blocked: const ['Sms'],
      );
      expect(out, {'Slack', 'Sms'});
    });
  });

  group('SourcePackages.forCategory', () {
    test('finds apps through renames, then by app name', () {
      const sources = {
        'Whatsapp': {'com.whatsapp': 40, 'com.whatsapp.w4b': 2},
      };
      expect(
        SourcePackages.forCategory(
          'Chats',
          sources: sources,
          aliases: const {'Whatsapp': 'Chats'},
          labels: const {},
        ),
        {'com.whatsapp': 40, 'com.whatsapp.w4b': 2},
      );
      expect(
        SourcePackages.forCategory(
          'Calendar',
          sources: sources,
          aliases: const {},
          labels: const {'com.google.android.calendar': 'Calendar'},
        ),
        {'com.google.android.calendar': 0},
      );
    });
  });
}
