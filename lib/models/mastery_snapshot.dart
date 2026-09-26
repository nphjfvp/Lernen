/// Ein Tages-Schnappschuss der aggregierten Fortschritts-Kennzahlen (Ampel-
/// Aufschlüsselung + Ø Behaltensrate) über ALLE Fächer hinweg – Grundlage für
/// den Wochenvergleich in StatsScreen ("mehr Grün als letzte Woche"), ohne
/// dafür ein vollständiges Review-Log führen zu müssen: ein Eintrag pro
/// Kalendertag reicht, überschrieben bei jedem erneuten Aufruf desselben
/// Tages (siehe MasterySnapshotRepository.recordToday).
class MasterySnapshot {
  const MasterySnapshot({
    required this.date,
    required this.red,
    required this.yellow,
    required this.green,
    required this.neu,
    this.averageRetrievability,
  });

  /// Datumsanteil ohne Uhrzeit – dient als eindeutiger Schlüssel (ein
  /// Eintrag pro Kalendertag, siehe [dateKey]).
  final DateTime date;
  final int red;
  final int yellow;
  final int green;
  final int neu;
  final double? averageRetrievability;

  /// Anteil grüner an allen BEREITS EINGESTUFTEN Karten (rot+gelb+grün, ohne
  /// "neu") – fairer für einen Wochenvergleich als die reine Anzahl, da die
  /// Gesamtkartenzahl über die Zeit wächst (neue Karten kommen dazu, ohne
  /// dass sich am Wissensstand etwas geändert hat).
  double? get greenShare {
    final assessed = red + yellow + green;
    if (assessed == 0) return null;
    return green / assessed;
  }

  String get dateKey => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'red': red,
        'yellow': yellow,
        'green': green,
        'neu': neu,
        'averageRetrievability': averageRetrievability,
      };

  factory MasterySnapshot.fromMap(Map<String, dynamic> map) => MasterySnapshot(
        date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime(2000),
        red: (map['red'] as num?)?.toInt() ?? 0,
        yellow: (map['yellow'] as num?)?.toInt() ?? 0,
        green: (map['green'] as num?)?.toInt() ?? 0,
        neu: (map['neu'] as num?)?.toInt() ?? 0,
        averageRetrievability: (map['averageRetrievability'] as num?)?.toDouble(),
      );
}
