import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/context/chat_context_store.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/waiting/wait_intent.dart';
import 'package:project_echo/features/echo/data/waiting/wait_model.dart';
import 'package:project_echo/features/echo/data/waiting/waiting_store.dart';
import 'package:project_echo/features/todo/data/todo_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Sun 8 Nov 2026, 4:12 PM.
final now = DateTime(2026, 11, 8, 16, 12);
DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
    now.subtract(Duration(days: days, hours: hours, minutes: minutes));

RawData msg(
  String sender,
  String content,
  DateTime when, {
  String? thread,
  bool group = false,
  String? title,
  Addressed addressed = Addressed.direct,
}) => RawData()
  ..source = 'WhatsApp'
  ..sender = sender
  ..content = content
  ..timestamp = when
  ..thread = thread ?? 'wa:$sender'
  ..threadTitle = title ?? sender
  ..isGroup = group
  ..addressed = addressed.name;

MyTurns turns(Map<String, List<(DateTime, String)>> byThread) => MyTurns({
  for (final e in byThread.entries)
    e.key: [for (final (t, x) in e.value) MyTurn(t, x)],
});

WaitingFeed compose(
  List<RawData> entries, {
  MyTurns my = const MyTurns({}),
  WaitFeedback? fb,
  Map<String, bool> verdicts = const {},
  Map<String, int> opened = const {},
}) => WaitingStore.compose(
  entries,
  my,
  now,
  feedback: fb,
  verdicts: verdicts,
  opened: opened,
);

