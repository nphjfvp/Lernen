import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/math_markup.dart';

void main() {
  group('MathMarkup.split', () {
    test('Text ohne Formeln bleibt ein Stück', () {
      expect(MathMarkup.split('Hallo Welt'), [const MathSegment.text('Hallo Welt')]);
      expect(MathMarkup.containsMath('Hallo Welt'), isFalse);
    });

    test('erkennt Formeln im Satz und abgesetzt', () {
      expect(MathMarkup.split(r'Es gilt $a^2+b^2=c^2$ im Dreieck.'), [
        const MathSegment.text('Es gilt '),
        const MathSegment.inline('a^2+b^2=c^2'),
        const MathSegment.text(' im Dreieck.'),
      ]);
      expect(MathMarkup.split(r'Formel: $$\int_0^1 x\,dx$$'), [
        const MathSegment.text('Formel: '),
        const MathSegment.display(r'\int_0^1 x\,dx'),
      ]);
    });

    test(r'erkennt \( … \) und \[ … \]', () {
      expect(MathMarkup.split(r'Also \(x=2\) und \[y=3\]'), [
        const MathSegment.text('Also '),
        const MathSegment.inline('x=2'),
        const MathSegment.text(' und '),
        const MathSegment.display('y=3'),
      ]);
    });

    test('Geldbeträge sind keine Formeln', () {
      expect(MathMarkup.containsMath(r'Das kostet 5 $ bis 10 $.'), isFalse);
      expect(MathMarkup.containsMath(r'Zwischen $5 und $10 am Tag'), isFalse);
      expect(MathMarkup.split(r'Preis: 3\$'), [const MathSegment.text(r'Preis: 3$')]);
    });

    test('nicht geschlossene Formel bleibt normaler Text', () {
      expect(MathMarkup.split(r'Nur $x ohne Ende'), [const MathSegment.text(r'Nur $x ohne Ende')]);
    });
  });

  group('MathMarkup.escapeLatexInJson', () {
    test(r'einfache Backslashes in Formeln werden gerettet (\frac, \theta, \nabla)', () {
      const raw = r'{"front": "Was ist $\frac{a}{b}$ bei $\theta$ und $\nabla f$?"}';
      final decoded = jsonDecode(MathMarkup.escapeLatexInJson(raw)) as Map;
      expect(decoded['front'], r'Was ist $\frac{a}{b}$ bei $\theta$ und $\nabla f$?');
    });

    test('bereits korrekt verdoppelte Backslashes bleiben unverändert', () {
      const raw = r'{"front": "$\\frac{1}{2}$"}';
      expect(MathMarkup.escapeLatexInJson(raw), raw);
      expect((jsonDecode(MathMarkup.escapeLatexInJson(raw)) as Map)['front'], r'$\frac{1}{2}$');
    });

    test(r'außerhalb von Formeln bleiben \n und \" gültige Escapes', () {
      const raw = r'{"back": "Zeile 1\nZeile \"2\"", "x": "$a\,b$"}';
      final decoded = jsonDecode(MathMarkup.escapeLatexInJson(raw)) as Map;
      expect(decoded['back'], 'Zeile 1\nZeile "2"');
      expect(decoded['x'], r'$a\,b$');
    });

    test(r'\( … \)-Formeln werden ebenfalls gerettet', () {
      const raw = r'{"front": "Berechne \(\frac{x}{2}\)"}';
      final decoded = jsonDecode(MathMarkup.escapeLatexInJson(raw)) as Map;
      expect(decoded['front'], r'Berechne \(\frac{x}{2}\)');
    });
  });
}
