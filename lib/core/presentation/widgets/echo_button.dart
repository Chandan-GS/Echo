import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';
import 'package:project_echo/core/presentation/animations/app_motion.dart';

class EchoButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool showArrow;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;

  const EchoButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.showArrow = false,
    this.backgroundColor,
    this.textColor,
    this.icon,
  });

  @override
  State<EchoButton> createState() => _EchoButtonState();
}

class _EchoButtonState extends State<EchoButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Listener drives the squeeze from raw pointer events without consuming the
    // gesture, so the underlying ElevatedButton keeps its ripple, onPressed and
    // disabled semantics.
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: _pressed ? AppMotion.fast : AppMotion.medium,
        curve: _pressed ? AppMotion.standard : AppMotion.spring,
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  widget.backgroundColor ?? context.colors.buttonDark,
              foregroundColor: widget.textColor ?? context.colors.textInverse,
              disabledBackgroundColor: context.colors.dividerColor,
              disabledForegroundColor: context.colors.textSecondary.withValues(
                alpha: 0.5,
              ),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: widget.onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.text,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.showArrow) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
