import 'package:isar/isar.dart';

part 'raw_data.g.dart';

@collection
class RawData {
  Id id = Isar.autoIncrement;

  late String source; // e.g., WhatsApp, Gmail, Calendar

  late String sender;

  late String content;

  @Index()
  late DateTime timestamp;

  /// Which conversation this came from (app + hashed chat id), when the app
  /// says. Notifications without one are grouped by app.
  @Index()
  String? thread;

  /// The group's name, or the other person's in a one-to-one chat.
  String? threadTitle;

  bool isGroup = false;

  /// Who this was meant for, worked out when it arrived. One of the
  /// [Addressed] names; null for anything that isn't a chat message.
  String? addressed;

  /// The sender as shown to people: "Rahul · College gang" for a group.
  @ignore
  String get who =>
      isGroup && (threadTitle?.isNotEmpty ?? false) && threadTitle != sender
      ? (sender.isEmpty ? threadTitle! : '$sender · $threadTitle')
      : sender;

  /// The native buffer's key for this notification, so one delivered again
  /// (the app died before confirming it was saved) isn't saved twice. Null
  /// for live notifications and calendar events.
  @Index()
  String? captureKey;

  /// The notification's key in the system shade, so that swiping it away
  /// later finds the messages it carried. Null for anything saved before
  /// History, and for calendar events.
  @Index()
  String? noticeKey;

  /// How it left the shade: one of [NoticeRemoval]'s names. Null while it's
  /// still there, or when Echo never saw it go.
  String? removal;

  /// When the owner swiped it away. Null if they never did.
  @Index()
  DateTime? swipedAt;

  /// When quiet hours held it back. Null if it reached the owner as it came.
  @Index()
  DateTime? heldAt;

  /// The owner wrote this, through Echo: a "you sent" line in History rather
  /// than something they were sent. Null for everything else.
  bool? sent;

  // 384-dimensional vector from all-MiniLM-L6-v2
  List<double>? embedding;

  /// Serialization for phone→desktop sync. The embedding (384 floats) and the
  /// Isar id are deliberately omitted — the desktop mirror only displays these
  /// notifications, so shipping the vectors would bloat the payload for no gain.
  Map<String, dynamic> toSyncMap() => {
        'source': source,
        'sender': sender,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (thread != null) 'thread': thread,
        if (threadTitle != null) 'threadTitle': threadTitle,
        if (isGroup) 'isGroup': true,
        if (addressed != null) 'addressed': addressed,
        if (removal != null) 'removal': removal,
        if (swipedAt != null) 'swipedAt': swipedAt!.toIso8601String(),
        if (heldAt != null) 'heldAt': heldAt!.toIso8601String(),
        if (sent == true) 'sent': true,
      };

  static RawData fromSyncMap(Map<String, dynamic> m) => RawData()
    ..source = (m['source'] ?? '').toString()
    ..sender = (m['sender'] ?? '').toString()
    ..content = (m['content'] ?? '').toString()
    ..timestamp =
        DateTime.tryParse((m['timestamp'] ?? '').toString()) ?? DateTime.now()
    ..thread = m['thread']?.toString()
    ..threadTitle = m['threadTitle']?.toString()
    ..isGroup = m['isGroup'] == true
    ..addressed = m['addressed']?.toString()
    ..removal = m['removal']?.toString()
    ..swipedAt = DateTime.tryParse((m['swipedAt'] ?? '').toString())
    ..heldAt = DateTime.tryParse((m['heldAt'] ?? '').toString())
    ..sent = m['sent'] == true ? true : null;
}

/// How a notification left the shade, as saved in [RawData.removal].
abstract final class NoticeRemoval {
  /// The owner swiped it away, or cleared the shade.
  static const swiped = 'swiped';

  /// The owner tapped it.
  static const opened = 'opened';

  /// The app took it back, usually because the chat was read elsewhere.
  static const app = 'app';
}
