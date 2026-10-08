import 'package:project_echo/features/echo/data/context/addressed.dart';
import 'package:project_echo/features/echo/data/models/raw_data.dart';
import 'package:project_echo/features/echo/data/relevance/briefing_selection.dart';

/// One Vault entry, with what the filters ask about it worked out once on
/// load rather than on every keystroke.
class VaultItem {
  final RawData entry;

  /// Its Vault category ("Whatsapp", or what the owner renamed it to).
  final String app;

  /// Whether it was meant for the owner: a direct chat, a mention or a reply.
  final Addressed? forYou;

  /// Sender, group name and text, lower-cased, for search.
  final String _haystack;

  VaultItem(this.entry, {required Map<String, String> aliases})
    : app = displaySource(entry.source, aliases),
      forYou = _forYou(entry.addressed),
      _haystack = [
        entry.sender,
        entry.threadTitle ?? '',
        entry.content,
      ].join('\n').toLowerCase();

  static Addressed? _forYou(String? addressed) {
    final a = Addressed.parse(addressed);
    return a == null || a == Addressed.group ? null : a;
  }

  /// The name shown in bold: the sender, or the app when there isn't one.
  String get who => entry.sender.trim().isEmpty ? app : entry.sender;

  /// The line under [who]: the group it was said in, else the app.
  String get where => entry.isGroup && (entry.threadTitle?.isNotEmpty ?? false)
      ? entry.threadTitle!
      : app;

  /// Every word of [query] appears somewhere, so "neha demo" finds Neha's
  /// message about the demo.
  bool matches(String query) {
    for (final word in query.toLowerCase().split(RegExp(r'\s+'))) {
      if (word.isNotEmpty && !_haystack.contains(word)) return false;
    }
    return true;
  }
}

enum VaultDay { any, today, yesterday, week }

/// What the filter row is set to.
class VaultQuery {
  final String text;

  /// A category from [VaultItem.app]; null for all apps.
  final String? app;
  final bool forYouOnly;
  final VaultDay day;

  const VaultQuery({
    this.text = '',
    this.app,
    this.forYouOnly = false,
    this.day = VaultDay.any,
  });

  VaultQuery copyWith({
    String? text,
    String? Function()? app,
    bool? forYouOnly,
    VaultDay? day,
  }) => VaultQuery(
    text: text ?? this.text,
    app: app != null ? app() : this.app,
    forYouOnly: forYouOnly ?? this.forYouOnly,
    day: day ?? this.day,
  );

  bool accepts(VaultItem item, DateTime now) {
    if (app != null && item.app != app) return false;
    if (forYouOnly && item.forYou == null) return false;
    if (!_inDay(item.entry.timestamp, now)) return false;
    return item.matches(text);
  }

  bool _inDay(DateTime t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    return switch (this.day) {
      VaultDay.any => true,
      VaultDay.today => day == today,
      VaultDay.yesterday => day == DateTime(now.year, now.month, now.day - 1),
      // The same seven days as the week card and the header's count.
      VaultDay.week => !day.isBefore(
        DateTime(now.year, now.month, now.day - 6),
      ),
    };
  }
}

/// A line of the table: a day's heading or one entry.
sealed class VaultLine {
  const VaultLine();
}

class VaultDayLine extends VaultLine {
  final DateTime day;
  final int count;
  const VaultDayLine(this.day, this.count);
}

class VaultEntryLine extends VaultLine {
  final VaultItem item;
  const VaultEntryLine(this.item);
}

/// [items] (newest first) that pass [query], under a heading per day with
/// that day's count of what passed.
List<VaultLine> vaultLines(
  List<VaultItem> items,
  VaultQuery query,
  DateTime now,
) {
  final lines = <VaultLine>[];
  DateTime? day;
  var headingAt = -1;
  var count = 0;
  for (final item in items) {
    if (!query.accepts(item, now)) continue;
    final t = item.entry.timestamp;
    final d = DateTime(t.year, t.month, t.day);
    if (d != day) {
      if (headingAt >= 0) lines[headingAt] = VaultDayLine(day!, count);
      day = d;
      count = 0;
      headingAt = lines.length;
      lines.add(VaultDayLine(d, 0));
    }
    count++;
    lines.add(VaultEntryLine(item));
  }
  if (headingAt >= 0) lines[headingAt] = VaultDayLine(day!, count);
  return lines;
}

/// The apps present, busiest first, leaving out [blocked] categories (as the
/// phone Vault's chips do). Each comes with one of its entries, for its icon.
List<(String, RawData)> vaultApps(
  List<VaultItem> items, {
  Iterable<String> blocked = const [],
}) {
  final counts = <String, int>{};
  final sample = <String, RawData>{};
  for (final item in items) {
    counts[item.app] = (counts[item.app] ?? 0) + 1;
    sample.putIfAbsent(item.app, () => item.entry);
  }
  final hidden = blocked.toSet();
  final apps = counts.keys.where((a) => !hidden.contains(a)).toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [for (final a in apps) (a, sample[a]!)];
}

/// "Today", "Yesterday", "Tuesday" within the week, "Sat 12 Sep" before.
String vaultDayLabel(DateTime day, DateTime now) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  // In UTC, so a clock change doesn't make a day 23 hours long.
  final ago = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  if (ago == 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  final weekday = weekdays[day.weekday - 1];
  if (ago > 1 && ago < 7) return weekday;
  return '${weekday.substring(0, 3)} ${day.day} ${months[day.month - 1]}';
}

/// "1,284".
String groupedCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
