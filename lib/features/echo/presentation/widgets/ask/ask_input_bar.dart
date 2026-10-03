import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:material_symbols_icons/symbols.dart';
import 'package:project_echo/core/presentation/widgets/pressable.dart';

/// Ask Echo's bottom bar: a rounded field with a mic for dictating, which
/// becomes a send arrow once there's text.
class AskInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;

  /// Whether the mic is offered (not on desktop).
  final bool dictation;

  const AskInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hint,
    required this.onSend,
    this.dictation = true,
  });

  @override
  State<AskInputBar> createState() => _AskInputBarState();
}

class _AskInputBarState extends State<AskInputBar> {
  final _speech = stt.SpeechToText();
  var _dictating = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _speech.cancel();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _dictate() async {
    if (_dictating) {
      await _speech.stop();
      setState(() => _dictating = false);
      return;
    }
    final ok = await _speech.initialize();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Echo needs the microphone to hear you.'),
          ),
        );
      }
      return;
    }
    // The speech plugin is one object shared with voice mode, and only its
    // first initialize sets these, so they're claimed for each session.
    _speech
      ..statusListener = (status) {
        if (status == 'done' && mounted) setState(() => _dictating = false);
      }
      ..errorListener = (_) {
        if (mounted) setState(() => _dictating = false);
      };
    setState(() => _dictating = true);
    await _speech.listen(
      onResult: (r) {
        widget.controller.value = TextEditingValue(
          text: r.recognizedWords,
          selection: TextSelection.collapsed(offset: r.recognizedWords.length),
        );
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasText = widget.controller.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.only(left: 20, right: 7),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(29),
              // Dark mode: a hairline, since a shadow doesn't show there.
              border: context.isDarkMode
                  ? Border.all(color: colors.dividerColor)
                  : null,
              boxShadow: context.isDarkMode
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: widget.enabled,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.send,
                    cursorColor: colors.primaryGreen,
                    style: GoogleFonts.nunito(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _dictating ? 'Listening…' : widget.hint,
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 15.5,
                        color: colors.textSecondary.withValues(alpha: 0.6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) {
                      if (widget.enabled && hasText) widget.onSend();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                // Send swaps in for the mic once there's something to send.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: hasText || !widget.dictation
                      ? _RoundButton(
                          key: const ValueKey('send'),
                          size: 44,
                          color: hasText && widget.enabled
                              ? colors.primaryGreen
                              : colors.dividerColor,
                          onTap: hasText && widget.enabled
                              ? widget.onSend
                              : null,
                          child: Icon(
                            Symbols.arrow_upward_rounded,
                            size: 24,
                            color: context.isDarkMode
                                ? colors.textInverse
                                : Colors.white,
                          ),
                        )
                      : _RoundButton(
                          key: const ValueKey('mic'),
                          size: 44,
                          // A soft disc at rest, so it reads as a button in
                          // both themes; green while listening.
                          color: _dictating
                              ? colors.primaryGreen
                              : Color.lerp(
                                  colors.surface,
                                  colors.textPrimary,
                                  context.isDarkMode ? 0.08 : 0.05,
                                )!,
                          onTap: widget.enabled ? _dictate : null,
                          child: Icon(
                            Symbols.mic_rounded,
                            fill: _dictating ? 1 : 0,
                            size: 24,
                            color: _dictating
                                ? (context.isDarkMode
                                      ? colors.textInverse
                                      : Colors.white)
                                : colors.textPrimary,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  const _RoundButton({
    super.key,
    required this.size,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Pressable(
    scale: 0.9,
    child: Material(
      color: color,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    ),
  );
}
