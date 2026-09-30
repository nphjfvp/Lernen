import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/calc_engine.dart';
import 'package:lernen/services/calc_plan.dart';

Map<String, dynamic> _ohm() => {
      'title': 'Ohmsches Gesetz',
      'given': [
        {'symbol': 'U', 'name': 'Spannung', 'raw': '12,3 V', 'value': 12.3, 'unit': 'V'},
        {'symbol': 'I', 'name': 'Strom', 'raw': '450 mA', 'value': '0,45', 'unit': 'A', 'uncertain': true},
      ],
      'steps': [
        {
          'symbol': 'R',
          'name': 'Widerstand',
          'latex': r'$R = \frac{U}{I}$',
          'expression': 'U / I',
          'unit': 'Ω',
          'explanation': 'Ohmsches Gesetz',
        },
        {'symbol': 'P', 'name': 'Leistung', 'latex': 'P = U \\cdot I', 'expression': 'U * I', 'unit': 'W'},
      ],
      'result': ['R', 'P'],
      'assumptions': ['Ideale Messgeräte'],
      'missing': [],
    };

void main() {
  group('CalcPlan.fromJson', () {
    test('liest gegeben, Schritte, Ergebnis und Annahmen', () {
      final plan = CalcPlan.fromJson(_ohm());
      expect(plan.title, 'Ohmsches Gesetz');
      expect(plan.given.map((g) => g.symbol), ['U', 'I']);
      expect(plan.given[1].values, [0.45]); // "0,45" als Text gelesen
      expect(plan.given[1].uncertain, isTrue);
      expect(plan.given[0].raw, '12,3 V');
      expect(plan.steps.map((s) => s.symbol), ['R', 'P']);
      expect(plan.steps.first.latex, r'R = \frac{U}{I}'); // Dollarzeichen entfernt
      expect(plan.finalSymbols, ['R', 'P']);
      expect(plan.assumptions, ['Ideale Messgeräte']);
      expect(plan.problems, isEmpty);
    });

    test('Messreihen als Liste, Konstanten', () {
      final plan = CalcPlan.fromJson({
        'given': [
          {'symbol': 'U', 'values': ['1,0', 2, '3.5'], 'unit': 'V'},
          {'symbol': 'k_B', 'value': '1.380649e-23', 'unit': 'J/K', 'kind': 'constant'},
        ],
        'steps': [],
      });
      expect(plan.given[0].values, [1.0, 2.0, 3.5]);
      expect(plan.given[1].isConstant, isTrue);
      expect(plan.given[1].values.single, closeTo(1.380649e-23, 1e-30));
    });

    test('Unbrauchbares fällt weg und steht in den Problemen', () {
      final plan = CalcPlan.fromJson({
        'given': [
          {'symbol': 'sqrt', 'value': 1}, // reservierter Name
          {'symbol': 'a', 'value': 'viel'}, // keine Zahl
          {'symbol': 'b', 'value': 2},
          {'symbol': 'b', 'value': 3}, // doppelt
          'unsinn',
        ],
        'steps': [
          {'symbol': '', 'expression': 'b'},
          {'symbol': 'c', 'expression': ''},
          {'symbol': 'd', 'expression': 'b * 2'},
        ],
        'result': ['d', 'gibt-es-nicht'],
      });
      expect(plan.given.map((g) => g.symbol), ['b']);
      expect(plan.given.single.values, [2.0]);
      expect(plan.steps.map((s) => s.symbol), ['d']);
      expect(plan.finalSymbols, ['d']);
      expect(plan.problems, hasLength(5));
    });

    test('ohne Ergebnisangabe zählt der letzte Schritt; leerer Plan ist leer', () {
      final plan = CalcPlan.fromJson({
        'given': [{'symbol': 'a', 'value': 1}],
        'steps': [
          {'symbol': 'b', 'expression': 'a + 1'},
          {'symbol': 'c', 'expression': 'b + 1'},
        ],
      });
      expect(plan.finalSymbols, ['c']);
      expect(CalcPlan.fromJson(const {}).isEmpty, isTrue);
      expect(CalcPlan.fromJson(const {}).finalSymbols, isEmpty);
    });
  });

  group('CalcPlan.evaluate', () {
    test('rechnet mit den gegebenen Größen, setzt Werte ein', () {
      final results = CalcPlan.fromJson(_ohm()).evaluate();
      expect(results.every((r) => r.ok), isTrue);
      expect(results[0].values!.single, closeTo(27.3333333, 1e-6));
      expect(results[0].substitution, '12,3 V / 0,45 A');
      expect(results[0].valueText, '27,33 Ω');
      expect(results[1].values!.single, closeTo(5.535, 1e-9));
      expect(results[1].substitution, '12,3 V · 0,45 A');
    });

    test('ein korrigierter Eingabewert rechnet neu', () {
      final plan = CalcPlan.fromJson(_ohm()).withGiven('I', [0.5]);
      expect(plan.given[1].uncertain, isFalse); // selbst eingegeben = geprüft
      expect(plan.evaluate()[0].values!.single, closeTo(24.6, 1e-9));
    });

    test('Schritte bauen aufeinander auf; Fehler pflanzt sich verständlich fort', () {
      final plan = CalcPlan.fromJson({
        'given': [{'symbol': 'a', 'value': 0}],
        'steps': [
          {'symbol': 'b', 'expression': '1 / a'},
          {'symbol': 'c', 'expression': 'b * 2'},
          {'symbol': 'd', 'expression': 'a + 5'},
        ],
      });
      final r = plan.evaluate();
      expect(r[0].ok, isFalse);
      expect(r[0].error, contains('nicht definiert'));
      expect(r[1].ok, isFalse);
      expect(r[1].error, contains('„b“'));
      expect(r[2].values, [5.0]); // unabhängiger Schritt klappt trotzdem
    });

    test('Messreihen: Tabelle statt Einsetzen, Kennzahlen über die Reihe', () {
      final plan = CalcPlan.fromJson({
        'given': [
          {'symbol': 'U', 'values': [2, 4, 6], 'unit': 'V'},
          {'symbol': 'I', 'values': [0.1, 0.2, 0.3], 'unit': 'A'},
        ],
        'steps': [
          {'symbol': 'R', 'expression': 'U / I', 'unit': 'Ω'},
          {'symbol': 'R_m', 'expression': 'mean(R)', 'unit': 'Ω'},
          {'symbol': 'R_s', 'expression': 'slope(I; U)', 'unit': 'Ω'},
        ],
      });
      final r = plan.evaluate();
      expect(r[0].values, hasLength(3));
      expect(r[0].values, everyElement(closeTo(20, 1e-9)));
      expect(r[0].substitution, isNull);
      expect(r[0].inputs.keys, {'U', 'I'});
      expect(r[1].values!.single, closeTo(20, 1e-9));
      expect(r[2].values!.single, closeTo(20, 1e-9));
      expect(r[0].valueText, startsWith('[20; 20; 20]'));
    });

    test('ungültiger Name eines Schritts wird gemeldet, nicht gerechnet', () {
      final plan = CalcPlan(steps: const [CalcStep(symbol: 'sqrt', expression: '1 + 1')]);
      expect(plan.evaluate().single.error, contains('kein gültiger Name'));
    });
  });

  group('Rechenweg als Text', () {
    test('Gegeben, Rechenweg mit Einsetzen, Ergebnis, Annahmen', () {
      final plan = CalcPlan.fromJson(_ohm());
      final text = plan.asText(plan.evaluate());
      expect(text, contains('Rechnung: Ohmsches Gesetz'));
      expect(text, contains('U = 12,3 V (Spannung)'));
      expect(text, contains('1) Widerstand: R = U / I = 12,3 V / 0,45 A = 27,33 Ω'));
      expect(text, contains('2) Leistung: P = U · I = 12,3 V · 0,45 A = 5,535 W'));
      expect(text, contains('Ergebnis:\n  R = 27,33 Ω\n  P = 5,535 W'));
      expect(text, contains('Annahmen:\n  - Ideale Messgeräte'));
    });

    test('Fehlgeschlagene Schritte stehen mit Grund da, fehlende Angaben werden genannt', () {
      final plan = CalcPlan.fromJson({
        'given': [{'symbol': 'a', 'value': 0}],
        'steps': [
          {'symbol': 'b', 'expression': '1 / a'},
        ],
        'missing': ['Die Länge des Drahtes fehlt'],
      });
      final text = plan.asText(plan.evaluate());
      expect(text, contains('nicht berechenbar'));
      expect(text, isNot(contains('Ergebnis:')));
      expect(text, contains('Es fehlt noch:\n  - Die Länge des Drahtes fehlt'));
    });

    test('Werte als Reihe', () {
      final g = CalcGiven(symbol: 'x', values: const [1, 2.5], unit: 'm');
      expect(g.valuesText, '1; 2,5');
      expect(CalcEngine.parseNumber('2,5'), 2.5);
    });
  });
}
