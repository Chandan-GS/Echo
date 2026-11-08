import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/people/data/birthday_matcher.dart';

void main() {
  group('matchWish', () {
    const wishes = {
      'Happy birthday Neha!! 🎂🎉': 'Neha',
      'happy bday neha': 'neha',
      'HBD Rohan': 'Rohan',
      'Happy birthday to dear Neha': 'Neha',
      'happpy birthdayyy Riya': 'Riya',
      'Many many happy returns of the day Neha': 'Neha',
      'Neha happy birthday!': 'Neha',
      'Neha ko happy birthday': 'Neha',
      'Neha ji happy birthday': 'Neha',
      'Janamdin mubarak Neha': 'Neha',
      'Janmdin ki bahut bahut badhai Neha': 'Neha',
      'Neha ko janmdin ki shubhkamnayein': 'Neha',
      'birthday mubarak ho Rohan': 'Rohan',
      'जन्मदिन मुबारक नेहा': 'नेहा',
      'जन्मदिन की बहुत बहुत बधाई राहुल': 'राहुल',
      'राहुल को जन्मदिन की शुभकामनाएं': 'राहुल',
      'हैप्पी बर्थडे नेहा': 'नेहा',
      'Happy birthday Neha Sharma': 'Neha Sharma',
    };
    for (final MapEntry(:key, :value) in wishes.entries) {
      test('wish: $key', () => expect(matchWish(key)?.name, value));
    }

    const noOne = [
      'Happy birthday party planning committee meets at 6',
      'Birthday party planning: who is in?',
      "Neha's birthday party is at 7",
      'Planning a birthday surprise for Riya',
      'Whose birthday is it today',
      'Mera birthday next week hai',
      'Thanks for the birthday wishes everyone',
      'Happy birthday Neha in advance',
      'Belated happy birthday Rohan',
      'Happy birthday kisko?',
      'Yesterday was his birthday',
      'Cake order karna hai birthday ke liye',
      'Happy birthday party kal hai',
      'Forwarded: Happy birthday Neha',
      'जन्मदिन की पार्टी कब है',
    ];
    for (final text in noOne) {
      test('not a wish: $text', () => expect(matchWish(text), isNull));
    }

    test('names no one', () {
      for (final text in [
        'Happy birthday 🎉',
        'Happy birthday to you',
        'Happy birthday sir',
        'HBD bro',
        'Happy birthday dear',
        'हैप्पी बर्थडे',
      ]) {
        expect(matchWish(text), isNotNull, reason: text);
        expect(matchWish(text)!.name, isNull, reason: text);
      }
    });

    test('stops at the end of the name', () {
      expect(matchWish('Happy birthday Neha have a great one')?.name, 'Neha');
      expect(matchWish('happy birthday neha didi')?.name, 'neha');
      expect(matchWish('Happy birthday Neha, many more')?.name, 'Neha');
    });
  });

  group('birthdaysFrom', () {
    WishLine l(String sender, String text, [String group = 'College gang']) =>
        WishLine(
          sender: sender,
          text: text,
          at: DateTime(2026, 11, 8, 9),
          group: group,
        );

    test('two people across groups make a birthday', () {
      final found = birthdaysFrom([
        l('Rohan', 'Happy birthday Neha!!'),
        l('Riya', 'hbd neha', 'Office'),
      ]);
      expect(found, hasLength(1));
      expect(found.single.name, 'Neha');
      expect(found.single.groups, ['College gang', 'Office']);
      expect(found.single.wishers, ['Rohan', 'Riya']);
    });

    test('one person is not enough', () {
      expect(birthdaysFrom([l('Rohan', 'Happy birthday Neha')]), isEmpty);
    });

    test('the same person twice is not enough', () {
      expect(
        birthdaysFrom([
          l('Rohan', 'Happy birthday Neha'),
          l('Rohan', 'Happy birthday Neha!!', 'Office'),
        ]),
        isEmpty,
      );
    });

    test('an unnamed wish supports a named one in the same group', () {
      final found = birthdaysFrom([
        l('Rohan', 'Happy birthday Neha'),
        l('Priya', 'Happy birthday 🎂'),
      ]);
      expect(found.single.wishers, ['Rohan', 'Priya']);
    });

    test('an unnamed wish elsewhere does not', () {
      expect(
        birthdaysFrom([
          l('Rohan', 'Happy birthday Neha'),
          l('Priya', 'Happy birthday 🎂', 'Society'),
        ]),
        isEmpty,
      );
    });

    test('nobody wishes themselves, and the owner is no card', () {
      expect(
        birthdaysFrom([
          l('Neha', 'Happy birthday Neha'),
          l('Rohan', 'Happy birthday Neha'),
        ]),
        isEmpty,
      );
      expect(
        birthdaysFrom([
          l('Rohan', 'Happy birthday Chandan'),
          l('Riya', 'hbd chandan'),
        ], ownerNames: ['Chandan']),
        isEmpty,
      );
    });

    test('chatter about no one stays out', () {
      expect(
        birthdaysFrom([
          l('Rohan', 'birthday party planning at 6'),
          l('Riya', 'Who is bringing the birthday cake?'),
        ]),
        isEmpty,
      );
    });
  });
}
