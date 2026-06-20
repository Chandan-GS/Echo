import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_echo/core/theme/app_theme.dart';

class EchoButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppTheme.buttonDark,
          foregroundColor: textColor ?? Colors.white,
          disabledBackgroundColor: AppTheme.dividerColor,
          disabledForegroundColor: AppTheme.textSecondary.withValues(
            alpha: 0.5,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
