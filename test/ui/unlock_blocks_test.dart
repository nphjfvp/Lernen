import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/learn_credit.dart';
import 'package:lernen/models/unlock_block.dart';
import 'package:lernen/repositories/learn_credit_repository.dart';
import 'package:lernen/repositories/unlock_block_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/services/unlock_block_service.dart';
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
      UnlockBlockService.aiFactory = () => AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          final messages = (jsonDecode(r.body) as Map)['messages'] as List;
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
      // Kurz danach nicht schon wieder (außer auf Wunsch).
      await LearnCreditRepository.saveRulesIn(db, const LearnCreditRules(enabled: true));
      expect(await UnlockBlockService.instance.refresh('m1'), 0);
      expect(sent, hasLength(1));
    });
  });

  testWidgets('Block lösen: Fehlversuch → Übungseinheit (+5) → neue Aufgabe → gelöst (+25)', (tester) async {
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
    });
    var solve = false;
    UnlockBlockService.aiFactory = () => AiService(
      apiKey: 'k',
      model: 'm',
      client: MockClient((r) async {
        final system = '${((jsonDecode(r.body) as Map)['messages'] as List)[0]['content']}';
        if (system.contains('ÜBUNGSEINHEIT')) {
          return _reply({
            'intro': r'Der Haken: aus $u = x^2$ folgt $du = 2x\,dx$.',
            'exercises': ['Übung 1', 'Übung 2'],
            'retry': {'problem': 'Neue Aufgabe gleicher Art', 'answer': '5', 'solution': 'Weg'},
          });
        }
        return _reply(
          solve
              ? {'solved': true, 'feedback': 'Richtig!'}
              : {'solved': false, 'feedback': 'Der Faktor 2x fehlt.', 'explain': r'Aus $u = x^2$ folgt $du = 2x\,dx$.'},
        );
      }),
    );
    UnlockBlockScreen.practiceHook = (context, moduleId, problem) async => true;
    final repo = UnlockBlockRepository(openDatabase: () async => db);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: UnlockBlockScreen(block: _block('b1'), repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('unlock-answer-0')), 'u = x^2, ...');
    await tester.tap(find.byKey(const ValueKey('unlock-check-0')));
    await tester.pumpAndSettle();
    expect(find.text('Der Faktor 2x fehlt.'), findsOneWidget);
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

    // Lösung ansehen zählt als Hilfe – auch wenn es dann stimmt.
    solve = true;
    await tester.tap(find.byKey(const ValueKey('unlock-solution-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('unlock-answer-1')), 'abgeschrieben');
    await tester.tap(find.byKey(const ValueKey('unlock-check-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('zählt es nicht als „ohne Hilfe“'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('unlock-answer-0')), 'richtig gerechnet');
    await tester.tap(find.byKey(const ValueKey('unlock-check-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unlock-solved')), findsNothing, reason: 'Aufgabe 2 noch mit Hilfe');
    final stored = (await tester.runAsync(() => repo.all()))!.single;
    expect(stored.tasks[0].state, UnlockTaskState.solved);
    expect(stored.tasks[1].helped, isTrue);
    expect((await tester.runAsync(() => LearnCreditRepository.loadFrom(db)))!.bonus.keys, ['unlock:b1:practice']);
  });
}
