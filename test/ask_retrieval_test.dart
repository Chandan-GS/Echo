import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/ask/ask_retrieval.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

// Sat 26 Sep 2026.
DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 9, day, hour, minute);

final now = at(26, 13, 30);
var _nextId = 1;

RawData note(String sender, String content, DateTime receivedAt,
        {String source = 'Whatsapp'}) =>
    RawData()
      ..id = _nextId++
      ..source = source
      ..sender = sender
      ..content = content
      ..timestamp = receivedAt;

final amma = note('Amma', 'Come for dinner tomorrow at 8 PM', at(25, 21));
final dentist = note('Dr Mehta Clinic', 'Your appointment is tomorrow at 11:00 AM', at(26, 9),
    source: 'Sms');
final kavya = note('Kavya', 'Movie on Sunday, 6:30 PM show', at(26, 10, 30));
final vikram = note('Vikram', 'Goa trip on Oct 3, pack light', at(26, 11));
final didi = note('Didi', 'Can you pick up medicines for dad?', at(26, 12, 30));
final ravi = note('Ravi', 'Standup today at 10:30 AM', at(26, 8));
final karan = note('Karan', 'Badminton later?', at(25, 11));
final all = [amma, dentist, kavya, vikram, didi, ravi, karan];

Set<String> senders(String question) => rankForQuestion(
      question: question,
      now: now,
      entries: all,
    ).map((r) => r.entry.sender).toSet();

void main() {
  group('time questions use resolved windows, not the literal words', () {
    test('"tomorrow" finds what is ABOUT tomorrow', () {
      final found = senders('What do I have tomorrow?');
      expect(found, containsAll(['Dr Mehta Clinic', 'Kavya']));
      // Amma said "tomorrow" yesterday — that's today, not tomorrow.
      expect(found, isNot(contains('Amma')));
      expect(found, isNot(contains('Vikram')));
      expect(found, isNot(contains('Didi')));
    });

    test('"today" finds today, including what yesterday called tomorrow', () {
      final found = senders("What's on today?");
      expect(found, containsAll(['Amma', 'Ravi', 'Didi']));
      expect(found, isNot(contains('Dr Mehta Clinic')));
    });

    test('"yesterday" finds what arrived yesterday', () {
      final found = senders('What came in yesterday?');
      expect(found, containsAll(['Amma', 'Karan']));
      expect(found, isNot(contains('Didi')));
    });

    test('"coming up" means now until the end of tomorrow', () {
      final found = senders("What's coming up?");
      expect(found, containsAll(['Amma', 'Dr Mehta Clinic', 'Kavya']));
      expect(found, isNot(contains('Ravi'))); // 10:30 AM, already over
      expect(found, isNot(contains('Vikram')));
    });
  });

  test('sender and content keywords still work', () {
    expect(senders('What did Vikram say?'), contains('Vikram'));
    expect(senders('anything about medicines'), contains('Didi'));
  });

  test('carried ids from the previous answer get a boost', () {
    final ranked = rankForQuestion(
      question: 'when is it',
      now: now,
      entries: all,
      carriedIds: {kavya.id},
      threshold: 0.2,
    );
    expect(ranked.first.entry, kavya);
  });

  group('labels', () {
    test('resolved against now, with passed items marked', () {
      expect(askTimeLabel(amma, now), 'Today (Sat 26 Sep), 8:00 PM');
      expect(askTimeLabel(dentist, now), 'Tomorrow (Sun 27 Sep), 11:00 AM');
      expect(askTimeLabel(ravi, now), 'Today (Sat 26 Sep), 10:30 AM, already over');
      expect(askTimeLabel(didi, now), 'arrived today at 12:30 PM');
    });

    test('arrival questions get the arrival time too', () {
      expect(isArrivalQuestion('what came in yesterday'), isTrue);
      expect(isArrivalQuestion("what's on tomorrow"), isFalse);
      expect(askTimeLabel(ravi, now, withArrival: true),
          'Today (Sat 26 Sep), 10:30 AM, already over; arrived today at 8:00 AM');
    });
  });

  test('small talk is recognized as a whole message only', () {
    expect(isSmallTalk('thanks!'), isTrue);
    expect(isSmallTalk('hey'), isTrue);
    expect(isSmallTalk('thanks, what did Neha say?'), isFalse);
  });
}
