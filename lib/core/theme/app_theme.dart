import 'package:flutter/material.dart';
import 'package:project_echo/core/theme/google_fonts.dart';

class AppColors {
  final Color background;
  final Color textPrimary;
  final Color textSecondary;
  final Color primaryGreen;
  final Color lightGreenBackground;
  final Color amberBackground;
  final Color buttonDark;
  final Color dividerColor;
  final Color surface;
  final Color textInverse;

  const AppColors({
    required this.background,
    required this.textPrimary,
    required this.textSecondary,
    required this.primaryGreen,
    required this.lightGreenBackground,
    required this.amberBackground,
    required this.buttonDark,
    required this.dividerColor,
    required this.surface,
    required this.textInverse,
  });
}

extension AppThemeContext on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  AppColors get colors => isDarkMode
      ? const AppColors(
          background: AppTheme.backgroundDark,
          textPrimary: AppTheme.textPrimaryDark,
          textSecondary: AppTheme.textSecondaryDark,
          primaryGreen: Color.fromARGB(255, 110, 188, 118),
          lightGreenBackground: AppTheme.primaryGreen,
          amberBackground: AppTheme.darkAmberBackground,
          buttonDark: AppTheme.buttonLight,
          dividerColor: AppTheme.dividerColorDark,
          surface: AppTheme.surfaceDark,
          textInverse: AppTheme.textPrimary,
        )
      : const AppColors(
          background: AppTheme.backgroundLight,
          textPrimary: AppTheme.textPrimary,
          textSecondary: AppTheme.textSecondary,
          primaryGreen: AppTheme.primaryGreen,
          lightGreenBackground: AppTheme.lightGreenBackground,
          amberBackground: AppTheme.amberBackground,
          buttonDark: AppTheme.buttonDark,
          dividerColor: AppTheme.dividerColor,
          surface: Colors.white,
          textInverse: Colors.white,
        );
}

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

  // --- Dark Palette ---
  static const Color backgroundDark = Color(0xFF1A1A1A); // Dark paper/charcoal
  static const Color surfaceDark = Color(
    0xFF262626,
  ); // Slightly lighter than background
  static const Color textPrimaryDark = Color(0xFFEFEFEF);
  static const Color textSecondaryDark = Color(0xFFA0A0A0);
  static const Color primaryGreenDark = Color(
    0xFF5CA363,
  ); // Slightly lighter for contrast
  static const Color darkGreenBackground = Color(
    0xFF233524,
  ); // Dark tinted green
  static const Color darkAmberBackground = Color(
    0xFF4A3E22,
  ); // Dark tinted amber
  static const Color buttonLight = Color(0xFFEFEFEF);
  static const Color dividerColorDark = Color(0xFF333333);

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
        bodyLarge: GoogleFonts.nunito(color: textPrimary, fontSize: 18),
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

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundDark,
      colorScheme: const ColorScheme.dark(
        primary: primaryGreenDark,
        secondary: darkGreenBackground,
        surface: backgroundDark,
        onPrimary: Colors.black,
        onSurface: textPrimaryDark,
      ),
      textTheme: TextTheme(
        // Headings — Old Standard TT (serif, editorial feel)
        displayLarge: GoogleFonts.oldStandardTt(
          color: textPrimaryDark,
          fontSize: 60,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        displayMedium: GoogleFonts.oldStandardTt(
          color: textPrimaryDark,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleLarge: GoogleFonts.oldStandardTt(
          color: textPrimaryDark,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        titleMedium: GoogleFonts.oldStandardTt(
          color: textPrimaryDark,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        // Body & Labels — Nunito
        bodyLarge: GoogleFonts.nunito(color: textPrimaryDark, fontSize: 18),
        bodyMedium: GoogleFonts.nunito(color: textSecondaryDark, fontSize: 14),
        bodySmall: GoogleFonts.nunito(color: textSecondaryDark, fontSize: 12),
        labelLarge: GoogleFonts.nunito(
          color: textSecondaryDark,
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: GoogleFonts.nunito(
          color: textSecondaryDark,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          return textPrimaryDark;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryGreenDark;
          }
          return Colors.grey.shade800;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
