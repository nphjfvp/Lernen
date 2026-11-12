import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/models/study_sequence.dart';
import 'package:lernen/services/continue_learning.dart';

Module _module(String id, String name, {DateTime? exam}) =>
    Module(id: id, name: name, colorValue: 0xFF3D5AFE, icon: '📘', examDate: exam, createdAt: DateTime(2026, 1, 1));

Flashcard _card(String id, String moduleId, {String? unit, String? material, int page = 1, double weight = 1}) =>
    Flashcard(
      id: id,
      moduleId: moduleId,
      front: 'Aufgabe $id',
      back: 'Lösung',
      createdAt: DateTime(2026, 9, 1).add(Duration(minutes: int.parse(id.replaceAll(RegExp(r'\D'), '')))),
      due: DateTime(2026, 9, 1),
      unitId: unit,
      sourceMaterialId: material,
      sourcePage: page,
      weight: weight,
    );

void main() {
  final mathe = _module('m', 'Mathe', exam: DateTime.now().add(const Duration(days: 61)));
  final physik = _module('p', 'Physik', exam: DateTime.now().add(const Duration(days: 20)));
  final cards = {
    'm': [for (var i = 1; i <= 11; i++) _card('a$i', 'm', material: 'blatt')],
    'p': [_card('b1', 'p', unit: 'u1'), _card('b2', 'p', unit: 'u1')],
  };
  String? title(String moduleId, StudySequenceKind kind, String id) => switch ((moduleId, kind, id)) {
    ('m', StudySequenceKind.material, 'blatt') => 'Übungsblatt 3.pdf',
    ('p', StudySequenceKind.unit, 'u1') => 'Kinematik',
    _ => null,
  };

  StudySequenceProgress progress(String moduleId, String key, Map<String, StudySequenceStatus> status, DateTime at) =>
      StudySequenceProgress(moduleId: moduleId, key: key, status: status, updatedAt: at);

  test('die zuletzt benutzte Reihe mit offenen Aufgaben – samt Stelle, an der es weitergeht', () {
    // 1–7 gelöst, 8 nicht geschafft, 9–11 gelöst: weiter bei Aufgabe 8.
    final sheet = progress('m', 'material:blatt', {
      for (var i = 1; i <= 11; i++) 'a$i': i == 8 ? StudySequenceStatus.failed : StudySequenceStatus.solved,
    }, DateTime(2026, 11, 12, 18));
    final older = progress('p', 'unit:u1', const {}, DateTime(2026, 11, 10));
    final target = ContinueLearning.pick(
      modules: [mathe, physik],
      progresses: [older, sheet],
      cardsByModule: cards,
      titleOf: title,
    )!;
    expect(target.moduleName, 'Mathe');
    expect(target.source!.title, 'Übungsblatt 3.pdf');
    expect(target.source!.key, 'material:blatt');
    expect(target.detail, 'Der Reihe nach · weiter bei Aufgabe 8 von 11');
  });

  test('ist die letzte Reihe fertig oder ihre Quelle gelöscht, kommt die nächste', () {
    final done = progress('m', 'material:blatt', {
      for (var i = 1; i <= 11; i++) 'a$i': StudySequenceStatus.solved,
    }, DateTime(2026, 11, 12));
    final gone = progress('m', 'material:geloescht', const {}, DateTime(2026, 11, 11));
    final open = progress('p', 'unit:u1', {'b1': StudySequenceStatus.solved}, DateTime(2026, 11, 9));
    final target = ContinueLearning.pick(
      modules: [mathe, physik],
      progresses: [done, gone, open],
      cardsByModule: cards,
      titleOf: title,
    )!;
    expect(target.moduleName, 'Physik');
    expect(target.detail, 'Der Reihe nach · weiter bei Aufgabe 2 von 2');
    // Nur für ein bestimmtes Fach gefragt: dort ist nichts offen → Üben in diesem Fach.
    final inMathe = ContinueLearning.pick(
      modules: [mathe, physik],
      progresses: [done, gone, open],
      cardsByModule: cards,
      titleOf: title,
      onlyModule: 'm',
    )!;
    expect(inMathe.source, isNull);
    expect(inMathe.moduleId, 'm');
    expect(inMathe.detail, startsWith('Üben · 11 Karten'));
  });

  test('nichts angefangen: Üben im Fach mit der nächsten Klausur; ohne Karten gibt es kein Ziel', () {
    final target = ContinueLearning.pick(
      modules: [mathe, physik],
      progresses: const [],
      cardsByModule: cards,
      titleOf: title,
    )!;
    expect(target.source, isNull);
    expect(target.moduleName, 'Physik');
    expect(target.detail, contains('Üben · 2 Karten · Klausur in'));
    expect(
      ContinueLearning.pick(modules: [mathe], progresses: const [], cardsByModule: const {}, titleOf: title),
      isNull,
    );
    // Stummgeschaltete Karten zählen nicht.
    expect(
      ContinueLearning.pick(
        modules: [mathe],
        progresses: const [],
        cardsByModule: {
          'm': [_card('a1', 'm', weight: 0)],
        },
        titleOf: title,
      ),
      isNull,
    );
  });
}
