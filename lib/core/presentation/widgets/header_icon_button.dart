import 'package:flutter/material.dart';
import 'package:project_echo/core/presentation/widgets/press_feedback.dart';
import 'package:project_echo/core/theme/app_theme.dart';

/// A plain icon beside a page's title ("Profile ⚙", "The Vault ☰"): no
/// circle behind it, its tap area a comfortable 48, and the icon itself on
/// the page's right edge, in line with everything under it.
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  static const _box = 48.0;
  static const _size = 27.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        // The tap area reaches past the edge so the icon sits on it.
        child: Transform.translate(
          offset: const Offset((_box - _size) / 2, 0),
          child: PressFeedback(
            scale: 0.85,
            child: InkResponse(
              onTap: onTap,
              radius: _box / 2,
              child: SizedBox(
                width: _box,
                height: _box,
                child: Icon(
                  icon,
                  size: _size,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
