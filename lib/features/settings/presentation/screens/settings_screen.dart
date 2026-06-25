import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/ai_mode_card.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const _SettingsView();
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                'Settings',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.15,
                ),
              ),

              const SizedBox(height: 32),

              // Appearance Section
              Text(
                'Appearance',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              const _AppearanceSegmentedControl(),
              const SizedBox(height: 32),

              // AI Engine Section
              Text(
                'AI Engine',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              BlocBuilder<SettingsCubit, SettingsState>(
                builder: (context, state) {
                  return FutureBuilder<String?>(
                    future: _getModelSize(),
                    builder: (context, snapshot) {
                      final sizeStr = snapshot.data;
                      return AiModeCard(
                        isSelected: state.isOfflineEngine,
                        icon: Icons.laptop_mac,
                        title: 'Offline (Private)',
                        tags: [
                          'Qwen2.5 1.5B',
                          sizeStr ?? '0.9 GB',
                          'No API cost',
                        ],
                        speedLabel: 'Fast',
                        isFast: true,
                        onTap: () {
                          context.read<SettingsCubit>().setAiEngine(
                            isOffline: true,
                          );
                        },
                      );
                    },
                  );
                },
              ),
              const _CloudEngineCard(),
              const SizedBox(height: 32),

              // Scheduled Briefings Section
              Text(
                'Scheduled Briefings',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              const _ScheduledBriefingsSection(),
              const SizedBox(height: 120), // Padding for the bottom nav bar
            ],
          ),
        ),
      ),
    );
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
}

class _AppearanceSegmentedControl extends StatelessWidget {
  const _AppearanceSegmentedControl();

  @override
  Widget build(BuildContext context) {
    final tabs = ['System', 'Light', 'Dark'];

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final selectedIndex = state.themeMode.index;

        return Container(
          height: 60,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.colors.textInverse,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: context.colors.dividerColor.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final itemWidth = totalWidth / 3;
              final activeLeft = selectedIndex * itemWidth;

              return Stack(
                children: [
                  // Fluid sliding active capsule
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    left: activeLeft,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colors.textPrimary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  // Tab Items Row
                  Row(
                    children: List.generate(tabs.length, (index) {
                      final title = tabs[index];
                      final isSelected = selectedIndex == index;

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            context.read<SettingsCubit>().setThemeMode(
                              ThemeMode.values[index],
                            );
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? context.colors.textInverse
                                    : context.colors.textSecondary,
                              ),
                              child: Text(title),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _CloudEngineCard extends StatefulWidget {
  const _CloudEngineCard();

  @override
  State<_CloudEngineCard> createState() => _CloudEngineCardState();
}

class _CloudEngineCardState extends State<_CloudEngineCard> {
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

class _ScheduledBriefingsSection extends StatelessWidget {
  const _ScheduledBriefingsSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final times = state.briefingTimes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your automated AI briefings will run in the background at these times.',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ...times.map((time) {
                  return _buildTimeChip(context, time);
                }).toList(),
                _buildAddButton(context),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimeChip(BuildContext context, String time) {
    final parsedTime = _parseTime(time);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.lightGreenBackground,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            parsedTime.format(context),
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () {
              context.read<SettingsCubit>().removeBriefingTime(time);
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle),
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: const TimeOfDay(hour: 7, minute: 0),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                timePickerTheme: TimePickerThemeData(
                  backgroundColor: context.colors.background,
                  dialHandColor: context.colors.primaryGreen,
                  dayPeriodColor: WidgetStateColor.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? context.colors.primaryGreen.withValues(alpha: 0.2)
                        : Colors.transparent,
                  ),
                  dayPeriodTextColor: Theme.of(context).colorScheme.onSecondary,
                ),
                colorScheme: ColorScheme.light(
                  primary: context.colors.primaryGreen,
                  onPrimary: Colors.white,
                  surface: context.colors.background,
                  onSurface: context.colors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );

        if (time != null && context.mounted) {
          final timeStr =
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          context.read<SettingsCubit>().addBriefingTime(timeStr);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: context.colors.textSecondary.withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 20, color: context.colors.textSecondary),
            const SizedBox(width: 16),
            Text(
              'Add Time',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
}
