import 'package:flutter/material.dart';

/// Drop-in replacement for [IndexedStack] that cross-fades (with a whisper of
/// scale) between children when [index] changes, instead of hard-cutting.
///
/// Like [IndexedStack] it keeps every child alive in the tree, so tab state
/// (scroll positions, in-flight requests, controllers) is preserved across
/// switches — only the visible one is interactive.
class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final v = _controller.value;
        // Opacity must stay in [0,1]; the scale rides an overshooting curve so
        // the incoming tab pops in with a springy bounce (like the chat bubbles).
        final fade = Curves.easeOut.transform(v);
        final scaleT = Curves.easeOutBack.transform(v);
        final scale = 0.90 + 0.10 * scaleT;
        return Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: List<Widget>.generate(widget.children.length, (i) {
            final isActive = i == widget.index;
            // Keep inactive pages laid out (state preserved) but invisible and
            // non-interactive. The active page bounces + fades in.
            return IgnorePointer(
              ignoring: !isActive,
              child: Opacity(
                opacity: isActive ? fade : 0,
                child: isActive
                    ? Transform.scale(scale: scale, child: widget.children[i])
                    : widget.children[i],
              ),
            );
          }),
        );
      },
    );
  }
}
