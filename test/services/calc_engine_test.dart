import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/calc_engine.dart';

double _one(String expr, [Map<String, List<double>> vars = const {}]) => CalcEngine.evaluate(expr, vars).single;

void main() {
  group('Rechnen', () {
    test('Punkt vor Strich, Klammern, Potenz rechtsassoziativ, unäres Minus', () {
      expect(_one('2 + 3 * 4'), 14);
      expect(_one('(2 + 3) * 4'), 20);
      expect(_one('2 ^ 3 ^ 2'), 512);
      expect(_one('-2 ^ 2'), -4);
      expect(_one('2 ^ -1'), 0.5);
      expect(_one('10 - 4 - 3'), 3);
      expect(_one('100 / 10 / 5'), 2);
      expect(_one('2 ** 3'), 8);
    });

    test('Zeichen aus Texten: Malpunkt, Kreuz, geteilt, langes Minus', () {
      expect(_one('3 · 4'), 12);
      expect(_one('3 × 4'), 12);
      expect(_one('12 ÷ 4'), 3);
      expect(_one('5 − 2'), 3);
    });

    test('Größen, Konstanten, Zehnerpotenz-Schreibweise', () {
      expect(_one('U / I', {'U': [12.3], 'I': [0.45]}), closeTo(27.3333333, 1e-6));
      expect(_one('2 * pi'), closeTo(6.283185307, 1e-9));
      expect(_one('1.5e-3 * 2'), closeTo(0.003, 1e-12));
      // Eine Größe darf so heißen wie eine Konstante und gewinnt dann.
      expect(_one('e * 2', {'e': [3.0]}), 6);
      // Kein unsichtbares Malzeichen: "2e" ist ein Fehler, nicht 2 mal Euler.
      expect(() => _one('2e'), throwsA(isA<CalcException>()));
    });

    test('Funktionen', () {
      expect(_one('sqrt(16)'), 4);
      expect(_one('lg(1000)'), closeTo(3, 1e-12));
      expect(_one('log(100)'), closeTo(2, 1e-12));
      expect(_one('log(8; 2)'), closeTo(3, 1e-12));
      expect(_one('ln(e)'), closeTo(1, 1e-12));
      expect(_one('sin(rad(90))'), closeTo(1, 1e-12));
      expect(_one('deg(pi)'), closeTo(180, 1e-9));
      expect(_one('hypot(3, 4)'), 5);
      expect(_one('pow(2, 10)'), 1024);
      expect(_one('round(3.14159; 2)'), 3.14);
      expect(_one('cbrt(-8)'), closeTo(-2, 1e-12));
      expect(_one('mod(7, 3)'), 1);
      expect(_one('max(2, 9)'), 9);
    });

    test('Messreihen: elementweise, Einzelwerte passen sich an', () {
      final r = CalcEngine.evaluate('U / R', {'U': [10.0, 20.0, 30.0], 'R': [2.0]});
      expect(r, [5.0, 10.0, 15.0]);
      expect(CalcEngine.evaluate('x + y', {'x': [1.0, 2.0], 'y': [10.0, 20.0]}), [11.0, 22.0]);
      expect(
        () => CalcEngine.evaluate('x + y', {'x': [1.0, 2.0], 'y': [1.0, 2.0, 3.0]}),
        throwsA(isA<CalcException>().having((e) => e.message, 'Meldung', contains('unterschiedlich viele'))),
      );
    });

    test('Kennzahlen über eine Reihe', () {
      final v = {'x': [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]};
      expect(_one('mean(x)', v), 5);
      expect(_one('sum(x)', v), 40);
      expect(_one('count(x)', v), 8);
      expect(_one('median(x)', v), 4.5);
      expect(_one('min(x)', v), 2);
      expect(_one('max(x)', v), 9);
      expect(_one('stdevp(x)', v), 2);
      expect(_one('stdev(x)', v), closeTo(2.13809, 1e-5));
      expect(_one('var(x)', v), closeTo(4.571428, 1e-5));
      expect(_one('rms(x)', {'x': [3.0, 4.0]}), closeTo(3.535534, 1e-6));
      // Abweichung vom Mittelwert je Wert – Reihe minus Einzelwert.
      expect(CalcEngine.evaluate('x - mean(x)', {'x': [1.0, 2.0, 3.0]}), [-1.0, 0.0, 1.0]);
    });

    test('Ausgleichsgerade: Steigung, Achsenabschnitt, Bestimmtheitsmaß', () {
      final v = {
        'x': [1.0, 2.0, 3.0, 4.0],
        'y': [3.1, 4.9, 7.2, 8.8],
      };
      expect(_one('slope(x; y)', v), closeTo(1.94, 1e-9));
      expect(_one('intercept(x; y)', v), closeTo(1.15, 1e-9));
      expect(_one('r2(x; y)', v), closeTo(0.9964, 1e-3));
      expect(_one('corr(x; y)', v), greaterThan(0.99));
      expect(() => CalcEngine.evaluate('slope(x; y)', {'x': [1.0, 1.0], 'y': [1.0, 2.0]}), throwsA(isA<CalcException>()));
      expect(() => CalcEngine.evaluate('slope(x; y)', {'x': [1.0], 'y': [1.0]}), throwsA(isA<CalcException>()));
    });

    test('verständliche Fehler statt Absturz', () {
      String message(String expr, [Map<String, List<double>> vars = const {}]) {
        try {
          CalcEngine.evaluate(expr, vars);
        } on CalcException catch (e) {
          return e.message;
        }
        return 'kein Fehler';
      }

      expect(message('1 / 0'), contains('nicht definiert'));
      expect(message('sqrt(-1)'), contains('nicht definiert'));
      expect(message('ln(0)'), contains('nicht definiert'));
      expect(message('X + 1'), contains('Unbekannte Größe „X“'));
      expect(message('foo(2)'), contains('Unbekannte Funktion „foo“'));
      expect(message('(1 + 2'), contains('Klammer'));
      expect(message('1 +'), contains('endet unerwartet'));
      expect(message('2 x'), contains('Unerwartetes'));
      expect(message('1 # 2'), contains('Unerwartetes Zeichen'));
      expect(message('sqrt(1; 2)'), contains('braucht 1 Wert'));
      expect(message(''), contains('leer'));
      // Kein Ausführen von Code: Zuweisungen und Punktzugriffe sind keine Syntax.
      expect(message('a = 3'), isNot('kein Fehler'));
      expect(message('x.y', {'x': [1.0]}), isNot('kein Fehler'));
    });

    test('Größen und Funktionsnamen', () {
      expect(CalcEngine.variablesOf('U / (R_1 + R_2) * sqrt(pi)'), {'U', 'R_1', 'R_2'});
      expect(CalcEngine.variablesOf('e * 2', known: {'e'}), {'e'});
      expect(CalcEngine.isValidSymbol('R_1'), isTrue);
      expect(CalcEngine.isValidSymbol('Δt'), isTrue);
      expect(CalcEngine.isValidSymbol('1R'), isFalse);
      // Funktionsnamen sind als Größe erlaubt (n = Drehzahl, rad, exp …) –
      // der Aufruf erkennt sich an der Klammer. Nur Konstanten nicht.
      expect(CalcEngine.isValidSymbol('n'), isTrue);
      expect(CalcEngine.isValidSymbol('sqrt'), isTrue);
      expect(CalcEngine.isValidSymbol('pi'), isFalse);
      expect(CalcEngine.isValidSymbol('e'), isFalse);
      expect(CalcEngine.isValidSymbol('a b'), isFalse);
      expect(CalcEngine.isValidSymbol(''), isFalse);
    });

    test('Größe mit Funktionsnamen: als Wert gelesen, mit Klammer als Funktion', () {
      expect(_one('n * 60', {'n': [25.0]}), 1500);
      expect(_one('n(x)', {'x': [1.0, 2.0, 3.0]}), 3); // Anzahl
      expect(_one('exp + 1', {'exp': [2.0]}), 3);
      expect(_one('exp(0) + exp', {'exp': [2.0]}), 3);
      expect(CalcEngine.variablesOf('n * 60 + count(x)'), {'n', 'x'});
    });

    test('Ausnahmen werden zu Meldungen: min/max ohne Wert, round mit unendlich vielen Stellen', () {
      expect(() => _one('max()'), throwsA(isA<CalcException>()));
      expect(() => _one('min()'), throwsA(isA<CalcException>()));
      expect(() => _one('round(2.5; 1/0)'), throwsA(isA<CalcException>()));
      expect(_one('round(3.14159; 400)'), closeTo(3.14159, 1e-9)); // Stellen begrenzt
    });

    test('Einsetzen: negative Werte und Werte mit Einheit an Potenzen in Klammern', () {
      expect(CalcEngine.substitute('x^2', {'x': '-3'}), '(-3)^2');
      expect(CalcEngine.substitute('a - b', {'a': '5', 'b': '-2'}), '5 - (-2)');
      expect(CalcEngine.substitute('l^2', {'l': '3 m'}), '(3 m)^2');
      expect(CalcEngine.substitute('2^k', {'k': '3'}), '2^3');
      expect(CalcEngine.substitute('U / I', {'U': '12,3 V', 'I': '0,45 A'}), '12,3 V / 0,45 A');
    });

    test('Einsetzen scheitert nie an einem unlesbaren Ausdruck', () {
      expect(CalcEngine.substitute('U / I %', {'U': '1'}), 'U / I %');
      expect(CalcEngine.substitute('x²', const {}), 'x²');
    });

    test('Einsetzen: Zahlen statt Größen, Malpunkt, deutsches Komma', () {
      expect(CalcEngine.substitute('U / I', {'U': '12,3 V', 'I': '0,45 A'}), '12,3 V / 0,45 A');
      expect(CalcEngine.substitute('2 * pi * f * L', {'f': '50 Hz', 'L': '0,1 H'}), '2 · pi · 50 Hz · 0,1 H');
      expect(CalcEngine.substitute('sqrt(a^2 + b^2)', {'a': '3', 'b': '4'}), 'sqrt(3^2 + 4^2)');
      expect(CalcEngine.substitute('-x + 1.5', {'x': '2'}), '-2 + 1,5');
      expect(CalcEngine.substitute('hypot(a; b)', {'a': '3', 'b': '4'}), 'hypot(3; 4)');
    });
  });

  group('Zahlen einlesen', () {
    test('Komma, Punkt, Tausender, negative Werte', () {
      expect(CalcEngine.parseNumber('1,5'), 1.5);
      expect(CalcEngine.parseNumber('1.5'), 1.5);
      expect(CalcEngine.parseNumber(' -3 '), -3);
      expect(CalcEngine.parseNumber('−3,25'), -3.25);
      expect(CalcEngine.parseNumber('1.234,5'), 1234.5);
      expect(CalcEngine.parseNumber('1,234.5'), 1234.5);
      expect(CalcEngine.parseNumber('1 234,5'), 1234.5);
      expect(CalcEngine.parseNumber(42), 42);
      expect(CalcEngine.parseNumber(0.5), 0.5);
    });

    test('Zehnerpotenzen in allen üblichen Schreibweisen', () {
      expect(CalcEngine.parseNumber('1e-3'), closeTo(0.001, 1e-15));
      expect(CalcEngine.parseNumber('1,5·10^-3'), closeTo(0.0015, 1e-15));
      expect(CalcEngine.parseNumber('2,2 × 10⁻⁶'), closeTo(2.2e-6, 1e-18));
      expect(CalcEngine.parseNumber('3*10^8'), 3e8);
      expect(CalcEngine.parseNumber('4.7E3'), 4700);
    });

    test('Eingaben in der App: Punkt vor drei Ziffern ist der Tausendertrenner', () {
      expect(CalcEngine.parseNumber('4.700', germanGrouping: true), 4700);
      expect(CalcEngine.parseNumber('1.234.567', germanGrouping: true), 1234567);
      expect(CalcEngine.parseNumber('1.234,5', germanGrouping: true), 1234.5);
      expect(CalcEngine.parseNumber('0.450', germanGrouping: true), 0.45); // führende Null: Dezimalpunkt
      expect(CalcEngine.parseNumber('4.7', germanGrouping: true), 4.7);
      expect(CalcEngine.parseNumber('4,7', germanGrouping: true), 4.7);
      // Werte der KI: Punkt = Dezimalpunkt.
      expect(CalcEngine.parseNumber('4.700'), 4.7);
    });

    test('keine Zahl → null (Einheiten gehören nicht dazu)', () {
      expect(CalcEngine.parseNumber('abc'), isNull);
      expect(CalcEngine.parseNumber(''), isNull);
      expect(CalcEngine.parseNumber(null), isNull);
      expect(CalcEngine.parseNumber('4,7 kΩ'), isNull);
      expect(CalcEngine.parseNumber('1,2,3'), isNull);
      expect(CalcEngine.parseNumber('1.2.3'), isNull);
      expect(CalcEngine.parseNumber(double.nan), isNull);
    });
  });

  group('Zahlen anzeigen', () {
    test('vier gültige Ziffern, deutsches Komma, ohne überflüssige Nullen', () {
      expect(CalcEngine.format(27.33333), '27,33');
      expect(CalcEngine.format(0.5), '0,5');
      expect(CalcEngine.format(1234.5678), '1235');
      expect(CalcEngine.format(12), '12');
      expect(CalcEngine.format(-3.14159), '-3,142');
      expect(CalcEngine.format(0), '0');
      expect(CalcEngine.format(9.9996), '10');
      expect(CalcEngine.format(0.004567), '0,004567');
    });

    test('sehr große und kleine Werte als Zehnerpotenz', () {
      expect(CalcEngine.format(0.0001234), '1,234 · 10⁻⁴');
      expect(CalcEngine.format(2.2e-6), '2,2 · 10⁻⁶');
      expect(CalcEngine.format(4700000), '4,7 · 10⁶');
      expect(CalcEngine.format(1e12), '1 · 10¹²');
    });

    test('Genauigkeit einstellbar, Sonderwerte', () {
      expect(CalcEngine.format(3.14159265, sig: 6), '3,14159');
      expect(CalcEngine.format(double.nan), '–');
      expect(CalcEngine.format(double.infinity), '∞');
    });
  });
}
