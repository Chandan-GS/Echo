import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/page_transitions.dart';
import 'package:project_echo/core/services/gemini_service.dart';
import 'package:project_echo/core/services/gemini_usage.dart' show modelLabel;
import 'package:project_echo/core/services/remote_config_service.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/settings/data/engine_status.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:project_echo/features/settings/presentation/cubit/settings_state.dart';
import 'package:project_echo/features/settings/presentation/screens/cloud_consent_page.dart';
import 'package:project_echo/features/settings/presentation/widgets/cloud_engine_card.dart';
import 'package:project_echo/features/settings/presentation/widgets/settings_kit.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings → Cloud engine: off until the consent page is accepted, then the
/// key and today's use of it. Reads the live engine state, so a key added
/// from the first-use sheet shows up here too.
class CloudEnginePage extends StatefulWidget {
  const CloudEnginePage({super.key});

  @override
  State<CloudEnginePage> createState() => _CloudEnginePageState();
}

class _CloudEnginePageState extends State<CloudEnginePage> {
  final _keyField = TextEditingController();
  bool _editing = false;
  bool _validating = false;
  bool? _valid;

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

  SettingsCubit get _cubit => context.read<SettingsCubit>();

  Future<void> _toggle(bool on) async {
    if (!on) {
      await _cubit.setAiEngine(isOffline: true);
      if (mounted) settingsToast(context, 'Cloud engine off');
      return;
    }
    final agreed = await _openConsent(alreadyOn: false);
    if (agreed != true || !mounted) return;
    final hasKey = _cubit.state.geminiApiKey.isNotEmpty;
    await _cubit.setAiEngine(isOffline: false);
    if (mounted) {
      settingsToast(
        context,
        hasKey ? 'Cloud engine on' : 'Cloud engine on. Add your Gemini key',
      );
    }
  }

  Future<bool?> _openConsent({required bool alreadyOn}) =>
      Navigator.of(context).push<bool>(
        bouncyRoute(CloudConsentPage(alreadyOn: alreadyOn)),
      );

  Future<void> _saveKey() async {
    final key = _keyField.text.trim();
    if (key.isEmpty) {
      await _cubit.setGeminiApiKey('');
      if (mounted) {
        setState(() {
          _editing = false;
          _valid = null;
        });
      }
      return;
    }
    setState(() {
      _validating = true;
      _valid = null;
    });
    final ok = await GeminiService.instance.validateKey(key);
    if (!mounted) return;
    setState(() {
      _validating = false;
      _valid = ok;
    });
    if (!ok) {
      settingsToast(context, 'Invalid API Key. Please try again.');
      return;
    }
    await _cubit.setGeminiApiKey(key);
    if (!mounted) return;
    _keyField.clear();
    setState(() {
      _editing = false;
      _valid = null;
    });
    settingsToast(context, 'API Key validated and saved successfully!');
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) settingsToast(context, "That link couldn't be opened.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final on = !state.isOfflineEngine;
        final hasKey = state.geminiApiKey.isNotEmpty;
        final model = modelLabel(RemoteConfigService.instance.geminiModel);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSwitchCard(
              icon: Symbols.cloud_rounded,
              title: 'Use a cloud engine',
              value: on
                  ? '$model · your own key'
                  : 'You’ll see exactly what is sent first',
              on: on,
              onChanged: _toggle,
            ),
            if (on) ...[
              if (!hasKey)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: SettingsHint(
                    icon: Symbols.key_rounded,
                    title: 'Add your key to start',
                    body:
                        'Until there’s a key, Echo keeps writing on this phone.',
                  ),
                ),
              const SettingsSubLabel('Gemini key'),
              _keyCard(context, state, hasKey),
              const SizedBox(height: 12),
              SettingsHint(
                icon: Symbols.fact_check_rounded,
                title: 'What gets sent',
                body: 'Read the consent again, or see a sample request.',
                onTap: () => _openConsent(alreadyOn: true),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _keyCard(BuildContext context, SettingsState state, bool hasKey) {
    final c = context.colors;
    final editing = _editing || !hasKey;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editing)
            _keyForm(context, canCancel: hasKey)
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Symbols.key_rounded, size: 18, color: c.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      maskApiKey(state.geminiApiKey),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _pill(
              context,
              'Replace Key',
              onTap: () => setState(() {
                _editing = true;
                _valid = null;
                _keyField.clear();
              }),
            ),
            const GeminiTodayUsage(),
          ],
        ],
      ),
    );
  }

  Widget _keyForm(BuildContext context, {required bool canCancel}) {
    final c = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: c.dividerColor, width: 1.5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'API Key',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keyField,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(fontFamily: 'monospace', color: c.textPrimary),
          decoration: InputDecoration(
            hintText: 'AIza…',
            hintStyle: TextStyle(color: c.textSecondary),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: c.primaryGreen, width: 1.5),
            ),
            suffixIcon: _validating
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _valid == false
                ? Icon(Symbols.error_rounded, color: context.warmAccent)
                : null,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _pill(context, 'Save', onTap: _validating ? null : _saveKey),
            if (canCancel) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() {
                  _editing = false;
                  _valid = null;
                  _keyField.clear();
                }),
                child: Text(
                  'Keep current key',
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _open('https://aistudio.google.com/app/apikey'),
          child: Text(
            'Get your API key from Google AI Studio',
            style: GoogleFonts.nunito(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: c.primaryGreen,
              decoration: TextDecoration.underline,
              decorationColor: c.primaryGreen,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(
    BuildContext context,
    String text, {
    required VoidCallback? onTap,
  }) {
    return Material(
      color: context.selectionFill,
      borderRadius: BorderRadius.circular(99),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            text,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.onSelection,
            ),
          ),
        ),
      ),
    );
  }
}
