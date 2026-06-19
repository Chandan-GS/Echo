import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- Core Palette (from design refs) ---
  static const Color backgroundLight = Color(0xFFF4F2EE); // Paper/cream
  static const Color textPrimary = Color(0xFF1E1E1E);
  static const Color textSecondary = Color(0xFF5A5A5A);
  static const Color primaryGreen = Color(0xFF49884F);
  static const Color lightGreenBackground = Color(0xFFD1E6D3);
  static const Color amberBackground = Color(0xFFFDE49B);
  static const Color buttonDark = Color(0xFF1E1E1E);
  static const Color dividerColor = Color(0xFFE0E0E0);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundLight,
      colorScheme: const ColorScheme.light(
        primary: primaryGreen,
        secondary: lightGreenBackground,
        surface: backgroundLight,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: TextTheme(
        // Headings — Old Standard TT (serif, editorial feel)
        displayLarge: GoogleFonts.oldStandardTt(
          color: textPrimary,
          fontSize: 60,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        displayMedium: GoogleFonts.oldStandardTt(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleLarge: GoogleFonts.oldStandardTt(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        titleMedium: GoogleFonts.oldStandardTt(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        // Body & Labels — Nunito
        bodyLarge: GoogleFonts.nunito(color: textPrimary, fontSize: 16),
        bodyMedium: GoogleFonts.nunito(color: textSecondary, fontSize: 14),
        bodySmall: GoogleFonts.nunito(color: textSecondary, fontSize: 12),
        labelLarge: GoogleFonts.nunito(
          color: textSecondary,
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: GoogleFonts.nunito(
          color: textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryGreen;
          }
          return Colors.grey.shade300;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
