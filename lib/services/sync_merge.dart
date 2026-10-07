import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/mastery_snapshot.dart';

/// Wie eine Sammlung des Sync-Stands ihre Einträge benennt.
typedef _KeyOf = String? Function(Map<String, dynamic> record);

/// Was beim Zusammenführen einer Sammlung geschah.
class CollectionMerge {
  const CollectionMerge({this.changedLocally = 0, this.changedRemotely = 0, this.conflicts = 0});

  /// Einträge, die sich auf DIESEM Gerät ändern (neu, aktualisiert, entfernt).
  final int changedLocally;

  /// Einträge, die in der Cloud neu oder anders sein werden (hier neu, hier
  /// weiter, hier gelöscht).
  final int changedRemotely;

  /// Einträge, die auf beiden Seiten geändert waren und nach einer Regel
  /// entschieden wurden.
  final int conflicts;
}

/// Ergebnis von [mergeSyncPayloads].
class SyncMergeResult {
  const SyncMergeResult({required this.payload, required this.collections});

  /// Der zusammengeführte Stand (Format wie SyncService.buildSyncPayload).
  final Map<String, dynamic> payload;
  final Map<String, CollectionMerge> collections;

  int get changedLocally => collections.values.fold(0, (sum, c) => sum + c.changedLocally);
  int get changedRemotely => collections.values.fold(0, (sum, c) => sum + c.changedRemotely);
  int get conflicts => collections.values.fold(0, (sum, c) => sum + c.conflicts);
}

/// Der Stand zum Zeitpunkt des letzten Abgleichs: je Sammlung Kennung → Hash
/// des Eintrags. Ohne ihn lässt sich nicht sagen, ob etwas gelöscht oder neu
/// dazugekommen ist (siehe [mergeSyncPayloads]).
typedef SyncBase = Map<String, Map<String, String>>;

/// Sammlungen des Sync-Stands mit Einträgen, die sich über eine Kennung
/// zuordnen lassen, und wie diese Kennung gebildet wird.
final Map<String, _KeyOf> _keyed = {
  'modules': _idKey,
  'materials': _idKey,
  'summaries': _idKey,
  'concepts': _idKey,
  'flashcards': _idKey,
  'lectureUnits': _idKey,
  'labExperiments': _idKey,
  'chatMessages': _idKey,
  'unsupportedTasks': _idKey,
  'masterySnapshots': (r) {
    final date = DateTime.tryParse('${r['date']}');
    return date == null ? null : MasterySnapshot.fromMap(r).dateKey;
  },
  'mockExamResults': (r) => r['moduleId'] == null || r['takenAt'] == null ? null : '${r['moduleId']}|${r['takenAt']}',
};

String? _idKey(Map<String, dynamic> record) {
  final id = record['id'];
  return id == null || '$id'.isEmpty ? null : '$id';
}

/// Sammlungen, deren Einträge zu einem Fach gehören – bleiben sie ohne ihr
/// Fach übrig (Fach auf einer Seite gelöscht), werden sie entfernt.
const _perModule = [
  'materials',
  'summaries',
  'concepts',
  'flashcards',
  'lectureUnits',
  'labExperiments',
  'chatMessages',
  'unsupportedTasks',
  'mockExamResults',
];

/// Stabiler Hash eines Eintrags (Schlüssel sortiert, damit die Reihenfolge in
/// der Datenbank keine Rolle spielt).
String recordHash(Object? record) {
  Object? canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) return [for (final e in v) canonical(e)];
    // 1.0 und 1 sind dasselbe (im Web gibt es keinen Unterschied, auf dem Handy
    // schon) – sonst wären dieselben Karten je nach Gerät "verschieden".
    if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
    return v;
  }

  return sha1.convert(utf8.encode(jsonEncode(canonical(record)))).toString();
}

/// Kennung → Hash für jede Sammlung des Stands (für den Basisstand).
SyncBase hashesOfPayload(Map<String, dynamic> payload) {
  final result = <String, Map<String, String>>{};
  for (final entry in _keyed.entries) {
    final hashes = <String, String>{};
    for (final record in _records(payload[entry.key])) {
      final key = entry.value(record);
      if (key != null) hashes[key] = recordHash(record);
    }
    result[entry.key] = hashes;
  }
  return result;
}

List<Map<String, dynamic>> _records(Object? list) => [
      if (list is List)
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
    ];

