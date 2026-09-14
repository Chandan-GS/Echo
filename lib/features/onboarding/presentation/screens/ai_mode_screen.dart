import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';
import 'package:project_echo/core/services/offline_model_repository.dart';
import 'package:project_echo/core/services/model_download_service.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';

class AiModeScreen extends StatefulWidget {
  const AiModeScreen({super.key});

  @override
  State<AiModeScreen> createState() => _AiModeScreenState();
}

class _AiModeScreenState extends State<AiModeScreen> {
  // The download itself lives in the shared ModelDownloadService, not local
  // State — a plain Future keeps running when this widget is disposed (e.g.
  // the user steps back/forward through onboarding mid-download), but local
  // State doesn't survive that, so the progress bar used to reset on return.
  bool isDownloaded = false;
  final ModelDownloadRepository _downloadRepository =
      createOfflineModelRepository();

  @override
  void initState() {
    super.initState();
    ModelDownloadService.instance.state.addListener(_onDownloadStateChanged);
    _refreshDownloadedState();
  }

  @override
  void dispose() {
    ModelDownloadService.instance.state.removeListener(_onDownloadStateChanged);
    super.dispose();
  }

  void _onDownloadStateChanged() {
    if (ModelDownloadService.instance.state.value.phase ==
        ModelDownloadPhase.done) {
      _refreshDownloadedState();
    }
  }

  Future<void> _refreshDownloadedState() async {
    final downloaded = await _downloadRepository.isModelDownloaded();
    if (!mounted) return;
    setState(() => isDownloaded = downloaded);
    if (downloaded) context.read<OnBoardingCubit>().setModelDownloaded(true);
  }

  void _startDownload() {
    ModelDownloadService.instance.startIfNeeded();
  }

  /// Starts the model download without blocking, then advances immediately.
  /// The sample-briefing preview (later steps) uses on-device TTS rather than
  /// the model, so setup can continue while the model downloads in the
  /// background. Briefing generation checks the model file directly on disk.
  void _downloadInBackgroundAndContinue() {
    ModelDownloadService.instance.startIfNeeded();
    context.read<OnBoardingCubit>().completeAiMode();
  }

  Future<String?> _getModelSize() async {
    try {
      final path = await _downloadRepository.downloadedPathOrNull();
      if (path != null) {
        final bytes = await File(path).length();
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
        return ValueListenableBuilder<ModelDownloadState>(
          valueListenable: ModelDownloadService.instance.state,
          builder: (context, dlState, _) {
            return OnboardingStepBody(
              title: 'How should Echo think?',
              subtitle: 'Change this anytime in settings.',
              footer: _Footer(
                settingsState: settingsState,
                isDownloading: dlState.phase == ModelDownloadPhase.downloading,
                isDownloaded: isDownloaded,
                downloadProgress: dlState.progress,
                onDownload: _startDownload,
                onContinue: cubit.completeAiMode,
                onBackgroundDownload: _downloadInBackgroundAndContinue,
              ),
              child: _EngineChoices(
                settingsState: settingsState,
                getModelSize: _getModelSize,
              ),
            );
          },
        );
      },
    );
  }
}

/// The two engine-choice cards. Side by side on desktop (there's room, and it
/// reads as an actual choice rather than a phone-style stacked list); stacked
/// on phone widths, exactly as before.
class _EngineChoices extends StatelessWidget {
  final SettingsState settingsState;
  final Future<String?> Function() getModelSize;

  const _EngineChoices({
    required this.settingsState,
    required this.getModelSize,
  });

  @override
  Widget build(BuildContext context) {
    final privateCard = FutureBuilder<String?>(
      future: getModelSize(),
      builder: (context, snapshot) {
        final sizeStr = snapshot.data ?? offlineModelSizeLabel();
        return AiModeCard(
          isSelected: settingsState.isOfflineEngine,
          icon: Icons.laptop_mac,
          title: 'Private (on this device)',
          tags: const [
            'Runs offline',
            'No API cost',
            'Nothing leaves your device',
          ],
          speedLabel: 'Fast',
          isFast: true,
          onTap: () {
            context.read<SettingsCubit>().setAiEngine(isOffline: true);
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
                  'One-time download of ${offlineModelDisplayName()} ($sizeStr). After that, it works with no internet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (Platform.isMacOS || Platform.isWindows) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: privateCard),
          const SizedBox(width: 16),
          const Expanded(child: CloudEngineCard()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        privateCard,
        const SizedBox(height: 16),
        const CloudEngineCard(),
      ],
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.primaryGreen,
                        ),
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
              ? 'Runs entirely on this device. Works without Wi-Fi.'
              : 'Your key is encrypted and stored only on this device.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
