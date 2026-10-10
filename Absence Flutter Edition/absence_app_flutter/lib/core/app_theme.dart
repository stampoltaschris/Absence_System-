import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ενιαία παλέτα & Theme για σχολική χρήση σε tablet.
class AppColors {
  static const Color primary = Color(0xFF0B3D5C);
  static const Color primaryMid = Color(0xFF156589);
  static const Color accent = Color(0xFFE07A2F);
  static const Color accentSoft = Color(0xFFFFF0E4);
  static const Color surface = Color(0xFFF3F7FA);
  static const Color surfaceElevated = Colors.white;
  static const Color ink = Color(0xFF1A2B36);
  static const Color muted = Color(0xFF5A6B76);
  static const Color success = Color(0xFF1B7A4E);
  static const Color danger = Color(0xFFB42318);
  static const Color warning = Color(0xFFB54708);
  static const Color locked = Color(0xFFF5D9A8);
  static const Color lockedInk = Color(0xFF7A4A00);
  static const Color submitted = Color(0xFFE6EEF5);
  static const Color submittedInk = Color(0xFF2C4A63);
  static const Color available = Color(0xFFFFFFFF);
  static const Color availableBorder = Color(0xFFC5D4DE);
}

class AppTheme {
  static ThemeData light() {
    final baseText = GoogleFonts.manropeTextTheme();
    final display = GoogleFonts.soraTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surfaceElevated,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.ink,
        onError: Colors.white,
      ),
      textTheme: baseText.copyWith(
        displaySmall: display.displaySmall?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: display.headlineSmall?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: display.titleLarge?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(color: AppColors.ink),
        bodyMedium: baseText.bodyMedium?.copyWith(color: AppColors.muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sora(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.availableBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.availableBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.availableBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primaryMid, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.muted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Φόντο με ήπια ατμόσφαιρα (όχι flat).
  static BoxDecoration pageBackground({bool warmAccent = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: warmAccent
            ? const [
                Color(0xFFEAF3F8),
                Color(0xFFF7F4EF),
                Color(0xFFE8EEF2),
              ]
            : const [
                Color(0xFFE7F0F6),
                Color(0xFFF3F7FA),
                Color(0xFFDDE8F0),
              ],
        stops: const [0.0, 0.55, 1.0],
      ),
    );
  }
}
