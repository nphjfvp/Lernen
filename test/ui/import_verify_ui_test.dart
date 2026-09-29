import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/concept_repository.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/pdf_question_import_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/import/pdf_question_import_screen.dart';
import 'package:lernen/ui/review/review_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// PDF, dessen Seiten lesbaren Text haben (die Prüfung liest ihn).
Uint8List _textPdf(List<String> pages) {
  final document = PdfDocument();
  for (final text in pages) {
    document.pages.add().graphics.drawString(text, PdfStandardFont(PdfFontFamily.helvetica, 11));
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

const _pages = [
  'Aufgabe 1: Wie lautet das Ohmsche Gesetz? Nennen Sie die Formel.',
  'Aufgabe 2: Wie berechnet man den Widerstand R aus Spannung und Strom?',
];

http.Response _chat(Object content) => http.Response(
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

/// Die drei KI-Rollen des Imports, an ihrem Systemprompt erkannt:
/// Seiten-Scan, Prüfung (zweite KI) und Stufen-Erweiterung.
class _FakeAi {
  _FakeAi({this.verify, this.scanPages = const [1, 2]});

  /// Antwort der Prüfung (`missing`/`surplus`); null = "alles stimmt".
  final Map<String, dynamic> Function()? verify;

  /// Seiten, auf denen der erste Durchlauf eine Frage findet.
  final List<int> scanPages;

  final calls = <String>[];
  final models = <String>[];
  final verifyRequests = <String>[];

  static const questions = {
    1: 'Wie lautet das Ohmsche Gesetz?',
    2: 'Wie berechnet man den Widerstand R?',
  };

  late final MockClient client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    models.add(body['model'] as String);
    final messages = body['messages'] as List;
    final system = messages[0]['content'] as String;
    final user = messages[1]['content'];
    if (system.contains('unabhängiger Prüfer')) {
      calls.add('verify');
      verifyRequests.add(user as String);
      return _chat(verify?.call() ?? {'documentCount': 2, 'missing': [], 'surplus': []});
    }
    if (system.contains('erweiterst bereits übernommene Quizfragen')) {
      calls.add('stages');
      final numbered = RegExp(r'^(\d+)\. \[[^\]]*\] (.*?) — Lösung:', multiLine: true).allMatches(user as String);
      return _chat({
        'cards': [
          for (final m in numbered)
            {
              'n': int.parse(m.group(1)!),
              'level': 'schwer',
              // Bewusst in jeder Anfrage gleich benannt: der Dienst muss die Ordner eindeutig machen.
              'group': 'Ohm ${m.group(1)}',
              'variants': [
                {
                  'level': 'leicht',
                  'type': 'single_choice',
                  'front': 'Leicht: ${m.group(2)}',
                  'options': [
                    {'text': 'richtig', 'isCorrect': true},
                    {'text': 'falsch A', 'isCorrect': false},
                    {'text': 'falsch B', 'isCorrect': false},
                  ],
                },
              ],
            },
        ],
      });
    }
    // Seiten-Scan (auch "nur eine Aufgabe" beim Nachholen).
    final texts = [for (final c in user as List) if (c['type'] == 'text') c['text'] as String];
    final pages = [for (final m in RegExp(r'Dokument-Seite (\d+)').allMatches(texts.first)) int.parse(m.group(1)!)];
    final focused = texts.any((t) => t.contains('NUR EINE AUFGABE'));
    calls.add(focused ? 'scan-focus' : 'scan');
    return _chat({
      'questions': [
        for (final p in pages)
          if (focused || scanPages.contains(p))
            {
              'page': p,
              'type': 'free_text',
              'front': questions[p],
              'correctText': 'Antwort $p',
              'solutionFromDocument': true,
            },
      ],
    });
  });

  AiService ai(String apiKey, String model) => AiService(apiKey: apiKey, model: model, client: client);
}

Future<List<Flashcard>> _cardsOf(WidgetTester tester, String moduleId) async {
  final all = (await tester.runAsync(() async {
    final db = await DatabaseService.instance.database;
    return (await DatabaseService.flashcards.find(db)).map((r) => Flashcard.fromMap(r.value)).toList();
  }))!;
  return [for (final c in all) if (c.moduleId == moduleId) c];
}

Future<void> _settle(WidgetTester tester, bool Function() done, {int tries = 100}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_import_verify_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => ReviewScreen.aiFactory = ReviewScreen.importServiceFactory = null);

  group('Fragen aus PDF importieren', () {
    Future<void> open(WidgetTester tester, _FakeAi fake, {required String moduleId}) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final material = MaterialItem(
        id: 'blatt-$moduleId',
        moduleId: moduleId,
        fileName: 'Blatt.pdf',
        kind: MaterialKind.exercise,
        extractedText: '',
        createdAt: DateTime(2026, 9, 27),
        fileBytesBase64: base64Encode(_textPdf(_pages)),
      );
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MaterialRepository()),
          ChangeNotifierProvider(create: (_) => FlashcardRepository()),
          ChangeNotifierProvider(create: (_) => SettingsRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PdfQuestionImportScreen(
                  moduleId: moduleId,
                  material: material,
                  serviceFactory: () => PdfQuestionImportService(
                    ai: fake.ai('k', 'vision-modell'),
                    renderer: (_) async => null,
                  ),
                  aiFactory: (model) => fake.ai('k', model),
                ),
              )),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jede Frage'));
      await tester.pump();
    }

    testWidgets('Prüfung + Stufen: zweite KI begründet, Nachholen ergänzt, Import speichert Stufen und Ordner',
        (tester) async {
      final fake = _FakeAi(
        scanPages: const [1], // Seite 2 wird beim ersten Durchlauf übersehen
        verify: () => {
          'documentCount': 2,
          'missing': [
            {
              'page': 2,
              'task': 'Aufgabe 2: Wie berechnet man den Widerstand R aus Spannung und Strom?',
              'reason': 'Steht auf Seite 2, aber keine übernommene Frage deckt sie ab.',
            },
          ],
          'surplus': [],
        },
      );
      await open(tester, fake, moduleId: 'iv-a');

      // Vorher wählbar: Prüfung und Stufen.
      expect(find.byKey(const ValueKey('import-opt-verify')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-opt-verify')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('import-opt-stages')));
      await tester.pump();
      expect(find.byKey(const ValueKey('import-level-leicht')), findsOneWidget);
      // Mittel abwählen: nur leicht und schwer.
      await tester.tap(find.byKey(const ValueKey('import-level-mittel')));
      await tester.pump();

      await tester.tap(find.text('Fragen suchen'));
      await tester.pumpAndSettle();

      // Erst gescannt, dann Stufen (Text-Modell), dann die Prüfung (Zweitmeinungs-Modell).
      expect(fake.calls, ['scan', 'stages', 'verify']);
      expect(fake.models, ['vision-modell', const AppSettings().questionModelId, const AppSettings().crosscheckModelId]);
      expect(find.text('1 Frage auf 1 Seite gefunden (+ 1 ergänzte Stufe).'), findsOneWidget);
      // Die zweite KI bekam den Text beider Seiten und die übernommene Frage.
      expect(fake.verifyRequests.single, contains('=== Seite 2 ==='));
      expect(fake.verifyRequests.single, contains('Aufgabe 2: Wie berechnet man den Widerstand R'));
      expect(fake.verifyRequests.single, contains('1. (Seite 1) Wie lautet das Ohmsche Gesetz?'));

      expect(find.textContaining('Zweite KI zählt 2 Fragen im Dokument · übernommen: 1'), findsOneWidget);
      expect(find.textContaining('1 Abweichung (1 fehlt, 0 zu viel)'), findsOneWidget);
      expect(find.text('Fehlt im Import · Seite 2 · Blatt.pdf'), findsOneWidget);
      expect(find.textContaining('Steht auf Seite 2, aber keine übernommene Frage deckt sie ab.'), findsOneWidget);
      expect(find.text('Original · Schwer'), findsOneWidget);
      expect(find.textContaining('Stufe Leicht · von der KI ergänzt'), findsOneWidget);

      // Manuell entscheiden: die fehlende Aufgabe nachholen.
      await tester.tap(find.byKey(const ValueKey('import-finding-accept-0')));
      await tester.pumpAndSettle();
      expect(fake.calls.sublist(3), ['scan-focus', 'stages']);
      expect(find.text('✓ ergänzt'), findsOneWidget);
      expect(find.text('Nach der Prüfung ergänzt'), findsOneWidget);
      expect(find.text('2 Fragen auf 2 Seiten gefunden (+ 2 ergänzte Stufen).'), findsOneWidget);

      await tester.tap(find.text('4 Fragen importieren'));
      await _settle(tester, () => find.text('4 Fragen importiert').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.text('4 Fragen importiert'), findsOneWidget);
      await tester.tap(find.text('Fertig'));
      await tester.pumpAndSettle();

      final saved = await _cardsOf(tester, 'iv-a');
      expect(saved, hasLength(4));
      final byFront = {for (final c in saved) c.front: c};
      final original = byFront['Wie lautet das Ohmsche Gesetz?']!;
      final variant = byFront['Leicht: Wie lautet das Ohmsche Gesetz?']!;
      expect(original.stageLevel, 2);
      expect(variant.stageLevel, 0);
      expect(variant.type, QuestionType.singleChoice);
      // Original und Variante teilen sich einen Ordner; der nachgeholte hat einen eigenen.
      expect(variant.stageGroup, original.stageGroup);
      expect(original.stageGroup, startsWith('Ohm 1#'));
      expect(byFront['Wie berechnet man den Widerstand R?']!.stageGroup, startsWith('Ohm 1 2#'));
      expect(byFront['Leicht: Wie berechnet man den Widerstand R?']!.stageGroup,
          byFront['Wie berechnet man den Widerstand R?']!.stageGroup);
      // Alle wissen, wo im Blatt sie stehen.
      expect(original.sourceMaterialId, 'blatt-iv-a');
      expect(variant.sourcePage, 1);
      expect(byFront['Wie berechnet man den Widerstand R?']!.sourcePage, 2);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"Entfernen" wählt die überzählige Frage samt ihrer Stufen ab, "Behalten" lässt sie', (tester) async {
      final fake = _FakeAi(
        verify: () => {
          'documentCount': 1,
          'missing': [],
          'surplus': [
            {'n': 2, 'kind': 'not_in_document', 'reason': 'Im Dokument steht keine Aufgabe zum Widerstand.'},
            {'n': 1, 'kind': 'duplicate', 'reason': 'Steht zweimal in der Liste.'},
          ],
        },
      );
      await open(tester, fake, moduleId: 'iv-b');
      await tester.tap(find.byKey(const ValueKey('import-opt-verify')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('import-opt-stages')));
      await tester.pump();
      await tester.tap(find.text('Fragen suchen'));
      await tester.pumpAndSettle();

      // 2 Originale + 2 Stufen, alle ausgewählt.
      expect(find.text('4 Fragen importieren'), findsOneWidget);
      expect(find.text('Steht nicht im Dokument · Seite 2 · Blatt.pdf'), findsOneWidget);
      expect(find.text('Doppelt übernommen · Seite 1 · Blatt.pdf'), findsOneWidget);
      expect(find.textContaining('Im Dokument steht keine Aufgabe zum Widerstand.'), findsOneWidget);

      // Nach Seite sortiert: Seite 1 (Doppelt) zuerst, Seite 2 danach.
      await tester.tap(find.byKey(const ValueKey('import-finding-accept-1')));
      await tester.pump();
      expect(find.text('✓ entfernt'), findsOneWidget);
      expect(find.text('2 Fragen importieren'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-finding-dismiss-0')));
      await tester.pump();
      expect(find.text('behalten'), findsOneWidget);
      expect(find.text('2 Fragen importieren'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Ohne Optionen keine zusätzlichen Anfragen; "Jetzt prüfen" geht danach von Hand', (tester) async {
      final fake = _FakeAi();
      await open(tester, fake, moduleId: 'iv-c');
      await tester.tap(find.text('Fragen suchen'));
      await tester.pumpAndSettle();

      // 1:1 wie im Dokument, keine Stufen, keine Prüfung.
      expect(fake.calls, ['scan']);
      expect(find.text('2 Fragen auf 2 Seiten gefunden.'), findsOneWidget);
      expect(find.byKey(const ValueKey('import-check-summary')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('import-check-run')));
      await tester.pumpAndSettle();
      expect(fake.calls, ['scan', 'verify']);
      expect(find.textContaining('Zweite KI zählt 2 Fragen im Dokument · übernommen: 2'), findsOneWidget);
      expect(find.text('Beide KIs sehen dasselbe – nichts fehlt, nichts ist zu viel.'), findsOneWidget);
      expect(find.text('Erneut prüfen'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Nachbereiten → Fragen importieren', () {
    Future<void> openReview(WidgetTester tester, _FakeAi fake, {required String moduleId}) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ReviewScreen.aiFactory = fake.ai;
      ReviewScreen.importServiceFactory =
          (ai) => PdfQuestionImportService(ai: fake.ai(ai.apiKey, ai.model), renderer: (_) async => null);
      final settings = SettingsRepository();
      final materials = MaterialRepository();
      await tester.runAsync(() async {
        await settings.update(const AppSettings(openRouterApiKey: 'sk-test'));
        await materials.save(MaterialItem(
          id: 'rv-blatt',
          moduleId: moduleId,
          fileName: 'Blatt 3.pdf',
          kind: MaterialKind.exercise,
          extractedText: _pages.join('\n'),
          createdAt: DateTime(2026, 9, 27),
          fileBytesBase64: base64Encode(_textPdf(_pages)),
        ));
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: materials),
          ChangeNotifierProvider(create: (_) => FlashcardRepository()),
          ChangeNotifierProvider(create: (_) => ConceptRepository()),
          ChangeNotifierProvider(create: (_) => LectureUnitRepository()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: ReviewScreen(moduleId: moduleId)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fragen importieren').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorhandenes Material verwenden'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blatt 3.pdf'));
      await tester.pump();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
    }

    testWidgets('Optionen: Prüfung und Stufen, Nachholen, Entfernen und Speichern mit Stufen', (tester) async {
      final fake = _FakeAi(
        scanPages: const [1],
        verify: () => {
          'documentCount': 2,
          'missing': [
            {
              'page': 2,
              'task': 'Aufgabe 2: Wie berechnet man den Widerstand R aus Spannung und Strom?',
              'reason': 'Steht auf Seite 2, keine Frage deckt sie ab.',
            },
          ],
          'surplus': [],
        },
      );
      await openReview(tester, fake, moduleId: 'rv-a');

      // Beide Optionen erscheinen im Import-Modus (bei "KI erstellt" nicht).
      expect(find.byKey(const ValueKey('import-opt-verify')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-opt-verify')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('import-opt-stages')));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.file_download_outlined));
      await _settle(tester, () => find.text('Speichern').evaluate().isNotEmpty);
      await tester.pumpAndSettle();

      expect(fake.calls, ['scan', 'stages', 'verify']);
      expect(find.textContaining('Zweite KI zählt 2 Fragen im Dokument · übernommen: 1'), findsOneWidget);
      expect(find.text('Fehlt im Import · Seite 2 · Blatt 3.pdf'), findsOneWidget);
      expect(find.textContaining('Steht auf Seite 2, keine Frage deckt sie ab.'), findsOneWidget);
      expect(find.text('Original · Schwer'), findsOneWidget);
      expect(find.text('Stufe Leicht · von der KI ergänzt'), findsOneWidget);
      // Original + eine ergänzte Stufe.
      expect(find.textContaining('0 Konzepte, 2 Karteikarten'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('import-finding-accept-0')));
      await tester.pumpAndSettle();
      expect(find.text('✓ ergänzt'), findsOneWidget);
      expect(find.text('Nach der Prüfung ergänzt'), findsOneWidget);
      expect(find.textContaining('0 Konzepte, 4 Karteikarten'), findsOneWidget);

      // Eine Original-Frage aus der Vorschau löschen nimmt ihre Stufe mit.
      await tester.tap(find.byKey(const ValueKey('preview-remove-0')));
      await tester.pump();
      expect(find.textContaining('0 Konzepte, 2 Karteikarten'), findsOneWidget);
      expect(find.text('Leicht: Wie lautet das Ohmsche Gesetz?'), findsNothing);

      await tester.tap(find.text('Speichern'));
      await _settle(tester, () => find.byType(ReviewScreen).evaluate().isEmpty, tries: 60);
      await tester.pumpAndSettle();

      final saved = await _cardsOf(tester, 'rv-a');
      expect(saved.map((c) => c.front).toSet(),
          {'Wie berechnet man den Widerstand R?', 'Leicht: Wie berechnet man den Widerstand R?'});
      final variant = saved.firstWhere((c) => c.front == 'Leicht: Wie berechnet man den Widerstand R?');
      final original = saved.firstWhere((c) => c.front == 'Wie berechnet man den Widerstand R?');
      expect(variant.stageLevel, 0);
      expect(original.stageLevel, 2);
      expect(variant.stageGroup, isNotNull);
      expect(variant.stageGroup, original.stageGroup);
      expect(original.sourcePage, 2);
      expect(variant.sourceMaterialId, 'rv-blatt');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Ohne Optionen bleibt der Import 1:1; die Prüfung geht danach von Hand', (tester) async {
      final fake = _FakeAi();
      await openReview(tester, fake, moduleId: 'rv-b');
      await tester.tap(find.byIcon(Icons.file_download_outlined));
      await _settle(tester, () => find.text('Speichern').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(fake.calls, ['scan']);
      expect(find.textContaining('0 Konzepte, 2 Karteikarten'), findsOneWidget);
      expect(find.byKey(const ValueKey('import-check-summary')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('import-check-run')));
      await tester.pumpAndSettle();
      expect(fake.calls, ['scan', 'verify']);
      expect(find.text('Beide KIs sehen dasselbe – nichts fehlt, nichts ist zu viel.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
