import 'formula_sheet.dart';

/// Ergebnis des Vorbereiten-Modus: strukturierte Zusammenfassung von
/// Vorlesungsfolien mit hervorgehobenen Kernkonzepten für den schnellen
/// Überblick vor der Vorlesung/Übung – oder, mit [formulaSheet], eine
/// Formelsammlung zu den Folien (dann sind [overview] und [keyPoints] leer).
/// Beides in einem Typ, damit Speichern, Sync, Fach-Export und Löschen des Fachs
/// ohne Zusatzarbeit mitlaufen.
class Summary {
  final String id;
  final String moduleId;
  final List<String> sourceMaterialIds;
  final String title;
  final String overview;
  final List<String> keyPoints;
  final DateTime createdAt;

  /// Welcher Vorlesungseinheit (siehe LectureUnit) diese Zusammenfassung
  /// zugeordnet ist – übernommen von der beim Vorbereiten gewählten
  /// Einheit. Null = keine Einheit gewählt (z.B. ältere Zusammenfassungen
  /// vor Einführung der Einheiten).
  final String? unitId;

  /// Gesetzt bei einer Formelsammlung (siehe [FormulaSheet]).
  final FormulaSheet? formulaSheet;

  bool get isFormulaSheet => formulaSheet != null;

  const Summary({
    required this.id,
    required this.moduleId,
    required this.sourceMaterialIds,
    required this.title,
    required this.overview,
    required this.keyPoints,
    required this.createdAt,
    this.unitId,
    this.formulaSheet,
  });

  Summary copyWith({String? title, FormulaSheet? formulaSheet}) => Summary(
        id: id,
        moduleId: moduleId,
        sourceMaterialIds: sourceMaterialIds,
        title: title ?? this.title,
        overview: overview,
        keyPoints: keyPoints,
        createdAt: createdAt,
        unitId: unitId,
        formulaSheet: formulaSheet ?? this.formulaSheet,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'moduleId': moduleId,
        'sourceMaterialIds': sourceMaterialIds,
        'title': title,
        'overview': overview,
        'keyPoints': keyPoints,
        'createdAt': createdAt.toIso8601String(),
        'unitId': unitId,
        if (formulaSheet != null) 'formulaSheet': formulaSheet!.toMap(),
      };

  /// Tolerant gegenüber importierten/älteren Datensätzen (fehlende Felder,
  /// Zahlen statt Texte) statt beim Laden abzustürzen.
  factory Summary.fromMap(Map<String, dynamic> map) => Summary(
        id: map['id'] as String,
        moduleId: map['moduleId'] as String,
        sourceMaterialIds: [for (final id in map['sourceMaterialIds'] as List? ?? const []) id.toString()],
        title: map['title']?.toString() ?? '',
        overview: map['overview']?.toString() ?? '',
        keyPoints: [for (final p in map['keyPoints'] as List? ?? const []) p.toString()],
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime(2000),
        unitId: map['unitId'] as String?,
        formulaSheet: FormulaSheet.tryFromMap(map['formulaSheet']),
      );
}
