import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  // Background
  static Color scaffoldBg(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;
  static Color cardBg(BuildContext context) => Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor;
  static Color cardBorder(BuildContext context) => Theme.of(context).dividerColor;

  // Accents — default colors, but could use colorScheme if needed
  static const Color primary = Color(0xFF7C4DFF);
  static const Color accent = Color(0xFF00E5FF);
  static const Color teal = Color(0xFF1DE9B6);
  static const Color purple = Color(0xFFB388FF);
  static const Color orange = Color(0xFFFFAB40);
  static const Color pink = Color(0xFFFF4081);
  static const Color cream = Color(0xFFD4E4BC);
  static const Color red = Color(0xFFFF5252);
  static const Color amber = Color(0xFFFFD740);

  // Text
  static Color textPrimary(BuildContext context) => Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
  static Color textSecondary(BuildContext context) => Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey;
  static Color textMuted(BuildContext context) => Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey.withOpacity(0.5);

  // Status
  static const Color good = Color(0xFF1DE9B6);
  static const Color warning = Color(0xFFFFAB40);
  static const Color danger = Color(0xFFFF5252);

  // Badge
  static Color badgeBg(double percent) {
    if (percent >= 85) return good.withOpacity(0.15);
    if (percent >= 75) return warning.withOpacity(0.15);
    return danger.withOpacity(0.15);
  }

  static Color badgeText(double percent) {
    if (percent >= 85) return good;
    if (percent >= 75) return warning;
    return danger;
  }

  // Gradient helpers
  static LinearGradient get primaryGradient => const LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get accentGradient => const LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF1DE9B6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static final ThemeData darkTheme = _buildDarkTheme();
  static final ThemeData lightTheme = _buildLightTheme();
  static final ThemeData nightfallTheme = _buildNightfallTheme();
  static final ThemeData sakuraTheme = _buildSakuraTheme();

  static ThemeData _buildDarkTheme() {
    final ThemeData base = ThemeData.dark();
    const Color scaffoldBg = Color(0xFF0B0E1A);
    const Color cardBg = Color(0xFF121829);
    const Color cardBorder = Color(0xFF1E2640);

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: AppColors.primary,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(color: const Color(0xFFF0F0F5)),
        bodyLarge: GoogleFonts.inter(color: const Color(0xFFF0F0F5)),
        bodyMedium: GoogleFonts.inter(color: const Color(0xFF8E92A4)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFF0F0F5),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFF0F0F5)),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withOpacity(0.5);
          }
          return Colors.grey.withOpacity(0.3);
        }),
      ),
      dividerColor: cardBorder,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: cardBg,
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    final ThemeData base = ThemeData.light();
    return base.copyWith(
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: const Color(0xFFF2F4F8),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        bodyLarge: GoogleFonts.inter(color: const Color(0xFF1A1A2E)),
        bodyMedium: GoogleFonts.inter(color: const Color(0xFF6B6F80)),
        bodySmall: GoogleFonts.inter(color: const Color(0xFFA0A4B8)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFF2F4F8),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1A1A2E),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE0E4EC), width: 1),
        ),
        elevation: 2,
      ),
      dividerColor: const Color(0xFFE0E4EC),
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: Colors.white,
      ),
    );
  }

  static ThemeData _buildNightfallTheme() {
    final ThemeData base = ThemeData.dark();
    const Color scaffoldBg = Color(0xFF090A0F);
    const Color cardBg = Color(0xFF11131A);
    const Color cardBorder = Color(0xFF1E212E);

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: const Color(0xFF6366F1), // Indigo
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(color: const Color(0xFFE2E8F0)),
        bodyLarge: GoogleFonts.inter(color: const Color(0xFFE2E8F0)),
        bodyMedium: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
        bodySmall: GoogleFonts.inter(color: const Color(0xFF64748B)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFE2E8F0),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE2E8F0)),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
        elevation: 0,
      ),
      dividerColor: cardBorder,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6366F1),
        secondary: Color(0xFF818CF8),
        surface: cardBg,
      ),
    );
  }

  static ThemeData _buildSakuraTheme() {
    final ThemeData base = ThemeData.light();
    const Color scaffoldBg = Color(0xFFFFF7F9);
    const Color cardBg = Colors.white;
    const Color cardBorder = Color(0xFFFFE4E8);

    return base.copyWith(
      primaryColor: const Color(0xFFF472B6), // Pink
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        bodyLarge: GoogleFonts.inter(color: const Color(0xFF4C1D95)),
        bodyMedium: GoogleFonts.inter(color: const Color(0xFF831843)),
        bodySmall: GoogleFonts.inter(color: const Color(0xFFBE185D).withOpacity(0.6)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF4C1D95)),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF4C1D95),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
        elevation: 2,
      ),
      dividerColor: cardBorder,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFF472B6),
        secondary: Color(0xFFFDA4AF),
        surface: cardBg,
      ),
    );
  }
}

/// Decoration for glass-style cards matching reference UI
BoxDecoration glassCardDecoration(
  BuildContext context, {
  Color? borderLeftColor,
  double borderRadius = 18,
}) {
  return BoxDecoration(
    gradient: AppColors.isDark(context)
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.cardBg(context),
              AppColors.cardBg(context).withOpacity(0.85),
            ],
          )
        : null,
    color: AppColors.isDark(context) ? null : AppColors.cardBg(context),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: AppColors.cardBorder(context), width: 1),
    boxShadow: [
      BoxShadow(
        color: AppColors.isDark(context)
            ? Colors.black.withOpacity(0.25)
            : Colors.black.withOpacity(0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}
