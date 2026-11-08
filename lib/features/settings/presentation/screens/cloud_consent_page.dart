import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/animations/fade_slide_in.dart';
import 'package:project_echo/core/presentation/widgets/echo_app_bar.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

/// What the cloud engine sends, before anything is. Pops true when agreed;
/// "Not now" and the back button leave it off.
class CloudConsentPage extends StatelessWidget {
  /// Already on: this is a re-read, so the buttons don't offer to turn it on.
  final bool alreadyOn;

  const CloudConsentPage({super.key, required this.alreadyOn});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: const EchoAppBar(title: ''),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          MediaQuery.paddingOf(context).bottom + 28,
        ),
        child: FadeSlideIn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Before anything leaves your phone',
                style: GoogleFonts.oldStandardTt(
                  fontSize: 32,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Here’s exactly what the cloud engine sends, and what it '
                'never does.',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  height: 1.5,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: c.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Block(
                      icon: Symbols.upload_rounded,
                      tint: _Tint.yes,
                      title: 'What is sent',
                      body:
                          'Only what each job needs: your question and the '
                          'messages that answer it, the messages your briefing '
                          'is written from, a group’s recent messages for its '
                          'summary, messages Echo turns into to-dos, and the '
                          'message you’re replying to. For a reply, that looks '
                          'like this:',
                      sample: const [
                        ('Rohan:', ' Coorg on Friday? I’m driving, leaving '
                            'early. You in?'),
                        ('Ask:', ' draft a short yes, ask what time'),
                      ],
                    ),
                    _divider(context),
                    const _Block(
                      icon: Symbols.block_rounded,
                      tint: _Tint.no,
                      title: 'What is never sent',
                      body:
                          'Your contact list, the rest of your History, '
                          'anything from apps you’ve switched off, your voice.',
                    ),
                    _divider(context),
                    const _Block(
                      icon: Symbols.public_rounded,
                      title: 'Where it goes',
                      body:
                          'Google’s Gemini API, with your own key. On Google’s '
                          'free tier, Google may use what’s sent to improve '
                          'its models. On a paid key, it doesn’t.',
                    ),
                    _divider(context),
                    const _Block(
                      icon: Symbols.history_toggle_off_rounded,
                      title: 'Stop any time',
                      body:
                          'Turn it off in Settings and nothing more is sent.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PressFeedback(
                scale: 0.97,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.buttonDark,
                    foregroundColor: c.textInverse,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(56),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    alreadyOn
                        ? 'Keep the cloud engine on'
                        : 'Turn on the cloud engine',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  alreadyOn ? 'Back' : 'Not now',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Divider(
    height: 1,
    color: context.colors.dividerColor.withValues(alpha: 0.6),
  );
}

enum _Tint { none, yes, no }

class _Block extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final _Tint tint;
  final List<(String, String)> sample;

  const _Block({
    required this.icon,
    required this.title,
    required this.body,
    this.tint = _Tint.none,
    this.sample = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fill, ink) = switch (tint) {
      _Tint.yes => (context.selectionFill, context.onSelection),
      _Tint.no => (context.warmAccent.withValues(alpha: 0.16), context.warmAccent),
      _Tint.none => (Color.lerp(c.background, c.surface, 0.3)!, c.textPrimary),
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    height: 1.5,
                    color: c.textSecondary,
                  ),
                ),
                if (sample.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.5,
                          color: c.textSecondary,
                        ),
                        children: [
                          for (final (i, line) in sample.indexed) ...[
                            if (i > 0) const TextSpan(text: '\n'),
                            TextSpan(
                              text: line.$1,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary,
                              ),
                            ),
                            TextSpan(text: line.$2),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
