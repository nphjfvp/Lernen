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
  /// `missing`. Eine `sectionId`, die es nicht gibt, gilt als "neuer Abschnitt".
  factory LabReportDraft.fromJson(Map<String, dynamic> json, {required Set<String> knownSectionIds}) {
    String text(Object? v) => (v ?? '').toString().trim();
    final sections = <LabDraftSection>[];
    final raw = json['sections'] ?? json['abschnitte'];
    for (final e in (raw is List ? raw : const [])) {
      if (e is! Map) continue;
      final body = text(e['text'] ?? e['content']);
      if (body.isEmpty) continue;
      final id = text(e['sectionId'] ?? e['id']);
      sections.add(LabDraftSection(
        sectionId: knownSectionIds.contains(id) ? id : null,
        title: text(e['title'] ?? e['titel']),
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

  /// Legt den Entwurf in [experiment] ab. Ohne [onlySectionId] ersetzt er alle
  /// bisherigen Entwürfe, sonst nur den dieses Abschnitts. Mit [adoptStructure]
  /// entstehen für Abschnitte, die nur die Vorlage kennt, neue Berichts-
  /// abschnitte (hinter dem zuletzt bedienten); ohne wandern sie als Unterpunkt in
  /// den davor. Der eigene Text und Einschätzungen bleiben unberührt.
  LabExperiment applyTo(
    LabExperiment experiment, {
    bool adoptStructure = true,
    String? onlySectionId,
    String Function()? newId,
  }) {
    final id = newId ?? () => const Uuid().v4();
    var report = [
      for (final s in experiment.report) onlySectionId == null || s.id == onlySectionId ? s.copyWith(clearDraft: true) : s,
    ];
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
        if (onlySectionId != null && existing != onlySectionId) continue;
        final index = report.indexWhere((r) => r.id == existing);
        if (index < 0) continue;
        addTo(existing, s.title, s.text, asSubsection: false);
        anchor = index;
        continue;
      }
      if (onlySectionId != null) continue;
      if (adoptStructure) {
        final section = LabReportSection(id: id(), title: s.title.isEmpty ? 'Weiterer Abschnitt' : s.title);
        anchor = anchor < 0 ? report.length : anchor + 1;
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
