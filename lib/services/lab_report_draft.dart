import 'package:uuid/uuid.dart';

import '../models/lab_experiment.dart';

/// Ein Abschnitt des Berichtsentwurfs.
class LabDraftSection {
  const LabDraftSection({required this.title, required this.text, this.sectionId});

  /// Der vorhandene Berichtsabschnitt, zu dem der Entwurf gehört; `null` bei
  /// einem Abschnitt, den nur die Vorlage kennt (z.B. "Anhang").
  final String? sectionId;
  final String title;
  final String text;
}

/// Grober Berichtsentwurf der KI (siehe AiService.draftLabReport): ein Text je
/// Abschnitt und eine Liste dessen, was noch fehlt. Dient nur als Inspiration –
/// [applyTo] legt ihn neben den eigenen Text, ersetzt ihn nie.
class LabReportDraft {
  const LabReportDraft({this.sections = const [], this.missing = const []});

  final List<LabDraftSection> sections;
  final List<String> missing;

  bool get isEmpty => sections.isEmpty;

  /// Liest die KI-Antwort: `sections` (je `sectionId`, `title`, `text`) und
  /// `missing`. Die KI gibt die langen Kennungen nicht immer exakt zurück – eine
  /// unbekannte `sectionId` wird deshalb über den Anfang der Kennung (mind. 8
  /// Zeichen, eindeutig) und dann über den Titel ([sectionTitles]: Kennung →
  /// Titel) zugeordnet; erst was dann noch unbekannt ist, gilt als "neuer
  /// Abschnitt".
  factory LabReportDraft.fromJson(
    Map<String, dynamic> json, {
    required Set<String> knownSectionIds,
    Map<String, String> sectionTitles = const {},
  }) {
    String text(Object? v) => (v ?? '').toString().trim();
    String? resolve(String id, String title) {
      if (knownSectionIds.contains(id)) return id;
      if (id.length >= 8) {
        final byPrefix = [for (final k in knownSectionIds) if (k.startsWith(id) || id.startsWith(k)) k];
        if (byPrefix.length == 1) return byPrefix.single;
      }
      final wanted = normalizeTitle(title);
      if (wanted.isEmpty) return null;
      final byTitle = [
        for (final e in sectionTitles.entries)
          if (knownSectionIds.contains(e.key) && normalizeTitle(e.value) == wanted) e.key,
      ];
      return byTitle.length == 1 ? byTitle.single : null;
    }

    final sections = <LabDraftSection>[];
    final raw = json['sections'] ?? json['abschnitte'];
    for (final e in (raw is List ? raw : const [])) {
      if (e is! Map) continue;
      final body = text(e['text'] ?? e['content']);
      if (body.isEmpty) continue;
      final title = text(e['title'] ?? e['titel']);
      sections.add(LabDraftSection(
        sectionId: resolve(text(e['sectionId'] ?? e['id']), title),
        title: title,
        text: body,
      ));
    }
    final missing = json['missing'] ?? json['fehlt'];
    return LabReportDraft(
      sections: sections,
      missing: [
        if (missing is List)
          for (final m in missing)
            if (text(m).isNotEmpty) text(m),
      ],
    );
  }

  /// Titel zum Vergleichen: klein, ohne Nummerierung ("2.1 "), Satzzeichen und
  /// doppelte Leerzeichen.
  static String normalizeTitle(String title) => title
      .toLowerCase()
      .replaceFirst(RegExp(r'^[\d.\s)]+'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// Legt den Entwurf in [experiment] ab. Ohne [onlySectionId] ersetzt er alle
  /// bisherigen Entwürfe, sonst nur den dieses Abschnitts – dorthin kommt dann
  /// alles, was die KI geliefert hat, auch wenn sie die Kennung nicht genau
  /// getroffen hat (sie sollte ja nur diesen einen Abschnitt schreiben). Mit
  /// [adoptStructure] entstehen für Abschnitte, die nur die Vorlage kennt, neue
  /// Berichtsabschnitte an der Stelle der Vorlage (vor dem ersten bekannten,
  /// sonst hinter dem zuletzt bedienten); gibt es schon einen gleichnamigen
  /// (z.B. aus einem früheren Entwurf), wird er wiederverwendet. Ohne
  /// [adoptStructure] wandern sie als Unterpunkt in den Abschnitt davor. Der
  /// eigene Text und Einschätzungen bleiben unberührt.
  LabExperiment applyTo(
    LabExperiment experiment, {
    bool adoptStructure = true,
    String? onlySectionId,
    String Function()? newId,
  }) {
    final id = newId ?? () => const Uuid().v4();

    if (onlySectionId != null) {
      if (!experiment.report.any((r) => r.id == onlySectionId) || sections.isEmpty) return experiment;
      final matching = [for (final s in sections) if (s.sectionId == onlySectionId) s];
      final chosen = matching.isNotEmpty ? matching : sections;
      final body = [
        for (final (i, s) in chosen.indexed)
          i == 0 || s.title.isEmpty || chosen.length == 1 ? s.text : '${s.title}\n${s.text}',
      ].join('\n\n');
      return experiment.updateSection(onlySectionId, (old) => old.copyWith(draft: body.trim()));
    }

    var report = [for (final s in experiment.report) s.copyWith(clearDraft: true)];
    // Abschnitt-Kennung → Entwurf, in Reihenfolge des Entstehens.
    final drafts = <String, StringBuffer>{};
    var anchor = -1; // Index des zuletzt bedienten Abschnitts in [report]

    void addTo(String sectionId, String title, String body, {required bool asSubsection}) {
      final buffer = drafts.putIfAbsent(sectionId, StringBuffer.new);
      if (buffer.isNotEmpty) buffer.write('\n\n');
      if (asSubsection && title.isNotEmpty) buffer.write('$title\n');
      buffer.write(body);
    }

    for (final s in sections) {
      final existing = s.sectionId;
      if (existing != null) {
        final index = report.indexWhere((r) => r.id == existing);
        if (index < 0) continue;
        addTo(existing, s.title, s.text, asSubsection: false);
        anchor = index;
        continue;
      }
      if (adoptStructure) {
        final wanted = normalizeTitle(s.title);
        final sameName = wanted.isEmpty ? -1 : report.indexWhere((r) => normalizeTitle(r.title) == wanted);
        if (sameName >= 0) {
          addTo(report[sameName].id, s.title, s.text, asSubsection: false);
          anchor = sameName;
          continue;
        }
        final section = LabReportSection(id: id(), title: s.title.isEmpty ? 'Weiterer Abschnitt' : s.title);
        anchor = anchor + 1; // -1 → ganz vorne (die Vorlage nennt ihn vor allen bekannten)
        report = [...report.sublist(0, anchor), section, ...report.sublist(anchor)];
        addTo(section.id, s.title, s.text, asSubsection: false);
      } else if (anchor >= 0) {
        addTo(report[anchor].id, s.title, s.text, asSubsection: true);
      } else if (report.isNotEmpty) {
        anchor = 0;
        addTo(report[0].id, s.title, s.text, asSubsection: true);
      }
    }
    return experiment.copyWith(
      report: [
        for (final r in report)
          drafts.containsKey(r.id) ? r.copyWith(draft: drafts[r.id].toString().trim()) : r,
      ],
    );
  }
}
