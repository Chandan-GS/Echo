import 'package:isar/isar.dart';

part 'raw_data.g.dart';

@collection
class RawData {
  Id id = Isar.autoIncrement;

  late String source; // e.g., WhatsApp, Gmail, Calendar

  late String sender;

  late String content;

  late DateTime timestamp;

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
      };

  static RawData fromSyncMap(Map<String, dynamic> m) => RawData()
    ..source = (m['source'] ?? '').toString()
    ..sender = (m['sender'] ?? '').toString()
    ..content = (m['content'] ?? '').toString()
    ..timestamp =
        DateTime.tryParse((m['timestamp'] ?? '').toString()) ?? DateTime.now();
}
