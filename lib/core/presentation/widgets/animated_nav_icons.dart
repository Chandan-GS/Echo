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
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}

/// An icon that does a playful tilt-and-pop bounce whenever it becomes
/// selected — like something just landed in the tray.
class BounceInIcon extends StatefulWidget {
  final bool isSelected;
  final IconData selectedIcon;
  final IconData unselectedIcon;
  final Color color;
  final double size;

  const BounceInIcon({
    super.key,
    required this.isSelected,
    required this.selectedIcon,
    required this.unselectedIcon,
    required this.color,
    this.size = 26,
  });

  @override
  State<BounceInIcon> createState() => _BounceInIconState();
}

class _BounceInIconState extends State<BounceInIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  late final Animation<double> _wiggle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.22), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -0.22, end: 0.22), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 0.22, end: 0.0), weight: 25),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.28), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.28, end: 1.0), weight: 60),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant BounceInIcon oldWidget) {
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
      builder: (context, child) {
        return Transform.rotate(
          angle: _wiggle.value,
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: Icon(
        widget.isSelected ? widget.selectedIcon : widget.unselectedIcon,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}
