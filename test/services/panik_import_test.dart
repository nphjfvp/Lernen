import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/claude_inbox.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/panik_content.dart';
import 'package:lernen/services/panik_import.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/module_export_service.dart';

/// Kleine, frei erfundene Inhaltsdatei (keine Skriptinhalte im Repo).
Map<String, dynamic> sample() => {
      'format': 'panik-content',
      'version': 1,
      'subject': 'Testmathe',
      'types': [
        {
          'id': 'A', 'title': 'Ableiten', 'area': 'Analysis', 'tier': 'P', 'weight': 'H',
          'recognition': ['f′ gesucht'], 'recipe': ['Regel wählen', 'ableiten'], 'mistakes': ['Vorzeichen'], 'sources': ['S1'],
        },
        {
          'id': 'B', 'title': 'Integrieren', 'area': 'Analysis', 'tier': 'A', 'weight': 'M', 'prerequisites': ['A'],
          'recognition': ['∫ gesucht'], 'recipe': ['Stammfunktion'], 'mistakes': ['+C'], 'sources': ['S2'],
        },
      ],
      'items': [
        {
          'id': 'a-b1', 'typeId': 'A', 'kind': 'example', 'source': 'S1', 'prompt': r'Leiten Sie $x^2$ ab.', 'answer': '2x',
          'task': {'kind': 'steps', 'steps': [{'title': 'Potenzregel', 'result': '2x^{1}'}, {'title': 'Vereinfachen', 'result': '2x'}]},
          'verified': true, 'fade': 1,
        },
        {
          'id': 'a-1', 'typeId': 'A', 'kind': 'task', 'prompt': r'Leiten Sie $x^3$ ab.', 'answer': '3x^2',
          'task': {'kind': 'steps', 'steps': [{'title': 'Potenzregel', 'result': '3x^2'}]}, 'verified': false,
        },
        {
          'id': 'b-r1', 'typeId': 'B', 'kind': 'reserve', 'prompt': r'$\int 2x\,dx$', 'answer': 'x^2+C',
          'task': {'kind': 'steps', 'steps': [{'title': 'Potenzregel rückwärts', 'result': 'x^2+C'}]}, 'verified': true,
        },
        {'id': 'erk-a-1', 'typeId': 'A', 'kind': 'recognize', 'prompt': r'Leiten Sie $x^3$ ab.', 'options': ['B', 'A'], 'answer': 'A', 'reason': 'f′ gesucht'},
        {'id': 'f-1', 'typeId': 'B', 'kind': 'formula', 'prompt': 'Potenzregel Integral', 'answer': r'$\int x^n=\frac{x^{n+1}}{n+1}$'},
      ],
    };

