import 'package:isar/isar.dart';

part 'raw_data.g.dart';

@collection
class RawData {
  Id id = Isar.autoIncrement;

  late String source; // e.g., WhatsApp, Gmail, Calendar

  late String sender;

  late String content;

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
    ..addressed = m['addressed']?.toString();
}
