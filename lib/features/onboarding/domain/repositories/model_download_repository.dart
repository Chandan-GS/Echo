abstract class ModelDownloadRepository {
  Future<String> downloadModel({
    required Function(int progress, int total) onProgress,
  });

  Future<bool> isModelDownloaded();

  /// The model's file path if fully downloaded, else null — avoids every
  /// caller re-deriving the path and re-checking existence/size itself.
  Future<String?> downloadedPathOrNull();
}
