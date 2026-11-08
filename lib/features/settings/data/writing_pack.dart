import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:project_echo/core/services/model_download_service.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the on-device writing model is here, and how big it really is.
@immutable
class WritingPackStatus {
  final bool ready;

  /// The file's real size once it's on the phone.
  final String? size;

  const WritingPackStatus({required this.ready, this.size});

  static const absent = WritingPackStatus(ready: false);
}

/// "1.23 GB" or "950 MB", from a file's size in bytes.
String packSizeLabel(int bytes) {
  const mb = 1024 * 1024;
  final inMb = bytes / mb;
  return inMb >= 1000
      ? '${(inMb / 1024).toStringAsFixed(1)} GB'
      : '${inMb.round()} MB';
}

/// The model's status, shared by every Settings page. Follows the download,
/// wherever it was started from (the first-use sheet starts it too).
class WritingPack {
  WritingPack._();

  static final status = ValueNotifier<WritingPackStatus>(
    WritingPackStatus.absent,
  );

  static bool _following = false;

  static const _wifiOnlyKey = 'writing_pack_wifi_only';

  /// Whether a download may only start on Wi-Fi. On by default: it's a big
  /// file.
  static Future<bool> wifiOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_wifiOnlyKey) ?? true;
  }

  static Future<void> setWifiOnly(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wifiOnlyKey, on);
  }

  /// Looks at the disk, and starts following the download. Safe to call on
  /// every page open.
  static Future<void> refresh() async {
    if (!_following) {
      _following = true;
      ModelDownloadService.instance.state.addListener(() {
        final phase = ModelDownloadService.instance.state.value.phase;
        if (phase == ModelDownloadPhase.done) refresh();
      });
    }
    try {
      final path = await createOfflineModelRepository().downloadedPathOrNull();
      if (path == null) {
        status.value = WritingPackStatus.absent;
        return;
      }
      final bytes = await File(path).length();
      status.value = WritingPackStatus(ready: true, size: packSizeLabel(bytes));
    } catch (e) {
      debugPrint('Couldn\'t read the writing pack: $e');
    }
  }

  /// Removes the model from this phone.
  static Future<void> remove() async {
    try {
      final path = await createOfflineModelRepository().downloadedPathOrNull();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('Couldn\'t remove the writing pack: $e');
    }
    await discardPartial();
    await refresh();
  }

  /// Deletes what an interrupted download kept, freeing the space. The next
  /// download starts from nothing.
  static Future<void> discardPartial() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final part = File(
        '${dir.path}/${ModelDownloadRepositoryImpl.fileName}.resume',
      );
      if (await part.exists()) await part.delete();
    } catch (e) {
      debugPrint('Couldn\'t discard the partial download: $e');
    }
  }
}
