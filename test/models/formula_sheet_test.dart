import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/formula_sheet.dart';
import 'package:lernen/models/summary.dart';

FormulaEntry _e(String name, String formula, FormulaLevel level, {bool supplemented = false, String note = ''}) =>
    FormulaEntry(name: name, formula: formula, level: level, supplemented: supplemented, note: note);

/// Die Integralrechnung aus der Beschreibung: Kernstoff, Hilfsregeln (Ableiten)
/// und Rechenregeln (Bruch-/Potenzrechnung).
FormulaSheet _integral({FormulaDetail detail = FormulaDetail.mittel}) => FormulaSheet(
      detail: detail,
      sections: [
        FormulaSection(title: 'Integrationsregeln', entries: [
          _e('Partielle Integration', r"\int u v' dx = uv - \int u' v dx", FormulaLevel.kern),
          _e('Substitution', r"\int f(g(x))g'(x)dx = \int f(t)dt", FormulaLevel.kern),
        ]),
        FormulaSection(title: 'Ableitungsregeln', entries: [
          _e('Produktregel', r"(uv)' = u'v + uv'", FormulaLevel.hilfsregel, supplemented: true),
          _e('Kettenregel', r"(f(g(x)))' = f'(g(x))g'(x)", FormulaLevel.hilfsregel),
        ]),
        FormulaSection(title: 'Rechenregeln', entries: [
          _e('Potenzgesetz', r'a^m \cdot a^n = a^{m+n}', FormulaLevel.rechenregel, supplemented: true),
          _e('Bruchaddition', r'\frac{a}{b}+\frac{c}{d}=\frac{ad+bc}{bd}', FormulaLevel.rechenregel, supplemented: true),
        ]),
      ],
    );

List<String> _names(FormulaSheet s, FormulaDetail d) => [
      for (final sec in s.visibleSections(d)) for (final e in sec.entries) e.name,
    ];

