import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/lab_experiment.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../theme/app_colors.dart';
import '../calc/calc_screen.dart';
import 'lab_create_screen.dart';
import 'lab_experiment_screen.dart';
import 'lab_photos_screen.dart';
import 'lab_widgets.dart';

/// Abschnitt "Laborversuche" im Fach: die Versuche mit Stand, dazu der Knopf
/// zum Anlegen eines neuen.
class LabExperimentsSection extends StatelessWidget {
  const LabExperimentsSection({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final experiments = context.watch<LabExperimentRepository?>()?.forModule(moduleId) ?? const <LabExperiment>[];
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'LABORVERSUCHE',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted),
            ),
            if (experiments.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text('(${experiments.length})', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (experiments.isEmpty)
          Text(
            'Vorbereitung, Durchführung und Bericht eines Laborversuchs an einem Ort – mit Termin im '
            'Kalender und der KI als Gegenleserin.',
            style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
          ),
        const SizedBox(height: 10),
        for (final e in experiments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _LabRow(experiment: e, moduleName: moduleName, now: now),
          ),
        OutlinedButton.icon(
          key: const ValueKey('lab-add'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LabCreateScreen(moduleId: moduleId, moduleName: moduleName),
          )),
          icon: const Icon(Icons.add),
          label: const Text('Laborversuch anlegen'),
        ),
        if (experiments.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('lab-photos-open'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => LabPhotosScreen(moduleId: moduleId, moduleName: moduleName),
            )),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Fotos zuordnen & auslesen'),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('calc-open'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CalcScreen(moduleName: moduleName),
          )),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Rechnen mit KI (Werte oder Bilder)'),
        ),
      ],
    );
  }
}

class _LabRow extends StatelessWidget {
  const _LabRow({required this.experiment, required this.moduleName, required this.now});

  final LabExperiment experiment;
  final String moduleName;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overdue = experiment.preparationOverdue(now, withinDays: 3);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: overdue ? c.warnSoft : c.surface,
        border: Border.all(color: overdue ? c.warn : c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        key: ValueKey('lab-row-${experiment.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LabExperimentScreen(experimentId: experiment.id, moduleName: moduleName),
        )),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Icon(Icons.science_outlined, size: 17, color: c.inkMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(experiment.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(labStatusLine(experiment, now),
                        style: TextStyle(fontSize: 12, color: overdue ? c.warn : c.inkMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: c.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
