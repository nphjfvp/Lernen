import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/ink_sheet.dart';
import 'package:lernen/ui/tasks/step_task_view.dart';
import 'package:provider/provider.dart';

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test', visionModelId: 'vision/test');
}

Flashcard _card() => Flashcard(
  id: 'ink1',
  moduleId: 'm1',
  front: r'Berechne $\int 2x (x^2+1)^3 \, dx$.',
  back: r'$\frac{(x^2+1)^4}{4} + C$',
  createdAt: DateTime(2026, 1, 1),
  due: DateTime(2026, 1, 1),
  type: QuestionType.steps,
  taskData: {
    'kind': 'steps',
    'steps': [
      {
        'title': 'Substituieren und integrieren',
        'prompt': 'Substituiere u = x² + 1.',
        'fields': [
          {
            'label': 'F(x) =',
            'answer': '(x^2+1)^4/4 + C',
            'variables': ['x'],
            'constants': ['C'],
          },
        ],
      },
    ],
  },
);

void main() {
  group('InkSheetController', () {
    test('Zelle aus der Lage des Strichs, Versionen, Radieren, Rückgängig', () {
      final ink = InkSheetController();
      const h = InkSheetController.rowHeight;
      ink.add([const Offset(20, h * 1.3), const Offset(80, h * 1.6)], 600);
      ink.add([const Offset(500, h * 0.4), const Offset(560, h * 0.6)], 600);
      expect(ink.strokes[0].cell, (row: 1, side: false));
      expect(ink.strokes[1].cell, (row: 0, side: true), reason: 'rechts vom Rand = Nebenrechnung');
      expect(ink.rowsUsed, 2);
      final v = ink.version((row: 1, side: false));
      expect(ink.eraseAt(const Offset(20, h * 1.3)), {(row: 1, side: false)});
      expect(ink.version((row: 1, side: false)), greaterThan(v));
      expect(ink.strokes, hasLength(1));
      expect(ink.undo(), {(row: 1, side: false)});
      expect(ink.strokes, hasLength(2));
      ink.clearCell((row: 0, side: true));
      expect(ink.strokesIn((row: 0, side: true)), isEmpty);
    });

    test('Stift schaltet „Nur Stift“ ein, bis der Nutzer selbst wählt', () {
      final ink = InkSheetController();
      ink.setPenOnly(true, chosen: false);
      expect(ink.penOnly, isTrue);
      ink.setPenOnly(false);
      ink.setPenOnly(true, chosen: false);
      expect(ink.penOnly, isFalse, reason: 'die eigene Wahl gilt');
    });
  });

  tearDown(() => StepTaskView.aiFactory = null);

  testWidgets('Mit Stift: Zeilen und Rand werden gelesen, nachgerechnet und lassen sich korrigieren', (tester) async {
    tester.view.physicalSize = const Size(700, 2800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <({String model, String text, bool image})>[];
    StepTaskView.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        final content = messages[1]['content'];
        final text = content is List ? '${content.first['text']}' : '$content';
        sent.add((model: model, text: text, image: content is List && content.length > 1));
        final reply = text.contains('Nebenrechnung vom Rand')
            ? {'text': 'u = x² + 1', 'unsure': false, 'note': ''}
            : text.contains('u = x² + 1')
            ? {'text': '= u⁴/3 + C', 'unsure': true, 'note': '3 oder 4 im Nenner?'}
            : {'text': '∫ 2x (x²+1)³ dx = ∫ u³ du', 'unsure': false, 'note': ''};
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(reply)},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final card = _card();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsRepository>.value(
        value: _SettingsWithKey(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: QuestionAnswerView(
              key: ValueKey(card.id),
              card: card,
              isNew: false,
              onComplete: ({Grade? selfGrade, bool? isCorrect}) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-mode-write')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-input-ink')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ink-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-ink-empty')), findsOneWidget);

    final paper = find.descendant(of: find.byKey(const ValueKey('ink-sheet')), matching: find.byType(CustomPaint)).last;
    final topLeft = tester.getTopLeft(paper);
    final width = tester.getSize(paper).width;
    const h = InkSheetController.rowHeight;

    Future<void> write(Offset from, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
      final g = await tester.startGesture(topLeft + from, kind: kind);
      for (var k = 1; k <= 6; k++) {
        await g.moveTo(topLeft + from + Offset(k * 8.0, (k.isEven ? 6 : -6)));
      }
      await g.up();
      await tester.pump();
    }

    Future<void> settle() async {
      await tester.pump(StepTaskView.inkPause);
      for (var k = 0; k < 5; k++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
    }

    // Zeile 1 und eine Nebenrechnung am Rand derselben Zeile.
    await write(const Offset(40, h * 0.5));
    await write(Offset(width * 0.75, h * 0.5));
    await settle();
    expect(sent.length, 2);
    expect(sent.every((s) => s.model == 'vision/test' && s.image), isTrue, reason: 'Bild-Modell mit Bild');
    String lineText(int i) => tester.widget<TextField>(find.byKey(ValueKey('step-line-$i'))).controller!.text;
    expect(lineText(0), '∫ 2x (x²+1)³ dx = ∫ u³ du');
    expect(lineText(1), 'u = x² + 1');
    expect(find.byKey(const ValueKey('step-ink-empty')), findsNothing);

    // Zeile 2 – unsicher gelesen: Hinweis am Feld.
    await write(const Offset(40, h * 1.5));
    await settle();
    expect(sent.length, 3);
    expect(sent.last.text, contains('Nebenrechnung: u = x² + 1'), reason: 'vorige Zeilen als Kontext');
    expect(lineText(2), '= u⁴/3 + C');
    expect(find.textContaining('3 oder 4 im Nenner'), findsOneWidget);

    // Die App rechnet nach: die gelesene Zeile 2 stimmt nicht.
    await tester.tap(find.byKey(const ValueKey('step-line-check-2')));
    await tester.pump();
    expect(find.textContaining('von der App nachgerechnet'), findsOneWidget);
    expect(sent.length, 3, reason: 'ohne KI');

    // Korrigieren per Tastatur: die Unsicher-Markierung verschwindet.
    await tester.enterText(find.byKey(const ValueKey('step-line-2')), '= u⁴/4 + C');
    await tester.pump();
    expect(find.textContaining('3 oder 4 im Nenner'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('step-line-check-2')));
    await tester.pump();
    expect(find.textContaining('Stimmt'), findsOneWidget);

    // Wegradieren entfernt die Zeile.
    await tester.tap(find.byKey(const ValueKey('ink-undo')));
    await tester.pump();
    await settle();
    expect(find.byKey(const ValueKey('step-line-2')), findsNothing);

    // Finger zeichnet nicht mehr, sobald ein Stift benutzt wurde.
    final before = sent.length;
    await write(const Offset(40, h * 3.5), kind: PointerDeviceKind.touch);
    await settle();
    expect(sent.length, before);
  });

  testWidgets('Mit Stift ohne Key: Hinweis, Tippen geht weiter', (tester) async {
    tester.view.physicalSize = const Size(700, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final card = _card();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: QuestionAnswerView(card: card, isNew: false, onComplete: ({Grade? selfGrade, bool? isCorrect}) {}),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-mode-write')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('step-input-ink')));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-ink-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('step-input-type')));
    await tester.pump();
    expect(find.byKey(const ValueKey('hand-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-line-0')), findsOneWidget);
  });
}
