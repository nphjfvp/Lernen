import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/module_export_service.dart';
import 'package:lernen/services/script_match_service.dart';
import 'package:lernen/services/source_locator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Uint8List _pdf(List<String> pages) {
  final document = PdfDocument();
  for (final text in pages) {
    document.pages.add().graphics.drawString(
          text,
          PdfStandardFont(PdfFontFamily.helvetica, 11),
          bounds: const Rect.fromLTWH(0, 0, 500, 700),
        );
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

MaterialItem _material(String id, List<String> pages,
        {MaterialKind kind = MaterialKind.slide, String? unitId, String name = 'Folien.pdf'}) =>
    MaterialItem(
      id: id,
      moduleId: 'm1',
      fileName: name,
      kind: kind,
      extractedText: pages.join('\n'),
      createdAt: DateTime(2026, 9, 1),
      fileBytesBase64: base64Encode(_pdf(pages)),
      unitId: unitId,
    );

Flashcard _card(String id, String front, String back,
        {String? sourceId, int? page, String? unitId, int? scriptPage, String? scriptId}) =>
    Flashcard(
      id: id,
      moduleId: 'm1',
      front: front,
      back: back,
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      sourceMaterialId: sourceId,
      sourcePage: page,
      unitId: unitId,
      scriptMaterialId: scriptId,
      scriptPage: scriptPage,
    );

const _folien = [
  'Organisatorisches: Termine, Klausur, Sprechstunde',
  'Das Ohmsche Gesetz: Spannung U gleich Widerstand R mal Strom I',
  'Kirchhoffsche Regeln: Knotenregel und Maschenregel im Netzwerk',
  'Leistung P gleich Spannung mal Strom, Einheit Watt',
];

http.Response _ok(Object content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': jsonEncode(content)},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_script_match_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  group('Flashcard: Fundstelle im Skript', () {
    final base = _card('a', 'Frage?', 'Antwort', sourceId: 'blatt', page: 2, scriptId: 'folien', scriptPage: 7);

    test('Zustand: gefunden, gesucht ohne Treffer, noch nicht gesucht', () {
      expect(base.hasScript, isTrue);
      expect(base.scriptSearched, isTrue);
      final none = base.copyWithScript(materialId: null, page: 0);
      expect(none.hasScript, isFalse);
      expect(none.scriptSearched, isTrue);
      final fresh = _card('b', 'F', 'A');
      expect(fresh.hasScript, isFalse);
      expect(fresh.scriptSearched, isFalse);
    });

    test('bleibt bei Speichern und bei jeder Fortschreibung der Karte erhalten', () {
      void check(Flashcard card, String what) {
        expect(card.scriptMaterialId, 'folien', reason: what);
        expect(card.scriptPage, 7, reason: what);
      }

      check(Flashcard.fromMap(base.toMap()), 'toMap/fromMap');
      check(
        base.copyWithReview(
          due: DateTime(2026, 10, 1),
          stability: 3,
          difficulty: 5,
          elapsedDays: 1,
          scheduledDays: 3,
          reps: 1,
          lapses: 0,
          state: 'review',
          lastReview: DateTime(2026, 9, 2),
        ),
        'copyWithReview',
      );
      check(base.copyWithContent(front: 'Neu'), 'copyWithContent');
      check(base.copyWithBoxUpdate(isCorrect: false).card, 'copyWithBoxUpdate falsch');
      check(base.copyWithBoxUpdate(isCorrect: true).card, 'copyWithBoxUpdate richtig');
      check(base.copyWithStage(level: 1), 'copyWithStage');
      check(base.copyWithWeight(2), 'copyWithWeight');

      // Stufenkette: befördern und zurückstufen.
      final chain = Flashcard(
        id: 'k',
        moduleId: 'm1',
        front: 'Leicht?',
        back: '',
        createdAt: DateTime(2026, 9, 1),
        due: DateTime(2026, 9, 1),
        type: QuestionType.singleChoice,
        options: const [QuizOption(text: 'A', isCorrect: true), QuizOption(text: 'B', isCorrect: false)],
        variantChain: const [QuestionType.singleChoice, QuestionType.freeText],
        scriptMaterialId: 'folien',
        scriptPage: 7,
      );
      final promoted = chain.copyWithPromotedVariant(
        newType: QuestionType.freeText,
        front: 'Schwer?',
        correctText: 'A',
      );
      check(promoted, 'copyWithPromotedVariant');
      check(promoted.copyWithDemotedVariant(), 'copyWithDemotedVariant');
    });

    test('Lernstand zurücksetzen nimmt die Fundstelle mit', () {
      check(Flashcard f) {
        expect(f.scriptMaterialId, 'folien');
        expect(f.scriptPage, 7);
      }

      check(ModuleExportService.resetLearningState(base));
    });
  });

  group('PageIndex', () {
    test('seltene Begriffe entscheiden, nur Seiten mit mindestens zwei Treffern, Limit und Aufwertung', () {
      final index = PageIndex(_folien);
      final query = SourceLocator.queryFor(_card('x', 'Wie lautet das Ohmsche Gesetz?', 'Spannung gleich Widerstand mal Strom'));
      final ranked = index.rank(query, limit: 3);
      expect(ranked.first.index, 1);
      expect(ranked.every((r) => r.hits >= 2), isTrue);
      expect(index.rank(query, limit: 1), hasLength(1));
      // Aufwertung dreht die Reihenfolge.
      final boosted = index.rank(query, limit: 3, boost: (i) => i == 3 ? 100 : 1);
      expect(boosted.first.index, 3);
      // Nur ein gemeinsamer Begriff reicht nicht.
      expect(index.rank(SourceLocator.queryFor(_card('y', 'Was ist ein Termin?', 'x'))), isEmpty);
    });
  });

  group('SourceLocator: Erklärung im Skript statt nur im Übungsblatt', () {
    final blatt = _material('blatt', ['Aufgabe 3: Wie lautet das Ohmsche Gesetz? Nennen Sie Spannung Widerstand Strom.'],
        kind: MaterialKind.exercise, name: 'Blatt 3.pdf');
    final folien = _material('folien', _folien);
    final card = _card('c', 'Wie lautet das Ohmsche Gesetz?', 'Spannung gleich Widerstand mal Strom',
        sourceId: 'blatt', page: 1);

    test('Übungsblatt-Frage: "Im Skript" landet auf der vermuteten Folie, die Aufgabe im Blatt', () async {
      final script = await SourceLocator().locate(card, materials: [blatt, folien]);
      expect(script!.material.id, 'folien');
      expect(script.page, 2);
      expect(script.guessed, isTrue);

      final worksheet = await SourceLocator().locate(card, materials: [blatt, folien], preferScript: false);
      expect(worksheet!.material.id, 'blatt');
      expect(worksheet.page, 1);
    });

    test('gefundene Fundstelle geht vor und gilt nicht als Vermutung', () async {
      final matched = card.copyWithScript(materialId: 'folien', page: 3);
      final script = await SourceLocator().locate(matched, materials: [blatt, folien]);
      expect(script!.page, 3);
      expect(script.guessed, isFalse);
      expect(script.pageText, contains('Kirchhoffsche'));
      // Die Aufgabe im Original bleibt erreichbar.
      final worksheet = await SourceLocator().locate(matched, materials: [blatt, folien], preferScript: false);
      expect(worksheet!.material.id, 'blatt');
    });

    test('ohne Treffer im Skript bleibt das Übungsblatt', () async {
      final other = _card('o', 'Photosynthese Chlorophyll?', 'Licht', sourceId: 'blatt', page: 1);
      final source = await SourceLocator().locate(other, materials: [blatt, folien]);
      expect(source!.material.id, 'blatt');
    });

    test('ohne Quelle sucht der Abgleich zuerst in den Folien, nicht im Übungsblatt', () async {
      final noSource = _card('n', 'Wie lautet das Ohmsche Gesetz?', 'Spannung gleich Widerstand mal Strom');
      final source = await SourceLocator().locate(noSource, materials: [blatt, folien]);
      expect(source!.material.id, 'folien');
    });
  });

  group('ScriptMatchService', () {
    final blatt = _material('blatt', ['Aufgabe 1'], kind: MaterialKind.exercise, name: 'Blatt.pdf');
    final folien = _material('folien', _folien);

    test('braucht einen Abgleich: Übungsblatt/ohne Quelle, noch nicht gesucht', () {
      final byId = {'blatt': blatt, 'folien': folien};
      expect(ScriptMatchService.needsMatch(_card('a', 'F', 'A', sourceId: 'blatt'), byId), isTrue);
      // Ohne bekannte Quelle nur auf ausdrücklichen Wunsch.
      expect(ScriptMatchService.needsMatch(_card('b', 'F', 'A'), byId), isFalse);
      expect(ScriptMatchService.needsMatch(_card('b', 'F', 'A'), byId, includeUnsourced: true), isTrue);
      expect(ScriptMatchService.needsMatch(_card('c', 'F', 'A', sourceId: 'folien'), byId), isFalse);
      final searched = _card('d', 'F', 'A', sourceId: 'blatt', scriptPage: 0);
      expect(ScriptMatchService.needsMatch(searched, byId), isFalse);
      expect(ScriptMatchService.needsMatch(searched, byId, force: true), isTrue);
    });

    test('lokale Kandidaten, die KI wählt die Seite mit der Erklärung', () async {
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        // Frage 1: die beste Kandidatin c1, Frage 2: keine passt.
        return _ok({
          'matches': [
            {'n': 1, 'page': 'c1'},
            {'n': 2, 'page': null},
          ],
        });
      });
      final ai = AiService(apiKey: 'k', model: 'm', client: client);
      final ohm = _card('ohm', 'Wie lautet das Ohmsche Gesetz?', 'Spannung gleich Widerstand mal Strom', sourceId: 'blatt');
      final vague = _card('vage', 'Wie sind Spannung und Leistung im Netzwerk verknüpft?', 'Watt', sourceId: 'blatt');
      final ohne = _card('ohne', 'Photosynthese Chlorophyll Licht?', 'Zucker', sourceId: 'blatt');
      final progress = <(int, int)>[];

      final run = await ScriptMatchService().match(
        [ohm, vague, ohne],
        materials: [blatt, folien],
        ai: ai,
        onProgress: (d, t) => progress.add((d, t)),
      );

      // Nur die Fragen mit Kandidaten gehen an die KI (eine Anfrage).
      expect(requests, hasLength(1));
      final prompt = jsonEncode(requests.single);
      expect(prompt, contains('Folien.pdf, Seite 2'));
      expect(prompt, contains('Ohmsche'));
      expect(prompt, isNot(contains('Photosynthese')));

      final byCard = {for (final m in run.matches) m.cardId: m};
      expect(byCard['ohm']!.found, isTrue);
      expect(byCard['ohm']!.materialId, 'folien');
      expect(byCard['ohm']!.page, 2);
      // KI sagt "keine passt" / keine Kandidaten: gesucht, nichts gefunden.
      expect(byCard['vage']!.found, isFalse);
      expect(byCard['ohne']!.found, isFalse);
      expect(run.found, 1);
      expect(run.failedCards, 0);
      expect(progress.last, (3, 3));
    });

    test('eine erfundene Kennung der KI zählt nicht; ein Fehler lässt die Fragen "ungesucht"', () async {
      final ohm = _card('ohm', 'Wie lautet das Ohmsche Gesetz?', 'Spannung gleich Widerstand mal Strom', sourceId: 'blatt');
      final invented = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((_) async => _ok({
              'matches': [
                {'n': 1, 'page': 'c99'},
              ],
            })),
      );
      final run1 = await ScriptMatchService().match([ohm], materials: [blatt, folien], ai: invented);
      expect(run1.matches.single.found, isFalse);

      final broken = AiService(apiKey: 'k', model: 'm', client: MockClient((_) async => http.Response('nope', 500)));
      final run2 = await ScriptMatchService().match([ohm], materials: [blatt, folien], ai: broken);
      expect(run2.matches, isEmpty);
      expect(run2.failedCards, 1);
    });

    test('ohne Folien-PDF passiert nichts (Übungsblätter sind kein Skript)', () async {
      final ai = AiService(apiKey: 'k', model: 'm', client: MockClient((_) async => throw StateError('kein Aufruf')));
      final run = await ScriptMatchService().match(
        [_card('a', 'Frage Ohmsche Gesetz Spannung?', 'Strom', sourceId: 'blatt')],
        materials: [blatt],
        ai: ai,
      );
      expect(run.matches, isEmpty);
    });
  });

  test('FlashcardRepository.updateScriptLocations ändert nur die Fundstelle, der Lernstand bleibt', () async {
    final repo = FlashcardRepository();
    final reviewed = _card('rep-1', 'Frage', 'Antwort', sourceId: 'blatt').copyWithReview(
      due: DateTime(2026, 10, 5),
      stability: 4,
      difficulty: 5,
      elapsedDays: 1,
      scheduledDays: 4,
      reps: 3,
      lapses: 0,
      state: 'review',
      lastReview: DateTime(2026, 9, 5),
      masteryBox: 2,
    );
    await repo.saveAll([reviewed, _card('rep-2', 'Zweite', 'A')]);
    final changed = await repo.updateScriptLocations({
      'rep-1': (materialId: 'folien', page: 12),
      'rep-2': (materialId: null, page: 0),
      'gibt-es-nicht': (materialId: 'folien', page: 1),
    });
    expect(changed, 2);

    final stored = await repo.loadById('rep-1');
    expect(stored!.scriptMaterialId, 'folien');
    expect(stored.scriptPage, 12);
    expect(stored.reps, 3);
    expect(stored.masteryBox, 2);
    expect(stored.sourceMaterialId, 'blatt');
    final none = await repo.loadById('rep-2');
    expect(none!.hasScript, isFalse);
    expect(none.scriptSearched, isTrue);
  });

  test('AiService.matchCardsToScript: nur Kennungen dieser Frage, sonst null', () async {
    final ai = AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((_) async => _ok({
            'matches': [
              {'n': 1, 'page': 'c2'},
              {'n': 2, 'page': 'c2'},
              {'n': 9, 'page': 'c1'},
            ],
          })),
    );
    final result = await ai.matchCardsToScript([
      (
        n: 1,
        type: 'Freitext',
        question: 'A?',
        answer: 'a',
        candidates: [(id: 'c1', label: 'x, Seite 1', text: 't1'), (id: 'c2', label: 'x, Seite 2', text: 't2')],
      ),
      (
        n: 2,
        type: 'Freitext',
        question: 'B?',
        answer: 'b',
        candidates: [(id: 'c1', label: 'x, Seite 3', text: 't3')],
      ),
    ]);
    expect(result[1], 'c2');
    expect(result[2], isNull); // c2 gehört nicht zu Frage 2
    expect(result.containsKey(9), isFalse);
  });
}
