import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/core/services/home_widgets_service.dart';

void main() {
  test('reads what the previews need from the native state', () {
    final state = HomeWidgetsState.fromNative(const {
      'canPin': true,
      'placed': {'ring': 1, 'todo': 0},
      'streak': 4,
      'status': 'Ready — tap to play',
      'week': [2, 2, 3, 0, 0, 0, 0],
      'date': 'Fri 7 Nov',
      'ready': true,
      'briefingOn': false,
      'listening': true,
      'waitingKnown': true,
      'waiting': [
        {
          'name': 'Rohan',
          'source': 'WhatsApp',
          'age': 1,
          'progress': 0.6,
          'since': '1d',
        },
      ],
      'waitingCount': 3,
      'oldestDays': 1,
      'hasList': true,
      'dueToday': 2,
      'todosToday': 3,
      'tomorrow': 1,
      'next': {
        'title': 'Send Karan the deck',
        'due': '6 PM',
        'countdown': 'in 30 min',
        'app': 'Slack',
      },
      'tomorrowTitle': 'Call the bank',
      'owesYou': 2,
    });

    expect(state.placedCount('ring'), 1);
    expect(state.waiting.single.name, 'Rohan');
    expect(state.waiting.single.age, 1);
    expect(state.waiting.single.progress, closeTo(0.6, 0.001));
    expect(state.next?.title, 'Send Karan the deck');
    expect(state.next?.due, '6 PM');
    expect(state.owesYou, 2);
    expect(state.briefingOn, isFalse);
    expect(state.waitingCount, 3);
  });

  test('a state without the preview fields still reads', () {
    final state = HomeWidgetsState.fromNative(const {
      'canPin': false,
      'placed': <String, int>{},
      'streak': 0,
      'status': '',
      'week': <int>[],
    });

    expect(state.waiting, isEmpty);
    expect(state.next, isNull);
    expect(state.waitingKnown, isFalse);
    expect(state.briefingOn, isTrue);
  });
}
