import '../models/lab_experiment.dart';
import '../models/material_item.dart';
import 'source_locator.dart';

/// Eine Stelle in den Unterlagen eines Versuchs (PDF-Seite, 1-basiert).
class LabReference {
  const LabReference({required this.material, required this.page});

  final MaterialItem material;
  final int page;

  String get label => '${material.fileName}, Seite $page';
}

/// Auszug aus den Unterlagen für die KI samt den Fundstellen, die die
/// Oberfläche als „Im Skript nachschlagen“ anbietet.
class LabContext {
  const LabContext({this.text = '', this.references = const []});

  final String text;
  final List<LabReference> references;

  bool get isEmpty => text.trim().isEmpty;
}

/// Sucht zu einer Aufgabe oder einem Berichtsabschnitt die passenden Seiten in
/// Theorie-Skript und Anleitung des Versuchs (lokaler Stichwort-Abgleich ohne
/// KI, siehe [PageIndex]) und stellt Messwerte und Antworten als Text für das
/// Gegenlesen zusammen.
class LabContextService {
  LabContextService({SourceLocator? locator}) : _locator = locator ?? SourceLocator();

  final SourceLocator _locator;

  /// Pseudo-Seiten für Materialien ohne PDF-Seiten (Word, Text): Absätze werden
  /// bis zu dieser Länge zusammengefasst.
  static const _pseudoPageLength = 2500;

  /// So viele Seiten kommen in den Auszug.
  static const maxPages = 3;

  /// Länge je Seite im Auszug.
  static const _pageCap = 3000;

