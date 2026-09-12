import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:project_echo/features/onboarding/data/onboarding_personalization.dart';
import 'package:project_echo/features/onboarding/presentation/widgets/selectable_tile.dart';

/// Settings ▸ Tone — lets the user change how Echo speaks (professional /
/// friendly / direct) at any time. Persists to the same `briefing_tone` key the
/// briefing prompt reads, so changes take effect on the next briefing.
class ToneSettingsSection extends StatefulWidget {
  const ToneSettingsSection({super.key});

  @override
  State<ToneSettingsSection> createState() => _ToneSettingsSectionState();
}

class _ToneSettingsSectionState extends State<ToneSettingsSection> {
  OnboardingTone _tone = OnboardingTone.professional;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final tone = onboardingToneFromId(prefs.getString('briefing_tone'));
    if (mounted) setState(() => _tone = tone);
  }

  Future<void> _select(OnboardingTone tone) async {
    setState(() => _tone = tone);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briefing_tone', tone.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: OnboardingTone.values
          .map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectableTile(
                title: t.label,
                subtitle: t.description,
                isSelected: _tone == t,
                onTap: () => _select(t),
              ),
            ),
          )
          .toList(),
    );
  }
}
