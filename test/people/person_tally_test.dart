import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/people/data/person_tally.dart';

RawData msg(
  String sender,
  DateTime at, {
  String source = 'Whatsapp',
  bool group = false,
  String? thread,
  String? addressed,
  String? title,
}) => RawData()
  ..source = source
  ..sender = sender
  ..content = 'hi'
  ..timestamp = at
  ..thread = thread
  ..threadTitle = title
  ..isGroup = group
  ..addressed = addressed ?? (group ? 'group' : 'direct');

MergedPerson person(
  Map<int, int> direct, {
  required DateTime lastDirect,
  required DateTime now,
  int? first,
}) {
  final week = weekOf(now);
  final weeks = {for (final e in direct.entries) week + e.key: e.value};
  return MergedPerson(
    key: 'whatsapp|amma',
    members: const ['whatsapp|amma'],
    name: 'Amma',
    sources: const ['Whatsapp'],
    direct: weeks,
    group: const {},
    firstWeek: week + (first ?? direct.keys.reduce((a, b) => a < b ? a : b)),
    lastAt: lastDirect.millisecondsSinceEpoch,
    lastDirectAt: lastDirect.millisecondsSinceEpoch,
    threads: const {},
  );
}

void main() {
  final now = DateTime(2026, 11, 11, 18); // a Wednesday

  group('personKeyFor', () {
    test('normalises spelling only', () {
      expect(personKeyFor('~Rohan  Sharma', 'Whatsapp'), 'whatsapp|rohan sharma');
      expect(personKeyFor('Rohan 🔥', 'WhatsApp'), 'whatsapp|rohan');
      expect(personKeyFor('+91 98765 43210', 'Whatsapp'), 'whatsapp|919876543210');
      expect(personKeyFor('प्रिया', 'Whatsapp'), 'whatsapp|प्रिया');
      expect(personKeyFor('🙂', 'Whatsapp'), 'whatsapp|🙂');
    });

    test('keeps apps apart', () {
      expect(
        personKeyFor('Rohan', 'Whatsapp'),
        isNot(personKeyFor('Rohan', 'Telegram')),
      );
    });
  });

  group('weeks', () {
    test('start on Monday', () {
      expect(weekOf(DateTime(2026, 11, 9)), weekOf(DateTime(2026, 11, 15)));
      expect(weekOf(DateTime(2026, 11, 8)) + 1, weekOf(DateTime(2026, 11, 9)));
    });

    test('nextMonday is always ahead', () {
      expect(nextMonday(DateTime(2026, 11, 9, 8)), DateTime(2026, 11, 16));
      expect(nextMonday(DateTime(2026, 11, 8, 23)), DateTime(2026, 11, 9));
    });
  });

  group('counting', () {
    test('keeps counts apart from group chatter', () {
      final book = TallyBook();
      book.count(msg('Riya', now, thread: 't1'));
      book.count(msg('Riya', now, group: true, thread: 'g1', title: 'Gang'));
      book.count(
        msg('Riya', now, group: true, thread: 'g1', addressed: 'mentioned'),
      );
      final p = book.people['whatsapp|riya']!;
      expect(p.direct[weekOf(now)], 2);
      expect(p.group[weekOf(now)], 1);
      expect(p.lastDirectAt, now.millisecondsSinceEpoch);
    });

    test('ignores bots, the owner, non-chat and group notices', () {
      final book = TallyBook();
      book.count(msg('Deploy bot', now, group: true));
      book.count(msg('You', now));
      book.count(msg('', now));
      book.count(msg('Whatsapp', now));
      book.count(msg('Gang', now, group: true, title: 'Gang'));
      book.count(msg('Gmail', now)..addressed = null);
      expect(book.people, isEmpty);
    });

    test('survives a round trip and prunes old weeks', () {
      final book = TallyBook(backfilled: true);
      book.count(msg('Riya', now, thread: 't1'));
      book.count(msg('Riya', now.subtract(const Duration(days: 120))));
      book.prune(now);
      final back = TallyBook.decode(book.encode());
      expect(back.backfilled, isTrue);
      final p = back.people['whatsapp|riya']!;
      expect(p.direct.keys, [weekOf(now)]);
      expect(p.threads['t1']?.isGroup, isFalse);
    });

    test('garbage decodes to empty', () {
      expect(TallyBook.decode('nope').people, isEmpty);
      expect(TallyBook.decode(null).backfilled, isFalse);
    });
  });

  group('merging', () {
    Map<String, PersonTally> book(List<RawData> ms) {
      final b = TallyBook();
      ms.forEach(b.count);
      return b.people;
    }

    test('one first name on two apps stays two people', () {
      final m = mergePeople(
        book([
          msg('Karan', now),
          msg('Karan', now, source: 'Slack'),
        ]),
      );
      expect(m, hasLength(2));
    });

    test('a full name across apps is one person', () {
      final m = mergePeople(
        book([
          msg('Karan Mehta', now),
          msg('Karan Mehta', now, source: 'Slack'),
        ]),
      );
      expect(m, hasLength(1));
      expect(m.single.sources, hasLength(2));
    });

    test('a rename in one thread is one person', () {
      final m = mergePeople(
        book([
          msg('Rohan', now, thread: 't1'),
          msg('Rohan S', now.add(const Duration(hours: 1)), thread: 't1'),
        ]),
      );
      expect(m, hasLength(1));
      expect(m.single.name, 'Rohan S');
    });

    test('a thread with three names is not evidence', () {
      final m = mergePeople(
        book([
          msg('A One', now, thread: 't1'),
          msg('B Two', now, thread: 't1'),
          msg('C Three', now, thread: 't1'),
        ]),
      );
      expect(m, hasLength(3));
    });

    test('a short and a long name on one app stay apart', () {
      final m = mergePeople(
        book([msg('Rohan', now), msg('Rohan Sharma', now)]),
      );
      expect(m, hasLength(2));
    });

    test('excluded apps are left out', () {
      final m = mergePeople(
        book([
          msg('Karan Mehta', now),
          msg('Karan Mehta', now, source: 'Slack'),
        ]),
        keep: (s) => s != 'Slack',
      );
      expect(m.single.sources, ['Whatsapp']);
    });
  });

  group('driftOf', () {
    final sixDays = now.subtract(const Duration(days: 6));

    test('daily writer gone quiet', () {
      final p = person(
        {-7: 12, -6: 14, -5: 11, -4: 13, -3: 12, -2: 10, -1: 3, 0: 0},
        lastDirect: sixDays,
        now: now,
      );
      final d = driftOf(p, now);
      expect(d, isNotNull);
      expect(d!.line, 'Usually every day. No messages in 6 days.');
      expect(d.line, isNot(contains('talk')));
    });

    test('weekly writer gone for weeks', () {
      final p = person(
        {-9: 3, -8: 2, -7: 4, -6: 3, -5: 2},
        first: -9,
        lastDirect: now.subtract(const Duration(days: 35)),
        now: now,
      );
      expect(driftOf(p, now)!.line, 'Used to be every week. No messages in 5 weeks.');
    });

    test('needs three weeks of history', () {
      final p = person(
        {-1: 20, 0: 0},
        lastDirect: sixDays,
        now: now,
      );
      expect(driftOf(p, now), isNull);
    });

    test('three weeks can be enough with a clear habit', () {
      final p = person(
        {-2: 20, -1: 1, 0: 0},
        lastDirect: sixDays,
        now: now,
      );
      expect(driftOf(p, now), isNotNull);
    });

    test('a steady rhythm is fine', () {
      final p = person(
        {-5: 7, -4: 7, -3: 7, -2: 7, -1: 7, 0: 4},
        lastDirect: now.subtract(const Duration(hours: 3)),
        now: now,
      );
      expect(driftOf(p, now), isNull);
    });

    test('someone who writes every few weeks is judged by that', () {
      final p = person(
        {-11: 5, -7: 5, -3: 5},
        first: -11,
        lastDirect: now.subtract(const Duration(days: 20)),
        now: now,
      );
      expect(driftOf(p, now), isNull);
    });

    test('too few messages to have a rhythm', () {
      final p = person(
        {-5: 1, -3: 1, -2: 1},
        first: -5,
        lastDirect: now.subtract(const Duration(days: 20)),
        now: now,
      );
      expect(driftOf(p, now), isNull);
    });

    test('the owner writing recently settles it', () {
      final p = person(
        {-7: 12, -6: 14, -5: 11, -4: 13, -3: 12, -2: 10, -1: 3, 0: 0},
        lastDirect: sixDays,
        now: now,
      );
      expect(
        driftOf(p, now, lastMine: now.subtract(const Duration(days: 2))),
        isNull,
      );
    });

    test('never twice in a week', () {
      expect(mayShowDrift(null, 100), isTrue);
      expect(mayShowDrift(100, 100), isTrue);
      expect(mayShowDrift(100, 101), isFalse);
      expect(mayShowDrift(100, 106), isFalse);
      expect(mayShowDrift(100, 107), isTrue);
    });
  });

  test('rhythm words', () {
    final p = person(
      {-3: 7, -2: 7, -1: 7},
      lastDirect: now,
      now: now,
    );
    expect(rhythmOf(p, now), 'Every day');
  });
}