  /// Die Unterlagen des Versuchs in Suchreihenfolge: erst die Theorie, dann
  /// die Anleitung (steht die Antwort in beiden, zählt das Theorie-Skript).
  static List<MaterialItem> sourcesOf(LabExperiment experiment, Iterable<MaterialItem> materials) {
    final byId = {for (final m in materials) m.id: m};
    return [
      for (final id in [...experiment.theoryMaterialIds, ...experiment.guideMaterialIds])
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<List<({MaterialItem material, int? page, String text})>> _pagesOf(List<MaterialItem> sources) async {
    final pages = <({MaterialItem material, int? page, String text})>[];
    for (final m in sources) {
      final texts = await _locator.pageTextsOf(m);
      if (texts.any((t) => t.trim().isNotEmpty)) {
        for (var i = 0; i < texts.length; i++) {
          pages.add((material: m, page: i + 1, text: texts[i]));
        }
      } else {
        for (final chunk in splitIntoPseudoPages(m.extractedText)) {
          pages.add((material: m, page: null, text: chunk));
        }
      }
    }
    return pages;
  }

  /// Zerlegt Text ohne Seitenangaben an Absatzgrenzen in Stücke von etwa
  /// [_pseudoPageLength] Zeichen.
  static List<String> splitIntoPseudoPages(String text) {
    final result = <String>[];
    var current = StringBuffer();
    for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
      final p = paragraph.trim();
      if (p.isEmpty) continue;
      if (current.isNotEmpty && current.length + p.length > _pseudoPageLength) {
        result.add(current.toString().trim());
        current = StringBuffer();
      }
      current
        ..write(p)
        ..write('\n\n');
    }
    if (current.toString().trim().isNotEmpty) result.add(current.toString().trim());
    return result;
  }

  /// Die besten Seiten zu [question] (und, wenn [answer] gegeben ist, dem
  /// Vokabular der eigenen Antwort). Ohne Treffer bleibt der Auszug leer.
  Future<LabContext> contextFor({
    required LabExperiment experiment,
    required Iterable<MaterialItem> materials,
    required String question,
    String answer = '',
    int limit = maxPages,
  }) async {
    final sources = sourcesOf(experiment, materials);
    if (sources.isEmpty) return const LabContext();
    final pages = await _pagesOf(sources);
    if (pages.isEmpty) return const LabContext();
    final index = PageIndex([for (final p in pages) p.text]);
    final ranked = index.rank(
      (question: SourceLocator.keywords(question), answer: SourceLocator.keywords(answer)),
      limit: limit,
    );
    if (ranked.isEmpty) return const LabContext();
    final text = StringBuffer();
    final references = <LabReference>[];
    for (final hit in ranked) {
      final page = pages[hit.index];
      final where = page.page == null ? page.material.fileName : '${page.material.fileName}, Seite ${page.page}';
      final body = page.text.trim();
      text
        ..writeln('[$where]')
        ..writeln(body.length > _pageCap ? '${body.substring(0, _pageCap)} …' : body)
        ..writeln();
      if (page.page != null && page.material.hasViewablePdf) {
        references.add(LabReference(material: page.material, page: page.page!));
      }
    }
    return LabContext(text: text.toString().trim(), references: references);
  }

  /// Messwerte eines Versuchsteils als Text (leere Zellen als „–“).
  static String measurementsOf(LabPart? part) =>
      part == null ? '' : part.tables.map((t) => t.asText()).where((t) => t.trim().isNotEmpty).join('\n\n');

  /// Alle Messwerte des Versuchs, je Teil mit Überschrift.
  static String allMeasurements(LabExperiment experiment) => [
        for (final part in experiment.parts)
          if (measurementsOf(part).isNotEmpty) '${part.title}\n${measurementsOf(part)}',
      ].join('\n\n');

  /// Die bereits beantworteten Auswertungsfragen eines Teils (Aufgabe und
  /// eigene Antwort).
  static String answersOf(LabPart? part) => part == null
      ? ''
      : [
          for (final q in part.questions)
            if (q.answered) '${q.number} ${q.text}\nAntwort: ${q.answer.trim()}',
        ].join('\n\n');

  /// Der ganze Versuch als Text für den Berichtsentwurf: je Versuchsteil Ziele,
  /// Durchführung, Messwerte, Notizen (samt dort gespeicherter Rechenwege) und
  /// die beantworteten Auswertungsfragen, dazu die beantworteten
  /// Vorbereitungsaufgaben. Unbeantwortetes bleibt weg.
  static String reportData(LabExperiment e) {
    final b = StringBuffer();
    if (e.hints.isNotEmpty) {
      b.writeln('Hinweise aus der Anleitung: ${e.hints.join('; ')}');
      b.writeln();
    }
    for (final part in e.parts) {
      b.writeln('## Versuchsteil: ${part.title}');
      for (final g in part.goals) {
        b.writeln('Ziel: $g');
      }
      if (part.steps.isNotEmpty) {
        b.writeln('Durchführung:');
        for (final (i, step) in part.steps.indexed) {
          b.writeln('  ${i + 1}. ${step.text}${step.done ? '' : ' (nicht abgehakt)'}');
        }
      }
      final measurements = measurementsOf(part);
      if (measurements.isNotEmpty) {
        b.writeln('Messwerte:');
        b.writeln(measurements);
      }
      if (part.notes.trim().isNotEmpty) {
        b.writeln('Notizen und Rechnungen:');
        b.writeln(part.notes.trim());
      }
      final answers = answersOf(part);
      if (answers.isNotEmpty) {
        b.writeln('Beantwortete Auswertungsfragen:');
        b.writeln(answers);
      }
      b.writeln();
    }
    final prep = [
      for (final q in e.prep)
        if (q.answered) '${q.number} ${q.text}\nAntwort: ${q.answer.trim()}',
    ];
    if (prep.isNotEmpty) {
      b.writeln('## Vorbereitungsaufgaben mit Antworten');
      b.writeln(prep.join('\n\n'));
    }
    return b.toString().trim();
  }

  /// Die bisherigen eigenen Berichtstexte, je Abschnitt mit Überschrift.
  static String ownReportTexts(LabExperiment e) => [
        for (final s in e.report)
          if (s.text.trim().isNotEmpty) '### ${s.title}\n${s.text.trim()}',
      ].join('\n\n');
}
