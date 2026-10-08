import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/bom_task.dart';
import 'package:lernen/services/bom_calculator.dart';

/// 10 Erzeugnis
///  ├─ 2× 11 BG1
///  │    ├─ 3× 21 Teil A
///  │    └─ 1× 22 BG2
///  │         ├─ 4× 31 Teil B
///  │         └─ 2× 21 Teil A
///  ├─ 2× 22 BG2 (nicht noch einmal aufgelöst)
///  └─ 1,5 kg 23 Stahl
BomTask sample({List<BomPart>? parts, double base = 1}) => BomTask(
  baseQuantity: base,
  parts: parts ?? [for (final k in BomListKind.values) BomPart(kind: k)],
  root: const BomNode(
    number: '10',
    name: 'Erzeugnis',
    children: [
      BomNode(
        number: '11',
        name: 'BG1',
        quantity: 2,
        children: [
          BomNode(number: '21', name: 'Teil A', quantity: 3),
          BomNode(
            number: '22',
            name: 'BG2',
            children: [
              BomNode(number: '31', name: 'Teil B', quantity: 4),
              BomNode(number: '21', name: 'Teil A', quantity: 2),
            ],
          ),
        ],
      ),
      BomNode(number: '22', name: 'BG2', quantity: 2),
      BomNode(number: '23', name: 'Stahl', quantity: 1.5, unit: 'kg'),
    ],
  ),
);

