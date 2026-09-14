import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/repositories/model_download_repository.dart';

class ModelDownloadRepositoryImpl implements ModelDownloadRepository {
  final String modelUrl =
      "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q3_k_m.gguf";

  static const String fileName = 'qwen2.5_1.5b_instruct_q3_k_m.gguf';
  static const String displayName = 'Qwen2.5 1.5B';
  static const String sizeLabel = '~0.9 GB';

  /// The q3_k_m model is ~0.8 GB. Anything much smaller than this on disk is a
  /// truncated/partial download and must be treated as "not downloaded" so we
  /// don't hand a corrupt GGUF to the inference engine.
  static const int _minValidModelBytes = 200 * 1024 * 1024; // 200 MB

  @override
  Future<String> downloadModel({
    required Function(int progress, int total) onProgress,
  }) async {
    // 1. Get the app's internal documents directory
    final dir = await getApplicationDocumentsDirectory();

    // Clean up old LiteRT model if present
    final oldFilePath = "${dir.path}/deepseek_r1_1_5b.litertlm";
    final oldFile = File(oldFilePath);
    if (await oldFile.exists()) {
      try {
        await oldFile.delete();
        print("🗑️ Deleted old LiteRT model file at: $oldFilePath");
      } catch (_) {}
    }

    // Clean up old q8_0 model if present
    final oldQ8FilePath = "${dir.path}/qwen2.5_1.5b_instruct_q8_0.gguf";
    final oldQ8File = File(oldQ8FilePath);
    if (await oldQ8File.exists()) {
      try {
        await oldQ8File.delete();
        print("🗑️ Deleted old q8_0 model file at: $oldQ8FilePath");
      } catch (_) {}
    }

    final filePath = "${dir.path}/$fileName";
    final file = File(filePath);

    // 2. Check if a *complete* model already exists. A partial file left by a
    // previous interrupted download would otherwise be reported as valid.
    if (await file.exists() && await file.length() >= _minValidModelBytes) {
      print("✅ Model already exists at: $filePath");
      return filePath;
    }

    print("⬇️ Downloading model...");

    // 3. Download to a temporary `.part` file, then atomically rename on
    // success. On any failure, delete the partial so it can't poison the
    // "already exists" checks on the next attempt.
    final partPath = "$filePath.part";
    final partFile = File(partPath);
    final dio = Dio();
    try {
      await dio.download(
        modelUrl,
        partPath,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received, total);
          }
        },
      );

      // Guard against a "successful" but empty/truncated response.
      if (await partFile.length() < _minValidModelBytes) {
        throw Exception(
          'Downloaded file is too small (${await partFile.length()} bytes) — likely truncated.',
        );
      }

      // Replace any stale/partial final file, then promote the temp file.
      if (await file.exists()) {
        await file.delete();
      }
      await partFile.rename(filePath);

      print("✅ Model downloaded to: $filePath");
      return filePath;
    } catch (e) {
      // Best-effort cleanup of any leftover partial file.
      try {
        if (await partFile.exists()) await partFile.delete();
      } catch (_) {}
      print("❌ Model download failed: $e");
      rethrow;
    }
  }

  @override
  Future<bool> isModelDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = "${dir.path}/$fileName";
    final file = File(filePath);
    if (!await file.exists()) return false;
    // Reject truncated/partial files that would crash offline inference.
    return await file.length() >= _minValidModelBytes;
  }

  @override
  Future<String?> downloadedPathOrNull() async {
    return await isModelDownloaded()
        ? '${(await getApplicationDocumentsDirectory()).path}/$fileName'
        : null;
  }
}
