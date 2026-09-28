import 'package:flutter/material.dart';

/// Die in den Einstellungen wählbare Farbpalette (siehe Design-Mockups) –
/// Form/Layout der Screens bleiben in allen dreien gleich, nur die Token in
/// [AppColors] tauschen. [klar] ist der Standard.
enum AppThemeSkin { ruhig, klar, lebendig }

extension AppThemeSkinLabel on AppThemeSkin {
  String get label => switch (this) {
        AppThemeSkin.ruhig => 'Ruhig',
        AppThemeSkin.klar => 'Klar',
        AppThemeSkin.lebendig => 'Lebendig',
      };

  /// Für die Vorschau-Kachel in den Einstellungen – nicht Teil von
  /// [AppColors], daher fest statt aus dem Theme gelesen.
  Color get previewSolid => switch (this) {
        AppThemeSkin.ruhig => const Color(0xFF676FBC),
        AppThemeSkin.klar => const Color(0xFF23449A),
        AppThemeSkin.lebendig => const Color(0xFFB84A33),
      };
}

/// [name] zurück in [AppThemeSkin] – ein unbekannter/fehlender Wert (älterer
/// Datensatz, Tippfehler beim Sync) landet nie fehlerhaft, sondern beim
/// Standard [AppThemeSkin.klar].
AppThemeSkin themeSkinFromName(String? name) =>
    AppThemeSkin.values.firstWhere((s) => s.name == name, orElse: () => AppThemeSkin.klar);

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

  /// "Klar" – editorialer Look (Serifen-Überschriften, Haarlinien in der
  /// Formsprache selbst, siehe Design-Mockups): Papierton, Tinte-Blau als
  /// Akzent statt eines nahe an Warn-/Fehlerfarbe liegenden Rottons. Standard
  /// in den Einstellungen ([AppThemeSkin.klar]).
  static const klarLight = AppColors(
    bg: Color(0xFFFAF8F3),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1ECE1),
    ink: Color(0xFF211E1A),
    inkMuted: Color(0xFF5E5B54),
    accent: Color(0xFF23449A),
    accentSoft: Color(0xFFE3E8F5),
    accentOnSoft: Color(0xFF1D3A82),
    accentSolid: Color(0xFF23449A),
    accentInk: Color(0xFFFFFFFF),
    border: Color(0xFFE4DCCF),
    danger: Color(0xFF9A3A2A),
    dangerSoft: Color(0xFFF7E4DF),
    warn: Color(0xFF8A5C00),
    warnSoft: Color(0xFFFBEFDA),
    good: Color(0xFF2C5E43),
    goodSoft: Color(0xFFE7F0EA),
  );

  static const klarDark = AppColors(
    bg: Color(0xFF171614),
    surface: Color(0xFF201F1B),
    surfaceAlt: Color(0xFF282621),
    ink: Color(0xFFEEECE6),
    inkMuted: Color(0xFFA5A198),
    accent: Color(0xFF9DB5FF),
    accentSoft: Color(0xFF293150),
    accentOnSoft: Color(0xFFB7C6FF),
    accentSolid: Color(0xFF3D5FC4),
    accentInk: Color(0xFFFFFFFF),
    border: Color(0xFF332F28),
    danger: Color(0xFFF09A88),
    dangerSoft: Color(0xFF3A241E),
    warn: Color(0xFFE3AE62),
    warnSoft: Color(0xFF3A331F),
    good: Color(0xFF8FCBA8),
    goodSoft: Color(0xFF1D2B23),
  );

  /// "Lebendig" – warm und farbiger, Terrakotta als Akzent (siehe
  /// Design-Mockups). [danger] bewusst ins Kräftig-Karmesinrote statt in
  /// dieselbe Terrakotta-Familie wie [accentSolid] verschoben – sonst wäre
  /// eine falsch beantwortete Frage farblich kaum vom Akzent zu
  /// unterscheiden.
  static const lebendigLight = AppColors(
    bg: Color(0xFFFFF8F2),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFBEDE2),
    ink: Color(0xFF2B2320),
    inkMuted: Color(0xFF6E625B),
    accent: Color(0xFF9C3D28),
    accentSoft: Color(0xFFFBE3DA),
    accentOnSoft: Color(0xFF9C3D28),
    accentSolid: Color(0xFFB84A33),
    accentInk: Color(0xFFFFFFFF),
    border: Color(0xFFF0E1D4),
    danger: Color(0xFFA32541),
    dangerSoft: Color(0xFFFBE3E8),
    warn: Color(0xFF8A5C00),
    warnSoft: Color(0xFFFDF0D2),
    good: Color(0xFF2F6336),
    goodSoft: Color(0xFFE3F1E3),
  );

  static const lebendigDark = AppColors(
    bg: Color(0xFF1B1512),
    surface: Color(0xFF251D19),
    surfaceAlt: Color(0xFF2F2521),
    ink: Color(0xFFFBF1EA),
    inkMuted: Color(0xFFBCA99D),
    accent: Color(0xFFE3A18F),
    accentSoft: Color(0xFF402A22),
    accentOnSoft: Color(0xFFF0BBAC),
    accentSolid: Color(0xFFC4593F),
    accentInk: Color(0xFFFFFFFF),
    border: Color(0xFF3A2E28),
    danger: Color(0xFFF0839A),
    dangerSoft: Color(0xFF3B1F26),
    warn: Color(0xFFF2B84B),
    warnSoft: Color(0xFF3A2E14),
    good: Color(0xFF6FCB84),
    goodSoft: Color(0xFF1E2E21),
  );

  /// Token-Set für [skin]/[brightness] – Grundlage für [AppTheme.forSkin].
  static AppColors of(AppThemeSkin skin, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (skin) {
      AppThemeSkin.ruhig => isDark ? dark : light,
      AppThemeSkin.klar => isDark ? klarDark : klarLight,
      AppThemeSkin.lebendig => isDark ? lebendigDark : lebendigLight,
    };
  }

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