void main() {
  final calc = BomCalculator(sample());

  group('Listen berechnen', () {
    test('Strukturstückliste: von links nach unten, wiederholte Baugruppe aufgelöst', () {
      final rows = calc.structure();
      expect(
        [for (final r in rows) '${r.level}:${r.number}:${bomQuantityText(r.quantity)}'],
        ['1:11:2', '2:21:3', '2:22:1', '3:31:4', '3:21:2', '1:22:2', '2:31:4', '2:21:2', '1:23:1,5'],
      );
      expect(calc.structure(totals: true).map((r) => bomQuantityText(r.quantity)).toList(), [
        '2',
        '6',
        '2',
        '8',
        '4',
        '2',
        '8',
        '4',
        '1,5',
      ]);
    });

    test('Mengenübersicht: Pfade multipliziert, Vorkommen addiert, mit/ohne Baugruppen', () {
      expect(
        {for (final r in calc.overview()) r.number: r.quantity},
        {'11': 2, '21': 14, '22': 4, '23': 1.5, '31': 16},
      );
      expect(
        {for (final r in calc.overview(includeAssemblies: false)) r.number: r.quantity},
        {'21': 14, '23': 1.5, '31': 16},
      );
      final doubled = BomCalculator(sample(base: 2));
      expect(doubled.overview().firstWhere((r) => r.number == '21').quantity, 28);
    });

    test('Baukasten: Listen fürs Erzeugnis und jede Baugruppe, direkte Bestandteile mit AK', () {
      expect(calc.assemblies(), ['10', '11', '22']);
      expect(
        [for (final r in calc.modular('10')) '${r.number}:${bomQuantityText(r.quantity)}:${r.ak}'],
        ['11:2:1', '22:2:1', '23:1,5:2'],
      );
      expect([for (final r in calc.modular('22')) '${r.number}:${r.quantity}:${r.ak}'], ['31:4.0:2', '21:2.0:2']);
      expect(calc.modular('21'), isEmpty);
    });

    test('Musterlösung als Text', () {
      final text = calc.fullSolution();
      expect(text, contains('Mengenübersichtsstückliste\n11 | BG1 | 2'));
      expect(text, contains('...Stufe 3 | 31 | Teil B | 4'));
      expect(text, contains('Baukastenstückliste 22 BG2\n31 | Teil B | 4 | AK 2'));
      expect(text, contains('23 | Stahl | 1,5 kg'));
    });
  });

  group('prüfen', () {
    test('Mengenübersicht: nicht multipliziert, nur ein Vorkommen, doppelt, Erzeugnis, fehlt', () {
      final part = sample().parts[0];
      final v = calc.checkOverview(part, const [
        BomInput(number: '11', quantity: 2),
        BomInput(number: '31', quantity: 4),
        BomInput(number: '21', quantity: 6),
        BomInput(number: '21', quantity: 14),
        BomInput(number: '10', quantity: 1),
        BomInput(number: '99', quantity: 1),
      ]);
      expect(v.rows[0], isNull);
      expect(v.rows[1], contains('nicht multipliziert'));
      expect(v.rows[2], contains('3-mal im Baum vor'));
      expect(v.rows[3], contains('doppelt'));
      expect(v.rows[4], contains('Erzeugnis selbst'));
      expect(v.rows[5], contains('kommt im Erzeugnisbaum nicht vor'));
      expect(v.missing.single, 'Es fehlen noch 2 Zeilen.');
      expect(v.ok, isFalse);

      final onlyParts = calc.checkOverview(const BomPart(kind: BomListKind.overview, includeAssemblies: false), const [
        BomInput(number: '11', quantity: 2),
        BomInput(number: '21', quantity: 14),
        BomInput(number: '23', quantity: 1.5),
        BomInput(number: '31', quantity: 16),
      ]);
      expect(onlyParts.rows.first, contains('Baugruppe'));
      expect(onlyParts.rows.skip(1), everyElement(isNull));
    });

    test('Strukturstückliste: vergessene Zeile verschiebt nicht alles, Gesamtmenge statt Linienmenge, Stufe', () {
      final part = sample().parts[1];
      final all = [for (final r in calc.structure()) BomInput(number: r.number, level: r.level, quantity: r.quantity)];
      expect(calc.checkStructure(part, all).ok, isTrue);

      final skipped = [...all]..removeAt(1);
      final v = calc.checkStructure(part, skipped);
      expect(v.rows, everyElement(isNull));
      expect(v.missing.single, 'Es fehlt noch 1 Zeile.');

      final wrong = [...all];
      wrong[3] = const BomInput(number: '31', level: 3, quantity: 8);
      wrong[4] = const BomInput(number: '21', level: 2, quantity: 2);
      final w = calc.checkStructure(part, wrong);
      expect(w.rows[3], contains('nicht die Gesamtmenge'));
      expect(w.rows[4], contains('Stufe'));
      expect(w.wrongRows, 2);

      final swapped = [all[5], ...all.take(5), ...all.skip(6)];
      expect(calc.checkStructure(part, swapped).rows.first, contains('falschen Stelle'));
    });

    test('Baukasten: fehlende Liste, Liste für ein Teil, multipliziert, AK, zu tief', () {
      final part = sample().parts[2];
      final v = calc.checkModular(part, {
        '10': const [
          BomInput(number: '11', quantity: 2, ak: 1),
          BomInput(number: '22', quantity: 2, ak: 2),
          BomInput(number: '31', quantity: 4, ak: 2),
        ],
        '22': const [BomInput(number: '31', quantity: 8, ak: 2), BomInput(number: '21', quantity: 2, ak: 2)],
        '23': const [],
      });
      expect(v.rows[0], isNull);
      expect(v.rows[1], contains('AK 1'));
      expect(v.rows[2], contains('kein direkter Bestandteil'));
      expect(v.rows[3], contains('nicht multiplizieren'));
      expect(v.rows[4], isNull);
      expect(v.listProblems['23'], contains('keine eigene Stückliste'));
      expect(v.missing, [
        'Es fehlt noch 1 Liste (jede Baugruppe mit AK 1 und das Erzeugnis brauchen eine eigene).',
        'Es fehlt noch 1 Zeile.',
      ]);
    });

    test('Tipps nennen am Ende Anzahl bzw. Listen', () {
      expect(calc.hints(sample().parts[0]).last, 'Es sind 5 Zeilen.');
      expect(calc.hints(sample().parts[2]).last, 'Gebraucht werden Listen für: 10 Erzeugnis, 11 BG1, 22 BG2.');
    });
  });

  group('Modell', () {
    test('toMap/fromMap und KI-Feldnamen', () {
      final task = sample(
        parts: const [
          BomPart(kind: BomListKind.overview, includeAssemblies: false),
          BomPart(kind: BomListKind.modular, lists: ['10', '11']),
        ],
      );
      final back = BomTask.fromMap(task.toMap())!;
      expect(back.toMap(), task.toMap());

      final ai = BomTask.fromMap({
        'tree': {
          'sachNr': 10,
          'bezeichnung': 'Apfelkuchen',
          'children': [
            {'nr': '12', 'name': 'Teigdeckel', 'menge': '220 g', 'einheit': 'g'},
            {'nr': '11', 'name': 'gefüllter Boden', 'uncertain': true},
          ],
        },
        'parts': [
          'Strukturstückliste',
          {'list': 'Baustellenstückliste'},
        ],
      })!;
      expect(ai.root.number, '10');
      expect(ai.root.children.first.quantity, 220);
      expect(ai.root.children.last.quantity, 1);
      expect(ai.parts.map((p) => p.kind), [BomListKind.structure, BomListKind.modular]);
      expect(ai.hasUncertain, isTrue);
      expect(ai.confirmed().hasUncertain, isFalse);
      expect(
        BomTask.fromMap({
          'root': {'nr': '1'},
        })!.parts,
        hasLength(3),
      );
      expect(
        BomTask.fromMap({
          'root': {'nr': '1'},
        })!.isUsable,
        isFalse,
      );
    });

    test('Textform für den Editor: hin und zurück, Fehler mit Zeile', () {
      final text = BomTask.outline(sample().root);
      expect(text.split('\n').first, '0; 10; Erzeugnis');
      expect(text, contains('\n3; 31; Teil B; 4\n'));
      expect(text, contains('1; 23; Stahl; 1,5; kg'));
      final parsed = BomTask.parseOutline(text);
      expect(parsed.error, isNull);
      expect(
        BomTask(root: parsed.root!, parts: const []).toMap(),
        BomTask(root: sample().root, parts: const []).toMap(),
      );

      expect(BomTask.parseOutline('1; 10; x').error, contains('Stufe 0'));
      expect(BomTask.parseOutline('0; 10\n2; 11').error, contains('Zeile 2'));
      expect(BomTask.parseOutline('0; 10\n1; 11; a; viel').error, contains('keine Zahl'));
      expect(BomTask.parseOutline('0; 10\n1;').error, contains('Sach-Nr. fehlt'));
    });

    test('Listenart aus KI-Wörtern', () {
      expect(bomListKindFrom('Mengenübersichtsstückliste'), BomListKind.overview);
      expect(bomListKindFrom('structure'), BomListKind.structure);
      expect(bomListKindFrom('Baustückliste'), BomListKind.modular);
      expect(bomListKindFrom('Baukasten'), BomListKind.modular);
      expect(bomListKindFrom('irgendwas'), isNull);
      expect(parseBomQuantity('1.500 g'), 1500);
      expect(parseBomQuantity('1,5'), 1.5);
      expect(bomQuantityText(0.25), '0,25');
    });
  });
}
