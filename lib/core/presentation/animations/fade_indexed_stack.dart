import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

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
    this.duration = AppMotion.medium,
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
        final t = Curves.easeOut.transform(_controller.value);
        return Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: List<Widget>.generate(widget.children.length, (i) {
            final isActive = i == widget.index;
            // Keep inactive pages laid out (state preserved) but invisible and
            // non-interactive. The active page fades + scales in.
            return IgnorePointer(
              ignoring: !isActive,
              child: Opacity(
                opacity: isActive ? t : 0,
                child: isActive
                    ? Transform.scale(
                        scale: 0.99 + 0.01 * t,
                        child: widget.children[i],
                      )
                    : widget.children[i],
              ),
            );
          }),
        );
      },
    );
  }
}
