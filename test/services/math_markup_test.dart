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

    test('Formeln ohne Dollarzeichen werden erkannt, Fließtext bleibt Text', () {
      expect(MathMarkup.split(r'Es gilt U = R \cdot I. Danach weiter.'), [
        const MathSegment.text('Es gilt '),
        const MathSegment.inline(r'U = R \cdot I'),
        const MathSegment.text('. Danach weiter.'),
      ]);
      expect(MathMarkup.split(r'Der Widerstand ist \frac{U}{I} = 5 \Omega'), [
        const MathSegment.text('Der Widerstand ist '),
        const MathSegment.inline(r'\frac{U}{I} = 5 \Omega'),
      ]);
      expect(MathMarkup.split('Fläche x^{2} rechnen'), [
        const MathSegment.text('Fläche '),
        const MathSegment.inline('x^{2}'),
        const MathSegment.text(' rechnen'),
      ]);
      // Zeilen bleiben getrennt.
      final lines = MathMarkup.split('Erst \\alpha\nDann Text');
      expect(lines.where((s) => s.isMath).single.content, r'\alpha');
      expect(lines.last, const MathSegment.text('\nDann Text'));
    });

    test('kein Fehlalarm: Pfade, normale Sätze, Hochkomma-Formeln ohne Befehl', () {
      expect(MathMarkup.containsMath(r'Datei unter C:\Users\name\skript.pdf'), isFalse);
      expect(MathMarkup.containsMath('Die Spannung U ist 5 V.'), isFalse);
      expect(MathMarkup.containsMath('Siehe Seite 3 von 10'), isFalse);
    });

    test('Formel in Backticks und mit Leerzeichen innen', () {
      expect(MathMarkup.split(r'Formel: `\sqrt{a^2+b^2}`'), [
        const MathSegment.text('Formel: '),
        const MathSegment.inline(r'\sqrt{a^2+b^2}'),
      ]);
      expect(MathMarkup.split(r'Also $ U = R \cdot I $ gilt.'), [
        const MathSegment.text('Also '),
        const MathSegment.inline(r' U = R \cdot I '),
        const MathSegment.text(' gilt.'),
      ]);
      // Code ohne LaTeX bleibt Code-Text.
      expect(MathMarkup.containsMath('Befehl `ls -la` ausführen'), isFalse);
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
    test('LaTeX ohne Dollarzeichen in JSON wird nicht zu Steuerzeichen', () {
      final decoded = jsonDecode(MathMarkup.escapeLatexInJson(r'{"a": "Es gilt \frac{U}{I} und \beta, \theta, \nabla, \rho"}'));
      expect(decoded['a'], r'Es gilt \frac{U}{I} und \beta, \theta, \nabla, \rho');
    });

    test('echte Zeilenumbrüche und Tabs außerhalb von Formeln bleiben', () {
      final decoded = jsonDecode(MathMarkup.escapeLatexInJson(r'{"a": "Zeile 1\nund weiter\tab\nnur"}'));
      expect(decoded['a'], 'Zeile 1\nund weiter\tab\nnur');
    });

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

    test(r'ein einzelnes $ im Text macht echte Zeilenumbrüche nicht kaputt', () {
      const raw = r'{"front": "Was gibt echo $HOME aus?\n 1. Zeile\n2", "u": "$\u00e4 \underline{x}$"}';
      final decoded = jsonDecode(MathMarkup.escapeLatexInJson(raw)) as Map;
      expect(decoded['front'], 'Was gibt echo \$HOME aus?\n 1. Zeile\n2');
      expect(decoded['u'], r'$ä \underline{x}$');
    });

    test(r'abgesetzte Formeln ($$…$$) werden ebenso gerettet', () {
      const raw = r'{"a": "$$\frac{1}{2}$$ und $$\beta + \nabla$$ dann $\theta$"}';
      final decoded = jsonDecode(MathMarkup.escapeLatexInJson(raw)) as Map;
      expect(decoded['a'], r'$$\frac{1}{2}$$ und $$\beta + \nabla$$ dann $\theta$');
    });
  });
}
