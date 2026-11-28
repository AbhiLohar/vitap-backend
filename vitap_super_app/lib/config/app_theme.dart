import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // Background
  static Color scaffoldBg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;
  static Color cardBg(BuildContext context) =>
      Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor;
  static Color cardBorder(BuildContext context) =>
      Theme.of(context).dividerColor;

  // Brand
  static const Color primary = Color(0xFF172554);
  static const Color secondary = Color(0xFF526DAB);
  static const Color accent = Color(0xFF526DAB);
  static const Color teal = Color(0xFF0F9D7A);
  static const Color purple = Color(0xFF7C5CFC);
  static const Color orange = Color(0xFFE68A2E);
  static const Color pink = Color(0xFFE8457C);
  static const Color cream = Color(0xFFD4E4BC);
  static const Color red = Color(0xFFD9534F);
  static const Color amber = Color(0xFFD99A32);

  /// Theme-aware primary accent color (navy in light, bright periwinkle in dark/nightfall)
  static Color adaptivePrimary(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// High-contrast foreground color to sit on top of `colorScheme.primary` surfaces
  static Color onPrimary(BuildContext context) {
    final p = Theme.of(context).colorScheme.primary;
    final lum = p.computeLuminance();
    const darkInk = Color(0xFF0B1120);
    final contrastWithDark = (lum + 0.05) / (darkInk.computeLuminance() + 0.05);
    final contrastWithWhite = 1.05 / (lum + 0.05);
    return contrastWithDark >= contrastWithWhite ? darkInk : Colors.white;
  }

  /// High-contrast green for dark & light surfaces alike
  static Color adaptiveGreen(BuildContext context) =>
      isDark(context) ? const Color(0xFF34D399) : const Color(0xFF15803D);

  // Text
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.color ??
      (isDark(context) ? const Color(0xFFE8EAF0) : const Color(0xFF171A23));
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.color ?? const Color(0xFF777F8C);
  static Color textMuted(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFF9CA3AF);

  // Status
  static const Color good = Color(0xFF16865A);
  static const Color warning = Color(0xFFD99A32);
  static const Color danger = Color(0xFFD9534F);

  // Badge
  static Color badgeBg(double percent) {
    if (percent >= 85) return good.withOpacity(0.08);
    if (percent >= 75) return warning.withOpacity(0.08);
    return danger.withOpacity(0.08);
  }

  static Color badgeText(double percent) {
    if (percent >= 85) return good;
    if (percent >= 75) return warning;
    return danger;
  }

  // Gradients
  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [Color(0xFF172554), Color(0xFF1E3A6E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get accentGradient => const LinearGradient(
        colors: [Color(0xFF526DAB), Color(0xFF7B93C9)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

class AppTheme {
  static final ThemeData darkTheme = _buildDarkTheme();
  static final ThemeData lightTheme = _buildLightTheme();
  static final ThemeData nightfallTheme = _buildNightfallTheme();
  static final ThemeData sakuraTheme = _buildSakuraTheme();

  // ── Light Theme ──────────────────────────────────────────────────────
  static ThemeData _buildLightTheme() {
    final ThemeData base = ThemeData.light();
    const Color scaffoldBg = Color(0xFFF7F8FA);
    const Color cardBg = Color(0xFFFFFFFF);
    const Color border = Color(0xFFE8EAF0);
    const Color textPri = Color(0xFF171A23);
    const Color textSec = Color(0xFF555D6B);
    const Color textMut = Color(0xFF6B7280);
    const Color pri = Color(0xFF172554);
    const Color sec = Color(0xFF526DAB);

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: pri,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(color: textPri, fontWeight: FontWeight.w700),
        bodyLarge: GoogleFonts.inter(color: textPri),
        bodyMedium: GoogleFonts.inter(color: textSec),
        bodySmall: GoogleFonts.inter(color: textMut),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: textPri),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPri,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return const Color(0xFFB0B5BF);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return pri;
          return const Color(0xFFE0E3EA);
        }),
      ),
      dividerColor: border,
      colorScheme: const ColorScheme.light(
        primary: pri,
        onPrimary: Colors.white,
        secondary: sec,
        surface: cardBg,
        onSurface: textPri,
        error: Color(0xFFD9534F),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF172554),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: pri, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD9534F)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: textMut, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pri,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: pri),
      tabBarTheme: TabBarThemeData(
        indicatorColor: pri,
        labelColor: pri,
        unselectedLabelColor: textSec,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 14),
      ),
    );
  }

  // ── Dark Theme ───────────────────────────────────────────────────────
  static ThemeData _buildDarkTheme() {
    final ThemeData base = ThemeData.dark();
    const Color scaffoldBg = Color(0xFF0F1117);
    const Color cardBg = Color(0xFF1A1D27);
    const Color border = Color(0xFF2A2D37);
    const Color textPri = Color(0xFFE8EAF0);
    const Color textSec = Color(0xFF9EA5B5);
    const Color textMut = Color(0xFF838A9B);
    const Color pri = Color(0xFF7B93C9);
    const Color sec = Color(0xFF8BA3D9);

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: pri,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(color: textPri, fontWeight: FontWeight.w700),
        bodyLarge: GoogleFonts.inter(color: textPri),
        bodyMedium: GoogleFonts.inter(color: textSec),
        bodySmall: GoogleFonts.inter(color: textMut),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPri,
        ),
        iconTheme: const IconThemeData(color: textPri),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return const Color(0xFF838A9B);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return pri;
          return const Color(0xFF2A2D37);
        }),
      ),
      dividerColor: border,
      colorScheme: const ColorScheme.dark(
        primary: pri,
        onPrimary: Color(0xFF0B1120),
        secondary: sec,
        surface: cardBg,
        onSurface: textPri,
        error: Color(0xFFD9534F),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: pri, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD9534F)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: textMut, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pri,
          foregroundColor: const Color(0xFF0B1120),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: pri),
      tabBarTheme: TabBarThemeData(
        indicatorColor: pri,
        labelColor: pri,
        unselectedLabelColor: textSec,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 14),
      ),
    );
  }

  // ── Nightfall Theme (deep OLED dark) ─────────────────────────────────
  static ThemeData _buildNightfallTheme() {
    final ThemeData base = ThemeData.dark();
    const Color scaffoldBg = Color(0xFF080A10);
    const Color cardBg = Color(0xFF12141C);
    const Color border = Color(0xFF1E2130);
    const Color textPri = Color(0xFFE2E4EB);
    const Color textSec = Color(0xFF979EB0);
    const Color textMut = Color(0xFF808798);
    const Color pri = Color(0xFF8BA3D9);
    const Color sec = Color(0xFF98ADE0);

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      primaryColor: pri,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(color: textPri, fontWeight: FontWeight.w700),
        bodyLarge: GoogleFonts.inter(color: textPri),
        bodyMedium: GoogleFonts.inter(color: textSec),
        bodySmall: GoogleFonts.inter(color: textMut),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPri,
        ),
        iconTheme: const IconThemeData(color: textPri),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return const Color(0xFF808798);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return pri;
          return const Color(0xFF1E2130);
        }),
      ),
      dividerColor: border,
      colorScheme: const ColorScheme.dark(
        primary: pri,
        onPrimary: Color(0xFF0B1120),
        secondary: sec,
        surface: cardBg,
        onSurface: textPri,
        error: Color(0xFFD9534F),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1E293B),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: pri, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD9534F)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: textMut, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pri,
          foregroundColor: const Color(0xFF0B1120),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: pri),
      tabBarTheme: TabBarThemeData(
        indicatorColor: pri,
        labelColor: pri,
        unselectedLabelColor: textSec,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 14),
      ),
    );
  }

  // ── Sakura Theme (warm light) ────────────────────────────────────────
  static ThemeData _buildSakuraTheme() {
    final ThemeData base = ThemeData.light();
    const Color scaffoldBg = Color(0xFFFFF7F9);
    const Color cardBg = Colors.white;
    const Color border = Color(0xFFFFE4E8);
    const Color textPri = Color(0xFF4C1D55);
    const Color textSec = Color(0xFF7B4461);
    const Color textMut = Color(0xFF96566E);
    const Color pri = Color(0xFFD62865);
    const Color sec = Color(0xFFF5A0BA);

    return base.copyWith(
      primaryColor: pri,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.inter(color: textPri, fontWeight: FontWeight.w700),
        bodyLarge: GoogleFonts.inter(color: textPri),
        bodyMedium: GoogleFonts.inter(color: textSec),
        bodySmall: GoogleFonts.inter(color: textMut),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: textPri),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPri,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return const Color(0xFF96566E);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return pri;
          return const Color(0xFFFFE4E8);
        }),
      ),
      dividerColor: border,
      colorScheme: const ColorScheme.light(
        primary: pri,
        onPrimary: Colors.white,
        secondary: sec,
        surface: cardBg,
        onSurface: textPri,
        error: Color(0xFFD9534F),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF4C1D55),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: pri, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD9534F)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: textMut, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: pri,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: pri),
      tabBarTheme: TabBarThemeData(
        indicatorColor: pri,
        labelColor: pri,
        unselectedLabelColor: textSec,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 14),
      ),
    );
  }
}

/// Clean card decoration for the design system
BoxDecoration glassCardDecoration(
  BuildContext context, {
  Color? borderLeftColor,
  double borderRadius = 14,
}) {
  return BoxDecoration(
    color: AppColors.cardBg(context),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: AppColors.cardBorder(context), width: 1),
    boxShadow: [
      BoxShadow(
        color: AppColors.isDark(context)
            ? Colors.black.withOpacity(0.12)
            : Colors.black.withOpacity(0.04),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
