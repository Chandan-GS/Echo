import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/features/onboarding/domain/repositories/model_download_repository.dart';
import 'package:project_echo/features/onboarding/data/repositories/model_download_repository_impl.dart';

class AiModeScreen extends StatefulWidget {
  const AiModeScreen({super.key});

  @override
  State<AiModeScreen> createState() => _AiModeScreenState();
}

class _AiModeScreenState extends State<AiModeScreen> {
  bool isOfflineSelected = true;
  final TextEditingController _apiKeyController = TextEditingController();

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
      print("Model downloaded to $modelPath");
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isDownloading = false;
      });
      print("Download failed: $e");
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OnBoardingCubit>();
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textPrimary,
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
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Offline Card
                    AiModeCard(
                      title: 'Offline (Private)',
                      icon: Icons.computer_rounded,
                      isSelected: isOfflineSelected,
                      onTap: () => setState(() => isOfflineSelected = true),
                      tags: const ['DeepSeek 1.5B', '1.8GB', 'No API cost'],
                      speedLabel: 'Slower',
                      isFast: false,
                    ),

                    const SizedBox(height: 16),

                    // Online Card
                    AiModeCard(
                      title: 'Online (Cloud)',
                      icon: Icons.cloud_outlined,
                      isSelected: !isOfflineSelected,
                      onTap: () => setState(() => isOfflineSelected = false),
                      tags: const [
                        'OpenAI / Gemini',
                        'Encrypted key',
                        '~\$0.002/day',
                      ],
                      speedLabel: 'Faster',
                      isFast: true,
                      expandedContent: _buildApiKeyField(),
                    ),

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
                                                color: AppTheme.textPrimary,
                                              ),
                                        ),
                                        Text(
                                          '${(downloadProgress * 100).toInt()}%',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.primaryGreen,
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
                                        backgroundColor: AppTheme.dividerColor,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                              AppTheme.primaryGreen,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : EchoButton(
                                key: const ValueKey('button'),
                                text: isOfflineSelected
                                    ? (isDownloaded
                                          ? 'Continue'
                                          : 'Download DeepSeek model')
                                    : 'Save & Continue',
                                icon: isOfflineSelected && !isDownloaded
                                    ? Icons.download_rounded
                                    : null,
                                onPressed: () {
                                  if (isOfflineSelected && !isDownloaded) {
                                    _startDownload();
                                  } else {
                                    context
                                        .read<OnBoardingCubit>()
                                        .completeAiMode();
                                  }
                                },
                              ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          isOfflineSelected
                              ? 'Requires ~1.8GB of free space. Works without Wi-Fi.'
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
  }

  Widget _buildApiKeyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'API Key',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _apiKeyController,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'sk-...',
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
            filled: true,
            fillColor: AppTheme.backgroundLight,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primaryGreen),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Used to generate your daily briefing. You will be billed by your provider.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
