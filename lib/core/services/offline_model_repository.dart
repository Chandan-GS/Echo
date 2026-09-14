import 'dart:io';

import 'package:project_echo/core/services/desktop_model_repository.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';

/// Resolves the on-device ("offline") model repository for THIS platform.
/// Desktop (macOS/Windows) defaults to the larger, more capable Qwen2.5 7B —
/// desktops have the RAM/disk headroom a phone doesn't, and the earlier
/// on-device 1.5B was too weak for coherent answers under thin context.
/// Phone keeps the small 1.5B tuned for constrained memory/storage.
ModelDownloadRepository createOfflineModelRepository() =>
    (Platform.isMacOS || Platform.isWindows)
        ? DesktopModelRepository()
        : ModelDownloadRepositoryImpl();

/// Human-readable name/size for the resolved platform's model, for UI copy.
String offlineModelDisplayName() => (Platform.isMacOS || Platform.isWindows)
    ? DesktopModelRepository.displayName
    : ModelDownloadRepositoryImpl.displayName;

String offlineModelSizeLabel() => (Platform.isMacOS || Platform.isWindows)
    ? DesktopModelRepository.sizeLabel
    : ModelDownloadRepositoryImpl.sizeLabel;
