import 'package:flutter_test/flutter_test.dart';
import 'package:project_echo/features/desktop/presentation/vault/vault_filter.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';

void main() {
  final now = DateTime(2026, 10, 3, 18, 0);

  VaultItem item(
    String source,
    String sender,
    String content,
    DateTime at, {
    String? group,
    String? addressed,
    Map<String, String> aliases = const {},
  }) => VaultItem(
    RawData()
      ..source = source
      ..sender = sender
      ..content = content
      ..timestamp = at
      ..isGroup = group != null
      ..threadTitle = group
      ..addressed = addressed,
    aliases: aliases,
  );

  // Newest first, as the Vault reads them.
  final items = [
    item(
      'whatsapp',
      'Rahul',
      'I can drive Friday',
      DateTime(2026, 10, 3, 15, 58),
      group: 'College gang',
      addressed: 'reply',
    ),
    item(
      'slack',
      'Neha',
      'Demo moved to 7 PM tomorrow',
      DateTime(2026, 10, 3, 11, 2),
      addressed: 'direct',
    ),
    item(
      'whatsapp',
      'Sneha',
      'Booked the table',
      DateTime(2026, 10, 2, 20, 0),
      group: 'College gang',
      addressed: 'group',
    ),
    item('sms', 'Bank', 'Your bill is due', DateTime(2026, 9, 20, 9, 0)),
  ];

  List<String> senders(VaultQuery q) => [
    for (final line in vaultLines(items, q, now))
      if (line is VaultEntryLine) line.item.entry.sender,
  ];

  test('search matches sender, group and text, every word', () {
    expect(senders(const VaultQuery(text: 'rahul')), ['Rahul']);
    // Part of a word counts, as you type it.
    expect(senders(const VaultQuery(text: 'neha')), ['Neha', 'Sneha']);
    expect(senders(const VaultQuery(text: 'college')), ['Rahul', 'Sneha']);
    expect(senders(const VaultQuery(text: 'DEMO tomorrow')), ['Neha']);
    expect(senders(const VaultQuery(text: 'neha friday')), isEmpty);
    expect(senders(const VaultQuery(text: '  ')), hasLength(4));
  });

  test('filters by app, for-you and day', () {
    expect(senders(const VaultQuery(app: 'Whatsapp')), ['Rahul', 'Sneha']);
    expect(senders(const VaultQuery(forYouOnly: true)), ['Rahul', 'Neha']);
    expect(senders(const VaultQuery(day: VaultDay.today)), ['Rahul', 'Neha']);
    expect(senders(const VaultQuery(day: VaultDay.yesterday)), ['Sneha']);
    expect(senders(const VaultQuery(day: VaultDay.week)), hasLength(3));
  });

  test('groups by day with the count of what passed', () {
    final lines = vaultLines(items, const VaultQuery(), now);
    final days = lines.whereType<VaultDayLine>().toList();
    expect(days.map((d) => d.count), [2, 1, 1]);
    expect(days.first.day, DateTime(2026, 10, 3));
    expect(lines.first, isA<VaultDayLine>());
    expect(vaultLines(items, const VaultQuery(text: 'zzz'), now), isEmpty);
  });

  test('apps are busiest first, without blocked ones, and use aliases', () {
    expect(vaultApps(items).map((a) => a.$1), ['Whatsapp', 'Slack', 'Sms']);
    expect(vaultApps(items, blocked: ['Slack']).map((a) => a.$1), [
      'Whatsapp',
      'Sms',
    ]);
    final renamed = item(
      'whatsapp',
      'Amma',
      'Call me',
      now,
      aliases: {'Whatsapp': 'Family'},
    );
    expect(renamed.app, 'Family');
    expect(renamed.where, 'Family');
    expect(items.first.where, 'College gang');
  });

  test('day labels and counts read naturally', () {
    expect(vaultDayLabel(DateTime(2026, 10, 3), now), 'Today');
    expect(vaultDayLabel(DateTime(2026, 10, 2), now), 'Yesterday');
    expect(vaultDayLabel(DateTime(2026, 9, 29), now), 'Tuesday');
    expect(vaultDayLabel(DateTime(2026, 9, 20), now), 'Sun 20 Sep');
    expect(groupedCount(1284), '1,284');
    expect(groupedCount(999), '999');
    expect(groupedCount(1000000), '1,000,000');
  });
}
