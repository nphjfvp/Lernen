import 'package:uuid/uuid.dart';

import '../models/concept.dart';
import '../models/flashcard.dart';
import '../models/module.dart';
import '../models/panik_content.dart';
import 'database_service.dart';
import 'module_export_service.dart';

/// Macht aus einer Panik-Inhaltsdatei ([PanikContent]) ein neues Fach, das
/// wie ein importiertes Fach gespeichert wird (ModuleExportService.saveImported).
///
/// Bewusst ohne neue Datenfelder – alles reist über vorhandene Felder mit
/// Sync, Export und Löschen mit:
/// - Typ → [Concept] (Rezept, Erkennungsmerkmale, Fehler als Erklärung;
///   Voraussetzungen als `prerequisiteIds`).
/// - Eintrag → [Flashcard] mit `conceptId` = Typ. Die Panik-Angaben (Art,
///   Fading, geprüft, Pflichtkern, Gewicht …) stehen in `taskData['panik']`,
///   lesbar über [PanikCardInfo.of].
/// - Rechenwege (Beispiel, Aufgabe, Reserve) sind Karteikarten: vorn die
///   Aufgabe, hinten der ganze Lösungsweg. Die Schritte mit Prinzip-Etikett
///   stehen zusätzlich in `taskData['panik']['steps']` für die Papier-Ansicht
///   des Panik-Modus. (Kein StepTask: der verlangt Eingabefelder je Schritt.)
/// - Reserveaufgaben sind stummgeschaltet (Gewicht 0): Sie kommen nie im
///   Daily Quiz, nur in Probeklausuren des Panik-Modus.
class PanikImport {
  /// Name des Felds in [Flashcard.taskData].
  static const infoKey = 'panik';

  static ImportedModule build(PanikContent content, {DateTime? now, String Function()? newId}) {
    final id = newId ?? () => const Uuid().v4();
    final created = now ?? DateTime.now();
    final moduleId = id();
    final module = Module(id: moduleId, name: content.subject, colorValue: 0xFFD9534F, icon: '🚨', examDate: null, createdAt: created);

    final conceptIdOf = {for (final t in content.types) t.id: id()};
    final typeById = {for (final t in content.types) t.id: t};
    final concepts = [
      for (final t in content.types)
        Concept(
          id: conceptIdOf[t.id]!,
          moduleId: moduleId,
          title: t.title,
          explanation: _explanation(t),
          sourceMaterialIds: const [],
          createdAt: created,
          prerequisiteIds: [for (final p in t.prerequisites) conceptIdOf[p]!],
        ),
    ];

    final cards = [
      for (final item in content.items)
        _card(item, typeById, id(), moduleId, conceptIdOf[item.typeId]!, created),
    ];
    return ImportedModule(module: module, lectureUnits: const [], materials: const [], concepts: concepts, flashcards: cards);
  }

