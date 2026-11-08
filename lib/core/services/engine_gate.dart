import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/core/presentation/widgets/engine_sheet.dart';
import 'package:project_echo/core/services/model_download_service.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/demo/demo_mode.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where Echo writes its sentences. Reads the settings Onboarding and
/// Settings already write, so a choice made there counts here.
enum WritingEngine { phone, computer, gemini }

/// The engine those settings add up to, in the order [AskAiCubit] tries them:
/// a paired computer, then Gemini, then the model on the phone. Null when none
/// of them can write yet.
WritingEngine? resolveWritingEngine({
  required bool preferComputer,
  required String? computerHost,
  required bool offlineEngine,
  required String geminiKey,
  required bool modelOnPhone,
}) {
  if (preferComputer && (computerHost?.isNotEmpty ?? false)) {
    return WritingEngine.computer;
  }
  if (!offlineEngine && geminiKey.trim().isNotEmpty) return WritingEngine.gemini;
  if (modelOnPhone) return WritingEngine.phone;
  return null;
}

/// Asks how Echo should write the first time something needs it: Ask Echo or
/// a drafted reply, and never anywhere else.
class EngineGate {
  EngineGate._();

  /// "Skip for now": search-only until an engine is chosen.
  static const searchOnlyKey = 'engine_search_only';

  static Future<bool>? _open;

  /// The engine that can write right now, if any. Desktop builds and the
  /// filming build always can.
  static Future<WritingEngine?> current() async {
    if (kEchoDemo || Platform.isMacOS || Platform.isWindows) {
      return WritingEngine.phone;
    }
    final prefs = await SharedPreferences.getInstance();
    return resolveWritingEngine(
      preferComputer: prefs.getBool('prefer_desktop_engine') ?? false,
      computerHost: prefs.getString('desktop_engine_host'),
      offlineEngine: prefs.getBool('is_offline_engine') ?? true,
      geminiKey: prefs.getString('gemini_api_key') ?? '',
      modelOnPhone: await createOfflineModelRepository().isModelDownloaded(),
    );
  }

  /// Whether the owner has said to just search for now.
  static Future<bool> isSearchOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(searchOnlyKey) ?? false;
  }

  static Future<void> setSearchOnly(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(searchOnlyKey, on);
  }

  /// True when an engine is ready. Otherwise asks, unless the owner already
  /// said to just search, or the model is on its way, and Ask can carry on
  /// searching meanwhile. [reason] is 'ask' or 'draft'.
  static Future<bool> ensure(
    BuildContext context, {
    required String reason,
  }) async {
    if (await current() != null) return true;
    if (!await willAsk(reason) || !context.mounted) return false;
    return choose(context, reason: reason);
  }

  /// Whether [ensure] would open the sheet for [reason], given no engine is
  /// ready yet.
  static Future<bool> willAsk(String reason) async {
    if (reason != 'ask') return true;
    return !(await isSearchOnly() ||
        EngineDownload.instance.running ||
        ModelDownloadService.instance.isDownloading);
  }

  /// Opens the sheet whatever is already set ("Get a written answer
  /// instead"). True when an engine is ready afterwards.
  static Future<bool> choose(BuildContext context, {required String reason}) =>
      _open ??= showEngineSheet(
        context,
        reason: reason,
      ).then((chosen) => chosen ?? false).whenComplete(() => _open = null);
}

/// Why a download stopped.
enum DownloadProblem { offline, noSpace, failed }

/// What the phone's [names] of network interfaces say about its connection.
enum NetworkKind { wifi, mobile, unknown }

NetworkKind networkKindOf(Iterable<String> names) {
  final lower = names.map((n) => n.toLowerCase()).toList();
  bool any(List<String> prefixes) =>
      lower.any((n) => prefixes.any((p) => n.startsWith(p)));
  if (any(const ['wlan', 'swlan', 'wifi', 'eth', 'en'])) {
    return NetworkKind.wifi;
  }
  if (any(const ['rmnet', 'v4-rmnet', 'ccmni', 'pdp', 'seth', 'clat', 'wwan'])) {
    return NetworkKind.mobile;
  }
  return NetworkKind.unknown;
}

/// The phone's connection, best guess; [NetworkKind.unknown] never blocks a
/// download, it only skips the mobile-data warning.
Future<NetworkKind> currentNetworkKind() async {
  try {
    final interfaces = await NetworkInterface.list();
    return networkKindOf(interfaces.map((i) => i.name));
  } catch (_) {
    return NetworkKind.unknown;
  }
}

/// What went wrong, in terms the sheet can say plainly.
DownloadProblem classifyDownloadError(Object error) {
  final os = switch (error) {
    FileSystemException e => e.osError,
    _ => null,
  };
  // ENOSPC: the disk filled up mid-write.
  if (os?.errorCode == 28 || (os?.message.contains('No space') ?? false)) {
    return DownloadProblem.noSpace;
  }
  if (error is SocketException || error is HttpException) {
    return DownloadProblem.offline;
  }
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => DownloadProblem.offline,
      DioExceptionType.badResponse => DownloadProblem.failed,
      _ =>
        error.error is SocketException || error.error is HttpException
            ? DownloadProblem.offline
            : DownloadProblem.failed,
    };
  }
  return DownloadProblem.failed;
}

