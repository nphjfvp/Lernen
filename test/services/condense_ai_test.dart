import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/condense.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/condense_service.dart';

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

CondensePage _page(int number, List<String> blocks) => CondensePage(
      number: number,
      blocks: [for (var i = 0; i < blocks.length; i++) CondenseBlock(page: number, index: i + 1, text: blocks[i])],
    );

/// Welche Art Anfrage: Auswertung der Aufgaben oder Auswahl in der Vorlesung.
bool _isAnalysis(Map<String, dynamic> request) =>
    ((request['messages'] as List).first['content'] as String).contains('auf das Nötige zu kürzen');

String _user(Map<String, dynamic> request) => (request['messages'] as List).last['content'] as String;

void main() {
  group('AiService.analyzeCondenseTasks', () {
    test('liest Aufgaben und Anforderungen, Dopplungen werden einmal geführt', () async {
      late Map<String, dynamic> request;
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          request = jsonDecode(r.body) as Map<String, dynamic>;
          return _chat(jsonEncode({
            'tasks': ['Aufgabe 1: ∫ x e^x dx'],
            'needs': ['Partielle Integration', ' partielle  Integration ', {'text': 'Produktregel'}, ''],
          }));
        }),
      );
      final plan = await ai.analyzeCondenseTasks(task: 'alles zum Lösen', exercisesText: 'Berechne das Integral.');
      expect(plan.tasks, ['Aufgabe 1: ∫ x e^x dx']);
      expect(plan.needs.map((n) => (n.id, n.text)), [('n1', 'Partielle Integration'), ('n2', 'Produktregel')]);
      expect(_isAnalysis(request), isTrue);
      expect(_user(request), contains('Auftrag des Studierenden: alles zum Lösen'));
      expect(_user(request), contains('Berechne das Integral.'));
    });

    test('ohne Aufgaben nur mit dem Auftrag', () async {
      late Map<String, dynamic> request;
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          request = jsonDecode(r.body) as Map<String, dynamic>;
          return _chat(jsonEncode({'needs': ['Laplace-Transformation']}));
        }),
      );
      final plan = await ai.analyzeCondenseTasks(task: 'alles zur Laplace-Transformation');
      expect(plan.needs.single.text, 'Laplace-Transformation');
      expect(_user(request), contains('keine Übungsaufgaben'));
    });

    test('mit Aufgaben, aber ohne Anforderungen in der Antwort: Fehler mit Rohantwort', () async {
      final ai = AiService(apiKey: 'k', model: 'm', client: MockClient((_) async => _chat('{"needs": []}')));
      await expectLater(
        ai.analyzeCondenseTasks(task: 'x', exercisesText: 'Aufgabe'),
        throwsA(isA<AiServiceException>().having((e) => e.rawResponse, 'rawResponse', contains('needs'))),
      );
    });

    test('lange Aufgabentexte: weitere Abschnitte bekommen die schon erfassten Anforderungen', () async {
      final requests = <String>[];
      var call = 0;
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          requests.add(_user(jsonDecode(r.body) as Map<String, dynamic>));
          call++;
          return _chat(jsonEncode({'needs': ['Anforderung $call']}));
        }),
      );
      final text = List.filled(8, 'Aufgabe ${'x' * 1500}').join('\n\n');
      final plan = await ai.analyzeCondenseTasks(task: 't', exercisesText: text, granularity: ChunkGranularity.fine);
      expect(requests.length, greaterThan(1));
      expect(requests[1], contains('Bereits erfasste Anforderungen'));
      expect(requests[1], contains('- Anforderung 1'));
      expect(plan.needs.length, requests.length);
    });
  });

  group('AiService.condenseLecture', () {
    final pages = [
      _page(1, ['Organisatorisches']),
      _page(2, ['Partielle Integration', 'Formel: uv minus Integral u v', 'Beispiel: x e^x']),
      _page(3, ['Geschichte']),
    ];
    const plan = CondensePlan(needs: [
      CondenseNeed(id: 'n1', text: 'Partielle Integration'),
      CondenseNeed(id: 'n2', text: 'Laplace'),
    ]);

    test('eine Anfrage: Blöcke mit Kennungen, Anforderungen und Strenge im Prompt; Auswahl wird eingelesen', () async {
      final requests = <Map<String, dynamic>>[];
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          requests.add(jsonDecode(r.body) as Map<String, dynamic>);
          return _chat(jsonEncode({
            'sections': [
              {'title': 'Partielle Integration', 'kind': 'erklaerung', 'why': 'Aufgabe 1', 'blocks': ['2.1-2.2'], 'covers': ['n1', 'n9']},
              {'title': 'Beispiel', 'kind': 'beispiel', 'blocks': ['2.3'], 'covers': []},
              {'title': 'Unsinn', 'blocks': ['9.9']},
            ],
            'skipped': ['Organisatorisches', 'Geschichte', 'Organisatorisches'],
          }));
        }),
      );
      final seen = <String>[];
      final result = await ai.condenseLecture(
        pages: pages,
        task: 'alles zum Lösen',
        plan: plan,
        strictness: CondenseStrictness.knapp,
        onProgress: (what, done, total) => seen.add('$what $done/$total'),
      );

      expect(requests, hasLength(1), reason: 'mit fertigem Plan keine Auswertung der Aufgaben');
      final user = _user(requests.single);
      expect(user, contains('[2.2] Formel: uv minus Integral u v'));
      expect(user, contains('=== Seite 3 ==='));
      expect(user, contains('n1: Partielle Integration'));
      expect(user, contains('KNAPP'));
      expect(user, contains('Auftrag des Studierenden: alles zum Lösen'));

      expect(result.sections.map((s) => s.title), ['Partielle Integration', 'Beispiel']);
      expect(result.sections.first.blockIds, ['2.1', '2.2']);
      expect(result.sections.first.covers, ['n1'], reason: 'unbekannte Anforderungen fallen weg');
      expect(result.sections.last.kind, CondenseKind.beispiel);
      expect(result.skipped, ['Organisatorisches', 'Geschichte']);
      expect(result.uncovered(includeExamples: true).map((n) => n.id), ['n2']);
      expect(seen.first, startsWith('Übungsaufgaben auswerten'));
      expect(seen.last, 'Vorlesung durchgehen: Seite 1–3 1/1');
    });

    test('ohne Plan wird erst ausgewertet, dann ausgewählt', () async {
      final kinds = <String>[];
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          final request = jsonDecode(r.body) as Map<String, dynamic>;
          if (_isAnalysis(request)) {
            kinds.add('analyse');
            return _chat(jsonEncode({'needs': ['Partielle Integration']}));
          }
          kinds.add('auswahl');
          expect(_user(request), contains('n1: Partielle Integration'));
          return _chat(jsonEncode({'sections': [{'title': 'A', 'blocks': ['2.2'], 'covers': ['n1']}]}));
        }),
      );
      final result = await ai.condenseLecture(pages: pages, task: 't', exercisesText: 'Aufgabe 1');
      expect(kinds, ['analyse', 'auswahl']);
      expect(result.plan.needs.single.id, 'n1');
      expect(result.uncovered(includeExamples: true), isEmpty);
    });

    test('Rolling-Kontext: spätere Abschnitte kennen Abgedecktes, Offenes und bisherige Überschriften', () async {
      final big = [for (var i = 1; i <= 3; i++) _page(i, ['Absatz $i ${'y' * 3000}'])];
      final users = <String>[];
      var call = 0;
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          users.add(_user(jsonDecode(r.body) as Map<String, dynamic>));
          call++;
          return _chat(jsonEncode({
            'sections': call == 1
                ? [
                    {'title': 'Erster Teil', 'blocks': ['1.1'], 'covers': ['n1']},
                  ]
                : [],
            'skipped': ['Thema $call'],
          }));
        }),
      );
      final result = await ai.condenseLecture(
        pages: big,
        task: 't',
        plan: plan,
        granularity: ChunkGranularity.fine,
      );
      expect(users.length, 3);
      expect(users[0], isNot(contains('Schon in früheren Abschnitten')));
      expect(users[1], contains('Schon in früheren Abschnitten erklärt: n1.'));
      expect(users[1], contains('Noch nicht gefunden: n2'));
      expect(users[1], contains('Bisher behaltene Abschnitte: Erster Teil.'));
      expect(users[1], contains('Dies ist Abschnitt 2 von 3'));
      expect(result.sections, hasLength(1));
      expect(result.skipped, ['Thema 1', 'Thema 2', 'Thema 3']);
    });

    test('ohne Rolling-Kontext bleibt es bei den Anforderungen', () async {
      final big = [for (var i = 1; i <= 2; i++) _page(i, ['Absatz $i ${'y' * 4000}'])];
      final users = <String>[];
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          users.add(_user(jsonDecode(r.body) as Map<String, dynamic>));
          return _chat(jsonEncode({'sections': [{'title': 'A', 'blocks': ['1.1', '2.1']}]}));
        }),
      );
      await ai.condenseLecture(pages: big, task: 't', plan: plan, granularity: ChunkGranularity.fine, rollingContext: false);
      expect(users.length, 2);
      expect(users[1], isNot(contains('Schon in früheren')));
      expect(users[1], isNot(contains('Bisher behaltene')));
    });

    test('Kennungen eines anderen Abschnitts werden nicht angenommen', () async {
      final big = [for (var i = 1; i <= 2; i++) _page(i, ['Absatz $i ${'y' * 4000}'])];
      var call = 0;
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          call++;
          // Beide Antworten nennen Seite 1 – im zweiten Aufruf gibt es die nicht.
          return _chat(jsonEncode({'sections': [{'title': 'A$call', 'blocks': ['1.1']}]}));
        }),
      );
      final result = await ai.condenseLecture(pages: big, task: 't', plan: plan, granularity: ChunkGranularity.fine);
      expect(result.sections.map((s) => s.title), ['A1']);
    });

    test('ein unlesbarer Abschnitt wird einmal wiederholt', () async {
      var call = 0;
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          call++;
          return call == 1 ? _chat('Hier ist keine Auswahl') : _chat(jsonEncode({'sections': [{'title': 'A', 'blocks': ['2.2']}]}));
        }),
      );
      final result = await ai.condenseLecture(pages: pages, task: 't', plan: plan);
      expect(call, 2);
      expect(result.sections.single.blockIds, ['2.2']);
    });

    test('zweimal unlesbar: Fehler', () async {
      final ai = AiService(apiKey: 'k', model: 'm', client: MockClient((_) async => _chat('kein JSON')));
      await expectLater(ai.condenseLecture(pages: pages, task: 't', plan: plan), throwsA(isA<AiServiceException>()));
    });

    test('nichts behalten: Fehler mit Rohantwort statt eines leeren Dokuments', () async {
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((_) async => _chat(jsonEncode({'sections': [], 'skipped': ['alles']}))),
      );
      await expectLater(
        ai.condenseLecture(pages: pages, task: 't', plan: plan),
        throwsA(isA<AiServiceException>().having((e) => e.rawResponse, 'rawResponse', contains('skipped'))),
      );
    });

    test('eine Vorlesung ohne Text meldet das, ohne die KI zu fragen', () async {
      var calls = 0;
      final ai = AiService(apiKey: 'k', model: 'm', client: MockClient((_) async {
        calls++;
        return _chat('{}');
      }));
      await expectLater(
        ai.condenseLecture(pages: const [CondensePage(number: 1, blocks: [])], task: 't', plan: plan),
        throwsA(isA<AiServiceException>().having((e) => e.message, 'message', contains('kein Text'))),
      );
      expect(calls, 0);
    });

    test('auch ohne Aufgaben und Plan arbeitet die Auswahl mit dem Auftrag allein', () async {
      final ai = AiService(
        apiKey: 'k',
        model: 'm',
        client: MockClient((r) async {
          final request = jsonDecode(r.body) as Map<String, dynamic>;
          if (_isAnalysis(request)) return _chat(jsonEncode({'needs': []}));
          return _chat(jsonEncode({'sections': [{'title': 'A', 'blocks': ['2.2']}]}));
        }),
      );
      final result = await ai.condenseLecture(pages: pages, task: 'alles zur Integration');
      expect(result.plan.needs, isEmpty);
      expect(result.sections, hasLength(1));
    });
  });

  test('Gruppierung nach Granularität stimmt mit CondenseService.group überein', () {
    final big = [for (var i = 1; i <= 3; i++) _page(i, ['y' * 3000])];
    expect(CondenseService.group(big, 6000).length, greaterThan(1));
    expect(CondenseService.group(big, null).length, 1);
  });
}
