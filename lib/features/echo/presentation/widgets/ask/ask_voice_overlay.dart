import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/features/echo/presentation/widgets/echo_mascot.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Asking out loud: Echo listens over a soft wash, shows what it heard, and
/// hands the words back when it stops. Tapping anywhere stops listening.
class AskVoiceOverlay extends StatefulWidget {
  /// Called once with what was heard, which may be empty.
  final ValueChanged<String> onDone;

  /// Why listening couldn't start.
  final ValueChanged<String> onError;

  const AskVoiceOverlay({
    super.key,
    required this.onDone,
    required this.onError,
  });

  @override
  State<AskVoiceOverlay> createState() => _AskVoiceOverlayState();
}

class _AskVoiceOverlayState extends State<AskVoiceOverlay>
    with SingleTickerProviderStateMixin {
  final _speech = stt.SpeechToText();
  late final _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  var _heard = '';
  var _closed = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _speech.cancel();
    _ripple.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    final ok = await _speech.initialize();
    if (!mounted) return;
    if (!ok) {
      _closed = true;
      widget.onError('Echo needs the microphone to hear you.');
      return;
    }
    // The speech plugin keeps its first initialize's listeners, so they're
    // claimed for each session.
    _speech
      ..statusListener = (status) {
        if (status == 'done') _finish();
      }
      ..errorListener = (_) => _finish();
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult) _finish();
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
    );
  }

  void _finish() {
    if (_closed || !mounted) return;
    _closed = true;
    _speech.stop();
    widget.onDone(_heard.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasWords = _heard.trim().isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: ColoredBox(
        color: c.background.withValues(alpha: 0.94),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        _Ring(animation: _ripple, offset: i / 3),
                      const EchoMascot(
                        state: EchoState.listening,
                        size: 130,
                        showRings: false,
                        glow: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 58),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: Text(
                        hasWords ? _heard : ' ',
                        key: ValueKey(hasWords),
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.oldStandardTt(
                          fontSize: 22,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Listening… tap to stop',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A green ring widening and fading as Echo listens, a third apart.
class _Ring extends StatelessWidget {
  final Animation<double> animation;
  final double offset;
  const _Ring({required this.animation, required this.offset});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = (animation.value + offset) % 1;
        final fade = t < 0.3 ? (t / 0.3) * 0.7 : 0.7 * (1 - (t - 0.3) / 0.7);
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.55 + 0.7 * t,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: context.selectionFill, width: 6),
              ),
            ),
          ),
        );
      },
    );
  }
}
