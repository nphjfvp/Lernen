import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/gantt_task.dart';
import 'package:lernen/services/gantt_scheduler.dart';

/// Die ERP-Aufgabe: BG Welle = Zahnrad 1 + Welle, Start Tag 1, Liefertermin Tag 20.
GanttTask erpTask({GanttDirection direction = GanttDirection.forward, GanttCounting counting = GanttCounting.inclusive}) =>
    GanttTask.fromMap({
      'direction': direction == GanttDirection.forward ? 'vorwärts' : 'rückwärts',
      'counting': counting == GanttCounting.points ? 'Zeitpunkte' : 'Tage einschließlich',
      'starttermin': 1,
      'liefertermin': 'Tag 20',
      'items': [
        {
          'id': 'z',
          'name': 'Zahnrad 1',
          'operations': [
            {'name': 'Drehen', 'duration': 1},
            {'name': 'Wälzfräsen', 'dauer': 5},
            {'name': 'Härten', 'duration': 2},
            {'name': 'Hartbearbeitung', 'duration': '3 Tage'},
          ],
        },
        {
          'name': 'Welle',
          'unsicher': true,
          'operations': [
            {'name': 'Drehen', 'duration': 2},
            {'name': 'Profilrollen', 'duration': 1},
            {'name': 'Härten', 'duration': 2},
            {'name': 'Schleifen', 'duration': 2},
          ],
        },
        {
          'id': 'b',
          'name': 'BG Welle',
          'needs': ['z', 'Welle'],
          'operations': [
            {'name': 'Montage', 'duration': 2},
          ],
        },
      ],
      'questions': [
        for (final item in ['z', 'Welle', 'b']) ...[
          {'item': item, 'ask': 'Starttermin'},
          {'item': item, 'ask': 'Endtermin'},
          {'item': item, 'ask': 'Liegezeit'},
        ],
      ],
    })!;

Map<String, int?> starts(GanttPlan plan) => {for (final e in plan.opStarts.entries) e.key: e.value};

