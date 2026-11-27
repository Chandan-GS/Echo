import 'package:project_echo/core/services/streak_service.dart';
import 'package:project_echo/features/profile/data/week_stats.dart';

/// What the shareable week card says, and nothing more: four counts.
///
/// Privacy is the product, so this is built only from numbers — how many
/// messages Echo read, how many mornings the briefing was heard, how many
/// replies went out through Echo, and the streak. It never sees a name, a
/// sender, a message, an app or a thread, so the card can't show one.
class WeekCardData {
  /// Messages Echo read over the last seven days.
  final int read;

  /// Of the last seven days, those on which the briefing was heard.
  final int mornings;

  /// Replies sent through Echo over the last seven days.
  final int replies;

  /// The current streak, in days.
  final int streak;

  /// The first and last days the card covers.
  final DateTime from;
  final DateTime to;

  const WeekCardData({
    required this.read,
    required this.mornings,
    required this.replies,
    required this.streak,
    required this.from,
    required this.to,
  });

  static const days = 7;

  /// Echo's Play listing, tagged so installs from the card can be counted.
  static const playLink =
      'https://play.google.com/store/apps/details?id=com.chandangs.echo'
      '&referrer=utm_source%3Dshare_card%26utm_medium%3Dapp';

  static const appTitle = 'Echo: AI Notification Summary';
  static const storeLine = 'Free on Google Play';

  /// The streak milestones after which the celebration offers a share.
  static const milestones = {3, 7, 14, 30};

  /// Puts the card together from the Profile week, the days the briefing
  /// was heard (as [StreakService] keys them) and the current streak.
  static WeekCardData assemble({
    required WeekStats week,
    required Set<String> heardDates,
    required int streak,
    required DateTime now,
  }) {
    final keys = StreakService();
    final mornings = [
      for (var i = 0; i < days; i++)
        DateTime(week.from.year, week.from.month, week.from.day + i),
    ].where((d) => heardDates.contains(keys.dateKeyFor(d))).length;
    return WeekCardData(
      read: week.read,
      mornings: mornings,
      replies: week.replies,
      streak: streak,
      from: week.from,
      to: DateTime(now.year, now.month, now.day),
    );
  }

  /// Whether the week has anything worth sharing: a morning heard, or
  /// enough messages read that the number means something.
  bool get worthSharing => mornings >= 1 || read >= 20;

  /// The card's big line.
  String get headline => read > 0
      ? 'This week Echo read ${number(read)} '
            '${read == 1 ? 'message' : 'messages'} for me'
      : 'This week I heard $mornings of $days mornings';

  /// The numbers under the headline, as (value, what it counts).
  List<(String, String)> get stats => [
    if (read > 0 && mornings > 0)
      ('$mornings of $days', 'mornings I heard my briefing'),
    if (replies > 0)
      (
        number(replies),
        replies == 1 ? 'reply through Echo' : 'replies through Echo',
      ),
    if (streak >= 2) ('$streak days', 'in a row with Echo'),
  ];

  /// The one line that goes with the image in the share sheet.
  String get shareText {
    final parts = [
      headline,
      if (read > 0 && mornings > 0) 'I heard $mornings of $days mornings',
      if (replies > 0)
        '${number(replies)} ${replies == 1 ? 'reply' : 'replies'} through Echo',
    ];
    return '${parts.join(' · ')}. $appTitle, on Google Play: $playLink';
  }

  /// Every string the card draws, for checking what it could reveal.
  List<String> get allText => [
    headline,
    for (final (v, l) in stats) ...[v, l],
    range,
    appTitle,
    storeLine,
    shareText,
  ];

  /// "20 – 26 Nov".
  String get range {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final a = from.month == to.month
        ? '${from.day}'
        : '${from.day} ${months[from.month - 1]}';
    return '$a – ${to.day} ${months[to.month - 1]}';
  }

  /// "1,284".
  static String number(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
}
