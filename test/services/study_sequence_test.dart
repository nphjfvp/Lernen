import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/lecture_unit.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/study_sequence.dart';
import 'package:lernen/services/study_sequence.dart';
import 'package:lernen/services/sync_merge.dart';
import 'package:lernen/ui/practice/study_sequence_screen.dart';

Flashcard _card(String id, {String? material, int? page, int minute = 0, String? unit}) => Flashcard(
  id: id,
  moduleId: 'm',
  front: 'Aufgabe $id',
  back: 'Lösung',
  createdAt: DateTime(2026, 11, 1, 10, minute),
  due: DateTime(2026, 11, 1),
  sourceMaterialId: material,
  sourcePage: page,
  unitId: unit,
);

void main() {
  const pdf = StudySequenceSource(kind: StudySequenceKind.material, id: 'p1', title: 'Blatt 1');
  StudySequenceProgress empty() => StudySequenceProgress(moduleId: 'm', key: pdf.key, updatedAt: DateTime(2026));

  test('Reihenfolge: nach Material, Seite und Import-Zeitpunkt; nur die Quelle', () {
    final cards = [
      _card('c', material: 'p1', page: 2, minute: 0),
      _card('a', material: 'p1', page: 1, minute: 5),
      _card('b', material: 'p1', page: 1, minute: 6),
      _card('x', material: 'p2', page: 1),
    ];
    expect(StudySequence.ordered(cards, pdf).map((c) => c.id), ['a', 'b', 'c']);
    final unitCards = [
      _card('u2', material: 'p2', unit: 'u', minute: 1),
      _card('u1', material: 'p1', unit: 'u', minute: 9),
      _card('u3', unit: 'u', minute: 0),
    ];
    const unit = StudySequenceSource(kind: StudySequenceKind.unit, id: 'u', title: 'Einheit 1');
    expect(StudySequence.ordered(unitCards, unit, materialOrder: ['p1', 'p2']).map((c) => c.id), ['u1', 'u2', 'u3']);
  });

  test('1–7 gelöst, 8 nicht, 9–11 gelöst → nächste Runde startet bei 8 und überspringt 9–11', () {
    final cards = [for (var i = 1; i <= 12; i++) _card('$i', material: 'p1', minute: i)];
    var p = empty();
    expect(StudySequence.round(cards, p).length, 12);
    expect(StudySequence.nextPosition(cards, p), 1);
    for (var i = 1; i <= 11; i++) {
      p = StudySequence.record(cards, p, '$i', i == 8 ? StudySequenceStatus.failed : StudySequenceStatus.solved);
    }
    // Mitten in der Runde aufgehört: weiter bei 12.
    expect(p.nextId, '12');
    expect(StudySequence.round(cards, p).map((c) => c.id), ['12']);
    p = StudySequence.record(cards, p, '12', StudySequenceStatus.solved);
    expect(p.nextId, isNull, reason: 'Runde beendet');
    expect(StudySequence.round(cards, p).map((c) => c.id), ['8']);
    expect(StudySequence.nextPosition(cards, p), 8);
    p = StudySequence.record(cards, p, '8', StudySequenceStatus.solved);
    expect(StudySequence.open(cards, p), isEmpty);
    expect(StudySequence.nextPosition(cards, p), isNull);
  });

  test('Kann ich schon, Wieder öffnen, Neustart ab beliebiger Aufgabe', () {
    final cards = [for (var i = 1; i <= 6; i++) _card('$i', material: 'p1', minute: i)];
    var p = StudySequence.record(cards, empty(), '1', StudySequenceStatus.solved);
    p = StudySequence.record(cards, p, '2', StudySequenceStatus.failed);
    p = StudySequence.record(cards, p, '3', StudySequenceStatus.skipped);
    expect(p.isDone('3'), isTrue);
    expect(StudySequence.round(cards, p).map((c) => c.id), ['4', '5', '6']);
    p = StudySequence.setUnderstood(p, '3', false);
    expect(p.isDone('3'), isFalse);
    p = StudySequence.setUnderstood(p, '5', true);
    expect(StudySequence.round(cards, p).map((c) => c.id), ['4', '6']);

    // Neustart ab 5: 1 bleibt gelöst, 2–4 gelten als erledigt, ab 5 offen.
    p = StudySequence.restartAt(cards, p, 4);
    expect(p.status['1'], StudySequenceStatus.solved);
    expect(p.status['2'], StudySequenceStatus.skipped);
    expect(p.status.containsKey('5'), isFalse);
    expect(StudySequence.round(cards, p).map((c) => c.id), ['5', '6']);
    // Von vorn.
    p = StudySequence.restartAt(cards, p, 0);
    expect(p.status, isEmpty);
    expect(StudySequence.nextPosition(cards, p), 1);
  });

  test('Stand speichern/lesen und beim Abgleich gewinnt der neuere', () {
    final p = StudySequenceProgress(
      moduleId: 'm',
      key: pdf.key,
      status: const {'a': StudySequenceStatus.solved, 'b': StudySequenceStatus.failed},
      nextId: 'c',
      updatedAt: DateTime(2026, 11, 2),
    );
    final back = StudySequenceProgress.fromMap(p.toMap())!;
    expect(back.toMap(), p.toMap());
    expect(back.id, 'm|material:p1');
    expect(StudySequenceProgress.fromMap({'moduleId': 'm'}), isNull);
    final older = StudySequenceProgress(moduleId: 'm', key: pdf.key, updatedAt: DateTime(2026, 11, 1));
    final modules = [
      {'id': 'm', 'name': 'Mathe'},
    ];
    final merged = mergeSyncPayloads(
      local: {
        'modules': modules,
        'studySequences': [older.toMap()],
      },
      remote: {
        'modules': modules,
        'studySequences': [p.toMap()],
      },
      base: const {},
    );
    expect(((merged.payload['studySequences'] as List).single as Map)['nextId'], 'c');
  });

  test('Auswahl: nur Einheiten und PDFs mit Aufgaben, mit Anzahl', () {
    final sources = studySequenceSources(
      units: [
        LectureUnit(id: 'u1', moduleId: 'm', title: 'Einheit 1', createdAt: DateTime(2026)),
        LectureUnit(id: 'u2', moduleId: 'm', title: 'Leer', createdAt: DateTime(2026)),
      ],
      materials: [
        MaterialItem(
          id: 'p1',
          moduleId: 'm',
          fileName: 'Blatt 1.pdf',
          kind: MaterialKind.exercise,
          extractedText: '',
          createdAt: DateTime(2026),
        ),
      ],
      cards: [
        _card('a', material: 'p1', unit: 'u1'),
        _card('b', unit: 'u1'),
      ],
    );
    expect([for (final s in sources) '${s.source.title}:${s.count}'], ['Einheit 1:2', 'Blatt 1.pdf:1']);
    expect(sources.last.source.key, 'material:p1');
  });
}
