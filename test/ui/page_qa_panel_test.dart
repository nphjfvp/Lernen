import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/page_note.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/widgets/page_qa_panel.dart';
import 'package:provider/provider.dart';

class _Settings extends SettingsRepository {
  _Settings({this.withKey = true});
  final bool withKey;

  @override
  AppSettings get settings => AppSettings(openRouterApiKey: withKey ? 'sk-test' : null);
}

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

Widget _app(Widget child, {bool withKey = true}) => ChangeNotifierProvider<SettingsRepository>.value(
      value: _Settings(withKey: withKey),
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: Scaffold(body: child)),
    );

void main() {
  tearDown(() => PageQaPanel.aiFactory = null);

  testWidgets('Frage: die aktuell angezeigte Seite wird erfasst, die Antwort ist markierbar und speicherbar', (tester) async {
    final requests = <Map<String, dynamic>>[];
    PageQaPanel.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((request) async {
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return _chat('Der Trigger startet die Aufzeichnung.');
          }),
        );
    final controller = PageQaController();
    addTearDown(controller.dispose);
    var page = 4;
    final saved = <PageNote>[];
    var notes = <PageNote>[];

    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, setState) => PageQaPanel(
        controller: controller,
        documentText: 'Dokumenttext',
        capturePage: () async => (image: Uint8List.fromList([1, 2, 3]), page: page, total: 14),
        currentPage: page,
        totalPages: 14,
        notes: notes,
        onSaveNote: (n) async {
          saved.add(n);
          setState(() => notes = [...notes, n]);
        },
      ),
    )));

    expect(find.text('Seite 4 von 14 · sieht die angezeigte Seite + den Dokumenttext'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('qa-input')), 'Was macht der Trigger?');
    await tester.tap(find.byKey(const ValueKey('qa-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(requests, hasLength(1));
    expect(controller.turns.single.page, 4);
    expect(find.text('Der Trigger startet die Aufzeichnung.'), findsOneWidget);
    // Alles darin lässt sich markieren.
    expect(find.byType(SelectionArea), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('qa-save-0')));
    await tester.pump();
    await tester.pump();
    expect(saved, hasLength(1));
    expect(saved.single.page, 4);
    expect(saved.single.question, 'Was macht der Trigger?');
    expect(saved.single.text, 'Der Trigger startet die Aufzeichnung.');
    expect(find.textContaining('Als Notiz auf Seite 4 gespeichert'), findsOneWidget);
    // Zweimal speichern gibt es nicht.
    expect(find.byKey(const ValueKey('qa-save-0')), findsNothing);
  });

  testWidgets('beim Blättern bleibt das Panel offen: die nächste Frage bezieht sich auf die neue Seite', (tester) async {
    final pagesSeen = <int>[];
    final prompts = <String>[];
    PageQaPanel.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((request) async {
            final messages = jsonDecode(request.body)['messages'] as List;
            prompts.add(jsonEncode(messages));
            return _chat('Antwort ${prompts.length}');
          }),
        );
    final controller = PageQaController();
    addTearDown(controller.dispose);
    var page = 2;
    late StateSetter rebuild;

    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return PageQaPanel(
          controller: controller,
          documentText: 'Text',
          capturePage: () async {
            pagesSeen.add(page);
            return (image: Uint8List.fromList([1]), page: page, total: 10);
          },
          currentPage: page,
          totalPages: 10,
        );
      },
    )));

    Future<void> ask(String q) async {
      await tester.enterText(find.byKey(const ValueKey('qa-input')), q);
      await tester.tap(find.byKey(const ValueKey('qa-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }

    await ask('Erste Frage');
    rebuild(() => page = 3);
    await tester.pump();
    expect(find.text('Seite 3 von 10 · sieht die angezeigte Seite + den Dokumenttext'), findsOneWidget);
    await ask('Zweite Frage');

    expect(pagesSeen, [2, 3]);
    expect(controller.turns.map((t) => t.page), [2, 3]);
    // Die frühere Frage steht mit ihrer Seite im Verlauf, damit sich die KI nicht darauf bezieht.
    expect(prompts.last, contains('[Seite 2] Erste Frage'));
    // Ohne onSaveNote gibt es kein Speichern (z.B. bei einer noch nicht gespeicherten Datei).
    expect(find.byKey(const ValueKey('qa-save-0')), findsNothing);
  });

  testWidgets('ohne API-Key eine verständliche Meldung, kein Aufruf', (tester) async {
    final controller = PageQaController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(
      PageQaPanel(
        controller: controller,
        documentText: '',
        capturePage: () async => fail('darf nicht erfasst werden'),
        currentPage: 1,
        totalPages: 1,
      ),
      withKey: false,
    ));
    await tester.enterText(find.byKey(const ValueKey('qa-input')), 'Frage');
    await tester.tap(find.byKey(const ValueKey('qa-send')));
    await tester.pump();
    expect(find.textContaining('Kein OpenRouter-API-Key'), findsOneWidget);
  });

  testWidgets('Notizen: diese Seite zuerst, zur Seite springen, löschen', (tester) async {
    final controller = PageQaController();
    addTearDown(controller.dispose);
    final jumps = <int>[];
    final deleted = <PageNote>[];
    final notes = [
      PageNote(id: 'a', page: 7, question: 'Was ist X?', text: 'X ist ein Wert.', createdAt: DateTime(2026, 9, 1)),
      PageNote(id: 'b', page: 3, text: 'Notiz auf Seite 3', createdAt: DateTime(2026, 9, 2)),
    ];
    await tester.pumpWidget(_app(PageQaPanel(
      controller: controller,
      documentText: '',
      capturePage: () async => null,
      currentPage: 3,
      totalPages: 10,
      notes: notes,
      onJumpToPage: jumps.add,
      onDeleteNote: (n) async => deleted.add(n),
    )));

    expect(find.text('Notizen (2)'), findsOneWidget);
    await tester.tap(find.text('Notizen (2)'));
    await tester.pumpAndSettle();
    expect(find.text('DIESE SEITE'), findsOneWidget);
    expect(find.text('ANDERE SEITEN'), findsOneWidget);
    expect(find.text('Notiz auf Seite 3'), findsOneWidget);
    expect(find.text('Was ist X?'), findsOneWidget);
    expect(find.text('X ist ein Wert.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Seite 7'));
    expect(jumps, [7]);
    await tester.tap(find.byKey(const ValueKey('note-delete-a')));
    expect(deleted.single.id, 'a');
  });

  testWidgets('Kopfzeile: Seitenwechsel und Schließen nur, wenn angeboten', (tester) async {
    final controller = PageQaController();
    addTearDown(controller.dispose);
    var swapped = 0;
    var closed = 0;
    await tester.pumpWidget(_app(PageQaPanel(
      controller: controller,
      documentText: '',
      capturePage: () async => null,
      currentPage: 1,
      totalPages: 1,
      onSwapSide: () => swapped++,
      onClose: () => closed++,
    )));
    await tester.tap(find.byKey(const ValueKey('qa-swap')));
    await tester.tap(find.byKey(const ValueKey('qa-close')));
    expect((swapped, closed), (1, 1));
  });

  test('PageNote: Speichern und Lesen, kaputte Felder verkraften', () {
    final note = PageNote(id: 'n', page: 5, question: 'F', text: 'A', createdAt: DateTime(2026, 9, 3, 12));
    final back = PageNote.fromMap(note.toMap());
    expect((back.id, back.page, back.question, back.text, back.createdAt), ('n', 5, 'F', 'A', DateTime(2026, 9, 3, 12)));
    final broken = PageNote.fromMap({'id': 'x'});
    expect((broken.page, broken.text, broken.question), (1, '', ''));
  });
}
