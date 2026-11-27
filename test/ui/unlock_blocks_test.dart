import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/learn_credit.dart';
import 'package:lernen/models/unlock_block.dart';
import 'package:lernen/repositories/learn_credit_repository.dart';
import 'package:lernen/repositories/unlock_block_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/fsrs_service.dart';
import 'package:lernen/services/unlock_block_service.dart';
import 'package:lernen/services/unlock_task_card.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/unlock/unlock_blocks_screen.dart';
import 'package:sembast/sembast_memory.dart';

UnlockBlock _block(String id, {List<UnlockTask>? tasks, UnlockPractice? practice}) => UnlockBlock(
  id: id,
  moduleId: 'm1',
  title: 'Substitution',
  reason: 'Fehler beim Üben',
  tasks: tasks ?? const [UnlockTask(problem: 'A1', answer: '1'), UnlockTask(problem: 'A2', answer: '2')],
  practice: practice,
  createdAt: DateTime(2026, 11, 15),
);

http.Response _reply(Object content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content is String ? content : jsonEncode(content)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('Modell und Zeitkonto', () {
    test('Block: übersteht Speichern, unberührt/gelöst, Übungseinheit', () {
      final practice = UnlockPractice.fromMap({
        'task': 1,
        'intro': 'Der Haken: du = 2x dx.',
        'exercises': ['Ü1', 'Ü2'],
        'retry': {'problem': 'Neue Aufgabe', 'answer': '3', 'solution': '…'},
      })!;
      expect(practice.completed, isFalse);
      expect(practice.withFinished(0).withFinished(1).completed, isTrue);
      final block = _block('b', practice: practice);
      final back = UnlockBlock.fromMap(jsonDecode(jsonEncode(block.toMap())))!;
      expect(back.practice!.retry!.problem, 'Neue Aufgabe');
      expect(back.tasks, hasLength(2));
      expect(_block('x').untouched, isTrue);
      expect(back.untouched, isFalse);
      final solved = _block('y').copyWith(
        tasks: const [
          UnlockTask(problem: 'A1', state: UnlockTaskState.solved),
          UnlockTask(problem: 'A2', state: UnlockTaskState.solved),
        ],
      );
      expect(solved.solved, isTrue);
    });

    test('Bonusminuten: je Kennung einmal, über Geräte vereint, zählen zur Tageszeit', () {
      final now = DateTime(2026, 11, 15, 12);
      const rules = LearnCreditRules();
      var credit = const LearnCredit().withBonus('unlock:a:practice', 5, now, 4);
      credit = credit.withBonus('unlock:a:practice', 5, now, 4);
      expect(credit.bonusOn('2026-11-15'), 5);
      final other = const LearnCredit().withBonus('unlock:b:solved', 30, now, 4);
      final merged = credit.mergedWith(LearnCredit.fromMap(other.toSyncMap()));
      expect(merged.bonusOn('2026-11-15'), 35);
      expect(LearnAllowance.of(merged, rules, now).minutes, 30 + 35);
      expect(LearnAllowance.of(merged, rules, now).nextStep, contains('Entsperr-Block'));
      expect(LearnAllowance.of(merged, rules, now.add(const Duration(days: 1))).minutes, 30);
      // Festgelegt: Minuten je Block nur weniger.
      final locked = rules.copyWith(lockedUntil: now.add(const Duration(days: 7)));
      expect(locked.guard(locked.copyWith(blockMinutes: 90, practiceMinutes: 20), now).blockMinutes, 30);
      expect(locked.guard(locked.copyWith(blockMinutes: 90, practiceMinutes: 20), now).practiceMinutes, 5);
    });
  });

  group('Gutschrift und Anpassen', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase('unlock_${DateTime.now().microsecondsSinceEpoch}');
      UnlockBlockService.openDatabase = () async => db;
      UnlockBlockService.instance.reset();
    });

    tearDown(() async {
      UnlockBlockService.openDatabase = null;
      UnlockBlockService.aiFactory = null;
      await db.close();
    });

    test('Übungseinheit +5, danach gelöst die übrigen 25 – jede Gutschrift nur einmal', () async {
      final repo = UnlockBlockRepository(openDatabase: () async => db);
      final now = DateTime(2026, 11, 15, 12);
      var block = _block(
        'b1',
        practice: const UnlockPractice(task: 0, intro: 'Haken', exercises: ['Ü1'], finished: {0}),
      );
      var r = await repo.reward(block, now: now);
      expect(r.minutes, 5);
      block = r.block.copyWith(
        tasks: const [
          UnlockTask(problem: 'A1', state: UnlockTaskState.solved),
          UnlockTask(problem: 'A2', state: UnlockTaskState.solved),
        ],
      );
      r = await repo.reward(block, now: now);
      expect(r.minutes, 25);
      expect((await repo.reward(r.block, now: now)).minutes, 0);
      final credit = await LearnCreditRepository.loadFrom(db);
      expect(credit.bonusOn('2026-11-15'), 30);
      // Ohne Übungseinheit: gleich die vollen 30.
      final direct = _block('b2').copyWith(
        tasks: const [
          UnlockTask(problem: 'A1', state: UnlockTaskState.solved),
          UnlockTask(problem: 'A2', state: UnlockTaskState.solved),
        ],
      );
      expect((await repo.reward(direct, now: now)).minutes, 30);
    });

    test('Anpassen: nach Fehlern, angefangene bleiben, unberührte werden ersetzt, höchstens 3', () async {
      final repo = UnlockBlockRepository(openDatabase: () async => db);
      await DatabaseService.modules.record('m1').put(db, {'id': 'm1', 'name': 'Mathe 2'});
      await DatabaseService.materials.record('pdf').put(db, {
        'id': 'pdf',
        'moduleId': 'm1',
        'fileName': 'Blatt 3.pdf',
        'kind': 'exercise',
        'extractedText': 'Aufgabe 1: Berechne das Integral mit Substitution.',
        'createdAt': '2026-11-01T00:00:00.000',
      });
      await DatabaseService.flashcards.record('k').put(db, {
        'id': 'k',
        'moduleId': 'm1',
        'front': 'Integriere 2x cos(x²)',
        'back': 'sin(x²) + C',
        'lapses': 3,
      });
      await repo.save(_block('alt'));
      await repo.save(
        _block(
          'angefangen',
          tasks: const [
            UnlockTask(problem: 'A1', state: UnlockTaskState.failed, attempts: 1),
            UnlockTask(problem: 'A2'),
          ],
        ),
      );
      final sent = <String>[];
      final prepared = <String>[];
      UnlockBlockService.aiFactory = () => AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          final messages = (jsonDecode(r.body) as Map)['messages'] as List;
          if ('${messages[0]['content']}'.contains('interaktive Aufgaben')) {
            // Beim Anlegen gleich lösbar gemacht (Rechenweg-Karte je Aufgabe).
            prepared.add('${messages[1]['content']}');
            return _reply({'tasks': []});
          }
          sent.add('${messages[1]['content']}');
          return _reply({
            'keep': [],
            'blocks': [
              for (var i = 0; i < 4; i++)
                {
                  'title': 'Thema $i',
                  'reason': 'Fehler beim Üben',
                  'tasks': [
                    {'problem': 'P$i a', 'answer': '1', 'solution': 'S'},
                    {'problem': 'P$i b', 'answer': '2', 'solution': 'S'},
                  ],
                },
            ],
          });
        }),
      );
      // Sperre aus: nur auf Wunsch.
      expect(await UnlockBlockService.instance.refresh('m1'), 0);
      expect(sent, isEmpty);
      final added = await UnlockBlockService.instance.refresh('m1', force: true);
      expect(added, 2, reason: '3 offen höchstens, einer ist angefangen');
      expect(sent.single, contains('Integriere 2x cos(x²)'));
      expect(sent.single, contains('Blatt 3.pdf (Übungsblatt)'));
      final blocks = await repo.forModule('m1');
      expect(blocks.map((b) => b.id), contains('angefangen'));
      expect(blocks.map((b) => b.id), isNot(contains('alt')));
      expect(blocks, hasLength(3));
      expect(prepared, hasLength(4), reason: 'je neue Aufgabe eine Karte');
      final fresh = blocks.firstWhere((b) => b.id != 'angefangen');
      expect(fresh.tasks.every((t) => t.card != null), isTrue);
      expect(fresh.tasks.first.card!['type'], QuestionType.freeText.name, reason: 'keine Rechenaufgabe: Freitext');
      // Kurz danach nicht schon wieder (außer auf Wunsch).
      await LearnCreditRepository.saveRulesIn(db, const LearnCreditRules(enabled: true));
      expect(await UnlockBlockService.instance.refresh('m1'), 0);
      expect(sent, hasLength(1));
    });

    test('Gescheiterte Anfrage: kurz danach nicht schon wieder (sie kann schon gekostet haben)', () async {
      await DatabaseService.modules.record('m1').put(db, {'id': 'm1', 'name': 'Mathe 2'});
      await DatabaseService.flashcards.record('k').put(db, {'id': 'k', 'moduleId': 'm1', 'front': 'F', 'lapses': 1});
      await LearnCreditRepository.saveRulesIn(db, const LearnCreditRules(enabled: true));
      var calls = 0;
      UnlockBlockService.aiFactory = () => AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          calls++;
          return http.Response('{"error":{"code":401,"message":"No auth"}}', 401);
        }),
      );
      await expectLater(UnlockBlockService.instance.refresh('m1'), throwsA(isA<AiServiceException>()));
      final first = calls;
      expect(first, greaterThan(0));
      expect(await UnlockBlockService.instance.refresh('m1'), 0);
      expect(calls, first);
    });
  });

  group('Karte zur Aufgabe', () {
    AiService ai(Map<String, Object> reply, List<String> sent) => AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        sent.add('${messages[1]['content']}');
        return _reply(reply);
      }),
    );
    final block = _block(
      'b',
      tasks: const [
        UnlockTask(problem: r"Löse $y' = 1 + y^2$, $y(0) = 0$.", answer: r'$y = \tan x$', solution: 'Trennen'),
      ],
    );

    test('Rechenaufgabe: Rechenweg mit Schritten (Stift, Taschenrechner, Vorrechnen)', () async {
      final sent = <String>[];
      final card = await buildUnlockCard(
        ai({
          'tasks': [
            {
              'kind': 'steps',
              'front': 'Löse die DGL.',
              'back': 'y = tan x',
              'taskData': {
                'steps': [
                  {
                    'title': 'Trennen der Variablen',
                    'fields': [
                      {
                        'label': 'y =',
                        'answer': 'tan(x)',
                        'variables': ['x'],
                      },
                    ],
                  },
                ],
              },
            },
          ],
        }, sent),
        block,
        0,
        now: DateTime(2026, 11, 17),
      );
      expect(sent.single, contains('Trennen'));
      expect(sent.single, contains(r'Ergebnis: $y = \tan x$'));
      expect(card.type, QuestionType.steps);
      expect(card.moduleId, 'm1');
      expect(card.front, 'Löse die DGL.');
      expect(card.taskData?['steps'], isA<List>());
      expect(Flashcard.fromMap(card.toMap()).type, QuestionType.steps, reason: 'gespeichert und wieder gelesen');
    });

    test('Wissensfrage oder nichts Brauchbares: Freitext, den die KI bewertet', () async {
      for (final reply in [
        {
          'tasks': [
            {'kind': 'question', 'questionType': 'free_text', 'front': '', 'reason': 'Erklärfrage'},
          ],
        },
        {'tasks': []},
      ]) {
        final card = await buildUnlockCard(ai(reply, []), block, 0);
        expect(card.type, QuestionType.freeText);
        expect(card.front, block.tasks.first.problem);
        expect(card.correctText, r'$y = \tan x$');
      }
    });
  });

  testWidgets('Block lösen als Rechenweg: Fehlversuch → Übungseinheit (+5) → neue Aufgabe → gelöst (+25)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('unlock_ui_${DateTime.now().microsecondsSinceEpoch}'),
    ))!;
    addTearDown(db.close);
    UnlockBlockService.openDatabase = () async => db;
    addTearDown(() {
      UnlockBlockService.openDatabase = null;
      UnlockBlockService.aiFactory = null;
      UnlockBlockScreen.practiceHook = null;
      UnlockBlockScreen.solveHook = null;
    });
    final built = <String>[];
    UnlockBlockService.aiFactory = () => AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        final messages = (jsonDecode(r.body) as Map)['messages'] as List;
        final system = '${messages[0]['content']}';
        if (system.contains('ÜBUNGSEINHEIT')) {
          return _reply({
            'intro': r'Der Haken: aus $u = x^2$ folgt $du = 2x\,dx$.',
            'exercises': ['Übung 1', 'Übung 2'],
            'retry': {'problem': 'Neue Aufgabe gleicher Art', 'answer': '5', 'solution': 'Weg'},
          });
        }
        if (system.contains('interaktive Aufgaben')) {
          built.add('${messages[1]['content']}');
          return _reply({
            'tasks': [
              {
                'kind': 'steps',
                'front': 'Rechenweg-Aufgabe',
                'back': 'Lösung',
                'taskData': {
                  'steps': [
                    {
                      'title': 'Trennen und integrieren',
                      'fields': [
                        {
                          'label': 'y =',
                          'answer': 'tan(x)',
                          'variables': ['x'],
                        },
                      ],
                    },
                  ],
                },
              },
            ],
          });
        }
        return _reply({'solved': false, 'feedback': '?'});
      }),
    );
    UnlockBlockScreen.practiceHook = (context, moduleId, problem) async => true;
    final opened = <Flashcard>[];
    var next = (selfGrade: Grade.again, isCorrect: false);
    UnlockBlockScreen.solveHook = (context, card) async {
      opened.add(card);
      return (selfGrade: next.selfGrade, isCorrect: next.isCorrect);
    };
    final repo = UnlockBlockRepository(openDatabase: () async => db);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: UnlockBlockScreen(block: _block('b1'), repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unlock-answer-0')), findsNothing, reason: 'kein bloßes Textfeld mehr');

    // Lösen: die Aufgabe wird als Rechenweg aufbereitet (einmal) und geöffnet.
    await tester.tap(find.byKey(const ValueKey('unlock-solve-0')));
    await tester.pumpAndSettle();
    expect(built.single, contains('A1'));
    expect(opened.single.type, QuestionType.steps);
    expect(find.text('Noch nicht richtig.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unlock-solve-0')));
    await tester.pumpAndSettle();
    expect(built, hasLength(1), reason: 'Karte gespeichert, nicht neu gebaut');

    await tester.tap(find.byKey(const ValueKey('unlock-start-practice-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unlock-practice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unlock-exercise-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unlock-exercise-1')));
    await tester.pumpAndSettle();
    expect(find.text('+5 min Handyzeit'), findsOneWidget);
    expect(find.text('Neue Aufgabe gleicher Art'), findsOneWidget, reason: 'statt der schon gesehenen');
    expect(find.byKey(const ValueKey('unlock-practice-done')), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // Mit Hilfe (z.B. Vorrechnen vorher) richtig: zählt nicht als „ohne Hilfe“.
    next = (selfGrade: Grade.hard, isCorrect: true);
    await tester.tap(find.byKey(const ValueKey('unlock-solve-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('zählt nicht als „ohne Hilfe“'), findsOneWidget);

    // Neue Aufgabe ohne Hilfe gelöst.
    next = (selfGrade: Grade.good, isCorrect: true);
    await tester.tap(find.byKey(const ValueKey('unlock-solve-0')));
    await tester.pumpAndSettle();
    expect(built, hasLength(3), reason: 'Aufgabe 2 und die neue Aufgabe bekommen je ihre eigene Karte');
    expect(built.last, contains('Neue Aufgabe gleicher Art'));
    expect(find.text('Ohne Hilfe gelöst.'), findsOneWidget);
    expect(find.byKey(const ValueKey('unlock-solved')), findsNothing, reason: 'Aufgabe 2 noch mit Hilfe');
    final stored = (await tester.runAsync(() => repo.all()))!.single;
    expect(stored.tasks[0].state, UnlockTaskState.solved);
    expect(stored.tasks[0].card, isNotNull);
    expect(stored.tasks[1].helped, isTrue);
    expect((await tester.runAsync(() => LearnCreditRepository.loadFrom(db)))!.bonus.keys, ['unlock:b1:practice']);
  });
}
