import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';
import 'package:project_echo/core/utils/download_utils.dart';

class AiModeScreen extends StatefulWidget {
  const AiModeScreen({super.key});

  @override
  State<AiModeScreen> createState() => _AiModeScreenState();
}

class _AiModeScreenState extends State<AiModeScreen> {
  bool isDownloading = false;
  bool isDownloaded = false;
  double downloadProgress = 0.0;
  final ModelDownloadRepository _downloadRepository =
      ModelDownloadRepositoryImpl();

  @override
  void initState() {
    super.initState();
    _checkInitialDownloadState();
  }

  Future<void> _checkInitialDownloadState() async {
    final downloaded = await _downloadRepository.isModelDownloaded();
    if (mounted) {
      setState(() => isDownloaded = downloaded);
      if (downloaded) {
        context.read<OnBoardingCubit>().setModelDownloaded(true);
      }
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      isDownloading = true;
      downloadProgress = 0.0;
    });

    try {
      final modelPath = await _downloadRepository.downloadModel(
        onProgress: (received, total) {
          setState(() {
            downloadProgress = computeDownloadProgress(received, total);
          });
        },
      );

      if (!mounted) return;
      setState(() {
        isDownloading = false;
        isDownloaded = true;
      });
      context.read<OnBoardingCubit>().setModelDownloaded(true);
      debugPrint("Model downloaded to $modelPath");
    } catch (e) {
      if (!mounted) return;
      setState(() => isDownloading = false);
      debugPrint("Download failed: $e");
    }
  }

  /// Starts the model download without blocking, then advances immediately.
  /// The sample-briefing preview (later steps) uses on-device TTS rather than
  /// the model, so setup can continue while ~0.9 GB downloads in the
  /// background. Briefing generation checks the model file directly on disk.
  void _downloadInBackgroundAndContinue() {
    unawaited(() async {
      try {
        await _downloadRepository.downloadModel(onProgress: (_, _) {});
      } catch (e) {
        debugPrint('Background model download failed: $e');
      }
    }());
    context.read<OnBoardingCubit>().completeAiMode();
  }

  Future<String?> _getModelSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelPath = '${dir.path}/qwen2.5_1.5b_instruct_q3_k_m.gguf';
      final file = File(modelPath);
      if (await file.exists()) {
        final bytes = await file.length();
        final gb = bytes / (1024 * 1024 * 1024);
        return '${gb.toStringAsFixed(1)} GB';
      }
    } catch (_) {
      // Ignore
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settingsState) {
        return OnboardingStepBody(
          title: 'How should Echo think?',
          subtitle: 'Change this anytime in settings.',
          footer: _Footer(
            settingsState: settingsState,
            isDownloading: isDownloading,
            isDownloaded: isDownloaded,
            downloadProgress: downloadProgress,
            onDownload: _startDownload,
            onContinue: cubit.completeAiMode,
            onBackgroundDownload: _downloadInBackgroundAndContinue,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<String?>(
                future: _getModelSize(),
                builder: (context, snapshot) {
                  final sizeStr = snapshot.data ?? '~0.9 GB';
                  return AiModeCard(
                    isSelected: settingsState.isOfflineEngine,
                    icon: Icons.laptop_mac,
                    title: 'Private (on your phone)',
                    tags: const [
                      'Runs offline',
                      'No API cost',
                      'Nothing leaves your device',
                    ],
                    speedLabel: 'Fast',
                    isFast: true,
                    onTap: () {
                      context.read<SettingsCubit>().setAiEngine(
                        isOffline: true,
                      );
                    },
                    expandedContent: Row(
                      children: [
                        Icon(
                          Icons.memory_rounded,
                          size: 16,
                          color: context.colors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'One-time download of Qwen2.5 1.5B ($sizeStr). After that, it works with no internet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const CloudEngineCard(),
            ],
          ),
        );
      },
    );
  }
}

/// The dynamic bottom area: shows a live download bar, the primary CTA, an
/// optional "download in background" escape hatch, and a reassurance caption.
class _Footer extends StatelessWidget {
  final SettingsState settingsState;
  final bool isDownloading;
  final bool isDownloaded;
  final double downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onContinue;
  final VoidCallback onBackgroundDownload;

  const _Footer({
    required this.settingsState,
    required this.isDownloading,
    required this.isDownloaded,
    required this.downloadProgress,
    required this.onDownload,
    required this.onContinue,
    required this.onBackgroundDownload,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOffline = settingsState.isOfflineEngine;
    final canContinue = isOffline || settingsState.geminiApiKey.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: isDownloading
              ? Column(
                  key: const ValueKey('downloading'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Downloading model…',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                        ),
                        Text(
                          '${(downloadProgress * 100).toInt()}%',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.primaryGreen,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: downloadProgress,
                        minHeight: 12,
                        backgroundColor: colors.dividerColor,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colors.primaryGreen),
                      ),
                    ),
                  ],
                )
              : EchoButton(
                  key: const ValueKey('button'),
                  text: isOffline
                      ? (isDownloaded ? 'Continue' : 'Download Qwen2.5 model')
                      : 'Continue',
                  showArrow: !(isOffline && !isDownloaded),
                  icon: (isOffline && !isDownloaded)
                      ? Icons.download_rounded
                      : null,
                  onPressed: (isOffline && !isDownloaded)
                      ? onDownload
                      : (canContinue ? onContinue : null),
                ),
        ),
        if (isOffline && !isDownloaded && !isDownloading) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: onBackgroundDownload,
            child: Text(
              'Download in the background — continue setup',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.primaryGreen,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ] else
          const SizedBox(height: 12),
        Text(
          isOffline
              ? 'Runs entirely on your phone. Works without Wi-Fi.'
              : 'Your key is encrypted locally via Android Keystore.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
