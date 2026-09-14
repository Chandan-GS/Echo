import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';

enum ModelDownloadPhase { idle, downloading, done, error }

class ModelDownloadState {
  final ModelDownloadPhase phase;
  final double progress; // 0..1, meaningful only while downloading
  final String? error;

  const ModelDownloadState({
    required this.phase,
    this.progress = 0.0,
    this.error,
  });

  static const idle = ModelDownloadState(phase: ModelDownloadPhase.idle);
}

/// Tracks the offline model download in a singleton that outlives any single
/// screen. Progress used to live as local State on whichever widget started
/// the download (Settings' [ModelManagementSection] or onboarding's
/// [AiModeScreen]) — so navigating away mid-download disposed that widget and
/// the progress bar reset on return, even though the download itself (a plain
/// Future, not tied to widget lifecycle) kept running underneath. Every screen
/// now observes this one shared [state] instead, so it always reflects reality
/// regardless of which screen started the download or which one is showing.
class ModelDownloadService {
  ModelDownloadService._();
  static final ModelDownloadService instance = ModelDownloadService._();

  final ValueNotifier<ModelDownloadState> state = ValueNotifier(
    ModelDownloadState.idle,
  );

  Future<void>? _inFlight;

  /// Starts the download if one isn't already running. Safe to call from
  /// multiple screens — a second caller just observes the same in-flight
  /// download rather than starting a duplicate one.
  Future<void> startIfNeeded() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final repo = createOfflineModelRepository();
    state.value = const ModelDownloadState(
      phase: ModelDownloadPhase.downloading,
      progress: 0.0,
    );

    final future = repo
        .downloadModel(
          onProgress: (received, total) {
            if (total <= 0) return;
            state.value = ModelDownloadState(
              phase: ModelDownloadPhase.downloading,
              progress: (received / total).clamp(0.0, 1.0),
            );
          },
        )
        .then((_) {
          state.value = const ModelDownloadState(
            phase: ModelDownloadPhase.done,
            progress: 1.0,
          );
        })
        .catchError((Object e) {
          state.value = ModelDownloadState(
            phase: ModelDownloadPhase.error,
            error: e.toString(),
          );
        })
        .whenComplete(() {
          _inFlight = null;
        });

    _inFlight = future;
    return future;
  }

  bool get isDownloading => _inFlight != null;

  /// Clears a finished/errored state back to idle (e.g. after a screen has
  /// shown and acknowledged an error) without touching an in-flight download.
  void acknowledge() {
    if (_inFlight == null) state.value = ModelDownloadState.idle;
  }
}
