import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/line_chain.dart';
import 'package:lernen/services/math_input.dart';

List<ChainStatus> statuses(List<ChainLine> lines) => [for (final v in LineChain.check(lines)) v.status];

void main() {
  group('MathExpression im Rechenweg-Modus', () {
    double ev(String s, [Map<String, double> v = const {}, MathScope scope = const MathScope()]) =>
        MathExpression.parse(s, calculus: true, callables: {'u'}).evaluateIn(v, scope);

    test('bestimmte Integrale und Grenzen einsetzen', () {
      expect(ev('∫_0^1 x^2 dx'), closeTo(1 / 3, 1e-9));
      expect(ev(r'\int_{0}^{1} x^2 \, dx'), closeTo(1 / 3, 1e-9));
      expect(ev('∫_0^(pi/2) sin x dx'), closeTo(1, 1e-9));
      expect(ev('∫_1^2 dx/x'), closeTo(0.6931471805599453, 1e-9));
      expect(ev('[x³/3]_0^2'), closeTo(8 / 3, 1e-12));
    });

    test('Differentiale, d/dx und Aufrufe mit Substitution', () {
      final scope = MathScope(
        definitions: {'u': MathDefinition(MathExpression.parse('2x+1').root, parameter: 'x')},
        differentialVariable: 'x',
      );
      expect(ev('du/dx', {'x': 0.5}, scope), closeTo(2, 1e-6));
      expect(ev('du', {'x': 0.5}, scope), closeTo(2, 1e-6));
      expect(ev('u(1)', const {}, scope), 3);
      expect(ev('d/dx (x^3)', {'x': 2}, scope), closeTo(12, 1e-5));
    });

    test('unbestimmtes Integral braucht einen Anfang', () {
      expect(ev('∫ 2x dx', {'x': 2}).isNaN, isTrue);
      expect(ev('∫ 2x dx', {'x': 2}, const MathScope(anchor: {'x': 1})), closeTo(3, 1e-9));
    });

    test('ohne Rechenweg-Modus bleibt ∫ ungültig', () {
      expect(MathExpression.tryParse('∫ x dx'), isNull);
      expect(MathExpression.tryParse('2x+1')?.evaluate({'x': 1}), 3);
    });

    test('Fehlermeldungen', () {
      expect(() => MathExpression.parse('∫ x^2', calculus: true), throwsA(isA<MathInputException>()));
      expect(() => MathExpression.parse('∫_0 x dx', calculus: true), throwsA(isA<MathInputException>()));
    });
  });

  group('LineChain', () {
    test('Substitution mit Nebenrechnung', () {
      final v = LineChain.check(const [
        ChainLine('∫ 2x (x²+1)³ dx'),
        ChainLine('u = x² + 1', side: true),
        ChainLine('du = 2x dx', side: true),
        ChainLine('= ∫ u³ du'),
        ChainLine('= u⁴/4 + C'),
        ChainLine('= (x²+1)⁴/4 + C'),
      ]);
      expect([for (final x in v) x.status], [
        ChainStatus.unknown,
        ChainStatus.definition,
        ChainStatus.ok,
        ChainStatus.ok,
        ChainStatus.ok,
        ChainStatus.ok,
      ]);
    });

    test('falsche Stammfunktion wird erkannt', () {
      final v = LineChain.check(const [
        ChainLine('u = x² + 1', side: true),
        ChainLine('∫ 2x (x²+1)³ dx = ∫ u³ du'),
        ChainLine('= u⁴/3 + C'),
      ]);
      expect(v[1].status, ChainStatus.ok);
      expect(v[2].status, ChainStatus.wrong);
      expect(v[2].message, contains('Ableitungen'));
      expect(v[2].message, contains(r'\neq'));
    });

    test('falsches Differential in der Nebenrechnung', () {
      expect(
        statuses(const [ChainLine('∫ (3x+1)^2 dx'), ChainLine('u = 3x+1', side: true), ChainLine('du = 2 dx', side: true)]),
        [ChainStatus.unknown, ChainStatus.definition, ChainStatus.wrong],
      );
      expect(
        statuses(const [ChainLine('u = 3x+1', side: true), ChainLine('du/dx = 3 ⇒ dx = du/3', side: true)]),
        [ChainStatus.definition, ChainStatus.ok],
      );
    });

    test('bestimmtes Integral mit neuen Grenzen', () {
      expect(
        statuses(const [
          ChainLine('∫_0^1 2x (x²+1)³ dx'),
          ChainLine('u = x²+1; u(0) = 1, u(1) = 2', side: true),
          ChainLine('= ∫_1^2 u³ du'),
          ChainLine('= [u⁴/4]_1^2 = 15/4'),
        ]),
        [ChainStatus.unknown, ChainStatus.ok, ChainStatus.ok, ChainStatus.ok],
      );
      expect(
        statuses(const [ChainLine('∫_0^1 2x (x²+1)³ dx'), ChainLine('= ∫_0^1 u³ du'), ChainLine('u = x²+1', side: true)]),
        [ChainStatus.unknown, ChainStatus.wrong, ChainStatus.definition],
      );
    });

    test('falsche Grenze in der Nebenrechnung', () {
      final v = LineChain.check(const [ChainLine('u = x²+1', side: true), ChainLine('u(1) = 3', side: true)]);
      expect(v[1].status, ChainStatus.wrong);
    });

    test('Gleichungen: äquivalent umgeformt oder keine Aussage', () {
      expect(statuses(const [ChainLine('2x + 4 = 10'), ChainLine('2x = 6'), ChainLine('x = 3')]), [
        ChainStatus.unknown,
        ChainStatus.ok,
        ChainStatus.ok,
      ]);
      // Quadratisch – nicht proportional: keine (falsche) Fehlermeldung.
      expect(statuses(const [ChainLine('x² = 4'), ChainLine('x = 2')]), [ChainStatus.unknown, ChainStatus.unknown]);
    });

    test('Kette mit Bezeichnung und Ableitung', () {
      expect(statuses(const [ChainLine("f'(x) = d/dx (x² sin x) = 2x sin x + x² cos x")]), [ChainStatus.ok]);
      expect(statuses(const [ChainLine("f'(x) = d/dx (x² sin x) = 2x cos x")]), [ChainStatus.wrong]);
      expect(statuses(const [ChainLine('A = ∫_0^2 x² dx = 8/3')]), [ChainStatus.ok]);
      expect(statuses(const [ChainLine('A = ∫_0^2 x² dx = 4')]), [ChainStatus.wrong]);
    });

    test('Fortsetzung mit = über Zeilen', () {
      expect(statuses(const [ChainLine('(x+1)²'), ChainLine('= x² + 2x + 1'), ChainLine('= x² + x + 1')]), [
        ChainStatus.unknown,
        ChainStatus.ok,
        ChainStatus.wrong,
      ]);
    });

    test('Unlesbares und Text geben keine Aussage', () {
      expect(statuses(const [ChainLine('Ansatz: Produktregel'), ChainLine('x > 2')]), [
        ChainStatus.unknown,
        ChainStatus.unknown,
      ]);
    });
  });
}
