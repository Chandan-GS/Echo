import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/repositories/model_download_repository.dart';

class ModelDownloadRepositoryImpl implements ModelDownloadRepository {
  final String modelUrl =
      "https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm";

  @override
  Future<String> downloadModel({
    required Function(int progress, int total) onProgress,
  }) async {
    // 1. Get the app's internal documents directory
    final dir = await getApplicationDocumentsDirectory();
    final filePath = "${dir.path}/deepseek_r1_1_5b.litertlm";
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
    final filePath = "${dir.path}/deepseek_r1_1_5b.litertlm";
    final file = File(filePath);
    return await file.exists();
  }
}
