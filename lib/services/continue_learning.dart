import '../models/flashcard.dart';
import '../models/module.dart';
import '../models/study_sequence.dart';
import 'study_sequence.dart';

/// Wo es mit „Weiter lernen“ weitergeht.
class ContinueTarget {
  const ContinueTarget({required this.moduleId, required this.moduleName, required this.detail, this.source});

  final String moduleId;
  final String moduleName;

  /// Zweite Zeile der Karte, z.B. „Der Reihe nach · weiter bei Aufgabe 8“.
  final String detail;

  /// Die angefangene Reihe; null = „Üben“ im Fach.
  final StudySequenceSource? source;
}

/// „Weiter lernen“ auf der Startseite und im Fach: entscheidet, womit es
/// sinnvoll weitergeht – ohne dass man erst suchen muss.
///
/// 1. Die zuletzt benutzte Reihe („Der Reihe nach“), in der noch etwas offen
///    ist.
/// 2. Sonst „Üben“ im Fach mit der nächsten Klausur (ohne Termin: dem mit den
///    meisten Karten).
class ContinueLearning {
  const ContinueLearning._();

  /// [titleOf]: Name der Einheit bzw. PDF hinter einem gespeicherten Stand
  /// (`kind`, `id`) – null, wenn es sie nicht mehr gibt. [materialOrder]:
  /// Reihenfolge der Materialien eines Fachs. [onlyModule]: nur dieses Fach.
  static ContinueTarget? pick({
    required List<Module> modules,
    required List<StudySequenceProgress> progresses,
    required Map<String, List<Flashcard>> cardsByModule,
    required String? Function(String moduleId, StudySequenceKind kind, String id) titleOf,
    List<String> Function(String moduleId)? materialOrder,
    String? onlyModule,
    DateTime? now,
  }) {
    final byId = {for (final m in modules) m.id: m};
    final latest = [...progresses]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final p in latest) {
      final module = byId[p.moduleId];
      if (module == null || (onlyModule != null && module.id != onlyModule)) continue;
      final split = p.key.indexOf(':');
      if (split <= 0) continue;
      final kind = StudySequenceKind.values.where((k) => k.name == p.key.substring(0, split)).firstOrNull;
      final id = p.key.substring(split + 1);
      if (kind == null) continue;
      final title = titleOf(module.id, kind, id);
      if (title == null) continue;
      final source = StudySequenceSource(kind: kind, id: id, title: title);
      final ordered = StudySequence.ordered(
        cardsByModule[module.id] ?? const [],
        source,
        materialOrder: materialOrder?.call(module.id) ?? const [],
        order: p.order,
      );
      final position = StudySequence.nextPosition(ordered, p);
      if (position == null) continue;
      return ContinueTarget(
        moduleId: module.id,
        moduleName: module.name,
        source: source,
        detail: 'Der Reihe nach · weiter bei Aufgabe $position von ${ordered.length}',
      );
    }

    // Nichts angefangen: Üben, wo die Klausur am nächsten ist.
    final candidates = [
      for (final m in modules)
        if ((onlyModule == null || m.id == onlyModule) &&
            (cardsByModule[m.id] ?? const <Flashcard>[]).any((c) => !c.isMuted))
          m,
    ];
    if (candidates.isEmpty) return null;
    int days(Module m) {
      final d = m.daysUntilExam;
      return d == null || d < 0 ? 1 << 30 : d;
    }

    int count(Module m) => (cardsByModule[m.id] ?? const <Flashcard>[]).where((c) => !c.isMuted).length;
    candidates.sort((a, b) {
      final byExam = days(a).compareTo(days(b));
      return byExam != 0 ? byExam : count(b).compareTo(count(a));
    });
    final module = candidates.first;
    final n = count(module);
    final exam = module.daysUntilExam;
    return ContinueTarget(
      moduleId: module.id,
      moduleName: module.name,
      detail: [
        'Üben · $n ${n == 1 ? 'Karte' : 'Karten'}',
        if (exam != null && exam >= 0) exam == 0 ? 'Klausur heute' : 'Klausur in $exam ${exam == 1 ? 'Tag' : 'Tagen'}',
      ].join(' · '),
    );
  }
}
