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
}
