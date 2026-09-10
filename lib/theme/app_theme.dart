import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Baut Light-/Dark-ThemeData aus den [AppColors]-Tokens. Ein Basis-
/// [ColorScheme] wird mitgeführt, damit unrestylte Standard-Widgets (Dialoge,
/// SnackBars, …) nicht aus dem Rahmen fallen – die eigentliche Optik der
/// App-Screens kommt aber über `context.colors` (siehe app_colors.dart).
class AppTheme {
  AppTheme._();

  static ThemeData _build(AppColors c, Brightness brightness) {
    final textTheme = GoogleFonts.publicSansTextTheme(
      brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(bodyColor: c.ink, displayColor: c.ink);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.accentSolid,
      onPrimary: c.accentInk,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accentOnSoft,
      secondary: c.accent,
      onSecondary: c.accentInk,
      error: c.danger,
      onError: c.accentInk,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.ink,
      surfaceContainerHighest: c.surfaceAlt,
      onSurfaceVariant: c.inkMuted,
      outline: c.border,
      outlineVariant: c.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      colorScheme: colorScheme,
      textTheme: textTheme,
      fontFamily: GoogleFonts.publicSans().fontFamily,
      dividerColor: c.border,
      extensions: [c],
    );
  }

  static final light = _build(AppColors.light, Brightness.light);
  static final dark = _build(AppColors.dark, Brightness.dark);
}
