import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/task_folder_service.dart';

Flashcard _card(
  String id, {
  QuestionType type = QuestionType.learn,
  String? material,
  int? page,
  DateTime? createdAt,
}) =>
    Flashcard(
      id: id,
      moduleId: 'm1',
      front: 'Aufgabe $id',
      back: 'Erklärung $id',
      createdAt: createdAt ?? DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      type: type,
      sourceMaterialId: material,
      sourcePage: page,
    );

void main() {
  group('TaskFolderService.tasksOf', () {
    test('nur Lernaufgaben, nach Material, Seite und Erstellung sortiert', () {
      final cards = [
        _card('c', material: 'b', page: 1),
        _card('quiz', type: QuestionType.freeText, material: 'a', page: 1),
        _card('b', material: 'a', page: 3),
        _card('a2', material: 'a', page: 2, createdAt: DateTime(2026, 9, 2)),
        _card('a1', material: 'a', page: 2, createdAt: DateTime(2026, 9, 1)),
        _card('eigene'),
      ];
      expect(TaskFolderService.tasksOf(cards).map((c) => c.id), ['eigene', 'a1', 'a2', 'b', 'c']);
    });
  });

  group('TaskFolderService.isWarning', () {
    final now = DateTime(2026, 9, 29, 15, 30);
    bool warn(DateTime? exam, {int tasks = 3}) =>
        TaskFolderService.isWarning(taskCount: tasks, examDate: exam, now: now);

    test('rot genau ab 20 Tagen vor der Klausur, heute eingeschlossen', () {
      expect(warn(DateTime(2026, 10, 19)), isTrue); // 20 Tage
      expect(warn(DateTime(2026, 10, 20)), isFalse); // 21 Tage
      expect(warn(DateTime(2026, 9, 30)), isTrue); // morgen
      expect(warn(DateTime(2026, 9, 29, 8)), isTrue); // heute (Uhrzeit egal)
    }, );

    test('nicht ohne Klausurdatum, nach der Klausur oder ohne Aufgaben', () {
      expect(warn(null), isFalse);
      expect(warn(DateTime(2026, 9, 28)), isFalse);
      expect(warn(DateTime(2026, 10, 5), tasks: 0), isFalse);
    });

    test('Tage bis zur Klausur zählen ganze Kalendertage, auch über die Zeitumstellung', () {
      expect(TaskFolderService.daysUntilExam(DateTime(2026, 10, 27), now: DateTime(2026, 10, 24, 23, 59)), 3);
      expect(TaskFolderService.daysUntilExam(DateTime(2026, 3, 30), now: DateTime(2026, 3, 27, 0, 5)), 3);
      expect(TaskFolderService.daysUntilExam(DateTime(2026, 9, 28), now: now), -1);
      expect(TaskFolderService.daysUntilExam(null, now: now), isNull);
    });
  });
}
