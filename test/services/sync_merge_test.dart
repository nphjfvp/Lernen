import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/sync_merge.dart';

Map<String, dynamic> _module(String id, {String name = 'Fach', String? exam}) =>
    {'id': id, 'name': name, 'examDate': exam, 'colorValue': 1};

Map<String, dynamic> _card(String id, String moduleId, {String front = 'F', String? lastReview, int reps = 0, String? back}) => {
      'id': id,
      'moduleId': moduleId,
      'front': front,
      'back': back ?? 'B',
      'lastReview': lastReview,
      'reps': reps,
    };

Map<String, dynamic> _payload({
  List<Map<String, dynamic>> modules = const [],
  List<Map<String, dynamic>> flashcards = const [],
  List<Map<String, dynamic>> concepts = const [],
  List<Map<String, dynamic>> labs = const [],
  List<Map<String, dynamic>> chats = const [],
  List<Map<String, dynamic>> exams = const [],
  List<String> days = const [],
  Object? daily,
}) =>
    {
      'modules': modules,
      'materials': const [],
      'summaries': const [],
      'concepts': concepts,
      'flashcards': flashcards,
      'lectureUnits': const [],
      'labExperiments': labs,
      'chatMessages': chats,
      'masterySnapshots': const [],
      'mockExamResults': exams,
      'studyDays': days,
      'dailySession': daily,
    };

List<String> _ids(SyncMergeResult r, String collection) =>
    [for (final e in (r.payload[collection] as List)) (e as Map)['id'] as String]..sort();

