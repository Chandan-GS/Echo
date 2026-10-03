import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.only(left: 18, right: 8),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
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
                if (hasText || !widget.dictation)
                  _RoundButton(
                    size: 36,
                    color: hasText && widget.enabled
                        ? colors.buttonDark
                        : colors.dividerColor,
                    onTap: hasText && widget.enabled ? widget.onSend : null,
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: colors.textInverse,
                    ),
                  )
                else
                  _RoundButton(
                    size: 36,
                    color: _dictating
                        ? context.selectionFill
                        : Colors.transparent,
                    onTap: widget.enabled ? _dictate : null,
                    child: Icon(
                      _dictating ? Icons.mic_rounded : Icons.mic_none_rounded,
                      size: 22,
                      color: _dictating
                          ? context.onSelection
                          : colors.textSecondary,
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
    required this.size,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Material(
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
  );
}
