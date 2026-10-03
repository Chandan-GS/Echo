import 'package:flutter/material.dart';

/// An icon that spins a full turn whenever it becomes selected — like a gear
/// turning into place. Fires once per selection so the Settings tab always
/// feels alive rather than a static icon swap.
class SpinInIcon extends StatefulWidget {
  final bool isSelected;
  final IconData selectedIcon;
  final IconData unselectedIcon;
  final Color color;
  final double size;

  const SpinInIcon({
    super.key,
    required this.isSelected,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.color,
    this.size = 26,
  });

  @override
  State<SpinInIcon> createState() => _SpinInIconState();
}

class _SpinInIconState extends State<SpinInIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final Animation<double> _spin = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  );

  @override
  void didUpdateWidget(covariant SpinInIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.forward(from: 0);
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
      animation: _spin,
      builder: (context, child) {
        return Transform.rotate(angle: _spin.value * 2 * 3.14159265, child: child);
      },
      child: Icon(
        widget.isSelected ? widget.selectedIcon : widget.unselectedIcon,
        // The selected tab's icon is filled, the others outlined.
        fill: widget.isSelected ? 1 : 0,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}

/// An icon that lands when it becomes selected: squashed tall as the dock's
/// pill stretches to it, then wide, then settled — like something soft
/// dropping into place.
class SquashInIcon extends StatefulWidget {
  final bool isSelected;
  final IconData selectedIcon;
  final IconData unselectedIcon;
  final Color color;
  final double size;

  const SquashInIcon({
    super.key,
    required this.isSelected,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.color,
    this.size = 26,
  });

  @override
  State<SquashInIcon> createState() => _SquashInIconState();
}

class _SquashInIconState extends State<SquashInIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  /// (width, height) scale: tall, then wide, then itself.
  late final Animation<double> _x = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 20),
    TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.12), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 45),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  late final Animation<double> _y = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 20),
    TweenSequenceItem(tween: Tween(begin: 1.15, end: 0.92), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.0), weight: 45),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant SquashInIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.forward(from: 0);
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
      builder: (context, child) => Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.diagonal3Values(_x.value, _y.value, 1),
        child: child,
      ),
      child: Icon(
        widget.isSelected ? widget.selectedIcon : widget.unselectedIcon,
        // The selected tab's icon is filled, the others outlined.
        fill: widget.isSelected ? 1 : 0,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}
