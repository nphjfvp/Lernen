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
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/flashcards/flashcard_list_screen.dart';
import 'package:lernen/ui/study/script_match_runner.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SettingsWithKey extends SettingsRepository {
  _SettingsWithKey({this.withKey = true});
  final bool withKey;

  @override
  AppSettings get settings => AppSettings(openRouterApiKey: withKey ? 'sk-test' : null);
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

MaterialItem _material(String id, String moduleId, List<String> pages, MaterialKind kind, String name) => MaterialItem(
      id: id,
      moduleId: moduleId,
      fileName: name,
      kind: kind,
      extractedText: pages.join('\n'),
      createdAt: DateTime(2026, 9, 1),
      fileBytesBase64: base64Encode(_pdf(pages)),
    );

Flashcard _fromSheet(String id, String moduleId, {String? sourceId = 'blatt', int? scriptPage}) => Flashcard(
      id: id,
      moduleId: moduleId,
      front: 'Wie lautet das Ohmsche Gesetz?',
      back: 'Spannung gleich Widerstand mal Strom',
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      sourceMaterialId: sourceId,
      sourcePage: 1,
      scriptMaterialId: scriptPage == null ? null : 'folien',
      scriptPage: scriptPage,
    );

const _folien = [
  'Organisatorisches: Termine, Klausur, Sprechstunde',
  'Das Ohmsche Gesetz: Spannung U gleich Widerstand R mal Strom I',
  'Kirchhoffsche Regeln: Knotenregel und Maschenregel im Netzwerk',
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
    final dir = Directory.systemTemp.createTempSync('lernen_script_match_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => ScriptMatchContext.aiFactory = null);

  Future<MaterialRepository> materialsFor(WidgetTester tester, String moduleId, {bool withScript = true}) async {
    final materials = MaterialRepository();
    await tester.runAsync(() async {
      await materials.save(_material('blatt', moduleId, ['Aufgabe 1: Wie lautet das Ohmsche Gesetz?'],
          MaterialKind.exercise, 'Blatt 3.pdf'));
      if (withScript) await materials.save(_material('folien', moduleId, _folien, MaterialKind.slide, 'Folien.pdf'));
      await materials.loadForModule(moduleId);
    });
    return materials;
  }

  /// Lässt echte asynchrone Arbeit (Datenbank, PDF) laufen und pumpt dabei
  /// die Test-Uhr, bis [done] wahr ist.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done, {int tries = 100}) async {
    for (var i = 0; i < tries && !done(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Im Skript / Aufgabenblatt', () {
    Future<void> pumpCard(WidgetTester tester, Flashcard card, MaterialRepository materials) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>(create: (_) => _SettingsWithKey()),
          ChangeNotifierProvider.value(value: materials),
          ChangeNotifierProvider(create: (_) => ConceptRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: QuestionAnswerView(key: ValueKey(card.id), card: card, isNew: false, onComplete: ({selfGrade, isCorrect}) {}),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('vor dem Antworten: bei Übungsblatt-Fragen heißt der Knopf "Aufgabenblatt"', (tester) async {
      final materials = await materialsFor(tester, 'ui-a');
      await pumpCard(tester, _fromSheet('c1', 'ui-a'), materials);
      expect(find.byKey(const ValueKey('aid-source-early')), findsOneWidget);
      expect(find.text('Aufgabenblatt'), findsOneWidget);
      expect(find.text('Im Skript'), findsNothing);
    });

    testWidgets('Fragen aus den Folien behalten "Im Skript" vor dem Antworten', (tester) async {
      final materials = await materialsFor(tester, 'ui-b');
      await pumpCard(tester, _fromSheet('c2', 'ui-b', sourceId: 'folien'), materials);
      expect(find.text('Im Skript'), findsOneWidget);
      expect(find.text('Aufgabenblatt'), findsNothing);
    });
  });

  group('Skript-Abgleich in der Kartenliste', () {
    Future<void> pumpList(WidgetTester tester, String moduleId, SettingsRepository settings,
        MaterialRepository materials, FlashcardRepository cards) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          ChangeNotifierProvider.value(value: materials),
          ChangeNotifierProvider.value(value: cards),
          ChangeNotifierProvider(create: (_) => ConceptRepository()),
          ChangeNotifierProvider(create: (_) => LectureUnitRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: FlashcardListScreen(moduleId: moduleId, moduleName: 'Elektrotechnik'),
        ),
      ));
      await tester.pump();
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Weitere Aktionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erklärungen im Skript suchen'));
      await tester.pumpAndSettle();
    }

    testWidgets('KI wählt die Seite: Fundstelle steht danach an der Karte', (tester) async {
      final requests = <String>[];
      ScriptMatchContext.aiFactory = (key, model) => AiService(
            apiKey: key,
            model: model,
            client: MockClient((request) async {
              requests.add(request.body);
              return _ok({
                'matches': [
                  {'n': 1, 'page': 'c1'},
                ],
              });
            }),
          );
      final materials = await materialsFor(tester, 'ui-c');
      final cards = FlashcardRepository();
      await tester.runAsync(() async {
        await cards.saveAll([_fromSheet('c3', 'ui-c')]);
        await cards.loadForModule('ui-c');
      });
      await pumpList(tester, 'ui-c', _SettingsWithKey(), materials, cards);

      await openMenu(tester);
      expect(find.text('Erklärungen im Skript suchen?'), findsOneWidget);
      expect(find.textContaining('für 1 Frage aus Übungsblättern'), findsOneWidget);
      await tester.tap(find.text('Suchen'));
      await pumpUntil(tester, () => find.textContaining('Erklärung im Skript, S. 2').evaluate().isNotEmpty);

      expect(requests, hasLength(1));
      expect(requests.single, contains('Folien.pdf, Seite 2'));
      expect(find.textContaining('Erklärung im Skript, S. 2'), findsOneWidget);
      expect(find.textContaining('1 von 1 Fragen im Skript verortet'), findsOneWidget);
      final stored = await tester.runAsync(() => cards.loadById('c3'));
      expect(stored!.scriptMaterialId, 'folien');
      expect(stored.scriptPage, 2);
      expect(stored.sourceMaterialId, 'blatt'); // das Übungsblatt bleibt

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ohne API-Key gibt es eine verständliche Meldung', (tester) async {
      final cards = FlashcardRepository();
      final materials = await materialsFor(tester, 'ui-d');
      await tester.runAsync(() async {
        await cards.saveAll([_fromSheet('c4', 'ui-d')]);
        await cards.loadForModule('ui-d');
      });

      await pumpList(tester, 'ui-d', _SettingsWithKey(withKey: false), materials, cards);
      await openMenu(tester);
      expect(find.textContaining('OpenRouter-API-Key'), findsOneWidget);
    });

    testWidgets('ohne Folien-PDF im Fach gibt es eine verständliche Meldung', (tester) async {
      final cards = FlashcardRepository();
      final withoutScript = await materialsFor(tester, 'ui-f', withScript: false);
      await tester.runAsync(() async {
        await cards.saveAll([_fromSheet('c7', 'ui-f')]);
        await cards.loadForModule('ui-f');
      });

      await pumpList(tester, 'ui-f', _SettingsWithKey(), withoutScript, cards);
      await openMenu(tester);
      await pumpUntil(tester, () => find.textContaining('kein Skript (Folien als PDF)').evaluate().isNotEmpty);
      expect(find.textContaining('kein Skript (Folien als PDF)'), findsOneWidget);
      expect(find.text('Erklärungen im Skript suchen?'), findsNothing);
    });
  });

  testWidgets('nach dem Erstellen: matchNewCardsToScript sucht im Hintergrund und meldet das Ergebnis', (tester) async {
    ScriptMatchContext.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((_) async => _ok({
                'matches': [
                  {'n': 1, 'page': 'c1'},
                ],
              })),
        );
    final materials = await materialsFor(tester, 'ui-e');
    final cards = FlashcardRepository();
    final fresh = _fromSheet('c5', 'ui-e');
    // Eine Folien-Frage braucht keinen Abgleich.
    final fromSlides = _fromSheet('c6', 'ui-e', sourceId: 'folien');
    await tester.runAsync(() async {
      await cards.saveAll([fresh, fromSlides]);
      await cards.loadForModule('ui-e');
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsRepository>(create: (_) => _SettingsWithKey()),
        ChangeNotifierProvider.value(value: materials),
        ChangeNotifierProvider.value(value: cards),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => matchNewCardsToScript(context, [fresh, fromSlides]),
              child: const Text('Speichern'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Speichern'));
    await tester.pump();
    await pumpUntil(tester, () => find.textContaining('Suche die Erklärungen zu 1 Frage im Skript').evaluate().isNotEmpty);
    expect(find.textContaining('Suche die Erklärungen zu 1 Frage im Skript'), findsOneWidget);

    // Das Ergebnis erscheint, sobald die erste Meldung ausgelaufen ist.
    await pumpUntil(tester, () => find.textContaining('im Skript verortet').evaluate().isNotEmpty, tries: 200);
    expect(find.textContaining('1 von 1 Fragen im Skript verortet'), findsOneWidget);
    final stored = await tester.runAsync(() => cards.loadById('c5'));
    expect(stored!.scriptPage, 2);
    final untouched = await tester.runAsync(() => cards.loadById('c6'));
    expect(untouched!.scriptSearched, isFalse);

    await tester.pumpWidget(const SizedBox());
  });
}