List<String> names(WaitingFeed f) =>
    f.waiting.map((w) => w.message.sender).toList();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WaitModel.embed = (_) async => throw StateError('no model in tests');
  });

  group('the list', () {
    test('spans the retained window, oldest first, with ages', () {
      final feed = compose([
        msg('Neha', 'Can you share the link?', ago(hours: 1)),
        msg('Rohan', 'You in?', ago(hours: 20)),
        msg('Amma', 'Call when free', ago(days: 2)),
      ]);
      expect(names(feed), ['Amma', 'Rohan', 'Neha']);
      expect(feed.waiting.map((w) => w.ageBand), [2, 1, 0]);
      expect(feed.waiting.first.since, '2 days');
      expect(feed.waiting[1].since, 'Since yesterday');
      expect(feed.waiting.last.since, '1 hr');
      expect(feed.waiting.first.ageProgress, greaterThan(0.7));
      expect(feed.waiting.last.ageProgress, closeTo(0.3, 0.01));
    });

    test('an ok goes to the dashed row, not the list', () {
      final feed = compose([msg('Karan', 'ok thanks', ago(minutes: 10))]);
      expect(feed.waiting, isEmpty);
      expect(feed.acks.single.reason.label, 'Only a thank-you');
    });

    test('an ok after an unanswered ask keeps the ask', () {
      final feed = compose([
        msg('Karan', 'ok', ago(minutes: 5)),
        msg('Karan', 'Can you send the deck?', ago(minutes: 30)),
      ]);
      expect(feed.waiting.single.message.content, 'Can you send the deck?');
      expect(feed.acks, isEmpty);
    });

    test('group chatter stays out', () {
      final feed = compose([
        msg(
          'Riya',
          'Can someone bring chips?',
          ago(minutes: 4),
          thread: 'wa:gang',
          title: 'College gang',
          group: true,
          addressed: Addressed.group,
        ),
      ]);
      expect(feed.waiting, isEmpty);
    });

    test('the owner writing in the chat clears it', () {
      final m = msg('Rohan', 'You in?', ago(hours: 3));
      expect(
        compose(
          [m],
          my: turns({
            m.thread!: [(ago(hours: 1), 'Yes!')],
          }),
        ).waiting,
        isEmpty,
      );
    });

    test('a later message puts the chat back', () {
      final feed = compose(
        [
          msg('Rohan', 'What time?', ago(minutes: 20)),
          msg('Rohan', 'You in?', ago(hours: 3)),
        ],
        my: turns({
          'wa:Rohan': [(ago(hours: 1), 'Yes!')],
        }),
      );
      expect(feed.waiting.single.message.content, 'What time?');
    });
  });

  group('opened or read in its own app', () {
    final m = msg('Rohan', 'You in?', ago(hours: 3));

    test('clears the chat', () {
      final at = ago(hours: 1).millisecondsSinceEpoch;
      expect(compose([m], opened: {m.thread!: at}).waiting, isEmpty);
    });

    test('opened before the message came in does not', () {
      final at = ago(hours: 4).millisecondsSinceEpoch;
      expect(compose([m], opened: {m.thread!: at}).waiting, hasLength(1));
    });

    test('a newer message brings it back', () {
      final at = ago(hours: 1).millisecondsSinceEpoch;
      final feed = compose(
        [msg('Rohan', 'hello??', ago(minutes: 10)), m],
        opened: {m.thread!: at},
      );
      expect(feed.waiting.single.message.content, 'hello??');
    });

    test('no record of it changes nothing', () {
      expect(compose([m]).waiting, hasLength(1));
    });
  });

  group('expiry', () {
    test('drops off after three days', () {
      expect(
        compose([msg('Amma', 'Can you call?', ago(days: 3, hours: 1))]).waiting,
        isEmpty,
      );
    });

    test('stays while its deadline is ahead', () {
      final feed = compose([
        msg('Amma', 'Can you pay the bill by 12 Nov?', ago(days: 4)),
      ]);
      expect(feed.waiting, hasLength(1));
    });

    test('goes once the deadline has passed', () {
      expect(
        compose([msg('Amma', 'Can you pay by 5 Nov?', ago(days: 4))]).waiting,
        isEmpty,
      );
    });
  });

  group('the model', () {
    test('unsure stays on the list until it says otherwise', () {
      final m = msg('Riya', 'Flight lands 7:40, terminal 2', ago(hours: 1));
      final unsure = compose([m]);
      expect(unsure.waiting.single.reason.kind, WaitKind.unsure);
      expect(unsure.grey, [m.content]);

      final said = compose([m], verdicts: {WaitModel.keyFor(m.content): false});
      expect(said.waiting, isEmpty);
      expect(said.acks.single.reason.needsReply, isFalse);
      expect(said.grey, isEmpty);

      final needs = compose([m], verdicts: {WaitModel.keyFor(m.content): true});
      expect(needs.waiting.single.reason.label, 'Looks like it needs a reply');
    });

    test('nearer one side, or too close to call', () {
      const needs = [
        [1.0, 0.0],
      ];
      const none = [
        [0.0, 1.0],
      ];
      expect(resolveGrey([0.9, 0.1], needs, none), isTrue);
      expect(resolveGrey([0.1, 0.9], needs, none), isFalse);
      expect(resolveGrey([0.5, 0.5], needs, none), isNull);
      expect(resolveGrey([], needs, none), isNull);
    });

    test('an absent model leaves things unsure and never throws', () async {
      expect(await WaitModel.resolve(['Flight lands at 7']), 0);
      expect(await WaitModel.cached(), isEmpty);
    });

    test('the model is only asked about the grey zone', () {
      final feed = compose([msg('Karan', 'Can you send it?', ago(hours: 1))]);
      expect(feed.grey, isEmpty);
    });
  });

  group('what the owner says survives a restart', () {
    WaitingItem item(RawData m) => compose([m]).waiting.single;
    final m = msg('Rohan', 'You in?', ago(hours: 2));

    WaitFeedback reloaded(WaitFeedback fb) =>
        WaitFeedback.fromJson(Map<String, dynamic>.from(fb.toJson()));

    test('no reply needed removes it and teaches the phrase', () async {
      await WaitingStore.markNoReplyNeeded(item(m));
      final fb = reloaded(await WaitingStore.feedback());
      final feed = compose([m], fb: fb);
      expect(feed.waiting, isEmpty);
      expect(feed.acks.single.reason.label, 'You said no reply needed');

      // The same words from the same person, later.
      final again = msg('Rohan', 'You in?', ago(minutes: 5));
      expect(compose([again], fb: fb).waiting, isEmpty);

      // The same words from someone else are still asked.
      final other = msg('Karan', 'You in?', ago(minutes: 5));
      expect(compose([other], fb: fb).waiting, hasLength(1));
    });

    test('two people saying the same thing counts for everyone', () async {
      await WaitingStore.markNoReplyNeeded(item(m));
      await WaitingStore.markNoReplyNeeded(
        item(msg('Karan', 'You in?', ago(hours: 1))),
      );
      final fb = await WaitingStore.feedback();
      expect(
        compose([msg('Neha', 'You in?', ago(minutes: 5))], fb: fb).waiting,
        isEmpty,
      );
    });

    test('after three, a person’s unclear messages stay off', () async {
      for (var i = 0; i < 3; i++) {
        await WaitingStore.markNoReplyNeeded(
          item(msg('Riya', 'Are you there $i?', ago(hours: 3 - i))),
        );
      }
      final fb = await WaitingStore.feedback();
      expect(
        compose([
          msg('Riya', 'Flight lands at 7', ago(minutes: 1)),
        ], fb: fb).waiting,
        isEmpty,
      );
      // A clear question still gets through.
      expect(
        compose([
          msg('Riya', 'Can you pick me up?', ago(minutes: 1)),
        ], fb: fb).waiting,
        hasLength(1),
      );
    });

    test('“It does” puts it back and unlearns it', () async {
      final ok = msg('Karan', 'ok', ago(hours: 1));
      await WaitingStore.markNeedsReply(compose([ok]).acks.single);
      var fb = await WaitingStore.feedback();
      expect(compose([ok], fb: fb).waiting, hasLength(1));
      expect(
        compose([msg('Karan', 'ok', ago(minutes: 1))], fb: fb).waiting,
        hasLength(1),
      );

      await WaitingStore.markNoReplyNeeded(item(m));
      fb = await WaitingStore.feedback();
      expect(fb.phraseIsOff(waitPhrase(m.content), item2Key(m)), isTrue);
      await WaitingStore.markNeedsReply(item(m));
      fb = await WaitingStore.feedback();
      expect(compose([m], fb: fb).waiting, hasLength(1));
      expect(fb.phraseOff.containsKey(waitPhrase(m.content)), isFalse);
    });

    test('swiped away: gone, and teaches nothing', () async {
      await WaitingStore.markHandled(item(m));
      final fb = await WaitingStore.feedback();
      final feed = compose([m], fb: fb);
      expect(feed.waiting, isEmpty);
      expect(feed.acks, isEmpty);
      expect(fb.phraseOff, isEmpty);
      expect(fb.senderOff, isEmpty);
      // New message, new item.
      final next = msg('Rohan', 'You in?', ago(minutes: 1));
      expect(compose([m, next], fb: fb).waiting, hasLength(1));
    });

    test('undo brings it back', () async {
      await WaitingStore.markHandled(item(m));
      await WaitingStore.undoHandled(item(m));
      final fb = await WaitingStore.feedback();
      expect(compose([m], fb: fb).waiting, hasLength(1));
    });

    test('a holding reply doesn’t clear it, a real one does', () async {
      await WaitingStore.markHeld(item(m), text: 'Saw this!');
      final fb = await WaitingStore.feedback();
      final held = turns({
        m.thread!: [(ago(minutes: 30), 'Saw this!')],
      });
      final feed = compose([m], fb: fb, my: held);
      expect(feed.waiting.single.held, isTrue);

      // Opening the chat doesn't count against a held reply either.
      expect(
        compose(
          [m],
          fb: fb,
          my: held,
          opened: {m.thread!: ago(minutes: 20).millisecondsSinceEpoch},
        ).waiting,
        hasLength(1),
      );

      final real = turns({
        m.thread!: [(ago(minutes: 30), 'Saw this!'), (ago(minutes: 5), 'Yes')],
      });
      expect(compose([m], fb: fb, my: real).waiting, isEmpty);
    });

    test('a broken store starts clean', () async {
      SharedPreferences.setMockInitialValues({'waiting_store_v1': 'nonsense'});
      final fb = await WaitingStore.feedback();
      expect(compose([m], fb: fb).waiting, hasLength(1));
    });
  });

  test('keys are the same across rebuilt messages', () {
    final a = msg('Rohan', 'x', ago(hours: 1));
    final b = msg('Rohan', 'y', ago(hours: 1));
    expect(sourceKeyOf(a), sourceKeyOf(b));
  });
}

String item2Key(RawData m) => compose([m]).waiting.single.personKey;
