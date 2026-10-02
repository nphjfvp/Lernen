import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/formula_sheet.dart';
import 'package:lernen/services/ai_service.dart';

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

Map<String, dynamic> _entry(String name, String formula, String level, {String source = 'folien', String note = ''}) =>
    {'name': name, 'formula': formula, 'level': level, 'source': source, 'note': note};

void main() {
  group('AiService.generateFormulaSheet', () {
    test('liest Abschnitte, Stufen und "ergänzt" aus der Antwort; Dollarzeichen werden entfernt', () async {
      late Map<String, dynamic> request;
      final client = MockClient((r) async {
        request = jsonDecode(r.body) as Map<String, dynamic>;
        return _chat(jsonEncode({
          'title': 'Formelsammlung Integralrechnung',
          'sections': [
            {
              'title': 'Integrationsregeln',
              'entries': [
                _entry('Partielle Integration', r"\int u v' dx = uv - \int u' v dx", 'kern', note: 'u, v stetig differenzierbar'),
              ],
            },
            {
              'title': 'Ableitungsregeln',
              'entries': [_entry('Produktregel', r"$(uv)' = u'v + uv'$", 'hilfsregel', source: 'ergaenzt')],
            },
            {
              'title': 'Potenzgesetze',
              'entries': [_entry('Potenzgesetz', r'a^m \cdot a^n = a^{m+n}', 'rechenregel', source: 'ergaenzt')],
            },
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'm', client: client);

      final result = await ai.generateFormulaSheet('Folientext zur Integralrechnung', detail: FormulaDetail.fein);

      expect(result.title, 'Formelsammlung Integralrechnung');
      expect(result.sheet.detail, FormulaDetail.fein);
      expect(result.sheet.sections.map((s) => s.title), ['Integrationsregeln', 'Ableitungsregeln', 'Potenzgesetze']);
      final entries = [for (final s in result.sheet.sections) ...s.entries];
      expect(entries.map((e) => e.level), [FormulaLevel.kern, FormulaLevel.hilfsregel, FormulaLevel.rechenregel]);
      expect(entries.map((e) => e.supplemented), [false, true, true]);
      expect(entries[1].formula, isNot(startsWith(r'$')));
      expect(entries.first.note, 'u, v stetig differenzierbar');

      // Der Auftrag an die KI nennt die drei Stufen und die Beispiele aus der Anfrage.
      final messages = request['messages'] as List;
      final system = (messages.first as Map)['content'] as String;
      expect(system, contains('"kern"'));
      expect(system, contains('"hilfsregel"'));
      expect(system, contains('"rechenregel"'));
      expect(system, contains('Ableitungsregeln'));
      expect(system, contains('Bruchrechnung'));
      expect(system, contains('ERFINDE NICHTS'));
      expect((messages.last as Map)['content'], contains('Folientext zur Integralrechnung'));
    });

    test('Antwort mit einfachen Backslashes (\\frac, \\theta) wird repariert statt zu Steuerzeichen', () async {
      // Das Modell vergisst, die Backslashes im JSON zu verdoppeln.
      final raw = '{"title":"T","sections":[{"title":"A","entries":[{"name":"Bruch","formula":"\\frac{a}{b}",'
          '"level":"rechenregel"},{"name":"Winkel","formula":"\\theta + \\beta","level":"kern"}]}]}';
      final client = MockClient((r) async => _chat(raw));
      final ai = AiService(apiKey: 'key', model: 'm', client: client);

      final sheet = (await ai.generateFormulaSheet('x')).sheet;
      final formulas = [for (final s in sheet.sections) for (final e in s.entries) e.formula];
      expect(formulas, [r'\frac{a}{b}', r'\theta + \beta']);
    });

    test('mehrere Folienabschnitte: Ergebnisse werden zusammengeführt, schon erfasste Formeln mitgegeben', () async {
      var calls = 0;
      final prompts = <String>[];
      final client = MockClient((r) async {
        calls++;
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        prompts.add(((body['messages'] as List).last as Map)['content'] as String);
        return _chat(jsonEncode({
          'title': 'Abschnitt $calls',
          'sections': [
            {
              'title': 'Integrationsregeln',
              'entries': [
                _entry('Regel $calls', 'x^$calls', 'kern'),
                _entry('Gemeinsam', r'\int 1\,dx = x', 'kern'), // in jedem Abschnitt
              ],
            },
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'm', client: client);
      final longText = 'Ein langer Satz mit genug Inhalt, um mehrere Chunks zu erzwingen. ' * 400;
      final progress = <List<int>>[];

      final result = await ai.generateFormulaSheet(
        longText,
        granularity: ChunkGranularity.fine,
        onProgress: (done, total) => progress.add([done, total]),
      );

      expect(calls, greaterThan(1));
      expect(progress.last, [calls, calls]);
      expect(result.title, 'Abschnitt 1'); // Titel des ersten Abschnitts
      expect(result.sheet.sections, hasLength(1)); // gleicher Abschnittstitel → zusammengelegt
      final names = result.sheet.sections.single.entries.map((e) => e.name).toList();
      expect(names.where((n) => n == 'Gemeinsam'), hasLength(1)); // nur einmal
      expect(names, containsAll(['Regel 1', 'Regel 2']));
      // Ab dem zweiten Abschnitt kennt die KI die schon erfassten Formeln.
      expect(prompts.first, isNot(contains('Bereits erfasste Formeln')));
      expect(prompts[1], contains('Bereits erfasste Formeln'));
      expect(prompts[1], contains('Regel 1'));
    });

    test('ohne Rolling Context bekommen weitere Abschnitte keine Liste', () async {
      final prompts = <String>[];
      final client = MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        prompts.add(((body['messages'] as List).last as Map)['content'] as String);
        return _chat(jsonEncode({
          'sections': [
            {
              'title': 'A',
              'entries': [_entry('E${prompts.length}', 'a${prompts.length}', 'kern')],
            },
          ],
        }));
      });
      final ai = AiService(apiKey: 'key', model: 'm', client: client);
      final longText = 'Ein langer Satz mit genug Inhalt, um mehrere Chunks zu erzwingen. ' * 400;
      await ai.generateFormulaSheet(longText, granularity: ChunkGranularity.fine, rollingContext: false);
      expect(prompts.length, greaterThan(1));
      expect(prompts.every((p) => !p.contains('Bereits erfasste Formeln')), isTrue);
    });

    test('keine Formeln in der Antwort: verständlicher Fehler mit Rohantwort', () async {
      final client = MockClient((r) async => _chat(jsonEncode({'title': 'Leer', 'sections': []})));
      final ai = AiService(apiKey: 'key', model: 'm', client: client);
      await expectLater(
        () => ai.generateFormulaSheet('Text ohne Formeln'),
        throwsA(isA<AiServiceException>()
            .having((e) => e.message, 'message', contains('keine Formeln'))
            .having((e) => e.rawResponse, 'rawResponse', isNotNull)),
      );
    });

    test('ohne Titel: "Formelsammlung"; kaputtes JSON wirft mit Rohantwort', () async {
      final ok = AiService(
        apiKey: 'key',
        model: 'm',
        client: MockClient((r) async => _chat(jsonEncode({
              'sections': [
                {
                  'title': 'A',
                  'entries': [_entry('E', 'a', 'kern')],
                },
              ],
            }))),
      );
      expect((await ok.generateFormulaSheet('x')).title, 'Formelsammlung');
      final broken = AiService(apiKey: 'key', model: 'm', client: MockClient((r) async => _chat('kein json')));
      await expectLater(
        () => broken.generateFormulaSheet('x'),
        throwsA(isA<AiServiceException>().having((e) => e.rawResponse, 'rawResponse', isNotNull)),
      );
    });
  });
}
