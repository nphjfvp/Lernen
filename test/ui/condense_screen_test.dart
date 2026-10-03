import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/material_file_store.dart';
import 'package:lernen/services/pdf_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/condense/condense_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Uint8List _pdf(List<List<String>> pages) {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (final lines in pages) {
    final page = document.pages.add();
    for (var i = 0; i < lines.length; i++) {
      page.graphics.drawString(lines[i], font, bounds: Rect.fromLTWH(30, 40.0 + i * 30, 540, 20));
    }
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

/// Eine Vorlesung mit vier Seiten: Organisatorisches, partielle Integration (zwei
/// Blöcke), Geschichte, Substitution.
final _lecture = _pdf([
  ['Organisatorisches', 'Klausurtermin am Freitag'],
  [
    'Partielle Integration: Herleitung aus der Produktregel durch Integrieren beider Seiten',
    'Die Produktregel besagt, dass die Ableitung von u mal v gleich u strich v plus u v strich ist.',
    'Integriert man beide Seiten, so bleibt auf der linken Seite das Produkt u mal v stehen.',
    'Stellt man um, erhaelt man die bekannte Formel der partiellen Integration fuer Integrale.',
    'Bedingung: u und v muessen differenzierbar sein, sonst gilt die Formel nicht.',
  ],
  ['Geschichte der Analysis', 'Beispiel: Berechne x mal e hoch x'],
  ['Substitution', 'Ersetze g von x durch t und passe die Grenzen an.'],
]);

final _exercise = _pdf([
  ['Aufgabe 1: Berechne das Integral von x mal e hoch x.', 'Aufgabe 2: Berechne das Integral von 2x mal cos von x quadrat.'],
]);