/// Where a resumed download should pick up: the bytes already kept when the
/// server honoured the range (206), or from zero when it didn't.
int resumeOffset({required int kept, required int statusCode}) =>
    statusCode == 206 ? kept : 0;

/// The whole file's size from a Content-Range like "bytes 100-899/900".
int? totalFromContentRange(String? header) {
  if (header == null) return null;
  final slash = header.lastIndexOf('/');
  if (slash < 0) return null;
  return int.tryParse(header.substring(slash + 1).trim());
}

class EngineDownloadState {
  final bool downloading;
  final int received;

  /// 0 until the server says how big the file is.
  final int total;
  final DownloadProblem? problem;

  const EngineDownloadState({
    this.downloading = false,
    this.received = 0,
    this.total = 0,
    this.problem,
  });

  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0;
}

/// Fetches the on-phone writing model so it can pick up where it left off.
///
/// [ModelDownloadRepositoryImpl] throws its partial away on any error, so a
/// dropped connection near the end of a 0.9 GB file would start again from
/// nothing. This keeps the partial under its own name, asks for the rest with
/// a Range request, and reports through [ModelDownloadService.state] as well,
/// so Settings shows the same progress.
class EngineDownload {
  EngineDownload._();
  static final instance = EngineDownload._();

  final state = ValueNotifier(const EngineDownloadState());

  Future<bool>? _running;
  CancelToken? _cancel;

  bool get running => _running != null;

  /// Bytes already on disk from an interrupted download.
  Future<int> keptBytes() async {
    try {
      final part = await _partFile();
      return await part.exists() ? await part.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<File> _partFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/${ModelDownloadRepositoryImpl.fileName}.resume');
  }

  /// Starts or joins the download. Completes true when the model is on disk;
  /// false if it was cancelled or failed ([state] says why).
  Future<bool> start() =>
      _running ??= _run().whenComplete(() => _running = null);

  /// Stops it, keeping what's been fetched for next time.
  void cancel() => _cancel?.cancel('cancelled');

  Future<bool> _run() async {
    final cancel = _cancel = CancelToken();
    state.value = const EngineDownloadState(downloading: true);
    _mirror(0, 0);
    try {
      await _fetch(cancel, retryFromZero: true);
      ModelDownloadService.instance.state.value = const ModelDownloadState(
        phase: ModelDownloadPhase.done,
        progress: 1,
      );
      state.value = const EngineDownloadState();
      return true;
    } catch (e) {
      debugPrint('Writing model download stopped: $e');
      final cancelled = e is DioException && CancelToken.isCancel(e);
      // Settings shows its own download button from idle.
      ModelDownloadService.instance.acknowledge();
      if (!cancelled) {
        ModelDownloadService.instance.state.value = ModelDownloadState(
          phase: ModelDownloadPhase.error,
          error: '$e',
        );
      }
      state.value = EngineDownloadState(
        problem: cancelled ? null : classifyDownloadError(e),
      );
      return false;
    }
  }

  Future<void> _fetch(CancelToken cancel, {required bool retryFromZero}) async {
    final repo = ModelDownloadRepositoryImpl();
    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/${ModelDownloadRepositoryImpl.fileName}');
    final part = File('${target.path}.resume');

    var kept = await part.exists() ? await part.length() : 0;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
    final response = await dio.get<ResponseBody>(
      repo.modelUrl,
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: kept > 0 ? {'Range': 'bytes=$kept-'} : null,
        validateStatus: (s) => s != null && (s < 400 || s == 416),
      ),
    );

    // 416: what's kept doesn't fit the file any more. Start over, once.
    if (response.statusCode == 416) {
      await part.delete();
      if (!retryFromZero) throw Exception('Could not resume the download');
      return _fetch(cancel, retryFromZero: false);
    }

    kept = resumeOffset(kept: kept, statusCode: response.statusCode ?? 0);
    final body = response.data!;
    final total = response.statusCode == 206
        ? totalFromContentRange(response.headers.value('content-range')) ??
              kept + body.contentLength
        : body.contentLength;

    var received = kept;
    state.value = EngineDownloadState(
      downloading: true,
      received: received,
      total: total > 0 ? total : 0,
    );
    _mirror(received, total);

    // Kept on failure (no delete here): that's the whole point of it.
    final sink = await part.open(
      mode: kept > 0 ? FileMode.append : FileMode.write,
    );
    try {
      var lastTick = DateTime.now();
      await for (final chunk in body.stream) {
        await sink.writeFrom(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastTick) > const Duration(milliseconds: 180)) {
          lastTick = now;
          state.value = EngineDownloadState(
            downloading: true,
            received: received,
            total: total > 0 ? total : 0,
          );
          _mirror(received, total);
        }
      }
    } finally {
      await sink.close();
    }

    if (total > 0 && received < total) {
      throw const SocketException('Connection closed before the end');
    }
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    if (!await repo.isModelDownloaded()) {
      await target.delete();
      throw Exception('Downloaded model is incomplete');
    }
  }

  void _mirror(int received, int total) {
    ModelDownloadService.instance.state.value = ModelDownloadState(
      phase: ModelDownloadPhase.downloading,
      progress: total > 0 ? (received / total).clamp(0.0, 1.0) : 0,
    );
  }
}
