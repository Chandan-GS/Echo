abstract class ModelDownloadRepository {
  Future<String> downloadModel({
    required Function(int progress, int total) onProgress,
  });

  Future<bool> isModelDownloaded();
}
