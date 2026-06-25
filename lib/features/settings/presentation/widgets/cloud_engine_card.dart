import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';

class CloudEngineCard extends StatefulWidget {
  const CloudEngineCard({super.key});

  @override
  State<CloudEngineCard> createState() => _CloudEngineCardState();
}

class _CloudEngineCardState extends State<CloudEngineCard> {
  late TextEditingController _apiKeyController;
  bool _isValidating = false;
  bool? _isValid;
  bool _isEditingKey = false;

  @override
  void initState() {
    super.initState();
    final initialKey = context.read<SettingsCubit>().state.geminiApiKey;
    _apiKeyController = TextEditingController(text: initialKey);
    if (initialKey.isNotEmpty) {
      _isValid = true;
    } else {
      _isEditingKey = true;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _validateAndSave(String apiKey) async {
    if (apiKey.isEmpty) {
      setState(() => _isValid = null);
      context.read<SettingsCubit>().setGeminiApiKey('');
      return;
    }

    setState(() {
      _isValidating = true;
      _isValid = null;
    });

    final isValid = await GeminiService.instance.validateKey(apiKey);

    if (mounted) {
      setState(() {
        _isValidating = false;
        _isValid = isValid;
      });

      if (isValid) {
        context.read<SettingsCubit>().setGeminiApiKey(apiKey);
        setState(() {
          _isEditingKey = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('API Key validated and saved successfully!'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid API Key. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          previous.geminiApiKey != current.geminiApiKey,
      listener: (context, state) {
        if (state.geminiApiKey.isNotEmpty) {
          _apiKeyController.text = state.geminiApiKey;
          setState(() {
            _isEditingKey = false;
            _isValid = true;
          });
        }
      },
      builder: (context, state) {
        return AiModeCard(
          isSelected: !state.isOfflineEngine,
          icon: Icons.cloud_queue,
          title: 'Cloud AI (Gemini)',
          tags: const ['Gemini 2.5 Flash', 'Requires API Key'],
          speedLabel: 'Fastest',
          isFast: true,
          onTap: () {
            context.read<SettingsCubit>().setAiEngine(isOffline: false);
          },
          expandedContent: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isEditingKey && state.geminiApiKey.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            state.geminiApiKey.startsWith('AIza')
                                ? 'AIza...${state.geminiApiKey.length > 10 ? state.geminiApiKey.substring(state.geminiApiKey.length - 4) : ''}'
                                : '${state.geminiApiKey.substring(0, 4)}...${state.geminiApiKey.length > 8 ? state.geminiApiKey.substring(state.geminiApiKey.length - 4) : ''}',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isEditingKey = true;
                              _apiKeyController.clear();
                              _isValid = null;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor:
                                context.colors.lightGreenBackground,
                            foregroundColor: context.colors.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          child: const Text(
                            'Replace Key',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'API Key',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: 'sk-...',
                              hintStyle: TextStyle(
                                color: context.colors.textSecondary,
                              ),
                              filled: true,
                              fillColor: context.colors.background,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: context.colors.primaryGreen,
                                ),
                              ),
                              suffixIcon: _isValidating
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : _isValid == true
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    )
                                  : _isValid == false
                                  ? const Icon(Icons.error, color: Colors.red)
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isValidating
                              ? null
                              : () => _validateAndSave(_apiKeyController.text),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor:
                                context.colors.lightGreenBackground,
                            foregroundColor: context.colors.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          child: const Text(
                            'Replace',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final url = Uri.parse(
                          'https://aistudio.google.com/app/apikey',
                        );
                        try {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          debugPrint('Could not launch URL: $e');
                        }
                      },
                      child: Text(
                        'Get your API key from Google AI Studio',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.primaryGreen,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
