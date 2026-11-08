import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/people/data/people_store.dart';
import 'package:project_echo/features/people/data/person_tally.dart';
import 'package:shared_preferences/shared_preferences.dart';

RawData direct(String sender, DateTime at, {String? captureKey}) => RawData()
  ..source = 'Whatsapp'
  ..sender = sender
  ..content = 'hello'
  ..timestamp = at
  ..thread = 'com.whatsapp:$sender'
  ..threadTitle = sender
  ..isGroup = false
  ..addressed = 'direct'
  ..captureKey = captureKey;

Future<TallyBook> tally() async {
  final prefs = await SharedPreferences.getInstance();
  return TallyBook.decode(prefs.getString(PeopleStore.tallyKey));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime(2026, 11, 8, 10);

  setUp(() {
    // Already backfilled, so these tests don't need a database.
    SharedPreferences.setMockInitialValues({
      PeopleStore.tallyKey: jsonEncode({'b': true, 'p': {}}),
    });
  });

  test('counts a message', () async {
    await PeopleStore.recordMessage(direct('Riya', at));
    final book = await tally();
    expect(book.people['whatsapp|riya']?.direct[weekOf(at)], 1);
  });

  test('concurrent writes lose nothing', () async {
    await Future.wait([
      for (var i = 0; i < 50; i++) PeopleStore.recordMessage(direct('Riya', at)),
    ]);
    final book = await tally();
    expect(book.people['whatsapp|riya']?.direct[weekOf(at)], 50);
  });

  test('a redelivered round counts once', () async {
    await PeopleStore.recordAll([direct('Riya', at, captureKey: 'k1')]);
    await PeopleStore.recordAll([direct('Riya', at, captureKey: 'k1')]);
    final book = await tally();
    expect(book.people['whatsapp|riya']?.direct[weekOf(at)], 1);
  });

  test('a message with no capture key is always counted', () async {
    await PeopleStore.recordAll([direct('Riya', at)]);
    await PeopleStore.recordAll([direct('Riya', at)]);
    final book = await tally();
    expect(book.people['whatsapp|riya']?.direct[weekOf(at)], 2);
  });

  test('not-person messages are skipped', () async {
    await PeopleStore.recordAll([direct('Riya', at)..addressed = null]);
    expect((await tally()).people, isEmpty);
  });

  test('dontNudge survives and is cleared for merged people', () async {
    await PeopleStore.recordAll([direct('Riya Shah', at)]);
    await PeopleStore.setDontNudge('whatsapp|riya shah', true);
    var c = await PeopleStore.choicesFor(['whatsapp|riya shah']);
    expect(c.dontNudge, isTrue);
    await PeopleStore.setDontNudge('whatsapp|riya shah', false);
    c = await PeopleStore.choicesFor(['whatsapp|riya shah']);
    expect(c.dontNudge, isFalse);
  });
}
