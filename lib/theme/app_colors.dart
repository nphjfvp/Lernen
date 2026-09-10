import 'package:flutter/material.dart';

/// Design-Tokens der "Ruhig & Fokussiert"-Richtung (siehe Design-Mockups):
/// warmes Off-White/Tinte im Hellmodus, sanftes Dunkelblau-Grau im
/// Dunkelmodus, ein entsättigtes Periwinkle als einziger Akzent. Bewusst als
/// eigene [ThemeExtension] statt nur über [ColorScheme] modelliert, weil die
/// App mehr Rollen braucht als Material 3 vorsieht (z.B. eine weiche
/// "Soft"-Tönung pro Akzent-/Status-Farbe für Chips und Badges).
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.accentSoft,
    required this.accentOnSoft,
    required this.accentSolid,
    required this.accentInk,
    required this.border,
    required this.danger,
    required this.dangerSoft,
    required this.warn,
    required this.warnSoft,
    required this.good,
    required this.goodSoft,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkMuted;

  /// Identität/Icon-Farbe auf [accentSoft] (Icons, Punkte) – 3:1 Kontrast.
  final Color accent;
  final Color accentSoft;

  /// Text/Zahlen auf [accentSoft] (Badges, Stat-Zahlen) – 4.5:1 Kontrast.
  final Color accentOnSoft;

  /// Füllfarbe für Buttons/FAB, kombiniert mit [accentInk] als Beschriftung.
  final Color accentSolid;
  final Color accentInk;

  final Color border;

  final Color danger;
  final Color dangerSoft;
  final Color warn;
  final Color warnSoft;
  final Color good;
  final Color goodSoft;

  static const light = AppColors(
    bg: Color(0xFFFAFAF7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF3F1EB),
    ink: Color(0xFF2A2E3D),
    inkMuted: Color(0xFF6B7280),
    accent: Color(0xFF6B74C4),
    accentSoft: Color(0xFFE7E8F5),
    accentOnSoft: Color(0xFF5A61A5),
    accentSolid: Color(0xFF676FBC),
    accentInk: Color(0xFFFFFFFF),
    border: Color(0xFFE8E6DE),
    danger: Color(0xFF915949),
    dangerSoft: Color(0xFFF5E6E1),
    warn: Color(0xFF876433),
    warnSoft: Color(0xFFF5EAD6),
    good: Color(0xFF54704F),
    goodSoft: Color(0xFFE6EEE4),
  );

  static const dark = AppColors(
    bg: Color(0xFF1E212B),
    surface: Color(0xFF262A36),
    surfaceAlt: Color(0xFF2E3240),
    ink: Color(0xFFF2F1EC),
    inkMuted: Color(0xFF9CA3B5),
    accent: Color(0xFF8489D1),
    accentSoft: Color(0xFF333A5C),
    accentOnSoft: Color(0xFF9FA3DB),
    accentSolid: Color(0xFF6C70AB),
    accentInk: Color(0xFFFFFFFF),
    border: Color(0xFF343846),
    danger: Color(0xFFD08B7A),
    dangerSoft: Color(0xFF3B2C29),
    warn: Color(0xFFD6B178),
    warnSoft: Color(0xFF3A331F),
    good: Color(0xFF8FAE8A),
    goodSoft: Color(0xFF28352A),
  );

  /// Modul-Identitätsfarben (Icon-Kreise in Fächer-Listen) – bewusst getrennt
  /// von den Status-Farben oben, damit ein Fach-Akzent nie mit
  /// "dringend/warnung/erledigt" verwechselt wird.
  static const List<(Color solid, Color soft)> moduleHuesLight = [
    (Color(0xFF6B74C4), Color(0xFFE7E8F5)), // periwinkle
    (Color(0xFF9B72B0), Color(0xFFF0E6F5)), // plum
    (Color(0xFF4E8C86), Color(0xFFE2EFEE)), // teal
  ];
  static const List<(Color solid, Color soft)> moduleHuesDark = [
    (Color(0xFF8489D1), Color(0xFF333A5C)),
    (Color(0xFFB694C7), Color(0xFF3B2E44)),
    (Color(0xFF7CB0AA), Color(0xFF223B39)),
  ];

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      accentOnSoft: c(accentOnSoft, other.accentOnSoft),
      accentSolid: c(accentSolid, other.accentSolid),
      accentInk: c(accentInk, other.accentInk),
      border: c(border, other.border),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      warn: c(warn, other.warn),
      warnSoft: c(warnSoft, other.warnSoft),
      good: c(good, other.good),
      goodSoft: c(goodSoft, other.goodSoft),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
