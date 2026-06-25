import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/repositories/model_download_repository.dart';

class ModelDownloadRepositoryImpl implements ModelDownloadRepository {
  final String modelUrl =
      "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q3_k_m.gguf";

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

    final filePath = "${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf";
    final file = File(filePath);

    // 2. Check if the model already exists
    if (await file.exists()) {
      print("✅ Model already exists at: $filePath");
      return filePath;
    }

    print("⬇️ Downloading model...");

    // 3. Download the file using Dio with progress tracking
    final dio = Dio();
    await dio.download(
      modelUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          onProgress(received, total);
        }
      },
    );

    print("✅ Model downloaded to: $filePath");
    return filePath;
  }

  @override
  Future<bool> isModelDownloaded() async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = "${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf";
    final file = File(filePath);
    return await file.exists();
  }
}