/// Führt den lokalen und den Cloud-Stand zusammen – Dreiwege-Vergleich gegen
/// den Basisstand [base] (was beide beim letzten Abgleich gemeinsam hatten):
///
/// - Nur auf einer Seite vorhanden: neu → wird übernommen; war es im Basisstand
///   und ist dort unverändert, wurde es auf der anderen Seite gelöscht → fällt
///   weg; wurde es hier verändert und dort gelöscht, bleibt es (nichts geht
///   verloren).
/// - Auf beiden Seiten gleich: bleibt.
/// - Nur auf einer Seite seit dem Basisstand geändert: diese Fassung gilt.
/// - Auf beiden Seiten geändert (oder kein Basisstand): Karten – die mit dem
///   späteren Lernstand (letzte Wiederholung, dann Anzahl Wiederholungen),
///   Laborversuche – die mit mehr eigenem Text, sonst die lokale Fassung. Was
///   dabei verworfen wird, steht in den Sicherungen (SyncBackupService).
///
/// Ohne Basisstand (erster Abgleich dieses Geräts) kann nichts als gelöscht
/// gelten – es wird nur ergänzt. Einträge, deren Fach wegfällt, werden
/// entfernt. Lerntage werden vereinigt; der heutige Daily-Stand kommt aus der
/// Cloud (der Download führt ihn mit dem lokalen zusammen).
SyncMergeResult mergeSyncPayloads({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
  required SyncBase base,
}) {
  final merged = <String, dynamic>{};
  final stats = <String, CollectionMerge>{};

  for (final entry in _keyed.entries) {
    final name = entry.key;
    final keyOf = entry.value;
    Map<String, Map<String, dynamic>> byKey(Object? list) => {
          for (final r in _records(list))
            if (keyOf(r) != null) keyOf(r)!: r,
        };
    final l = byKey(local[name]);
    final r = byKey(remote[name]);
    final b = base[name] ?? const <String, String>{};
    final result = <String, Map<String, dynamic>>{};
    var conflicts = 0;

    for (final key in {...l.keys, ...r.keys}) {
      final lr = l[key];
      final rr = r[key];
      final bh = b[key];
      if (lr != null && rr != null) {
        final lh = recordHash(lr);
        final rh = recordHash(rr);
        if (lh == rh) {
          result[key] = lr;
        } else {
          final localChanged = bh == null || lh != bh;
          final remoteChanged = bh == null || rh != bh;
          if (localChanged && !remoteChanged) {
            result[key] = lr;
          } else if (remoteChanged && !localChanged) {
            result[key] = rr;
          } else {
            conflicts++;
            result[key] = _resolve(name, lr, rr);
          }
        }
      } else if (lr != null) {
        // Nur hier. Neu, oder dort gelöscht?
        if (bh == null || recordHash(lr) != bh) result[key] = lr;
      } else if (rr != null) {
        if (bh == null || recordHash(rr) != bh) result[key] = rr;
      }
    }
    merged[name] = result;
    stats[name] = CollectionMerge(conflicts: conflicts);
  }

  // Einträge ohne ihr Fach entfernen.
  final moduleKeys = (merged['modules'] as Map<String, Map<String, dynamic>>).keys.toSet();
  for (final name in _perModule) {
    (merged[name] as Map<String, Map<String, dynamic>>).removeWhere((_, record) => !moduleKeys.contains('${record['moduleId']}'));
  }

  // Zählen, was sich auf welcher Seite ändert, und in Listen zurückverwandeln.
  final payload = <String, dynamic>{};
  for (final entry in _keyed.entries) {
    final name = entry.key;
    final keyOf = entry.value;
    final mergedMap = merged[name] as Map<String, Map<String, dynamic>>;
    Map<String, String> hashes(Object? list) => {
          for (final rec in _records(list))
            if (keyOf(rec) != null) keyOf(rec)!: recordHash(rec),
        };
    final lh = hashes(local[name]);
    final rh = hashes(remote[name]);
    final mh = {for (final e in mergedMap.entries) e.key: recordHash(e.value)};
    int differences(Map<String, String> side) =>
        {...side.keys, ...mh.keys}.where((k) => side[k] != mh[k]).length;
    stats[name] = CollectionMerge(
      changedLocally: differences(lh),
      changedRemotely: differences(rh),
      conflicts: stats[name]!.conflicts,
    );
    payload[name] = mergedMap.values.toList();
  }

  // Lerntage: vereinigen.
  final localDays = {for (final d in (local['studyDays'] as List? ?? const [])) '$d'};
  final remoteDays = {for (final d in (remote['studyDays'] as List? ?? const [])) '$d'};
  final days = {...localDays, ...remoteDays}.toList()..sort();
  payload['studyDays'] = days;
  stats['studyDays'] = CollectionMerge(
    changedLocally: days.length - localDays.length,
    changedRemotely: days.length - remoteDays.length,
  );
  // Der Daily-Stand wird beim Anwenden mit dem lokalen zusammengeführt.
  payload['dailySession'] = remote['dailySession'] ?? local['dailySession'];

  return SyncMergeResult(payload: payload, collections: stats);
}

