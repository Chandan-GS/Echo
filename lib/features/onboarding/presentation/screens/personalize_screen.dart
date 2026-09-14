import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/core/presentation/animations/pressable.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/presentation/widgets/echo_button.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/presentation/cubit/on_boarding_cubit.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/selectable_tile.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';

class PersonalizeScreen extends StatefulWidget {
  const PersonalizeScreen({super.key});

  @override
  State<PersonalizeScreen> createState() => _PersonalizeScreenState();
}

class _PersonalizeScreenState extends State<PersonalizeScreen> {
  OnboardingTone _tone = OnboardingTone.professional;
  final Set<OnboardingInterest> _interests = {};
  TimeOfDay _briefingTime = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    // Restore any earlier choices so navigating back feels continuous.
    final prefs = await SharedPreferences.getInstance();
    final tone = onboardingToneFromId(prefs.getString('briefing_tone'));
    final interestIds = prefs.getStringList('briefing_interests') ?? const [];
    final times = prefs.getStringList('briefing_times');
    final parsed = _parseTime(times != null && times.isNotEmpty ? times.first : null);
    if (!mounted) return;
    setState(() {
      _tone = tone;
      _interests
        ..clear()
        ..addAll(
          interestIds
              .map(onboardingInterestFromId)
              .whereType<OnboardingInterest>(),
        );
      if (parsed != null) _briefingTime = parsed;
    });
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTime(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  String _to24h(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _briefingTime,
      helpText: 'When should Echo brief you?',
    );
    if (picked != null) setState(() => _briefingTime = picked);
  }

  void _continue() {
    // Persist the chosen schedule (replaces the silent 07:00 default) so the
    // home countdown and alarms reflect the user's choice immediately.
    context.read<SettingsCubit>().setBriefingTimes([_to24h(_briefingTime)]);
    context.read<OnBoardingCubit>().completePersonalize(
          tone: _tone,
          interests: _interests,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return OnboardingStepBody(
      title: 'Make Echo yours.',
      subtitle: 'A few taps and every briefing is tuned to you.',
      footer: EchoButton(
        text: 'Hear a sample',
        showArrow: true,
        onPressed: _continue,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('How should Echo speak to you?'),
          const SizedBox(height: 12),
          _ToneTiles(
            tone: _tone,
            onSelect: (t) => setState(() => _tone = t),
          ),
          const SizedBox(height: 16),
          _SectionTitle('What matters most to you?'),
          const SizedBox(height: 4),
          Text(
            'Echo will prioritise these. Pick a few.',
            style: GoogleFonts.nunito(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: OnboardingInterest.values.map((i) {
              final selected = _interests.contains(i);
              return _InterestChip(
                label: i.label,
                selected: selected,
                onTap: () => setState(() {
                  selected ? _interests.remove(i) : _interests.add(i);
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          _SectionTitle('When do you want your briefing?'),
          const SizedBox(height: 12),
          Pressable(
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.alarm_rounded, color: colors.primaryGreen),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      "I'll have it ready by ${_formatTime(_briefingTime)}",
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    'Change',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          _SectionTitle('Prefer a theme?'),
          const SizedBox(height: 12),
          const _ThemePicker(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A solid three-way theme picker (System / Light / Dark) wired to the shared
/// [SettingsCubit], so the choice persists and applies app-wide immediately.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
        const labels = ['System', 'Light', 'Dark'];
        return Row(
          children: List.generate(modes.length, (i) {
            final selected = state.themeMode == modes[i];
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == modes.length - 1 ? 0 : 10),
                child: _ThemePill(
                  label: labels[i],
                  selected: selected,
                  onTap: () =>
                      context.read<SettingsCubit>().setThemeMode(modes[i]),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ThemePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? context.selectionFill : colors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected ? context.onSelection : colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tone choices. A stacked full-width list on phone (unchanged); on
/// desktop, a two-up wrap so it reads as a set of cards rather than a phone
/// list stretched across a much wider column. Uses a computed width (not a
/// rigid GridView) since each tile's height varies with its subtitle length.
class _ToneTiles extends StatelessWidget {
  final OnboardingTone tone;
  final ValueChanged<OnboardingTone> onSelect;

  const _ToneTiles({required this.tone, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isMacOS || Platform.isWindows)) {
      return Column(
        children: OnboardingTone.values
            .map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableTile(
                  title: t.label,
                  subtitle: t.description,
                  isSelected: tone == t,
                  onTap: () => onSelect(t),
                ),
              ),
            )
            .toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: OnboardingTone.values
              .map(
                (t) => SizedBox(
                  width: itemWidth,
                  child: SelectableTile(
                    title: t.label,
                    subtitle: t.description,
                    isSelected: tone == t,
                    onTap: () => onSelect(t),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.nunito(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: context.colors.textPrimary,
      ),
    );
  }
}

class _InterestChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _InterestChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onSel = context.onSelection;
    return Material(
      color: selected ? context.selectionFill : colors.surface,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 17, color: onSel),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? onSel : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
