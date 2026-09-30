/// Ein früherer Cloud-Stand, der noch in der Cloud liegt (siehe
/// [planCloudHistory]). Seine Daten stehen in den Teil-Dokumenten
/// `sync_parts/{pushId}_0..partCount-1` – dieselbe Kennung wie im Format 3.
class CloudStateEntry {
  const CloudStateEntry({
    required this.pushId,
    required this.partCount,
    this.deviceId,
    this.at,
    this.modules,
    this.flashcards,
  });

  final String pushId;
  final int partCount;
  final String? deviceId;

  /// Wann dieser Stand hochgeladen wurde.
  final DateTime? at;
  final int? modules;
  final int? flashcards;

  Map<String, dynamic> toMap() => {
        'pushId': pushId,
        'partCount': partCount,
        'deviceId': deviceId,
        'at': at?.millisecondsSinceEpoch,
        'modules': modules,
        'flashcards': flashcards,
      };

  static CloudStateEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final pushId = raw['pushId'];
    final parts = (raw['partCount'] as num?)?.toInt() ?? 0;
    if (pushId is! String || pushId.isEmpty || parts < 1) return null;
    final at = (raw['at'] as num?)?.toInt();
    return CloudStateEntry(
      pushId: pushId,
      partCount: parts,
      deviceId: raw['deviceId'] as String?,
      at: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      modules: (raw['modules'] as num?)?.toInt(),
      flashcards: (raw['flashcards'] as num?)?.toInt(),
    );
  }

  /// Die früheren Stände aus dem Hauptdokument (neueste zuerst).
  static List<CloudStateEntry> listFrom(Object? raw) => [
        if (raw is List)
          for (final e in raw) ?fromMap(e),
      ];
}

/// Was beim Hochladen mit dem bisherigen Cloud-Stand geschieht.
class CloudHistoryPlan {
  const CloudHistoryPlan({required this.keep, required this.drop, required this.retired});

  /// Die früheren Stände nach dem Upload, neueste zuerst.
  final List<CloudStateEntry> keep;

  /// Stände, die herausfallen – ihre Teile werden gelöscht.
  final List<CloudStateEntry> drop;

  /// Der bisherige Stand, wenn er in den Verlauf wandert (sonst `null`: seine
  /// Teile werden wie bisher gelöscht).
  final CloudStateEntry? retired;
}

/// Wie viele frühere Cloud-Stände höchstens aufgehoben werden.
const maxCloudHistory = 5;

/// Ab diesem Abstand zum letzten Verlaufs-Eintrag wird auch ein Stand desselben
/// Geräts aufgehoben (sonst füllten die Uploads eines Lerntags den Verlauf).
const cloudHistoryMinGap = Duration(hours: 24);

/// Entscheidet beim Hochladen, ob der bisherige Cloud-Stand [previous] in den
/// Verlauf wandert.
///
/// Ein Stand wird aufgehoben, wenn er von einem ANDEREN Gerät stammt als dem,
/// das jetzt hochlädt (genau dann geht fremder Fortschritt verloren), wenn der
/// Verlauf noch leer ist, wenn er [cloudHistoryMinGap] älter ist als der letzte
/// Eintrag – oder mit [force] (Wiederherstellen: der ersetzte Stand soll
/// wiederfindbar bleiben). [previous] ist `null`, wenn der bisherige Stand nicht
/// aufhebbar ist (nichts in der Cloud, altes Format).
CloudHistoryPlan planCloudHistory({
  required List<CloudStateEntry> existing,
  required CloudStateEntry? previous,
  required String newDeviceId,
  bool force = false,
  int max = maxCloudHistory,
}) {
  final alreadyThere = previous != null && existing.any((e) => e.pushId == previous.pushId);
  final retire = previous != null &&
      !alreadyThere &&
      (force ||
          existing.isEmpty ||
          previous.deviceId != newDeviceId ||
          previous.at == null ||
          existing.first.at == null ||
          previous.at!.difference(existing.first.at!) >= cloudHistoryMinGap);
  final all = [if (retire) previous, ...existing];
  return CloudHistoryPlan(
    keep: all.take(max).toList(),
    drop: all.skip(max).toList(),
    retired: retire ? previous : null,
  );
}
