import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/math_input.dart';

double ev(String s, [Map<String, double> v = const {}, Set<String> names = const {}]) =>
    MathExpression.parse(s, names: names).evaluate(v);

void main() {
  group('MathExpression – lesen und rechnen', () {
    test('Grundrechenarten und Vorrang', () {
      expect(ev('1 + 2 * 3'), 7);
      expect(ev('(1 + 2) * 3'), 9);
      expect(ev('2^3^2'), 512);
      expect(ev('-2^2'), -4);
      expect(ev('2^-1'), 0.5);
      expect(ev('10 / 4'), 2.5);
      expect(ev('1/2x', {'x': 4}), 2, reason: 'wie auf dem Taschenrechner: (1/2)·x');
    });

    test('unsichtbares Malzeichen', () {
      expect(ev('2x', {'x': 3}), 6);
      expect(ev('2(x+1)', {'x': 3}), 8);
      expect(ev('(x+1)(x-1)', {'x': 3}), 8);
      expect(ev('x sqrt(x)', {'x': 4}), 8);
      expect(ev('2xy', {'x': 3, 'y': 5}), 30);
      expect(ev('3x^2', {'x': 2}), 12);
      expect(ev('x2', {'x': 3}), 6, reason: 'x2 ohne angegebenen Namen ist x·2');
    });

    test('Dezimalkomma, Unicode und Hochzahlen', () {
      expect(ev('1,5 + 0,25'), 1.75);
      expect(ev('3 · 4 − 2'), 10);
      expect(ev('x²', {'x': 3}), 9);
      expect(ev('x⁻¹', {'x': 4}), 0.25);
      expect(ev('2π'), closeTo(2 * math.pi, 1e-12));
      expect(ev('√(12 − 2x)', {'x': 4}), 2);
      expect(ev('√2·√2'), closeTo(2, 1e-12));
      expect(ev('6 ÷ 4'), 1.5);
      expect(ev('½x', {'x': 6}), 3);
    });

    test('Funktionen, Betrag und Konstanten', () {
      expect(ev('sin(pi/2)'), closeTo(1, 1e-12));
      expect(ev('sin(x)^2 + cos(x)^2', {'x': 0.7}), closeTo(1, 1e-12));
      expect(ev('sinx', {'x': 0}), 0);
      expect(ev('ln(e^2)'), closeTo(2, 1e-12));
      expect(ev('exp(1)'), closeTo(math.e, 1e-12));
      expect(ev('log(1000)'), closeTo(3, 1e-12), reason: 'log = Zehnerlogarithmus');
      expect(ev('|x - 5|', {'x': 2}), 3);
      expect(ev('2|x|y', {'x': -3, 'y': 2}), 12);
      expect(ev('Sin(0)'), 0);
      expect(ev('wurzel(9)'), 3);
      expect(ev('sin^2(x)', {'x': 0.4}), closeTo(math.pow(math.sin(0.4), 2), 1e-12));
    });

    test('Wurzel aus Negativem ist nicht definiert, ungerade Wurzeln gehen', () {
      expect(ev('sqrt(-1)').isNaN, isTrue);
      expect(ev('(-8)^(1/3)'), closeTo(-2, 1e-12));
      expect(ev('1/0').isInfinite, isTrue);
    });

    test('alles vor dem letzten Gleichheitszeichen fällt weg', () {
      expect(ev("u' = -1/u", {'u': 2}), -0.5);
      expect(ev('y(x) = x - sqrt(12 - 2x)', {'x': 4}), 2);
      expect(ev('C = 12'), 12);
    });

    test('LaTeX-Schreibweisen', () {
      expect(ev(r'\frac{-1}{u}', {'u': 4}), -0.25);
      expect(ev(r'$x-\sqrt{12-2x}$', {'x': 4}), 2);
      expect(ev(r'\sqrt[3]{27}'), closeTo(3, 1e-12));
      expect(ev(r'2 \cdot x^{2}', {'x': 3}), 18);
      expect(ev(r'\left(x+1\right)^{2}', {'x': 2}), 9);
      expect(ev(r'e^{-x}', {'x': 0}), 1);
      expect(ev(r'\frac{\pi\sqrt{3}}{8}'), closeTo(math.pi * math.sqrt(3) / 8, 1e-12));
    });

    test('wissenschaftliche Schreibweise und 2e', () {
      expect(ev('2e-3'), 0.002);
      expect(ev('1,5e3'), 1500);
      expect(ev('2e'), closeTo(2 * math.e, 1e-12));
      expect(ev('2e-x', {'x': 1}), closeTo(2 * math.e - 1, 1e-12));
    });

    test('Namen mit Index und Strich', () {
      final e = MathExpression.parse("C_1 x + y'");
      expect(e.freeSymbols, {'C_1', 'x', "y'"});
      expect(e.evaluate({'C_1': 2, 'x': 3, "y'": 1}), 7);
      expect(MathExpression.parse('C1 + x', names: {'C1'}).freeSymbols, {'C1', 'x'});
      expect(MathExpression.parse('kx', names: {'kx'}).freeSymbols, {'kx'});
      expect(MathExpression.parse('e x', names: {'e'}).freeSymbols, {'e', 'x'});
    });

    test('verständliche Fehler', () {
      Matcher fails(String part) => throwsA(isA<MathInputException>().having((e) => e.message, 'message', contains(part)));
      expect(() => MathExpression.parse(''), fails('leer'));
      expect(() => MathExpression.parse('(x + 1'), fails('Klammer'));
      expect(() => MathExpression.parse('x + 1)'), fails('zu viel'));
      expect(() => MathExpression.parse('x +'), fails('fehlt'));
      expect(() => MathExpression.parse('2 3'), fails('Rechenzeichen'));
      expect(() => MathExpression.parse('x ^'), fails('Hochzahl'));
      expect(() => MathExpression.parse('f(x, y)'), fails('Komma'));
      expect(() => MathExpression.parse('x # 2'), fails('#'));
      expect(() => MathExpression.parse('|x + 1'), fails('Betrag'));
      expect(() => MathExpression.parse('sqrt'), fails('Argument'));
      expect(MathExpression.tryParse('(('), isNull);
    });
  });

  group('MathExpression – LaTeX-Vorschau', () {
    String tex(String s) => MathExpression.parse(s).toLatex();

    test('Brüche, Wurzeln, Potenzen und Malpunkte', () {
      expect(tex('-1/u'), r'-\frac{1}{u}');
      expect(tex('x - sqrt(12 - 2x)'), r'x - \sqrt{12 - 2x}');
      expect(tex('2x^2'), '2x^{2}');
      expect(tex('(x+1)^2'), r'\left(x + 1\right)^{2}');
      expect(tex('2*3'), r'2 \cdot 3');
      expect(tex('x*(y-1)'), r'x \cdot \left(y - 1\right)');
      expect(tex('e^x'), 'e^{x}');
      expect(tex('|x|'), r'\left|x\right|');
      expect(tex('ln(x)'), r'\ln\left(x\right)');
      expect(tex('1,5x'), '1{,}5x');
      expect(tex('pi'), r'\pi');
      expect(tex('C_1'), 'C_{1}');
      expect(tex('a-(b-c)'), r'a - \left(b - c\right)');
      expect(tex('a+-b'), r'a + \left(-b\right)');
    });
  });

  group('formatNumber', () {
    test('Komma, ohne überflüssige Stellen', () {
      expect(MathExpression.formatNumber(12), '12');
      expect(MathExpression.formatNumber(0.5), '0,5');
      expect(MathExpression.formatNumber(1 / 3), '0,3333333333');
      expect(MathExpression.formatNumber(double.nan), 'nicht definiert');
    });
  });
}
