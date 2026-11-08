/// What actually writes for Echo right now.
enum EngineInUse { cloud, writingPack, none }

/// By the same rules briefings, Ask and drafts follow: the cloud only with
/// its switch on and a key, then the model on the phone.
EngineInUse engineInUse({
  required bool isOffline,
  required String geminiKey,
  required bool packReady,
}) {
  if (!isOffline && geminiKey.trim().isNotEmpty) return EngineInUse.cloud;
  return packReady ? EngineInUse.writingPack : EngineInUse.none;
}

/// The engine, in a few words, for a Settings row. [packName] is the real
/// model's name; a paired computer takes over whenever it can be reached.
String engineSummary(
  EngineInUse engine, {
  required String packName,
  bool computerPaired = false,
}) {
  final base = switch (engine) {
    EngineInUse.cloud => 'Gemini, with your own key',
    EngineInUse.writingPack => '$packName on this phone',
    EngineInUse.none => 'Nothing yet, so Echo finds but doesn’t write',
  };
  return computerPaired ? 'Your computer when it’s on, otherwise $base' : base;
}

/// "AIza…f3Xq": enough of a key to recognise, never all of it. Short keys
/// show nothing past the mask.
String maskApiKey(String key) {
  if (key.length < 12) return '••••';
  return '${key.substring(0, 4)}…${key.substring(key.length - 4)}';
}
