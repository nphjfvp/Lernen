import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/theme/app_theme.dart';

void main() {
  group('themeSkinFromName', () {
    test('liest die drei bekannten Namen zurück', () {
      expect(themeSkinFromName('ruhig'), AppThemeSkin.ruhig);
      expect(themeSkinFromName('klar'), AppThemeSkin.klar);
      expect(themeSkinFromName('lebendig'), AppThemeSkin.lebendig);
    });

    test('ein unbekannter oder fehlender Wert fällt auf "klar" (Standard) zurück', () {
      expect(themeSkinFromName('kaputt'), AppThemeSkin.klar);
      expect(themeSkinFromName(null), AppThemeSkin.klar);
      expect(themeSkinFromName(''), AppThemeSkin.klar);
    });
  });

  group('AppColors.of', () {
    test('liefert je Skin/Helligkeit ein eigenes, in sich stimmiges Token-Set', () {
      final seen = <Color>{};
      for (final skin in AppThemeSkin.values) {
        for (final brightness in Brightness.values) {
          final c = AppColors.of(skin, brightness);
          // Jede Kombination hat einen eigenen Hintergrundton (keine zwei
          // Skins/Modi sehen zufällig identisch aus).
          expect(seen.add(c.bg), isTrue, reason: '$skin/$brightness dupliziert bg eines anderen Sets');
          // Traffic-Light-Semantik bleibt in jedem Skin erkennbar getrennt:
          // Akzent, Erfolg, Warnung und Fehler sind nie dieselbe Farbe.
          expect({c.accentSolid, c.good, c.warn, c.danger}.length, 4,
              reason: '$skin/$brightness: Status-/Akzentfarben überlappen');
        }
      }
    });

    test('"Lebendig" hält Akzent (Terrakotta) und Fehlerfarbe (Karmesin) klar auseinander', () {
      // Regressionsschutz für den beim Bau gefundenen Farbkonflikt: der
      // warme Terrakotta-Akzent dieses Skins liegt nahe an einem klassischen
      // "Fehler"-Rot – danger wurde deshalb bewusst ins Karmesinrote
      // verschoben statt dieselbe Terrakotta-Familie zu wiederholen.
      for (final brightness in Brightness.values) {
        final c = AppColors.of(AppThemeSkin.lebendig, brightness);
        expect(c.accentSolid, isNot(c.danger));
      }
    });
  });

  group('AppTheme.forSkin', () {
    test('baut ein ThemeData mit dem passenden AppColors als Extension', () {
      for (final skin in AppThemeSkin.values) {
        for (final brightness in Brightness.values) {
          final theme = AppTheme.forSkin(skin, brightness);
          expect(theme.brightness, brightness);
          expect(theme.extension<AppColors>(), AppColors.of(skin, brightness));
        }
      }
    });

    test('Standard-Skin "klar" entspricht AppTheme.forSkin(.klar, ...)', () {
      // AppTheme.light/.dark bleiben bewusst die "ruhig"-Werte (Alt-Tests,
      // main.dart baut das tatsächlich gezeigte Theme über forSkin).
      expect(AppTheme.forSkin(AppThemeSkin.klar, Brightness.light).extension<AppColors>(), AppColors.klarLight);
      expect(AppTheme.forSkin(AppThemeSkin.klar, Brightness.dark).extension<AppColors>(), AppColors.klarDark);
    });
  });
}
