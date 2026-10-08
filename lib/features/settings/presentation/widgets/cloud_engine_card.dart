import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/gemini_usage.dart';
import 'package:project_echo/core/services/remote_config_service.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:material_symbols_icons/symbols.dart';

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
          icon: Symbols.cloud_queue_rounded,
          title: 'Cloud AI (Gemini)',
          tags: [
            modelLabel(RemoteConfigService.instance.geminiModel),
            'Your own key',
          ],
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
                    const _GeminiToday(),
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
                                      Symbols.check_circle_rounded,
                                      fill: 1,
                                      color: Colors.green,
                                    )
                                  : _isValid == false
                                  ? const Icon(
                                      Symbols.error_rounded,
                                      color: Colors.red,
                                    )
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

/// Today's Gemini use under the key: what's left when the daily limit is
/// known, otherwise the count so far. An estimate from this phone.
class _GeminiToday extends StatelessWidget {
  const _GeminiToday();

  static final _aiStudio = Uri.parse('https://aistudio.google.com/rate-limit');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = GoogleFonts.nunito(fontSize: 12.5, color: c.textSecondary);
    final strong = small.copyWith(
      color: c.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return ValueListenableBuilder<GeminiUsageSnapshot?>(
      valueListenable: GeminiUsage.instance.snapshot,
      builder: (context, usage, _) {
        if (usage == null) return const SizedBox.shrink();
        final left = usage.left;
        final limit = usage.dailyLimit;
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.dividerColor)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    grouped(left ?? usage.requests),
                    style: GoogleFonts.oldStandardTt(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      left != null
                          ? 'of about ${grouped(limit!)} left today'
                          : usage.requests == 1
                          ? 'request today'
                          : 'requests today',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (usage.fractionLeft != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: usage.fractionLeft,
                    minHeight: 8,
                    backgroundColor: c.dividerColor,
                    color: usage.isLow ? context.warmAccent : c.primaryGreen,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: small,
                        children: [
                          if (left != null) ...[
                            TextSpan(
                              text: grouped(usage.requests),
                              style: strong,
                            ),
                            const TextSpan(text: ' used · '),
                          ],
                          TextSpan(text: grouped(usage.tokens), style: strong),
                          const TextSpan(text: ' tokens'),
                        ],
                      ),
                    ),
                  ),
                  Text('Resets at ${clockTime(usage.resetsAt)}', style: small),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () =>
                    launchUrl(_aiStudio, mode: LaunchMode.externalApplication),
                child: Text.rich(
                  TextSpan(
                    style: small,
                    children: [
                      TextSpan(
                        text: left != null
                            ? 'An estimate from this phone. '
                            : 'Your daily limit shows here once Gemini reports it. ',
                      ),
                      TextSpan(
                        text: left != null
                            ? 'Exact limits in AI Studio'
                            : 'See it in AI Studio',
                        style: small.copyWith(
                          color: c.primaryGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
