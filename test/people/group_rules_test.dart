import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/people/data/group_rules.dart';

GroupLine line(
  String text, {
  String sender = 'Riya',
  String? addressed = 'group',
  DateTime? at,
}) => GroupLine(
  key: '$sender|$text',
  sender: sender,
  source: 'Whatsapp',
  text: text,
  at: at ?? DateTime(2026, 11, 7, 11, 42),
  thread: 'com.whatsapp:abc',
  title: 'College gang',
  addressed: addressed,
);

void main() {
  group('skipKindOf', () {
    test('sets aside noise', () {
      expect(skipKindOf('Good morning friends 🌅'), SkipKind.goodMorning);
      expect(skipKindOf('🌸 Shubhodaya 🌸'), SkipKind.goodMorning);
      expect(skipKindOf('सुप्रभात'), SkipKind.goodMorning);
      expect(skipKindOf('😂😂😂'), SkipKind.emoji);
      expect(skipKindOf('Forwarded: 10 signs'), SkipKind.forward);
      expect(skipKindOf('Sticker'), SkipKind.media);
      expect(skipKindOf('📷 Photo'), SkipKind.media);
      expect(skipKindOf('Thank you 🙏'), SkipKind.thanks);
      expect(skipKindOf('ok'), SkipKind.thanks);
    });

    test('keeps what says something', () {
      expect(skipKindOf('Everyone send ₹850 by Thursday pls'), isNull);
      expect(skipKindOf('Good morning, the meeting moved to 5'), isNull);
      expect(skipKindOf('Photo of the bill is in the drive'), isNull);
    });
  });

  group('moneyAskIn', () {
    test('finds what is asked', () {
      expect(
        moneyAskIn(line('Everyone send ₹850 by Thursday pls'))?.what,
        '₹850',
      );
      expect(moneyAskIn(line('Maintenance Rs 3,200 due by 10 Nov'))?.what, '₹3,200');
      expect(moneyAskIn(line('pay 500 rs to me'))?.what, '₹500');
      expect(moneyAskIn(line('Sabko 300 rupees dene hai'))?.what, '₹300');
      expect(
        moneyAskIn(line('Send to riya@okhdfc for the cab'))?.what,
        'a payment',
      );
      expect(moneyAskIn(line('UPI pe bhej do'))?.what, 'a payment');
    });

    test('says nothing about money talk', () {
      expect(moneyAskIn(line('I paid ₹500 for the Uber')), isNull);
      expect(moneyAskIn(line('Maine ₹500 bhej diya, maine kar diya')), isNull);
      expect(moneyAskIn(line('Dinner was ₹2000 total, not bad')), isNull);
      expect(moneyAskIn(line('Is UPI down?')), isNull);
      expect(moneyAskIn(line('See you at 5')), isNull);
    });

    test('reads the due date', () {
      final ask = moneyAskIn(line('Everyone send ₹850 by Thursday pls'))!;
      expect(ask.due?.weekday, DateTime.thursday);
    });
  });

  group('digestGroup', () {
    final now = DateTime(2026, 11, 7, 15);

    test('needs, dates and skips', () {
      final d = digestGroup([
        line('Everyone send ₹850 by Thursday pls'),
        line('Good morning all'),
        line('Hey Chandan can you share the deck?', sender: 'Vikram'),
        line('Trip on Friday at 6 AM', sender: 'Rohan'),
        line('😂😂'),
      ], ['Chandan'], now);
      expect(d.needs, hasLength(2));
      expect(d.needs.first.isMoney, isTrue);
      expect(d.needs.last.line.sender, 'Vikram');
      expect(d.dates.map((x) => x.line.sender), contains('Rohan'));
      expect(d.skipped.total, 2);
      expect(d.skippedKeys, hasLength(2));
    });

    test('paid asks are gone', () {
      final ask = line('Everyone send ₹850 by Thursday pls');
      final d = digestGroup([ask], const [], now, paid: {ask.key});
      expect(d.needs, isEmpty);
    });

    test('dates past or far off are not listed', () {
      final d = digestGroup([
        line('It was on 3 Nov at 5 PM'),
        line('Wedding on 20 Nov 2028'),
      ], const [], now);
      expect(d.dates, isEmpty);
    });

    test('the skip label reads the top kinds', () {
      final s = SkipSummary({
        SkipKind.forward: 5,
        SkipKind.goodMorning: 9,
      }, const []);
      expect(s.label, '14 good mornings and forwards');
    });
  });
}
