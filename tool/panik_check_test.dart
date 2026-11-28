// Prüft eine Panik-Inhaltsdatei mit genau dem Leser der App, bevor sie
// verschickt wird – die Datei selbst gehört NICHT ins Repo:
//
//   PANIK_FILE=/pfad/panik_mathe.json flutter test tool/panik_check_test.dart
//
// Liest die Datei wie der Import (PanikContent.parse + PanikImport.build) und
// setzt jede Formel aller entstehenden Karten (Vorderseite, Rückseite,
// Optionen, Rechenweg-Schritte) mit dem Formel-Parser der App.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/panik_content.dart';
import 'package:lernen/services/math_markup.dart';
import 'package:lernen/services/panik_import.dart';

void main() {
  final file = Platform.environment['PANIK_FILE'];

  test('Panik-Inhaltsdatei', () {
    expect(file, isNotNull, reason: 'PANIK_FILE setzen');
    final content = PanikContent.parse(jsonDecode(File(file!).readAsStringSync()));
    final imported = PanikImport.build(content);
    final bad = <String>[];
    var steps = 0;
    void check(String where, String text, {bool pureLatex = false}) {
      final formulas = pureLatex ? [text] : [for (final s in MathMarkup.split(text)) if (s.isMath) s.content];
      for (final f in formulas) {
        try {
          TexParser(f, const TexParserSettings()).parse();
        } catch (e) {
          bad.add('$where: $f\n   → $e');
        }
      }
    }

    for (final card in imported.flashcards) {
      final id = PanikCardInfo.of(card)?.itemId ?? card.id;
      check('$id Vorderseite', card.front);
      check('$id Rückseite', card.back);
      for (final o in card.options ?? const []) {
        check('$id Option', o.text);
      }
      final info = PanikCardInfo.of(card)!;
      for (final s in info.steps) {
        check('$id Schritt „${s.label}“', s.result, pureLatex: true);
      }
      if (info.answer.isNotEmpty) check('$id Ergebnis', info.answer, pureLatex: true);
      steps += info.steps.length;
    }
    // ignore: avoid_print
    print('${content.types.length} Typen, ${imported.flashcards.length} Karten, $steps Schritte, ${bad.length} Formelfehler'
        '${bad.isEmpty ? '' : '\n${bad.take(40).join('\n')}'}');
    expect(bad, isEmpty);
  });
}
