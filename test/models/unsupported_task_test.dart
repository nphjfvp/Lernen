import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/unsupported_task.dart';

UnsupportedTask _t(
  String id,
  String text, {
  String needs = '',
  String reason = '',
  String moduleId = 'm1',
  int? page,
}) => UnsupportedTask(
  id: id,
  moduleId: moduleId,
  text: text,
  needs: needs,
  reason: reason,
  sourcePage: page,
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  test('speichern und wieder lesen', () {
    final t = UnsupportedTask(
      id: 'u1',
      moduleId: 'm1',
      text: 'Skizziere das Diagramm.',
      reason: 'Kurve zeichnen',
      needs: 'Kurve in Diagramm zeichnen',
      sourceMaterialId: 'blatt',
      sourcePage: 3,
      createdAt: DateTime(2026, 10, 7, 12),
    );
    final again = UnsupportedTask.fromMap(t.toMap());
    expect(again.toMap(), t.toMap());
    expect(UnsupportedTask.fromMap(const {}).createdAt, DateTime.fromMillisecondsSinceEpoch(0));
  });

  test('gleiche Aufgabe: Leerzeichen und Groß/klein egal', () {
    expect(UnsupportedTask.sameKey('  Zeichne  das\nDiagramm '), UnsupportedTask.sameKey('zeichne das diagramm'));
  });

  test('Gruppen: nach Bedienart, häufigste zuerst, Sonstiges zuletzt', () {
    final groups = UnsupportedTask.grouped([
      _t('1', 'A'),
      _t('2', 'B', needs: 'begründung schreiben'),
      _t('3', 'C', needs: 'Kurve in Diagramm zeichnen'),
      _t('4', 'D', needs: 'kurve in diagramm zeichnen'),
      _t('5', 'E'),
      _t('6', 'F'),
    ]);
    expect(groups.map((g) => g.group), ['Kurve in Diagramm zeichnen', 'Begründung schreiben', 'Sonstiges']);
    expect(groups.map((g) => g.tasks.length), [2, 1, 3]);
  });

  test('als Text zum Weiterschicken', () {
    final long = 'x' * 500;
    final text = UnsupportedTask.exportText(
      [
        _t('1', 'Skizziere\n das Diagramm.', needs: 'Kurve in Diagramm zeichnen', reason: 'Kurve zeichnen.', page: 2),
        _t('2', long, moduleId: 'm2'),
      ],
      title: 'alle Fächer',
      moduleName: (id) => id == 'm1' ? 'Werkstoffkunde' : '',
    );
    final lines = text.split('\n');
    expect(lines.first, 'Noch nicht interaktiv – 2 Aufgaben (alle Fächer)');
    expect(
      text,
      contains(
        '## Kurve in Diagramm zeichnen (1)\n- Skizziere das Diagramm.\n  Grund: Kurve zeichnen.\n  (Fach: Werkstoffkunde, Seite 2)',
      ),
    );
    expect(text, contains('## Sonstiges (1)'));
    expect(lines.last, '- ${'x' * 400} …');
    expect(UnsupportedTask.exportText([_t('1', 'A')]).split('\n').first, 'Noch nicht interaktiv – 1 Aufgabe');
  });
}
