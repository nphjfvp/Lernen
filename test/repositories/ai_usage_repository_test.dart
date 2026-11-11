import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/ai_model_info.dart';
import 'package:lernen/models/ai_usage.dart';
import 'package:lernen/repositories/ai_usage_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/settings/ai_usage_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

const _priced = AiModelInfo(
  id: 'teuer/modell',
  name: 'Teures Modell',
  contextLength: 200000,
  promptPricePerMillion: 10,
  completionPricePerMillion: 50,
  supportsVision: true,
  isFree: false,
);

AiUsage _usage(DateTime at, String model, {int inTokens = 1000, int outTokens = 500, double? cost}) => AiUsage(
  at: at,
  model: model,
  label: 'Du erstellst eine Lektion',
  promptTokens: inTokens,
  completionTokens: outTokens,
  cost: cost,
);

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_ai_usage_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() => AiService.onUsage = null);

  test('usage-Block lesen: Tokens und Kosten; ohne Block oder leer → nichts', () {
    final usage = AiUsage.fromResponse(
      {'prompt_tokens': 1200, 'completion_tokens': 340, 'total_tokens': 1540, 'cost': 0.0042},
      model: 'm',
      label: 'L',
    )!;
    expect((usage.promptTokens, usage.completionTokens, usage.cost, usage.estimated), (1200, 340, 0.0042, false));
    expect(AiUsage.fromResponse(null, model: 'm', label: 'L'), isNull);
    expect(AiUsage.fromResponse({'prompt_tokens': 0}, model: 'm', label: 'L'), isNull);
    // Ohne gemeldeten Betrag: aus Tokens und Listenpreis – als Schätzung markiert.
    final plain = AiUsage.fromResponse(
      {'prompt_tokens': 1000000, 'completion_tokens': 100000},
      model: 'm',
      label: 'L',
    )!;
    expect(plain.cost, isNull);
    final estimated = plain.withEstimate(10, 50);
    expect((estimated.cost, estimated.estimated), (15.0, true));
    expect(plain.withEstimate(null, 50).cost, isNull);
    expect(usage.withEstimate(10, 50).cost, 0.0042, reason: 'gemeldeter Betrag gewinnt');
    expect(AiUsage.fromMap(estimated.toMap())!.estimated, isTrue);
  });

  test('Beträge deutsch geschrieben, kleine genauer', () {
    expect(formatUsd(0), '0,00 \$');
    expect(formatUsd(0.0034), '0,0034 \$');
    expect(formatUsd(0.0421), '0,042 \$');
    expect(formatUsd(1.257), '1,26 \$');
  });

  test('Summen je Tag/Monat/Modell, Schätzung aus dem Katalog, Neuladen, Zurücksetzen', () async {
    final repo = AiUsageRepository(modelInfo: (id) => id == _priced.id ? _priced : null);
    await repo.clear();
    final now = DateTime(2026, 11, 11, 14);
    repo
      ..record(_usage(now, 'billig/modell', cost: 0.002))
      ..record(_usage(now.subtract(const Duration(hours: 3)), 'billig/modell', cost: 0.003))
      // Ohne Betrag in der Antwort: 1000 · 10 $/Mio + 500 · 50 $/Mio = 0,035 $.
      ..record(_usage(now, 'teuer/modell'))
      // Gestern, letzter Monat, unbekannter Preis.
      ..record(_usage(DateTime(2026, 11, 10, 23), 'billig/modell', cost: 0.01))
      ..record(_usage(DateTime(2026, 10, 31, 23), 'billig/modell', cost: 1))
      ..record(_usage(now, 'unbekannt/modell'));
    await repo.settled;

    expect(repo.today(now).cost, closeTo(0.04, 1e-9));
    expect(repo.today(now).calls, 4);
    expect(repo.thisMonth(now).cost, closeTo(0.05, 1e-9));
    expect(repo.sum().cost, closeTo(1.05, 1e-9));
    expect(repo.sum().unknownCalls, 1);
    final models = repo.byModelThisMonth(now);
    expect(models.map((m) => m.model), ['teuer/modell', 'billig/modell', 'unbekannt/modell']);
    expect(models.first.estimatedCalls, 1);
    expect(repo.last!.model, 'unbekannt/modell', reason: 'jüngste zuerst');
    expect(repo.averageFor('billig/modell')!.calls, 4);
    expect(repo.averageFor('unbekannt/modell'), isNull);

    // Ein zweites Repository liest dasselbe aus der Datenbank.
    final other = AiUsageRepository();
    await other.load();
    expect(other.sum().cost, closeTo(1.05, 1e-9));
    expect(other.recent, hasLength(6));
    expect(other.recent.first.at.isAfter(other.recent.last.at), isTrue);

    await repo.clear();
    expect(repo.isEmpty, isTrue);
    final empty = AiUsageRepository();
    await empty.load();
    expect(empty.recent, isEmpty);
    expect(empty.sum().calls, 0);
  });

  test('nur die letzten Anfragen bleiben einzeln gespeichert, die Summen bleiben vollständig', () async {
    final repo = AiUsageRepository();
    await repo.clear();
    final start = DateTime(2026, 11, 11, 8);
    for (var i = 0; i < AiUsageRepository.keepEntries + 5; i++) {
      repo.record(_usage(start.add(Duration(seconds: i)), 'm', cost: 0.001));
    }
    await repo.settled;
    expect(repo.recent, hasLength(AiUsageRepository.keepEntries));
    expect(repo.sum().calls, AiUsageRepository.keepEntries + 5);
    final other = AiUsageRepository();
    await other.load();
    expect(other.recent, hasLength(AiUsageRepository.keepEntries));
    await repo.clear();
  });

  test('AiService meldet den Verbrauch jeder Antwort – auch der wiederholten', () async {
    final reported = <AiUsage>[];
    AiService.onUsage = reported.add;
    final ai = AiService(
      apiKey: 'key',
      model: 'stark/modell',
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"reason": "passt", "correct": true}'},
              },
            ],
            'usage': {'prompt_tokens': 800, 'completion_tokens': 40, 'cost': 0.0123},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    expect(await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B'), isTrue);
    expect(reported.single.model, 'stark/modell');
    expect(reported.single.cost, 0.0123);
    expect(reported.single.promptTokens, 800);
    expect(reported.single.label, startsWith('Du bewertest'));

    // Ein Fehler in der Kostenanzeige darf keine Antwort kosten.
    AiService.onUsage = (_) => throw StateError('kaputt');
    expect(await ai.checkFreeTextAnswer(question: 'F', correctAnswer: 'A', userAnswer: 'B'), isTrue);
  });

  testWidgets('Kostenübersicht in Handybreite: Summen, Modelle, letzte Anfragen, Zurücksetzen', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // In echter Zeit anlegen: Die Warteschlange des Repositorys gehört zu der
    // Zone, in der es entstanden ist.
    late final AiUsageRepository repo;
    await tester.runAsync(() async {
      repo = AiUsageRepository(modelInfo: (id) => id == _priced.id ? _priced : null);
      await repo.clear();
      repo
        ..record(_usage(DateTime.now(), 'billig/modell', cost: 0.002))
        ..record(_usage(DateTime.now(), 'teuer/modell', inTokens: 12000, outTokens: 4000));
      await repo.settled;
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AiUsageRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const Scaffold(body: Center(child: AiUsageTile())),
        ),
      ),
    );
    // 12000 · 10 + 4000 · 50 = 0,32 $ (geschätzt) + 0,002 $.
    expect(find.text('Heute 0,322 \$ · diesen Monat 0,322 \$'), findsOneWidget);
    await tester.tap(find.byType(AiUsageTile));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('ai-usage-today'))).data, '0,322 \$');
    expect(find.byKey(const ValueKey('ai-usage-model-teuer/modell')), findsOneWidget);
    expect(find.text('≈ 0,320 \$'), findsNWidgets(2), reason: 'je Modell und in der Liste, als Schätzung markiert');
    expect(find.text('0,0020 \$'), findsNWidgets(2));
    expect(find.textContaining('12k rein, 4,0k raus'), findsNWidgets(2));
    expect(tester.takeException(), isNull, reason: 'kein Überlauf in Handybreite');

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('ai-usage-reset')));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('ai-usage-reset-ok')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Noch keine.'), findsOneWidget);
    expect(repo.isEmpty, isTrue);
  });
}