void main() {
  group('PanikContent.parse', () {
    test('liest eine gültige Datei', () {
      final c = PanikContent.parse(sample());
      expect(PanikContent.looksLike(sample()), isTrue);
      expect(c.subject, 'Testmathe');
      expect(c.types.map((t) => t.id), ['A', 'B']);
      expect(c.types.first.core, isTrue);
      expect(c.types.last.prerequisites, ['A']);
      expect(c.items, hasLength(5));
      expect(c.items.first.steps.map((s) => s.label), ['Potenzregel', 'Vereinfachen']);
      expect(c.items.first.fade, 1);
    });

    test('erkennt fremde Formate nicht als Panik-Datei', () {
      expect(PanikContent.looksLike({'tasks': []}), isFalse);
      expect(PanikContent.looksLike('x'), isFalse);
    });

    Map<String, dynamic> broken(void Function(Map<String, dynamic>) change) => sample()..let(change);

    for (final (name, change) in <(String, void Function(Map<String, dynamic>))>[
      ('unbekannter Typ', (m) => (m['items'] as List)[1]['typeId'] = 'X'),
      ('doppelte ID', (m) => (m['items'] as List)[1]['id'] = 'a-b1'),
      ('leerer Rechenweg', (m) => (m['items'] as List)[1]['task'] = {'steps': []}),
      ('Erkennen-Antwort nicht in Optionen', (m) => (m['items'] as List)[3]['answer'] = 'B2'),
      ('unbekannte Voraussetzung', (m) => (m['types'] as List)[1]['prerequisites'] = ['Z']),
      ('fade zu groß', (m) => (m['items'] as List)[0]['fade'] = 2),
      ('falsche Stufe', (m) => (m['types'] as List)[0]['tier'] = 'X'),
      ('neuere Version', (m) => m['version'] = 99),
    ]) {
      test('lehnt ab: $name', () {
        expect(() => PanikContent.parse(broken(change)), throwsFormatException);
      });
    }
  });

  test('Postfach erkennt Panik-Lieferungen und zählt ihre Einträge', () {
    final panik = InboxDelivery(id: '1', title: 'Mathe', payload: jsonEncode(sample()));
    expect(panik.isPanik, isTrue);
    expect(panik.taskCount, 5);
    final broken = InboxDelivery(id: '2', title: 'x', payload: jsonEncode(sample()..['items'] = []));
    expect((broken.isPanik, broken.taskCount), (true, 0));
    expect(InboxDelivery(id: '3', title: 'y', payload: '{"tasks": []}').isPanik, isFalse);
  });

  group('PanikImport.build', () {
    var n = 0;
    final imported = PanikImport.build(PanikContent.parse(sample()), now: DateTime(2026, 11, 28), newId: () => 'id${n++}');
    Flashcard card(String item) => imported.flashcards.firstWhere((c) => PanikCardInfo.of(c)?.itemId == item);

    test('Fach, Konzepte und Voraussetzungen', () {
      expect(imported.module.name, 'Testmathe');
      expect(imported.concepts.map((c) => c.title), ['Ableiten', 'Integrieren']);
      expect(imported.concepts.last.prerequisiteIds, [imported.concepts.first.id]);
      expect(imported.concepts.first.explanation, contains('Pflichtkern'));
      expect(imported.flashcards, hasLength(5));
      expect(imported.flashcards.every((c) => c.moduleId == imported.module.id), isTrue);
    });

    test('Rechenweg-Karten mit Etiketten und Lösungsweg auf der Rückseite', () {
      final ex = card('a-b1');
      expect(ex.type, QuestionType.flashcard);
      expect(ex.conceptId, imported.concepts.first.id);
      final info = PanikCardInfo.of(Flashcard.fromMap(ex.toMap()))!;
      expect(info.steps.map((s) => s.label), ['Potenzregel', 'Vereinfachen']);
      expect(info.answer, '2x');
      expect(ex.back, contains(r'1. Potenzregel: $2x^{1}$'));
      expect(ex.back, isNot(contains('ungeprüft')));
      expect(card('a-1').back, contains('nicht maschinell geprüft'));
    });

    test('Reserve ist stummgeschaltet, sonst Gewicht 1; jede Karte für sich', () {
      expect(card('b-r1').isMuted, isTrue);
      expect(card('a-1').isMuted, isFalse);
      expect(imported.flashcards.map((c) => c.stageGroup).toSet(), hasLength(5));
    });

    test('Erkennen wird Single Choice mit Typ-Titeln', () {
      final r = card('erk-a-1');
      expect(r.type, QuestionType.singleChoice);
      expect(r.options!.map((o) => o.text), ['Integrieren', 'Ableiten']);
      expect(r.options!.where((o) => o.isCorrect).single.text, 'Ableiten');
    });

    test('Panik-Angaben überstehen Speichern und Laden', () {
      for (final c in imported.flashcards) {
        final reloaded = Flashcard.fromMap(c.toMap());
        expect(reloaded.type, c.type);
        expect(PanikCardInfo.of(reloaded)?.kind, PanikCardInfo.of(c)?.kind);
      }
      final info = PanikCardInfo.of(Flashcard.fromMap(card('a-b1').toMap()))!;
      expect((info.kind, info.typeId, info.core, info.fade, info.verified), (PanikItemKind.example, 'A', true, 1, true));
      expect(PanikCardInfo.of(Flashcard.fromMap(card('f-1').toMap()))!.kind, PanikItemKind.formula);
    });

    test('alle Karten bleiben normale Karten (kein „App aktualisieren“)', () {
      for (final c in imported.flashcards) {
        expect(c.taskData!['kind'], isNull);
        expect(Flashcard.fromMap(c.toMap()).type, c.type);
      }
    });

    test('speichert alles in einer Transaktion', () async {
      final db = await databaseFactoryMemory.openDatabase('panik_${DateTime.now().microsecondsSinceEpoch}');
      await db.transaction((txn) => ModuleExportService.saveImported(txn, imported));
      expect(await DatabaseService.flashcards.count(db), 5);
      expect(await DatabaseService.concepts.count(db), 2);
      await db.close();
    });
  });
}

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
