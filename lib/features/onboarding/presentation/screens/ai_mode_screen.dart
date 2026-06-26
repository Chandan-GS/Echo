import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';

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
      setState(() {
        isDownloaded = downloaded;
      });
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
            downloadProgress = received / total;
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
      setState(() {
        isDownloading = false;
      });
      debugPrint("Download failed: $e");
    }
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
    } catch (e) {
      // Ignore
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settingsState) {
        return Scaffold(
          appBar: AppBar(
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: context.colors.textPrimary,
              ),
              onPressed: () {
                cubit.checkPermissions();
              },
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How should Echo think?',
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You can change this anytime in settings.',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: context.colors.textSecondary),
                        ),
                        const SizedBox(height: 32),

                        // Offline Card
                        FutureBuilder<String?>(
                          future: _getModelSize(),
                          builder: (context, snapshot) {
                            // final sizeStr = snapshot.data;
                            return AiModeCard(
                              isSelected: settingsState.isOfflineEngine,
                              icon: Icons.laptop_mac,
                              title: 'Offline (Private)',
                              tags: ['Qwen2.5 1.5B', '0.9 GB', 'No API cost'],
                              speedLabel: 'Fast',
                              isFast: true,
                              onTap: () {
                                context.read<SettingsCubit>().setAiEngine(
                                  isOffline: true,
                                );
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // Online Card
                        const CloudEngineCard(),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    fillOverscroll: true,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Bottom Action
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: isDownloading
                                ? Container(
                                    key: const ValueKey('downloading'),
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Downloading model...',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: context
                                                        .colors
                                                        .textPrimary,
                                                  ),
                                            ),
                                            Text(
                                              '${(downloadProgress * 100).toInt()}%',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: context
                                                        .colors
                                                        .primaryGreen,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: downloadProgress,
                                            minHeight: 12,
                                            backgroundColor:
                                                context.colors.dividerColor,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  context.colors.primaryGreen,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : EchoButton(
                                    key: const ValueKey('button'),
                                    text: settingsState.isOfflineEngine
                                        ? (isDownloaded
                                              ? 'Continue'
                                              : 'Download Qwen2.5 model')
                                        : 'Continue',
                                    icon:
                                        settingsState.isOfflineEngine &&
                                            !isDownloaded
                                        ? Icons.download_rounded
                                        : null,
                                    onPressed:
                                        (settingsState.isOfflineEngine &&
                                            !isDownloaded)
                                        ? _startDownload
                                        : (settingsState.isOfflineEngine ||
                                              settingsState
                                                  .geminiApiKey
                                                  .isNotEmpty)
                                        ? () {
                                            cubit.completeAiMode();
                                          }
                                        : null,
                                  ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              settingsState.isOfflineEngine
                                  ? 'Requires ~0.9GB of free space. Works without Wi-Fi.'
                                  : 'Your key is encrypted locally via Android Keystore.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
