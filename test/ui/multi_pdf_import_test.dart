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

Uint8List _pdf(int pages, String prefix) {
  final document = PdfDocument();
  for (var i = 1; i <= pages; i++) {
    document.pages.add().graphics.drawString('$prefix Seite $i', PdfStandardFont(PdfFontFamily.helvetica, 12));
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

MaterialItem _material(String id, String name, int pages, {String? unitId}) => MaterialItem(
      id: id,
      moduleId: 'mp-m',
      fileName: name,
      kind: MaterialKind.exercise,
      extractedText: '',
      createdAt: DateTime(2026, 9, 27),
      fileBytesBase64: base64Encode(_pdf(pages, name)),
      unitId: unitId,
    );

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

List<int> _shown(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final text = ((body['messages'] as List)[1]['content'] as List).first['text'] as String;
  return [for (final m in RegExp(r'Dokument-Seite (\d+)').allMatches(text)) int.parse(m.group(1)!)];
}

String _system(http.Request request) => ((jsonDecode(request.body) as Map)['messages'] as List)[0]['content'] as String;

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_multi_pdf_import_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  Future<MaterialRepository> pump(WidgetTester tester, MockClient client, List<MaterialItem> materials) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = MaterialRepository();
    await tester.runAsync(() async {
      for (final m in materials) {
        await repo.save(m);
      }
      await repo.loadForModule('mp-m');
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider(create: (_) => SettingsRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: PdfQuestionImportScreen(
          moduleId: 'mp-m',
          serviceFactory: () => PdfQuestionImportService(
            ai: AiService(apiKey: 'k', model: 'vision', client: client),
            renderer: (_) async => null,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('mehrere PDFs auf einmal: alles wird fortlaufend gelesen, jede Frage kennt ihre Datei', (tester) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final shown = _shown(request);
      final rolling = _system(request).contains('FORTLAUFENDER IMPORT');
      return _chat({
        'pages': [for (final p in shown) {'page': p, 'tasks': 1}],
        'questions': [
          for (final p in shown)
            if (!(rolling && p == shown.first))
              {
                'page': p,
                'type': 'free_text',
                'front': 'Frage ${requests.length}/$p?',
                'correctText': 'Antwort',
                'solutionFromDocument': true,
              },
        ],
        'revisions': [],
      });
    });
    await pump(tester, client, [
      _material('mp-a', 'Blatt A.pdf', 6, unitId: 'u-a'),
      _material('mp-b', 'Blatt B.pdf', 2),
    ]);

    // Beide PDFs des Fachs liegen zur Wahl; "Alle hinzufügen" nimmt sie zusammen.
    expect(find.byKey(const ValueKey('import-material-mp-a')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-add-all')));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('import-file-1')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('6 Seiten'), findsOneWidget);
    expect(find.text('2 Seiten'), findsOneWidget);
    // Bei mehreren PDFs gibt es keinen Seitenbereich – es wird alles gelesen.
    expect(find.byKey(const ValueKey('import-from')), findsNothing);
    expect(find.text('Alle 8 Seiten aller 2 PDFs werden gelesen – ohne Begrenzung.'), findsOneWidget);
    // Blatt A: zwei Abschnitte (1–4 | 4,5,6), Blatt B: einer → 3 Anfragen.
    expect(find.textContaining('3 KI-Anfragen an dein Vision-Modell'), findsOneWidget);

    await tester.tap(find.text('Jede Frage'));
    await tester.pump();
    await tester.tap(find.text('Fragen suchen'));
    await tester.pumpAndSettle();

    expect(requests, hasLength(3));
    final shown = requests.map(_shown).toList();
    expect(shown, containsAll([
      [1, 2, 3, 4],
      [4, 5, 6],
      [1, 2],
    ]));
    expect(find.text('8 Fragen auf 8 Seiten in 2 PDFs gefunden.'), findsOneWidget);
    expect(find.text('Blatt A.pdf · Seite 4'), findsOneWidget);
    expect(find.text('Blatt B.pdf · Seite 2'), findsOneWidget);

    await tester.tap(find.text('8 Fragen importieren'));
    for (var i = 0; i < 40 && find.text('8 Fragen importiert').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('8 Fragen importiert'), findsOneWidget);
    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();

    final saved = (await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      return (await DatabaseService.flashcards.find(db)).map((r) => Flashcard.fromMap(r.value)).toList();
    }))!
        .where((c) => c.moduleId == 'mp-m')
        .toList();
    expect(saved, hasLength(8));
    final fromA = saved.where((c) => c.sourceMaterialId == 'mp-a').toList();
    final fromB = saved.where((c) => c.sourceMaterialId == 'mp-b').toList();
    expect(fromA, hasLength(6));
    expect(fromB, hasLength(2));
    expect(fromA.map((c) => c.sourcePage).toSet(), {1, 2, 3, 4, 5, 6});
    expect(fromA.every((c) => c.unitId == 'u-a'), isTrue);
    expect(fromB.every((c) => c.unitId == null), isTrue);
    expect(saved.every((c) => c.priorityIntroduction), isTrue);
  });

  testWidgets('ein fehlgeschlagener Abschnitt lässt sich einzeln wiederholen; Dateien lassen sich wieder entfernen',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final shown = _shown(request);
      // Der zweite Abschnitt [4 | 5, 6] scheitert beim ersten Versuch.
      if (calls == 2) return http.Response('boom', 500);
      return _chat({
        'pages': [for (final p in shown) {'page': p, 'tasks': 1}],
        'questions': [
          for (final p in shown)
            {'page': p, 'type': 'free_text', 'front': 'Frage auf Seite $p (Aufruf $calls)?', 'correctText': 'A'},
        ],
      });
    });
    await pump(tester, client, [_material('mp-c', 'Blatt C.pdf', 6), _material('mp-d', 'Blatt D.pdf', 1)]);

    await tester.tap(find.byKey(const ValueKey('import-material-mp-c')));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('import-file-0')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Eine PDF: Seitenbereich einstellbar, die andere liegt noch zur Wahl.
    expect(find.byKey(const ValueKey('import-from')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-material-mp-d')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-material-mp-d')));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('import-file-1')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('import-from')), findsNothing);
    // Wieder entfernen: die Datei liegt erneut zur Wahl, der Bereich kommt zurück.
    await tester.tap(find.byKey(const ValueKey('import-remove-file-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('import-file-1')), findsNothing);
    expect(find.byKey(const ValueKey('import-material-mp-d')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-from')), findsOneWidget);

    await tester.tap(find.text('Jede Frage'));
    await tester.pump();
    await tester.tap(find.text('Fragen suchen'));
    await tester.pumpAndSettle();

    // Seiten 1–4 gelesen; [5, 6] fehlen (Abschnitt 2 ist ausgefallen).
    expect(find.text('4 Fragen auf 4 Seiten gefunden.'), findsOneWidget);
    expect(find.textContaining('Seite 5–6'), findsOneWidget);
    expect(find.text('Fehlgeschlagene Seiten erneut versuchen (1)'), findsOneWidget);

    await tester.tap(find.text('Fehlgeschlagene Seiten erneut versuchen (1)'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.text('6 Fragen auf 6 Seiten gefunden.'), findsOneWidget);
    expect(find.textContaining('erneut versuchen'), findsNothing);
    // Nach Seite sortiert, die nachgeholten Seiten 5 und 6 stehen hinter 4.
    expect(find.text('Seite 5'), findsOneWidget);
    expect(find.text('Seite 6'), findsOneWidget);
  });

  testWidgets('Nachbereiten → Fragen importieren: mehrere PDFs auf einmal, Lösungen aus der Musterlösung nachgeschlagen',
      (tester) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final shown = _shown(request);
      final text = [
        for (final c in ((jsonDecode(request.body) as Map)['messages'] as List)[1]['content'] as List)
          if (c['type'] == 'text') c['text'],
      ].join('\n');
      // Nur die Anfragen für das Blatt kennen die Musterlösung als Nachschlagewerk.
      final isSheet = text.contains('=== Lösung.pdf, Seite 1 ===');
      return _chat({
        'pages': [for (final p in shown) {'page': p, 'tasks': 1}],
        'questions': [
          for (final p in shown)
            {
              'page': p,
              'type': 'free_text',
              'front': '${isSheet ? 'Blatt' : 'Lösung'}-Frage $p?',
              'correctText': 'A',
              'solutionFromDocument': true,
            },
        ],
      });
    });
    ReviewScreen.aiFactory = (key, model) => AiService(apiKey: key, model: model, client: client);
    ReviewScreen.importServiceFactory =
        (ai) => PdfQuestionImportService(ai: AiService(apiKey: ai.apiKey, model: ai.model, client: client), renderer: (_) async => null);
    final settings = SettingsRepository();
    final materials = MaterialRepository();
    await tester.runAsync(() async {
      await settings.update(const AppSettings(openRouterApiKey: 'sk-test'));
      await materials.save(MaterialItem(
        id: 'rm-blatt',
        moduleId: 'rm-m',
        fileName: 'Blatt.pdf',
        kind: MaterialKind.exercise,
        extractedText: 'Blatt Seite 1',
        createdAt: DateTime(2026, 9, 27),
        fileBytesBase64: base64Encode(_pdf(3, 'Blatt')),
      ));
      await materials.save(MaterialItem(
        id: 'rm-loesung',
        moduleId: 'rm-m',
        fileName: 'Lösung.pdf',
        kind: MaterialKind.exercise,
        extractedText: 'Lösung Seite 1',
        createdAt: DateTime(2026, 9, 27),
        fileBytesBase64: base64Encode(_pdf(1, 'Lösung')),
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
      child: MaterialApp(theme: AppTheme.light, home: const ReviewScreen(moduleId: 'rm-m')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fragen importieren').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vorhandenes Material verwenden'));
    await tester.pumpAndSettle();
    // Beide PDFs auf einmal wählen.
    await tester.tap(find.text('Blatt.pdf'));
    await tester.pump();
    await tester.tap(find.text('Lösung.pdf'));
    await tester.pump();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Übung ansehen'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.file_download_outlined));
    for (var i = 0; i < 80 && find.text('Speichern').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Blatt (3 Seiten) und Lösung (1 Seite): je ein Abschnitt.
    expect(requests, hasLength(2));
    expect(find.textContaining('0 Konzepte, 4 Karteikarten'), findsOneWidget);
    expect(find.text('Blatt-Frage 3?'), findsOneWidget);
    expect(find.text('Lösung-Frage 1?'), findsOneWidget);

    await tester.tap(find.text('Speichern'));
    for (var i = 0; i < 40 && find.byType(ReviewScreen).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(() async {
      final db = await DatabaseService.instance.database;
      return (await DatabaseService.flashcards.find(db)).map((r) => Flashcard.fromMap(r.value)).toList();
    }))!
        .where((c) => c.moduleId == 'rm-m')
        .toList();
    expect(saved, hasLength(4));
    expect(saved.where((c) => c.sourceMaterialId == 'rm-blatt').map((c) => c.sourcePage).toSet(), {1, 2, 3});
    expect(saved.where((c) => c.sourceMaterialId == 'rm-loesung').map((c) => c.sourcePage), [1]);

    await tester.pumpWidget(const SizedBox());
    ReviewScreen.aiFactory = ReviewScreen.importServiceFactory = null;
  });
}