Map<String, dynamic> _resolve(String collection, Map<String, dynamic> local, Map<String, dynamic> remote) {
  switch (collection) {
    case 'flashcards':
      final lr = DateTime.tryParse('${local['lastReview']}');
      final rr = DateTime.tryParse('${remote['lastReview']}');
      if (lr != null && rr != null && lr != rr) return lr.isAfter(rr) ? local : remote;
      if (lr == null && rr != null) return remote;
      if (lr != null && rr == null) return local;
      final lReps = (local['reps'] as num?)?.toInt() ?? 0;
      final rReps = (remote['reps'] as num?)?.toInt() ?? 0;
      return rReps > lReps ? remote : local;
    case 'labExperiments':
      return _labWork(remote) > _labWork(local) ? remote : local;
    case 'materials':
      // Markierungen und Notizen beider Seiten behalten (auf einem Gerät
      // markiert, auf dem anderen eine Seitennotiz gespeichert).
      return {
        ...local,
        for (final key in const ['highlights', 'pageNotes'])
          if (local[key] is List || remote[key] is List) key: _union(local[key], remote[key]),
        'notes': _joinNotes('${local['notes'] ?? ''}', '${remote['notes'] ?? ''}'),
      };
    default:
      return local;
  }
}

/// Zwei Fassungen desselben Notiz-Textes: steckt die eine in der anderen, gilt
/// die längere, sonst stehen beide untereinander.
String _joinNotes(String local, String remote) {
  if (remote.trim().isEmpty || local.contains(remote)) return local;
  if (local.trim().isEmpty || remote.contains(local)) return remote;
  return '$local\n\n$remote';
}

/// Die Elemente beider Listen, ohne Doppelte (Reihenfolge: erst die lokalen).
List<dynamic> _union(Object? local, Object? remote) {
  final seen = <String>{};
  return [
    for (final e in [if (local is List) ...local, if (remote is List) ...remote])
      if (seen.add(recordHash(e))) e,
  ];
}

/// Wie viel eigener Text in einem Laborversuch steckt (Antworten, Notizen,
/// Berichtstexte, Messwerte) – Maß für "wer ist weiter".
int _labWork(Map<String, dynamic> lab) {
  var total = 0;
  int len(Object? v) => '${v ?? ''}'.trim().length;
  for (final q in (lab['prep'] as List? ?? const [])) {
    if (q is Map) total += len(q['answer']);
  }
  for (final p in (lab['parts'] as List? ?? const [])) {
    if (p is! Map) continue;
    total += len(p['notes']);
    for (final q in (p['questions'] as List? ?? const [])) {
      if (q is Map) total += len(q['answer']);
    }
    for (final t in (p['tables'] as List? ?? const [])) {
      if (t is! Map) continue;
      final editable = t['editable'] as List? ?? const [];
      final rows = t['rows'] as List? ?? const [];
      for (var i = 0; i < rows.length; i++) {
        final cells = rows[i] as List? ?? const [];
        final flags = i < editable.length ? editable[i] as List? ?? const [] : const [];
        for (var j = 0; j < cells.length; j++) {
          if (j < flags.length && flags[j] == true) total += len(cells[j]);
        }
      }
    }
  }
  for (final s in (lab['report'] as List? ?? const [])) {
    if (s is Map) total += len(s['text']);
  }
  return total;
}

/// Ein Satz zum Ergebnis, z.B. "Auf diesem Gerät neu oder geändert: 2 Fächer,
/// 15 Karten. In der Cloud ergänzt: 4 Karten."
String describeMerge(SyncMergeResult result) {
  const labels = {
    'modules': 'Fächer',
    'materials': 'Materialien',
    'summaries': 'Zusammenfassungen',
    'concepts': 'Konzepte',
    'flashcards': 'Karten',
    'lectureUnits': 'Einheiten',
    'labExperiments': 'Laborversuche',
    'chatMessages': 'Chat-Nachrichten',
    'unsupportedTasks': 'Aufgaben auf der Liste „Noch nicht interaktiv“',
    'mockExamResults': 'Probeklausuren',
    'studyDays': 'Lerntage',
  };
  String list(int Function(CollectionMerge) pick) => [
        for (final e in labels.entries)
          if (result.collections[e.key] != null && pick(result.collections[e.key]!) > 0)
            '${pick(result.collections[e.key]!)} ${e.value}',
      ].join(', ');
  final here = list((c) => c.changedLocally);
  final cloud = list((c) => c.changedRemotely);
  if (here.isEmpty && cloud.isEmpty) return 'Beide Stände waren schon gleich.';
  return [
    if (here.isNotEmpty) 'Auf diesem Gerät neu oder geändert: $here.',
    if (cloud.isNotEmpty) 'In der Cloud neu oder geändert: $cloud.',
    if (result.conflicts > 0)
      '${result.conflicts} Einträge waren auf beiden Seiten geändert – es gilt der mit dem weiteren Lernstand bzw. '
          'der lokale (der andere steht in der Sicherung).',
  ].join(' ');
}