  /// Prüft, baut und speichert das neue Fach in EINER Transaktion.
  /// Wirft [FormatException] bei einer fehlerhaften Datei (dann bleibt nichts zurück).
  static Future<ImportedModule> save(Object? json) async {
    final imported = build(PanikContent.parse(json));
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) => ModuleExportService.saveImported(txn, imported));
    return imported;
  }

  static Flashcard _card(
    PanikItem item,
    Map<String, PanikType> typeById,
    String cardId,
    String moduleId,
    String conceptId,
    DateTime created,
  ) {
    final type = typeById[item.typeId]!;
    final info = <String, dynamic>{
      'item': item.id,
      'type': item.typeId,
      'kind': item.kind.name,
      'core': type.core,
      'weight': type.weight,
      'area': type.area,
      'source': item.source,
      'verified': item.verified,
      if (item.fade > 0) 'fade': item.fade,
    };

    // Je nach Art: Fragetyp, Vorder-/Rückseite, Optionen, Aufgabendaten.
    QuestionType questionType;
    String front;
    String back;
    List<QuizOption>? options;
    // Ohne `kind` auf oberster Ebene – sonst hielte die App die Karte für
    // eine interaktive Aufgabe eines unbekannten Typs.
    final taskData = {infoKey: info};
    switch (item.kind) {
      case PanikItemKind.example:
      case PanikItemKind.task:
      case PanikItemKind.reserve:
        questionType = QuestionType.flashcard;
        front = item.prompt;
        back = _stepsText(item);
        if (!item.verified) back += '\n\n⚠️ Lösung nicht maschinell geprüft.';
        info['answer'] = item.answer;
        info['steps'] = [for (final s in item.steps) {'title': s.label, 'result': s.result}];
      case PanikItemKind.recognize:
        questionType = QuestionType.singleChoice;
        front = 'Welches Verfahren passt?\n\n${item.prompt}';
        back = '${typeById[item.answer]!.title} – ${item.reason}';
        options = [
          for (final o in item.options)
            QuizOption(text: typeById[o]!.title, isCorrect: o == item.answer, why: o == item.answer ? item.reason : null),
        ];
      case PanikItemKind.formula:
        questionType = QuestionType.flashcard;
        front = item.prompt;
        back = item.answer;
    }

    return Flashcard(
      id: cardId,
      moduleId: moduleId,
      conceptId: conceptId,
      front: front,
      back: back,
      createdAt: created,
      due: created,
      type: questionType,
      options: options,
      taskData: taskData,
      // Jede Karte steht für sich – sonst behandelte die Stufen-Logik die
      // Karten eines Typs als Leicht/Mittel/Schwer derselben Frage.
      stageGroup: 'einzeln-$cardId',
      weight: item.kind == PanikItemKind.reserve ? 0 : 1,
    );
  }

  /// Lösungsweg als Text: je Schritt „1. Etikett: $Ergebnis$“, am Ende das Ergebnis.
  static String _stepsText(PanikItem item) => [
        for (final (i, s) in item.steps.indexed) '${i + 1}. ${s.label}: \$${s.result}\$',
        '',
        'Ergebnis: \$${item.answer}\$',
      ].join('\n');

  static String _explanation(PanikType t) => [
        if (t.recognition.isNotEmpty) 'Erkennen: ${t.recognition.join('; ')}',
        if (t.recipe.isNotEmpty) 'Rezept: ${[for (final (i, r) in t.recipe.indexed) '${i + 1}) $r'].join(' ')}',
        if (t.mistakes.isNotEmpty) 'Typische Fehler: ${t.mistakes.join('; ')}',
        '${t.core ? 'Pflichtkern' : 'Ausbau'} · Prüfungsgewicht ${t.weight}${t.weightReason.isEmpty ? '' : ' (${t.weightReason})'}',
        if (t.sources.isNotEmpty) 'Quellen: ${t.sources.join(', ')}',
      ].join('\n\n');
}

/// Panik-Angaben einer Karte (aus `taskData['panik']`), null bei normalen Karten.
class PanikCardInfo {
  const PanikCardInfo({
    required this.itemId,
    required this.typeId,
    required this.kind,
    required this.core,
    required this.weight,
    required this.area,
    required this.verified,
    this.source = '',
    this.fade = 0,
    this.answer = '',
    this.steps = const [],
  });

  final String itemId;
  final String typeId;
  final PanikItemKind kind;
  final bool core;
  final String weight;
  final String area;
  final bool verified;
  final String source;
  final int fade;

  /// Endergebnis (LaTeX) und Rechenweg – nur bei Beispiel, Aufgabe, Reserve.
  final String answer;
  final List<PanikStep> steps;

  static PanikCardInfo? of(Flashcard card) {
    final raw = card.taskData?[PanikImport.infoKey];
    if (raw is! Map) return null;
    final kind = PanikItemKind.values.where((k) => k.name == raw['kind']).firstOrNull;
    if (kind == null) return null;
    return PanikCardInfo(
      itemId: '${raw['item'] ?? ''}',
      typeId: '${raw['type'] ?? ''}',
      kind: kind,
      core: raw['core'] == true,
      weight: '${raw['weight'] ?? 'M'}',
      area: '${raw['area'] ?? ''}',
      verified: raw['verified'] == true,
      source: '${raw['source'] ?? ''}',
      fade: (raw['fade'] as num?)?.toInt() ?? 0,
      answer: '${raw['answer'] ?? ''}',
      steps: [
        for (final s in raw['steps'] is List ? raw['steps'] as List : const [])
          if (s is Map) PanikStep('${s['title'] ?? ''}', '${s['result'] ?? ''}'),
      ],
    );
  }
}