void main() {
  group('Genauigkeit: Grob / Mittel / Fein', () {
    test('Fein: alles – auch Rechenregeln (Bruch, Potenz) und Ableitungsregeln', () {
      expect(_names(_integral(), FormulaDetail.fein),
          ['Partielle Integration', 'Substitution', 'Produktregel', 'Kettenregel', 'Potenzgesetz', 'Bruchaddition']);
    });

    test('Mittel: Rechenregeln fallen weg, der Rest (auch Ableitungsregeln) bleibt', () {
      expect(_names(_integral(), FormulaDetail.mittel),
          ['Partielle Integration', 'Substitution', 'Produktregel', 'Kettenregel']);
    });

    test('Grob: auch die Ableitungsregeln fallen weg – nur der neue Stoff bleibt', () {
      expect(_names(_integral(), FormulaDetail.grob), ['Partielle Integration', 'Substitution']);
    });

    test('Eine in den Folien NEU eingeführte Ableitungsregel bleibt auch bei Grob (kern)', () {
      final sheet = FormulaSheet(sections: [
        FormulaSection(title: 'Differentialrechnung', entries: [
          _e('Produktregel', r"(uv)' = u'v + uv'", FormulaLevel.kern),
          _e('Bruchrechnung', r'\frac{a}{b}', FormulaLevel.rechenregel),
        ]),
      ]);
      expect(_names(sheet, FormulaDetail.grob), ['Produktregel']);
    });

    test('Abschnitte ohne sichtbare Einträge fallen weg; Zählung stimmt', () {
      final sheet = _integral();
      expect(sheet.visibleSections(FormulaDetail.grob).map((s) => s.title), ['Integrationsregeln']);
      expect(sheet.visibleCount(FormulaDetail.grob), 2);
      expect(sheet.visibleCount(FormulaDetail.mittel), 4);
      expect(sheet.visibleCount(FormulaDetail.fein), 6);
      expect(sheet.totalCount, 6);
      // Ohne Angabe gilt die gewählte Genauigkeit.
      expect(sheet.visibleCount(), 4);
      expect(sheet.withDetail(FormulaDetail.grob).visibleCount(), 2);
    });

    test('Der Wechsel der Genauigkeit verliert nichts: alles bleibt gespeichert', () {
      final grob = _integral(detail: FormulaDetail.grob);
      expect(grob.withDetail(FormulaDetail.fein).visibleCount(), 6);
      expect(FormulaSheet.fromMap(grob.toMap()).totalCount, 6);
    });
  });

  group('Lesen (Modellantwort, ältere Daten)', () {
    test('Stufe: Schreibweisen und Unbekanntes (→ Kernstoff, damit nichts verloren geht)', () {
      expect(FormulaLevel.parse('kern'), FormulaLevel.kern);
      expect(FormulaLevel.parse('Hilfsregel'), FormulaLevel.hilfsregel);
      expect(FormulaLevel.parse('hilfsregeln'), FormulaLevel.hilfsregel);
      expect(FormulaLevel.parse('rechenregel'), FormulaLevel.rechenregel);
      expect(FormulaLevel.parse('Rechenregeln'), FormulaLevel.rechenregel);
      expect(FormulaLevel.parse(null), FormulaLevel.kern);
      expect(FormulaLevel.parse('irgendwas'), FormulaLevel.kern);
    });

    test('Genauigkeit: unbekannt → Mittel', () {
      expect(FormulaDetail.parse('fein'), FormulaDetail.fein);
      expect(FormulaDetail.parse('GROB'), FormulaDetail.grob);
      expect(FormulaDetail.parse(null), FormulaDetail.mittel);
      expect(FormulaDetail.parse('x'), FormulaDetail.mittel);
    });

    test('Eintrag: Dollarzeichen werden entfernt, "source" wird zu "ergänzt", leere Formeln fallen weg', () {
      final sheet = FormulaSheet.fromMap({
        'sections': [
          {
            'title': 'A',
            'entries': [
              {'name': 'x', 'formula': r'$$a^2$$', 'level': 'kern', 'source': 'ergaenzt'},
              {'name': 'y', 'formula': r'\(b\)', 'source': 'folien'},
              {'name': 'z', 'formula': r'$c$'},
              {'name': 'leer', 'formula': '  '},
              'kaputt',
            ],
          },
          {'title': 'leer', 'entries': []},
          'kaputt',
        ],
      });
      expect(sheet.sections, hasLength(1));
      final e = sheet.sections.single.entries;
      expect(e.map((x) => x.formula), ['a^2', 'b', 'c']);
      expect(e.map((x) => x.supplemented), [true, false, false]);
    });

    test('Speichern und Lesen (Round-Trip), kaputte Felder verkraften', () {
      final sheet = _integral(detail: FormulaDetail.fein);
      final back = FormulaSheet.fromMap(sheet.toMap());
      expect(back.detail, FormulaDetail.fein);
      expect(back.sections.map((s) => s.title), ['Integrationsregeln', 'Ableitungsregeln', 'Rechenregeln']);
      expect(back.sections[1].entries.first.supplemented, isTrue);
      expect(back.sections[1].entries.first.level, FormulaLevel.hilfsregel);
      expect(FormulaSheet.fromMap(const {}).sections, isEmpty);
      expect(FormulaSheet.tryFromMap(null), isNull);
      expect(FormulaSheet.tryFromMap('x'), isNull);
    });

    test('stripMathDelimiters entfernt nur umschließende Begrenzer', () {
      expect(FormulaEntry.stripMathDelimiters(r' $$ a $$ '), 'a');
      expect(FormulaEntry.stripMathDelimiters(r'$a$'), 'a');
      expect(FormulaEntry.stripMathDelimiters(r'\[ a \]'), 'a');
      expect(FormulaEntry.stripMathDelimiters(r'a$b'), r'a$b');
      expect(FormulaEntry.stripMathDelimiters('x'), 'x');
    });
  });

  group('Zusammenführen mehrerer Folienabschnitte', () {
    test('gleiche Abschnitte werden zusammengelegt, gleiche Formeln nur einmal', () {
      final a = FormulaSheet(sections: [
        FormulaSection(title: 'Integrationsregeln', entries: [_e('Partielle Integration', r"\int u v'", FormulaLevel.kern)]),
      ]);
      final b = FormulaSheet(sections: [
        FormulaSection(title: 'integrationsregeln', entries: [
          _e('Partielle Integration (nochmal)', r"$\int u v'$", FormulaLevel.kern), // gleiche Formel
          _e('Substitution', r"\int f(g)g'", FormulaLevel.kern),
        ]),
        FormulaSection(title: 'Potenzgesetze', entries: [_e('Potenz', r'a^m a^n', FormulaLevel.rechenregel)]),
      ]);
      final m = a.merged(b);
      expect(m.sections.map((s) => s.title), ['Integrationsregeln', 'Potenzgesetze']);
      expect(m.sections.first.entries.map((e) => e.name), ['Partielle Integration', 'Substitution']);
      expect(m.totalCount, 3);
    });

    test('bei einer Doppelung gewinnt die höhere Stufe und "aus den Folien" vor "ergänzt"', () {
      final a = FormulaSheet(sections: [
        FormulaSection(title: 'A', entries: [_e('Produktregel', r"(uv)'", FormulaLevel.hilfsregel, supplemented: true)]),
      ]);
      final b = FormulaSheet(sections: [
        FormulaSection(title: 'B', entries: [_e('Produktregel', r"(uv)'", FormulaLevel.kern)]),
      ]);
      final e = a.merged(b).sections.single.entries.single;
      expect(e.level, FormulaLevel.kern);
      expect(e.supplemented, isFalse);
    });

    test('Leerzeichen, \\left/\\right und \\cdot machen keine neue Formel', () {
      expect(_e('x', r'a \cdot b', FormulaLevel.kern).dedupeKey, _e('y', r'a*b', FormulaLevel.kern).dedupeKey);
      expect(_e('x', r'\left( a \right)', FormulaLevel.kern).dedupeKey, _e('y', '(a)', FormulaLevel.kern).dedupeKey);
    });
  });

  test('asText: nur das, was bei der gewählten Genauigkeit sichtbar ist; "ergänzt" und Hinweis stehen dabei', () {
    final text = _integral(detail: FormulaDetail.mittel).asText(title: 'Formelsammlung Integralrechnung');
    expect(text, startsWith('# Formelsammlung Integralrechnung (Mittel)'));
    expect(text, contains('## Integrationsregeln'));
    expect(text, contains('- **Produktregel** (ergänzt): \$\$(uv)\' = u\'v + uv\'\$\$'));
    expect(text, isNot(contains('Potenzgesetz')));
    expect(text, isNot(contains('## Rechenregeln')));
    final fein = _integral(detail: FormulaDetail.fein).asText();
    expect(fein, contains('Potenzgesetz'));
    expect(fein, isNot(startsWith('#  ')));
  });

  group('Summary mit Formelsammlung', () {
    test('Round-Trip über toMap/fromMap; Zusammenfassungen ohne Sammlung bleiben unverändert', () {
      final s = Summary(
        id: 's1',
        moduleId: 'm1',
        sourceMaterialIds: const ['a'],
        title: 'Formelsammlung',
        overview: '',
        keyPoints: const [],
        createdAt: DateTime(2026, 10, 1),
        formulaSheet: _integral(detail: FormulaDetail.grob),
      );
      expect(s.isFormulaSheet, isTrue);
      final back = Summary.fromMap(s.toMap());
      expect(back.isFormulaSheet, isTrue);
      expect(back.formulaSheet!.detail, FormulaDetail.grob);
      expect(back.formulaSheet!.totalCount, 6);

      final plain = Summary(
        id: 's2',
        moduleId: 'm1',
        sourceMaterialIds: const [],
        title: 'Normal',
        overview: 'Text',
        keyPoints: const ['a'],
        createdAt: DateTime(2026, 10, 1),
      );
      expect(plain.toMap().containsKey('formulaSheet'), isFalse);
      expect(Summary.fromMap(plain.toMap()).isFormulaSheet, isFalse);
    });

    test('copyWith ändert Titel/Sammlung, der Rest bleibt', () {
      final s = Summary(
        id: 's1',
        moduleId: 'm1',
        sourceMaterialIds: const ['a'],
        title: 'Alt',
        overview: 'o',
        keyPoints: const ['k'],
        createdAt: DateTime(2026, 10, 1),
        unitId: 'u1',
        formulaSheet: _integral(),
      );
      final c = s.copyWith(title: 'Neu', formulaSheet: _integral(detail: FormulaDetail.fein));
      expect(c.title, 'Neu');
      expect(c.formulaSheet!.detail, FormulaDetail.fein);
      expect(c.unitId, 'u1');
      expect(c.keyPoints, ['k']);
      expect(s.copyWith().title, 'Alt');
    });
  });
}