http.Response _chat(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

bool _isAnalysis(Map<String, dynamic> request) =>
    ((request['messages'] as List).first['content'] as String).contains('auf das Nötige zu kürzen');

var _moduleCounter = 0;

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_condense_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() {
    CondenseScreen.aiFactory = null;
    CondenseScreen.pickFilesHook = null;
  });

  Map<String, dynamic> selectionAnswer() => {
        'sections': [
          {'title': 'Partielle Integration', 'kind': 'erklaerung', 'why': 'Aufgabe 1', 'blocks': ['2.1-2.2'], 'covers': ['n1']},
          {'title': 'Beispiel', 'kind': 'beispiel', 'why': 'ähnliche Aufgabe', 'blocks': ['3.1'], 'covers': []},
          {'title': 'Substitution', 'kind': 'erklaerung', 'why': 'Aufgabe 2', 'blocks': ['4.1'], 'covers': ['n2']},
        ],
        'skipped': ['Organisatorisches', 'Geschichte'],
      };

  void useAi({Map<String, dynamic>? selection, List<String> needs = const ['Partielle Integration', 'Substitution']}) {
    CondenseScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            final request = jsonDecode(r.body) as Map<String, dynamic>;
            if (_isAnalysis(request)) {
              return _chat(jsonEncode({'tasks': ['Aufgabe 1', 'Aufgabe 2'], 'needs': needs}));
            }
            return _chat(jsonEncode(selection ?? selectionAnswer()));
          }),
        );
  }

  late MaterialRepository materials;
  late String moduleId;

  Future<void> pump(
    WidgetTester tester, {
    MaterialItem? lecture,
    bool pdfLecture = true,
    String? lectureId,
    bool withKey = true,
    bool secondLecture = false,
  }) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    moduleId = 'm-condense-${_moduleCounter++}';
    final settings = SettingsRepository();
    materials = MaterialRepository();
    await tester.runAsync(() async {
      await settings.update(AppSettings(openRouterApiKey: withKey ? 'sk-test' : null));
      if (lecture != null || pdfLecture) {
        final id = 'lecture-$moduleId';
        String? filePath;
        String? base64;
        if (pdfLecture) (filePath, base64) = await MaterialFileStore.store(id, _lecture);
        await materials.save(MaterialItem(
          id: id,
          moduleId: moduleId,
          fileName: pdfLecture ? 'Analysis.pdf' : 'Skript.pptx',
          kind: MaterialKind.slide,
          extractedText: pdfLecture ? 'Analysis' : '--- Folie 1 ---\nOrganisatorisches\n\n--- Folie 2 ---\nPartielle Integration ist wichtig.\nFormel und Bedingung.',
          createdAt: DateTime(2026, 9, 1),
          filePath: filePath,
          fileBytesBase64: base64,
        ));
      }
    });
    if (secondLecture) {
      await tester.runAsync(
        () => materials.save(MaterialItem(
          id: 'second-$moduleId',
          moduleId: moduleId,
          fileName: 'Algebra.pptx',
          kind: MaterialKind.slide,
          extractedText: '--- Folie 1 ---\nGruppen',
          createdAt: DateTime(2026, 9, 2),
        )),
      );
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: materials),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CondenseScreen(moduleId: moduleId, lectureId: lectureId)),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, Finder finder, {int tries = 80}) async {
    for (var i = 0; i < tries && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  Future<void> uploadExercise(WidgetTester tester) async {
    CondenseScreen.pickFilesHook = () async => [(name: 'Blatt 3.pdf', bytes: _exercise)];
    await tester.tap(find.byKey(const ValueKey('condense-upload')));
    await waitFor(tester, find.byKey(const ValueKey('condense-exercise-0')));
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('condense-start')));
    await waitFor(tester, find.byKey(const ValueKey('condense-summary')));
  }

  testWidgets('ohne Vorlesung im Fach: Hinweis, Start gesperrt', (tester) async {
    await pump(tester, pdfLecture: false);
    expect(find.byKey(const ValueKey('condense-no-lecture')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('condense-start'))).onPressed, isNull);
  });

  testWidgets('Start braucht Aufgaben oder einen Auftrag', (tester) async {
    await pump(tester);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('condense-start'))).onPressed, isNotNull);
    await tester.enterText(find.byKey(const ValueKey('condense-prompt')), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('condense-start'))).onPressed, isNull);
    await uploadExercise(tester);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('condense-start'))).onPressed, isNotNull);
  });

  testWidgets('Aufgaben hochladen legen sie als Übungsblatt im Fach ab; entfernen aus der Auswahl geht', (tester) async {
    await pump(tester);
    await uploadExercise(tester);
    final saved = materials.forModule(moduleId).where((m) => m.kind == MaterialKind.exercise).toList();
    expect(saved.single.fileName, 'Blatt 3.pdf');
    expect(saved.single.extractedText, contains('Aufgabe 1'));
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    expect(find.byKey(const ValueKey('condense-exercise-0')), findsNothing);
  });

  testWidgets('ganzer Ablauf: kürzen, Vorschau, Beispiele und Abschnitte abwählen, speichern', (tester) async {
    useAi();
    await pump(tester);
    await uploadExercise(tester);
    await start(tester);

    // Seiten 2, 3 (Beispiel) und 4 – ohne Organisatorisches.
    expect(find.text('3 von 4 Seiten behalten (75 %)'), findsOneWidget);
    expect(find.text('Seiten 2–4'), findsOneWidget);
    expect(find.textContaining('Weggelassen (2)'), findsOneWidget);
    expect(find.text('Partielle Integration'), findsOneWidget);

    // Ohne Beispielaufgaben fällt Seite 3 weg.
    await tester.tap(find.byKey(const ValueKey('condense-examples')));
    await tester.pump();
    expect(find.text('2 von 4 Seiten behalten (50 %)'), findsOneWidget);
    expect(find.text('Seiten 2, 4'), findsOneWidget);

    // Einen Abschnitt abwählen: nur noch Seite 2.
    await tester.tap(find.byKey(const ValueKey('condense-section-2')));
    await tester.pump();
    expect(find.text('1 von 4 Seiten behalten (25 %)'), findsOneWidget);
    // Substitution (n2) wird jetzt nicht mehr erklärt.
    expect(find.byKey(const ValueKey('condense-notfound')), findsOneWidget);
    expect(find.textContaining('Substitution'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('condense-section-2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('condense-notfound')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('condense-save')));
    await waitFor(tester, find.text('Öffnen'));
    await tester.pumpAndSettle();

    final condensed = materials.forModule(moduleId).where((m) => m.kind == MaterialKind.condensed).single;
    expect(condensed.fileName, 'Analysis – gekürzt.pdf');
    expect(condensed.condensed!.pages, [2, 4]);
    expect(condensed.condensed!.totalPages, 4);
    expect(condensed.condensed!.includeExamples, isFalse);
    expect(condensed.condensed!.markers, isTrue);
    expect(condensed.condensed!.exerciseNames, ['Blatt 3.pdf']);
    expect(condensed.condensed!.skipped, ['Organisatorisches', 'Geschichte']);
    expect(condensed.extractedText, contains('Partielle Integration'));
    expect(condensed.extractedText, contains('Ersetze g von x durch t'));
    expect(condensed.extractedText, isNot(contains('Klausurtermin')));
    expect(condensed.extractedText, isNot(contains('Geschichte')));
    expect(condensed.hasViewablePdf, isTrue);

    final bytes = (await tester.runAsync(
      () => MaterialFileStore.load(filePath: condensed.filePath, fileBytesBase64: condensed.fileBytesBase64),
    ))!;
    final pages = PdfService().extractPageTexts(bytes);
    expect(pages, hasLength(2));
    expect(pages[0], contains('Original: S. 2'));
    expect(pages[1], contains('Original: S. 4'));
    expect(find.textContaining('Gekürzt gespeichert'), findsOneWidget);
  });

  testWidgets('ohne Markierungen enthält die PDF weder Stempel noch Streifen', (tester) async {
    useAi();
    await pump(tester);
    await uploadExercise(tester);
    await start(tester);
    await tester.tap(find.byKey(const ValueKey('condense-markers')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('condense-save')));
    await waitFor(tester, find.text('Öffnen'));
    await tester.pumpAndSettle();
    final condensed = materials.forModule(moduleId).where((m) => m.kind == MaterialKind.condensed).single;
    expect(condensed.condensed!.markers, isFalse);
    final bytes = (await tester.runAsync(
      () => MaterialFileStore.load(filePath: condensed.filePath, fileBytesBase64: condensed.fileBytesBase64),
    ))!;
    expect(PdfService().extractPageTexts(bytes).join(), isNot(contains('Original')));
  });

  testWidgets('Vorlesung ohne PDF: nur die Textfassung, Markierungen gesperrt', (tester) async {
    CondenseScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            final request = jsonDecode(r.body) as Map<String, dynamic>;
            if (_isAnalysis(request)) return _chat(jsonEncode({'needs': ['Partielle Integration']}));
            return _chat(jsonEncode({
              'sections': [
                {'title': 'Partielle Integration', 'blocks': ['2.1'], 'covers': ['n1']},
              ],
            }));
          }),
        );
    await pump(tester, pdfLecture: false, lecture: MaterialItem(id: 'x', moduleId: 'x', fileName: 'x', kind: MaterialKind.slide, extractedText: 'x', createdAt: DateTime(2026)));
    await start(tester);
    expect(find.text('1 von 2 Folien behalten (50 %)'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('condense-markers'))).onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('condense-save')));
    await waitFor(tester, find.text('Öffnen'));
    await tester.pumpAndSettle();
    final condensed = materials.forModule(moduleId).where((m) => m.kind == MaterialKind.condensed).single;
    expect(condensed.fileName, 'Skript – gekürzt');
    expect(condensed.hasViewablePdf, isFalse);
    expect(condensed.condensed!.label, 'Folie');
    expect(condensed.extractedText, contains('Partielle Integration ist wichtig.'));
  });

  testWidgets('Fehler der KI: zurück zu den Angaben mit Meldung, nichts gespeichert', (tester) async {
    CondenseScreen.aiFactory = (key, model) => AiService(apiKey: key, model: model, client: MockClient((_) async => http.Response('kaputt', 500)));
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('condense-start')));
    await waitFor(tester, find.byKey(const ValueKey('condense-error')));
    expect(find.textContaining('500'), findsWidgets);
    expect(find.byKey(const ValueKey('condense-start')), findsOneWidget);
    expect(materials.forModule(moduleId).where((m) => m.kind == MaterialKind.condensed), isEmpty);
  });

  testWidgets('ohne API-Key: Hinweis statt Start', (tester) async {
    await pump(tester, withKey: false);
    await tester.tap(find.byKey(const ValueKey('condense-start')));
    await tester.pump();
    expect(find.textContaining('OpenRouter-Key'), findsWidgets);
    expect(find.byKey(const ValueKey('condense-summary')), findsNothing);
  });

  testWidgets('Abbrechen während des Laufs verwirft das Ergebnis', (tester) async {
    CondenseScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            final request = jsonDecode(r.body) as Map<String, dynamic>;
            if (_isAnalysis(request)) return _chat(jsonEncode({'needs': ['A']}));
            return _chat(jsonEncode(selectionAnswer()));
          }),
        );
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('condense-start')));
    await waitFor(tester, find.byKey(const ValueKey('condense-cancel')));
    await tester.tap(find.byKey(const ValueKey('condense-cancel')));
    await tester.pump();
    // Die laufenden Anfragen werden noch zu Ende geführt, ihr Ergebnis zählt nicht mehr.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('condense-summary')), findsNothing);
    expect(find.byKey(const ValueKey('condense-start')), findsOneWidget);
  });

  testWidgets('Zurück aus der Vorschau fragt nach, weil das Ergebnis noch nicht gespeichert ist', (tester) async {
    useAi();
    await pump(tester);
    await start(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Ergebnis verwerfen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('condense-summary')), findsOneWidget);
  });

  testWidgets('mehrere Vorlesungen: ohne Vorwahl muss man wählen, mit Vorwahl steht sie schon da', (tester) async {
    await pump(tester, secondLecture: true);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('condense-start'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('condense-lecture')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analysis.pdf').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('condense-start'))).onPressed, isNotNull);
  });

  testWidgets('aus dem Menü einer Folie vorgewählt', (tester) async {
    await pump(tester, secondLecture: true, lectureId: 'second-m-condense-$_moduleCounter');
    expect(find.text('Algebra.pptx (nur Text)'), findsOneWidget);
    expect(find.text('Analysis.pdf'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('condense-start'))).onPressed, isNotNull);
  });
}
