import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../models/module.dart';
import '../../models/study_sequence.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/study_sequence_repository.dart';
import '../../services/continue_learning.dart';
import '../../theme/app_colors.dart';

/// Sucht das Ziel für „Weiter lernen“ (siehe [ContinueLearning.pick]) und lädt
/// dafür, was fehlt: die gespeicherten Stände und – nur für die zuletzt
/// benutzten Fächer – deren Einheiten und Materialien (für Namen und
/// Reihenfolge). Scheitert etwas, gibt es einfach kein Ziel.
Future<ContinueTarget?> loadContinueTarget({
  required List<Module> modules,
  required Map<String, List<Flashcard>> cardsByModule,
  LectureUnitRepository? units,
  MaterialRepository? materials,
  StudySequenceRepository? sequences,
  String? onlyModule,
}) async {
  try {
    final progresses = await (sequences ?? StudySequenceRepository()).all();
    final recent = [...progresses]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final moduleIds = <String>{
      for (final p in recent)
        if (onlyModule == null || p.moduleId == onlyModule) p.moduleId,
    }.take(4);
    for (final id in moduleIds) {
      if (units != null && units.forModule(id).isEmpty) await units.loadForModule(id);
      if (materials != null && materials.forModule(id).isEmpty) await materials.loadForModule(id);
    }
    return ContinueLearning.pick(
      modules: modules,
      progresses: progresses,
      cardsByModule: cardsByModule,
      onlyModule: onlyModule,
      titleOf: (moduleId, kind, id) => switch (kind) {
        StudySequenceKind.unit => units?.forModule(moduleId).where((u) => u.id == id).firstOrNull?.title,
        StudySequenceKind.material => materials?.forModule(moduleId).where((m) => m.id == id).firstOrNull?.fileName,
      },
      materialOrder: (moduleId) => [for (final m in materials?.forModule(moduleId) ?? const []) m.id],
    );
  } catch (_) {
    return null;
  }
}

/// Karte „Weiter lernen“: macht dort weiter, wo man aufgehört hat.
class ContinueLearningCard extends StatelessWidget {
  const ContinueLearningCard({
    super.key,
    required this.target,
    required this.onContinue,
    this.onOther,
    this.otherLabel = 'Zum Fach',
    this.showModule = true,
  });

  final ContinueTarget target;
  final VoidCallback onContinue;

  /// Zweiter, unauffälliger Knopf (z.B. das Fach öffnen).
  final VoidCallback? onOther;
  final String otherLabel;

  /// Fachname als Überschrift (auf der Startseite); im Fach selbst steht dort
  /// der Name der Reihe.
  final bool showModule;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WEITER LERNEN',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.accentOnSoft),
          ),
          const SizedBox(height: 8),
          Text(
            showModule ? target.moduleName : (target.source?.title ?? 'Üben'),
            key: const ValueKey('continue-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: c.ink),
          ),
          const SizedBox(height: 3),
          Text(
            showModule && target.source != null ? '${target.source!.title}\n${target.detail}' : target.detail,
            key: const ValueKey('continue-detail'),
            style: TextStyle(fontSize: 14, height: 1.4, color: c.accentOnSoft),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey('continue-go'),
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: c.accentSolid,
                  foregroundColor: c.accentInk,
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Weitermachen'),
              ),
              if (onOther != null)
                TextButton(
                  key: const ValueKey('continue-other'),
                  onPressed: onOther,
                  style: TextButton.styleFrom(foregroundColor: c.accentOnSoft, minimumSize: const Size(0, 46)),
                  child: Text(otherLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