void main() {
  group('Union: neu auf einer Seite', () {
    test('neuer Kurs vom Handy und ein Kurs vom PC: beide bleiben (auch ohne Basisstand)', () {
      final pc = _payload(modules: [_module('alt')], flashcards: [_card('c1', 'alt')]);
      final phone = _payload(modules: [_module('neu', name: 'Neuer Kurs')], flashcards: [_card('c9', 'neu')]);
      final result = mergeSyncPayloads(local: pc, remote: phone, base: const {});
      expect(_ids(result, 'modules'), ['alt', 'neu']);
      expect(_ids(result, 'flashcards'), ['c1', 'c9']);
      expect(result.changedLocally, greaterThan(0));
      expect(result.changedRemotely, greaterThan(0));
    });

    test('identische Stände: nichts ändert sich', () {
      final a = _payload(modules: [_module('m')], flashcards: [_card('c', 'm')], days: ['2026-09-01']);
      final result = mergeSyncPayloads(local: a, remote: a, base: hashesOfPayload(a));
      expect(result.changedLocally, 0);
      expect(result.changedRemotely, 0);
      expect(result.conflicts, 0);
    });
  });

  group('Fortschritt: der weitere Stand gewinnt', () {
    test('nur der PC hat gelernt: die Karte vom PC bleibt, das Handy zieht nach', () {
      final base = _payload(modules: [_module('m')], flashcards: [_card('c', 'm')]);
      final pc = _payload(modules: [_module('m')], flashcards: [_card('c', 'm', lastReview: '2026-09-28T10:00:00', reps: 5)]);
      final result = mergeSyncPayloads(local: pc, remote: base, base: hashesOfPayload(base));
      expect((result.payload['flashcards'] as List).single['reps'], 5);
      expect(result.conflicts, 0);
      expect(result.collections['flashcards']!.changedLocally, 0);
      expect(result.collections['flashcards']!.changedRemotely, 1);
    });

    test('nur das Handy hat gelernt: Karte kommt aufs Gerät', () {
      final base = _payload(modules: [_module('m')], flashcards: [_card('c', 'm')]);
      final phone = _payload(modules: [_module('m')], flashcards: [_card('c', 'm', lastReview: '2026-09-29T08:00:00', reps: 2)]);
      final result = mergeSyncPayloads(local: base, remote: phone, base: hashesOfPayload(base));
      expect((result.payload['flashcards'] as List).single['reps'], 2);
      expect(result.collections['flashcards']!.changedLocally, 1);
    });

    test('beide haben dieselbe Karte gelernt: die spätere Wiederholung gilt, egal auf welcher Seite', () {
      final base = _payload(modules: [_module('m')], flashcards: [_card('c', 'm')]);
      final pc = _payload(modules: [_module('m')], flashcards: [_card('c', 'm', lastReview: '2026-09-28T10:00:00', reps: 5)]);
      final phone = _payload(modules: [_module('m')], flashcards: [_card('c', 'm', lastReview: '2026-09-29T08:00:00', reps: 3)]);
      final b = hashesOfPayload(base);
      final onPc = mergeSyncPayloads(local: pc, remote: phone, base: b);
      final onPhone = mergeSyncPayloads(local: phone, remote: pc, base: b);
      expect((onPc.payload['flashcards'] as List).single['lastReview'], '2026-09-29T08:00:00');
      expect((onPhone.payload['flashcards'] as List).single['lastReview'], '2026-09-29T08:00:00');
      expect(onPc.conflicts, 1);
    });

    test('gleiche letzte Wiederholung: mehr Wiederholungen gewinnt; sonst lokal', () {
      final base = _payload(modules: [_module('m')], flashcards: [_card('c', 'm')]);
      final a = _payload(modules: [_module('m')], flashcards: [_card('c', 'm', lastReview: '2026-09-28T10:00:00', reps: 2)]);
      final b = _payload(modules: [_module('m')], flashcards: [_card('c', 'm', lastReview: '2026-09-28T10:00:00', reps: 4)]);
      expect((mergeSyncPayloads(local: a, remote: b, base: hashesOfPayload(base)).payload['flashcards'] as List).single['reps'], 4);
      // Nur eine Seite hat je gelernt.
      final never = _payload(modules: [_module('m')], flashcards: [_card('c', 'm', front: 'geändert')]);
      final result = mergeSyncPayloads(local: never, remote: a, base: hashesOfPayload(base));
      expect((result.payload['flashcards'] as List).single['lastReview'], '2026-09-28T10:00:00');
    });
  });

  group('Löschen über den Basisstand', () {
    final m = _module('m');
    final base = _payload(modules: [m, _module('weg')], flashcards: [_card('c1', 'm'), _card('c2', 'm')]);

    test('auf dem Handy gelöscht, am PC nicht angefasst: fällt auch am PC weg', () {
      final phone = _payload(modules: [m, _module('weg')], flashcards: [_card('c1', 'm')]);
      final result = mergeSyncPayloads(local: base, remote: phone, base: hashesOfPayload(base));
      expect(_ids(result, 'flashcards'), ['c1']);
    });

    test('am PC gelöscht, aufs Handy zurückgetragen', () {
      final pc = _payload(modules: [m, _module('weg')], flashcards: [_card('c1', 'm')]);
      final result = mergeSyncPayloads(local: pc, remote: base, base: hashesOfPayload(base));
      expect(_ids(result, 'flashcards'), ['c1']);
      expect(result.collections['flashcards']!.changedRemotely, 1);
    });

    test('dort gelöscht, hier weitergelernt: bleibt (nichts geht verloren)', () {
      final phone = _payload(modules: [m, _module('weg')], flashcards: [_card('c1', 'm')]);
      final pc = _payload(
        modules: [m, _module('weg')],
        flashcards: [_card('c1', 'm'), _card('c2', 'm', lastReview: '2026-09-28T10:00:00', reps: 3)],
      );
      final result = mergeSyncPayloads(local: pc, remote: phone, base: hashesOfPayload(base));
      expect(_ids(result, 'flashcards'), ['c1', 'c2']);
    });

    test('Fach gelöscht: seine Karten fallen mit weg, auch wenn sie dort noch weitergelernt wurden', () {
      final phone = _payload(modules: [m], flashcards: [_card('c1', 'm'), _card('c2', 'm')]);
      final pc = _payload(
        modules: [m, _module('weg')],
        flashcards: [_card('c1', 'm'), _card('c2', 'm'), _card('c3', 'weg'), _card('c4', 'weg')],
      );
      final baseWithWeg = _payload(
        modules: [m, _module('weg')],
        flashcards: [_card('c1', 'm'), _card('c2', 'm'), _card('c3', 'weg'), _card('c4', 'weg')],
      );
      final result = mergeSyncPayloads(local: pc, remote: phone, base: hashesOfPayload(baseWithWeg));
      expect(_ids(result, 'modules'), ['m']);
      expect(_ids(result, 'flashcards'), ['c1', 'c2']);
    });

    test('ohne Basisstand wird nie gelöscht, nur ergänzt (erster Abgleich)', () {
      final phone = _payload(modules: [m], flashcards: [_card('c1', 'm')]);
      final pc = _payload(modules: [m, _module('weg')], flashcards: [_card('c1', 'm'), _card('c2', 'm')]);
      final result = mergeSyncPayloads(local: pc, remote: phone, base: const {});
      expect(_ids(result, 'modules'), ['m', 'weg']);
      expect(_ids(result, 'flashcards'), ['c1', 'c2']);
    });
  });

  group('Andere Sammlungen', () {
    test('Kurs auf beiden Seiten anders geändert: die lokale Fassung gilt, es zählt als Konflikt', () {
      final base = _payload(modules: [_module('m', name: 'Alt')]);
      final pc = _payload(modules: [_module('m', name: 'Vom PC')]);
      final phone = _payload(modules: [_module('m', name: 'Vom Handy')]);
      final result = mergeSyncPayloads(local: pc, remote: phone, base: hashesOfPayload(base));
      expect((result.payload['modules'] as List).single['name'], 'Vom PC');
      expect(result.conflicts, 1);
    });

    test('nur eine Seite ändert den Kurs: diese Änderung kommt an', () {
      final base = _payload(modules: [_module('m', name: 'Alt')]);
      final phone = _payload(modules: [_module('m', name: 'Umbenannt')]);
      final result = mergeSyncPayloads(local: base, remote: phone, base: hashesOfPayload(base));
      expect((result.payload['modules'] as List).single['name'], 'Umbenannt');
      expect(result.conflicts, 0);
    });

    test('Laborversuch: der mit mehr eigener Arbeit gewinnt', () {
      Map<String, dynamic> lab(String answer) => {
            'id': 'lab',
            'moduleId': 'm',
            'prep': [
              {'id': 'q', 'answer': answer},
            ],
            'parts': const [],
            'report': const [],
          };
      final base = _payload(modules: [_module('m')], labs: [lab('')]);
      final pc = _payload(modules: [_module('m')], labs: [lab('Eine lange Antwort mit viel Text.')]);
      final phone = _payload(modules: [_module('m')], labs: [lab('kurz')]);
      final result = mergeSyncPayloads(local: phone, remote: pc, base: hashesOfPayload(base));
      expect((result.payload['labExperiments'] as List).single['prep'][0]['answer'], 'Eine lange Antwort mit viel Text.');
    });

    test('Lerntage werden vereinigt, Probeklausuren und Chats ergänzt', () {
      final exam1 = {'moduleId': 'm', 'takenAt': '2026-09-01T10:00:00', 'correct': 5, 'total': 10};
      final exam2 = {'moduleId': 'm', 'takenAt': '2026-09-20T10:00:00', 'correct': 8, 'total': 10};
      final pc = _payload(
        modules: [_module('m')],
        days: ['2026-09-01', '2026-09-02'],
        exams: [exam1],
        chats: [
          {'id': 'x1', 'moduleId': 'm', 'content': 'a'}
        ],
      );
      final phone = _payload(
        modules: [_module('m')],
        days: ['2026-09-02', '2026-09-03'],
        exams: [exam2],
        chats: [
          {'id': 'x2', 'moduleId': 'm', 'content': 'b'}
        ],
      );
      final result = mergeSyncPayloads(local: pc, remote: phone, base: const {});
      expect(result.payload['studyDays'], ['2026-09-01', '2026-09-02', '2026-09-03']);
      expect((result.payload['mockExamResults'] as List), hasLength(2));
      expect(_ids(result, 'chatMessages'), ['x1', 'x2']);
      expect(result.collections['studyDays']!.changedLocally, 1);
      expect(result.collections['studyDays']!.changedRemotely, 1);
    });

    test('Sammelliste „Noch nicht interaktiv“: beide Geräte ergänzen sich, gelöschte Einträge bleiben weg', () {
      Map<String, dynamic> u(String id) => {'id': id, 'moduleId': 'm', 'text': 'Aufgabe $id', 'createdAt': '2026-10-01T00:00:00.000'};
      final base = {..._payload(modules: [_module('m')]), 'unsupportedTasks': [u('alt'), u('weg')]};
      final pc = {..._payload(modules: [_module('m')]), 'unsupportedTasks': [u('alt'), u('pc')]};
      final phone = {..._payload(modules: [_module('m')]), 'unsupportedTasks': [u('alt'), u('weg'), u('handy')]};
      final result = mergeSyncPayloads(local: pc, remote: phone, base: hashesOfPayload(base));
      expect(_ids(result, 'unsupportedTasks'), ['alt', 'handy', 'pc']);
    });

    test('der Daily-Stand kommt aus der Cloud', () {
      final result = mergeSyncPayloads(
        local: _payload(modules: [_module('m')], daily: {'a': 1}),
        remote: _payload(modules: [_module('m')], daily: {'a': 2}),
        base: const {},
      );
      expect(result.payload['dailySession'], {'a': 2});
    });

    test('Einträge ohne Kennung werden übergangen statt den Abgleich zu stören', () {
      final broken = _payload(modules: [_module('m'), {'name': 'ohne id'}], flashcards: [_card('c', 'm')]);
      final result = mergeSyncPayloads(local: broken, remote: _payload(modules: [_module('m')]), base: const {});
      expect(_ids(result, 'modules'), ['m']);
    });
  });

  group('Materialien', () {
    Map<String, dynamic> material(String id, {List<Map<String, dynamic>> pageNotes = const [], String notes = '', int marks = 0}) => {
          'id': id,
          'moduleId': 'm',
          'fileName': 'skript.pdf',
          'notes': notes,
          'pageNotes': pageNotes,
          'highlights': [for (var i = 0; i < marks; i++) {'page': i, 'text': 'Stelle $i'}],
        };
    Map<String, dynamic> payload(Map<String, dynamic> m) => {..._payload(modules: [_module('m')]), 'materials': [m]};

    test('auf beiden Seiten geändert: Markierungen, Seitennotizen und Notizen beider Seiten bleiben', () {
      final base = payload(material('mat'));
      final pc = payload(material('mat', pageNotes: [{'id': 'a', 'page': 1, 'text': 'vom PC'}], notes: 'PC-Notiz'));
      final phone = payload(material('mat', pageNotes: [{'id': 'b', 'page': 2, 'text': 'vom Handy'}], marks: 2, notes: 'Handy-Notiz'));
      final result = mergeSyncPayloads(local: pc, remote: phone, base: hashesOfPayload(base));
      final merged = (result.payload['materials'] as List).single as Map;
      expect((merged['pageNotes'] as List).map((n) => (n as Map)['id']), ['a', 'b']);
      expect(merged['highlights'], hasLength(2));
      expect(merged['notes'], allOf(contains('PC-Notiz'), contains('Handy-Notiz')));
      expect(result.conflicts, 1);
    });

    test('dieselbe Notiz auf beiden Seiten wird nicht doppelt', () {
      final note = {'id': 'a', 'page': 1, 'text': 'gleich'};
      final result = mergeSyncPayloads(
        local: payload(material('mat', pageNotes: [note], notes: 'Text')),
        remote: payload(material('mat', pageNotes: [note], marks: 1, notes: 'Text')),
        base: const {},
      );
      final merged = (result.payload['materials'] as List).single as Map;
      expect(merged['pageNotes'], hasLength(1));
      expect(merged['notes'], 'Text');
    });
  });

  test('Basisstand: 1.0 und 1 sind derselbe Wert (Web und Handy unterscheiden das nicht)', () {
    expect(recordHash({'a': 1.0, 'b': [2.0]}), recordHash({'a': 1, 'b': [2]}));
    expect(recordHash({'a': 1.5}), isNot(recordHash({'a': 1})));
  });

  test('Basisstand: Hash ist von der Reihenfolge der Felder unabhängig', () {
    expect(recordHash({'a': 1, 'b': [1, 2], 'c': {'x': 1, 'y': 2}}), recordHash({'c': {'y': 2, 'x': 1}, 'b': [1, 2], 'a': 1}));
    expect(recordHash({'a': 1}), isNot(recordHash({'a': 2})));
    final hashes = hashesOfPayload(_payload(modules: [_module('m')], flashcards: [_card('c', 'm')]));
    expect(hashes['modules']!.keys, ['m']);
    expect(hashes['flashcards']!.keys, ['c']);
  });

  test('Zusammenfassung in Worten', () {
    final base = _payload(modules: [_module('m')]);
    final phone = _payload(modules: [_module('m'), _module('neu')], flashcards: [_card('c', 'neu'), _card('d', 'neu')]);
    final result = mergeSyncPayloads(local: base, remote: phone, base: hashesOfPayload(base));
    expect(describeMerge(result), 'Auf diesem Gerät neu oder geändert: 1 Fächer, 2 Karten.');
    final same = mergeSyncPayloads(local: base, remote: base, base: hashesOfPayload(base));
    expect(describeMerge(same), 'Beide Stände waren schon gleich.');
  });
}
