import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:path_provider/path_provider.dart';

import 'package:project_echo/core/services/background_activity_service.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';

/// Downloads and validates the larger desktop model, mirroring the phone's
/// `ModelDownloadRepositoryImpl` pattern (download to `.part`, atomically
/// rename, size-validate) but pointed at a model sized for a computer rather
/// than a phone. Implements the same [ModelDownloadRepository] interface so
/// desktop can be a drop-in replacement everywhere the phone's on-device model
/// is used — see `offline_model_repository.dart` for the platform resolver.
class DesktopModelRepository implements ModelDownloadRepository {
  // q4_k_m is split into two files on this repo (no single-file download);
  // q3_k_m is the largest quant still published as one file — confirmed via a
  // live HEAD request (3,808,391,072 bytes, ~3.8 GB) before wiring this in.
  static const String modelUrl =
      'https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q3_k_m.gguf';
  static const String fileName = 'qwen2.5_7b_instruct_q3_k_m.gguf';
  static const String displayName = 'Qwen2.5 7B';
  static const String sizeLabel = '~3.8 GB';

  /// The exact confirmed size of the real file (verified via a live HEAD
  /// request). Deliberately exact rather than a loose "close enough" floor —
  /// a floor a few hundred MB below the true size would silently accept a
  /// download that stalled partway through as "complete," handing fllama a
  /// truncated GGUF that loads but produces empty/garbage output instead of
  /// throwing a catchable error.
  static const int _expectedModelBytes = 3808391072;

  Future<String> _filePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName';
  }

  @override
  Future<bool> isModelDownloaded() async {
    final file = File(await _filePath());
    if (!await file.exists()) return false;
    return await file.length() == _expectedModelBytes;
  }

  @override
  Future<String?> downloadedPathOrNull() async {
    return await isModelDownloaded() ? await _filePath() : null;
  }

  @override
  Future<String> downloadModel({
    required Function(int progress, int total) onProgress,
  }) async {
    final filePath = await _filePath();
    final file = File(filePath);

    if (await file.exists() && await file.length() == _expectedModelBytes) {
      return filePath;
    }

    final partPath = '$filePath.part';
    final partFile = File(partPath);

    // A ~3.5 GB transfer over a real network hits transient drops. Prevent
    // macOS App Nap from throttling/cutting off the connection while the
    // window is minimized or not frontmost, and retry a couple of times on a
    // genuine mid-transfer failure before giving up.
    await BackgroundActivityService.begin();
    try {
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final dioClient = dio.Dio();
          await dioClient.download(
            modelUrl,
            partPath,
            deleteOnError: true,
            onReceiveProgress: (received, total) {
              if (total != -1) onProgress(received, total);
            },
          );

          if (await partFile.length() != _expectedModelBytes) {
            throw Exception(
              'Downloaded file is ${await partFile.length()} bytes, expected '
              '$_expectedModelBytes — likely truncated.',
            );
          }

          if (await file.exists()) await file.delete();
          await partFile.rename(filePath);
          return filePath;
        } catch (e) {
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
          if (attempt == maxAttempts) rethrow;
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      }
      // Unreachable — the loop always returns or rethrows on the last attempt.
      throw StateError('Model download failed after $maxAttempts attempts.');
    } finally {
      await BackgroundActivityService.end();
    }
  }
}
