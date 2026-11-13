import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/pocket_calculator.dart';

PocketCalculator run(List<String> keys, [PocketCalculator? calc]) {
  final c = calc ?? PocketCalculator();
  for (final k in keys) {
    c.press(k);
  }
  return c;
}

void main() {
  test('Grundrechnen, Punkt vor Strich, Klammern', () {
    final c = run(['2', 'ADD', '3', 'MUL', '4', 'EQ']);
    expect(c.result!.value, 14);
    expect(c.resultLatex(), '14');
    expect(run(['LPAR', '2', 'ADD', '3', 'RPAR', 'MUL', '4', 'EQ']).result!.value, 20);
    expect(run(['1', 'DOT', '5', 'MUL', '2', 'EQ']).result!.value, 3);
    expect(run(['0', 'DOT', '1', 'ADD', '0', 'DOT', '2', 'EQ']).resultLatex(), r'\frac{3}{10}');
    expect(run(['NEG', '3', 'SQ', 'EQ']).result!.value, -9, reason: '(−)3² = −9 wie auf dem Rechner');
  });

  test('Bruch-Vorlage: Zähler, ▼, Nenner, ▶', () {
    final c = run(['FRAC', '3', 'DOWN', '4', 'RIGHT', 'ADD', '1', 'EQ']);
    expect(c.result!.value, 1.75);
    expect(c.resultLatex(), r'\frac{7}{4}');
    c.press('SD');
    expect(c.resultLatex(), '1{,}75');
    // Zahl vor dem Bruch wird zum Zähler.
    expect(run(['2', 'FRAC', '3', 'EQ']).resultLatex(), r'\frac{2}{3}');
    expect(run(['FRAC', '1', 'EQ']).error, 'Syntax ERROR', reason: 'Nenner fehlt');
  });

  test('Potenzen, Wurzeln, ln, e^x, log, Fakultät', () {
    expect(run(['2', 'POW', '1', '0', 'EQ']).result!.value, 1024);
    expect(run(['SQRT', '8', 'EQ']).resultLatex(), r'2\sqrt{2}');
    expect(run(['SHIFT', 'LN', '5', 'EQ']).result!.value, closeTo(148.4131591025766, 1e-9));
    expect(run(['LN', '1', '0', '2', 'RPAR', 'MUL', '2', 'EQ']).result!.value, closeTo(9.250, 1e-3));
    expect(run(['LOG', '1', '0', '0', '0', 'EQ']).result!.value, 3);
    expect(run(['5', 'SHIFT', 'INV', 'EQ']).result!.value, 120);
    expect(run(['4', 'INV', 'EQ']).resultLatex(), r'\frac{1}{4}');
    expect(run(['SHIFT', 'EXP10', 'DIV', '2', 'EQ']).resultLatex(), r'\frac{\pi}{2}');
    expect(run(['1', 'DOT', '5', 'EXP10', '3', 'EQ']).result!.value, 1500);
  });

  test('Winkel in Grad, SETUP stellt auf Bogenmaß', () {
    expect(run(['SIN', '3', '0', 'EQ']).resultLatex(), r'\frac{1}{2}');
    expect(run(['SHIFT', 'SIN', '1', 'EQ']).result!.value, closeTo(90, 1e-9));
    final c = run(['SHIFT', 'MENU']);
    expect(c.angle, AngleUnit.rad);
    expect(run(['COS', 'SHIFT', 'EXP10', 'EQ'], c).result!.value, -1);
  });

  test('Ans, weiterrechnen, DEL, Cursor', () {
    final c = run(['3', 'MUL', '4', 'EQ']);
    run(['ADD', '1', 'EQ'], c);
    expect(c.result!.value, 13, reason: 'Ans + 1');
    run(['ANS', 'MUL', '2', 'EQ'], c);
    expect(c.result!.value, 26);
    run(['7', 'EQ'], c);
    expect(c.result!.value, 7, reason: 'Ziffer beginnt neu');
    final d = run(['1', '2', '3', 'DEL', 'EQ']);
    expect(d.result!.value, 12);
    final e = run(['1', '3', 'LEFT', '2', 'EQ']);
    expect(e.result!.value, 123, reason: 'Cursor nach links, einfügen');
    expect(run(['2', 'DIV', '0', 'EQ']).error, 'Math ERROR');
    expect(run(['RPAR', 'EQ']).error, 'Syntax ERROR');
  });

  test('SOLVE, CALC, ∫ und d/dx', () {
    final s = run(['2', 'X', 'ADD', '4', 'ALPHA', 'CALC', '1', '0', 'SHIFT', 'CALC']);
    expect(s.result!.value, 3);
    expect(s.resultLatex(), 'x = 3');
    final q = run(['X', 'SQ', 'SUB', '2', 'SHIFT', 'CALC']);
    expect(q.result!.value.abs(), closeTo(1.41421356, 1e-8));
    final c = run(['X', 'SQ', 'ADD', '1', 'CALC', '3', 'EQ']);
    expect(c.result!.value, 10);
    expect(run(['INT', 'X', 'SQ', 'SHIFT', 'RPAR', '0', 'SHIFT', 'RPAR', '3', 'RPAR', 'EQ']).result!.value, closeTo(9, 1e-9));
    expect(run(['SHIFT', 'INT', 'X', 'POW', '3', 'RIGHT', 'SHIFT', 'RPAR', '2', 'RPAR', 'EQ']).result!.value, closeTo(12, 1e-6));
  });

  test('Anzeige: natürliche Darstellung mit Cursor und Lücken', () {
    final c = run(['FRAC']);
    expect(c.inputLatex(withCursor: false), r'\frac{\square}{\square}');
    run(['3'], c);
    expect(c.inputLatex(), contains(r'\frac{3\textcolor'));
    expect(run(['SQRT', '2', 'RIGHT', 'ADD', 'SIN', '3', '0']).inputLatex(withCursor: false), r'\sqrt{2}+\sin(30');
    expect(PocketCalculator.formatDecimal(123456789012), r'1{,}23456789\times 10^{11}');
    final r = run(['FRAC', '3', 'DOWN', '4', 'EQ']);
    expect(r.resultInput(), '3/4');
  });
}