void main() {
  group('GanttTask lesen', () {
    test('tolerant: deutsche Schlüssel, Kennungen, Abhängigkeit über Namen, Fragen als Text', () {
      final t = erpTask();
      expect(t.items.map((i) => i.id), ['z', 't2', 'b']);
      expect(t.item('b')!.needs, ['z', 't2']);
      expect(t.item('z')!.operations[3].duration, 3);
      expect(t.item('t2')!.uncertain, isTrue);
      expect(t.hasUncertain, isTrue);
      expect(t.confirmed().hasUncertain, isFalse);
      expect(t.due, 20);
      expect(t.questions, hasLength(9));
      expect(t.questions.first, const GanttQuestion(itemId: 'z', ask: GanttAsk.start));
      expect(t.finalItems.single.name, 'BG Welle');
      expect(t.topologicalOrder!.last.id, 'b');
    });

    test('Speichern und wieder lesen ändert nichts', () {
      final t = erpTask(direction: GanttDirection.backward, counting: GanttCounting.points);
      final again = GanttTask.fromMap(t.toMap())!;
      expect(again.toMap(), t.toMap());
      expect(t.toMap()['kind'], 'gantt');
    });

    test('ungültig: Kreis, leer, rückwärts ohne Liefertermin', () {
      expect(
          GanttTask.fromMap({
            'items': [
              {'id': 'a', 'name': 'A', 'needs': ['b'], 'operations': [{'name': 'x', 'duration': 1}]},
              {'id': 'b', 'name': 'B', 'needs': ['a'], 'operations': [{'name': 'y', 'duration': 1}]},
            ],
          }),
          isNull);
      expect(GanttTask.fromMap({'items': []}), isNull);
      expect(
          GanttTask.fromMap({
            'direction': 'backward',
            'items': [
              {'name': 'A', 'operations': [{'name': 'x', 'duration': 1}]},
            ],
          }),
          isNull);
    });

    test('Beschreibung für KI-Hilfen', () {
      final text = erpTask().describe();
      expect(text, startsWith('Vorwärtsterminierung, Starttermin Tag 1, Liefertermin Tag 20'));
      expect(text, contains('BG Welle (braucht Zahnrad 1, Welle): Montage 2 Tage'));
      expect(text, contains('Gesucht: Start Zahnrad 1'));
    });
  });

  group('Vorwärtsterminierung', () {
    test('Termine, Liegezeiten und Puffer der ERP-Aufgabe', () {
      final t = erpTask();
      final p = GanttScheduler.plan(t);
      expect(p.opStarts, {
        'z#0': 1, 'z#1': 2, 'z#2': 7, 'z#3': 9, //
        't2#0': 1, 't2#1': 3, 't2#2': 4, 't2#3': 6,
        'b#0': 12,
      });
      int? a(String item, GanttAsk ask) => p.answer(GanttQuestion(itemId: item, ask: ask));
      expect([a('z', GanttAsk.start), a('z', GanttAsk.end), a('z', GanttAsk.slack)], [1, 11, 0]);
      expect([a('t2', GanttAsk.start), a('t2', GanttAsk.end), a('t2', GanttAsk.slack)], [1, 7, 4]);
      expect([a('b', GanttAsk.start), a('b', GanttAsk.end), a('b', GanttAsk.slack)], [12, 13, 7]);
      expect([a('z', GanttAsk.buffer), a('t2', GanttAsk.buffer), a('b', GanttAsk.buffer)], [7, 11, 7]);
      expect(p.problems, isEmpty);
      expect(p.span, (1, 13));
    });

    test('Zählweise Zeitpunkte: Enden eins später, Liegezeit der BG eins weniger', () {
      final p = GanttScheduler.plan(erpTask(counting: GanttCounting.points));
      int? a(String item, GanttAsk ask) => p.answer(GanttQuestion(itemId: item, ask: ask));
      expect([a('z', GanttAsk.end), a('t2', GanttAsk.end), a('b', GanttAsk.start), a('b', GanttAsk.end)], [12, 8, 12, 14]);
      expect([a('t2', GanttAsk.slack), a('b', GanttAsk.slack)], [4, 6]);
    });

    test('Liefertermin nicht zu halten', () {
      final p = GanttScheduler.plan(erpTask().copyWith(due: 12));
      expect(p.problems.single, contains('erst an Tag 13 fertig, 1 Tag zu spät'));
    });
  });

  group('Rückwärtsterminierung', () {
    test('alles so spät wie möglich, Liegezeiten 0, Puffer zum Starttermin', () {
      final p = GanttScheduler.plan(erpTask(direction: GanttDirection.backward));
      expect(p.opStarts, {
        'b#0': 19, //
        'z#0': 8, 'z#1': 9, 'z#2': 14, 'z#3': 16,
        't2#0': 12, 't2#1': 14, 't2#2': 15, 't2#3': 17,
      });
      expect([for (final id in ['z', 't2', 'b']) p.items[id]!.slack], [0, 0, 0]);
      expect([for (final id in ['z', 't2', 'b']) p.items[id]!.buffer], [7, 11, 7]);
    });

    test('Starttermin reicht nicht', () {
      final p = GanttScheduler.plan(erpTask(direction: GanttDirection.backward).copyWith(due: 10));
      expect(p.problems.single, contains('Zahnrad 1 müsste an Tag -2 beginnen'));
    });
  });

  group('eigenes Diagramm prüfen', () {
    test('richtig, Lücke, Folgefehler und fehlend (vorwärts)', () {
      final t = erpTask();
      final ref = GanttScheduler.plan(t);
      final user = starts(ref)
        ..['t2#2'] = 5
        ..['t2#3'] = 7
        ..['z#3'] = null;
      final bars = GanttScheduler.judgeBars(t, ref, user);
      expect(bars['z#0']!.status, BarStatus.ok);
      expect(bars['t2#2']!.status, BarStatus.bad);
      expect(bars['t2#2']!.text, 'beginnt erst an Tag 5. Vorwärts geht es ohne Lücke weiter, also an Tag 4.');
      expect(bars['t2#3']!.status, BarStatus.follow);
      expect(bars['z#3']!.status, BarStatus.missing);
      expect(bars['b#0']!.status, BarStatus.ok, reason: 'stimmt mit der Lösung überein');
    });

    test('Überlappung, falscher Start, Montage vor den Teilen', () {
      final t = erpTask();
      final ref = GanttScheduler.plan(t);
      final user = starts(ref)
        ..['z#0'] = 2
        ..['z#1'] = 1
        ..['b#0'] = 10;
      final bars = GanttScheduler.judgeBars(t, ref, user);
      expect(bars['z#0']!.text, contains('am Starttermin, Tag 1'));
      expect(bars['z#1']!.text, 'beginnt an Tag 1, aber Drehen läuft bei dir bis Tag 2.');
      expect(bars['b#0']!.text, 'beginnt an Tag 10, aber Zahnrad 1 ist bei dir erst an Tag 11 fertig.');
    });

    test('rückwärts: Ende am Liefertermin, Lücke und Folgefehler', () {
      final t = erpTask(direction: GanttDirection.backward);
      final ref = GanttScheduler.plan(t);
      final user = starts(ref)
        ..['b#0'] = 18
        ..['z#2'] = 13
        ..['z#1'] = 8;
      final bars = GanttScheduler.judgeBars(t, ref, user);
      expect(bars['b#0']!.text, contains('genau am Liefertermin, Tag 20'));
      expect(bars['z#2']!.text, 'endet schon an Tag 14. Rückwärts endet es direkt vor Hartbearbeitung, also an Tag 15.');
      expect(bars['z#1']!.status, BarStatus.follow);
    });

    test('Antworten: richtig, Folgefehler aus dem eigenen Diagramm, falsch, leer', () {
      final t = erpTask();
      final ref = GanttScheduler.plan(t);
      final user = starts(ref)
        ..['t2#2'] = 5
        ..['t2#3'] = 7;
      final answers = GanttScheduler.judgeAnswers(t, ref, user, {
        'z.start': '1',
        'z.end': 'Tag 11',
        't2.end': '8',
        't2.slack': '3',
        'b.slack': '6',
      });
      expect(answers['z.start']!.status, AnswerStatus.ok);
      expect(answers['z.end']!.status, AnswerStatus.ok);
      expect(answers['t2.end']!.status, AnswerStatus.follow);
      expect(answers['t2.slack']!.status, AnswerStatus.follow);
      expect(answers['b.slack']!.status, AnswerStatus.bad);
      expect(answers['b.slack']!.expected, 7);
      expect(answers['b.start']!.status, AnswerStatus.empty);
    });
  });

  group('Tipps und Rechenweg', () {
    test('Tipp zum ersten Problem', () {
      final t = erpTask();
      final ref = GanttScheduler.plan(t);
      expect(GanttScheduler.hint(t, ref, const {}, const {}), contains('Fang mit Zahnrad 1 · Drehen an'));
      final user = starts(ref)..['z#2'] = null;
      expect(GanttScheduler.hint(t, ref, user, const {}),
          'Härten (Zahnrad 1) beginnt am Tag nach Wälzfräsen. Wälzfräsen endet bei dir an Tag 6.');
      final montage = starts(ref)..['b#0'] = 3;
      expect(GanttScheduler.hint(t, ref, montage, const {}), contains('Zahnrad 1 an Tag 11 und Welle an Tag 7'));
      expect(GanttScheduler.hint(t, ref, starts(ref), const {}), contains('aus deinem Diagramm ab'));
      final all = {for (final q in t.questions) q.key: '${ref.answer(q)}'};
      expect(GanttScheduler.hint(t, ref, starts(ref), all), 'Alles eingetragen – jetzt prüfen.');
    });

    test('So rechnet man – vorwärts', () {
      final t = erpTask();
      final lines = GanttScheduler.explain(t, GanttScheduler.plan(t));
      expect(lines.join('\n'), contains('Zahnrad 1: Drehen Tag 1, Wälzfräsen Tag 2–6, Härten Tag 7–8, Hartbearbeitung Tag 9–11'));
      expect(lines.join('\n'), contains('Welle: 12 − 7 − 1 = 4 Tage'));
      expect(lines.join('\n'), contains('BG Welle: 20 − 13 = 7 Tage bis zum Liefertermin'));
      expect(GanttScheduler.solutionText(t), contains('Liegezeit Welle = 4'));
    });

    test('andere Zahlen zum Üben: Dauern ändern sich, Liefertermin bleibt erreichbar', () {
      final t = erpTask().copyWith(due: 13);
      final v = GanttScheduler.variant(t, math.Random(3));
      expect(v.items.expand((i) => i.operations).every((o) => o.duration >= 1 && !o.uncertain), isTrue);
      expect(GanttScheduler.plan(v).problems, isEmpty);
      expect(v.questions, t.questions);
    });
  });
}
