import 'package:flutter/material.dart';

import '../../services/import_verify_service.dart';
import '../../theme/app_colors.dart';
import 'math_text.dart';

/// Was der Nutzer mit einem Befund der zweiten KI gemacht hat.
enum FindingDecision { open, accepted, dismissed }

/// Ergebnis der Prüfung durch die zweite KI (siehe ImportVerifyService) mit
/// Begründung je Abweichung. Der Nutzer entscheidet: fehlende Aufgabe
/// ergänzen oder ignorieren, überzählige Frage entfernen oder behalten.
class ImportCheckPanel extends StatelessWidget {
  const ImportCheckPanel({
    super.key,
    required this.report,
    required this.running,
    required this.decisions,
    required this.busy,
    required this.onRun,
    required this.onAccept,
    required this.onDismiss,
    this.progress,
    this.note,
  });

  final ImportCheckReport? report;
  final bool running;

  /// Entscheidung je Befund (Position in [ImportCheckReport.findings]).
  final Map<int, FindingDecision> decisions;

  /// Befunde, deren Aktion gerade läuft (z.B. Ergänzen).
  final Set<int> busy;

  /// Prüfung (erneut) starten; null = nicht möglich.
  final VoidCallback? onRun;
  final void Function(int index) onAccept;
  final void Function(int index) onDismiss;
  final String? progress;

  /// Hinweis, z.B. welche Dateien nicht geprüft werden können.
  final String? note;

  static String acceptLabel(ImportFinding f) => f.isMissing ? 'Ergänzen' : 'Entfernen';
  static String dismissLabel(ImportFinding f) => f.isMissing ? 'Ignorieren' : 'Behalten';

  static String _title(ImportFinding f) => switch (f.kind) {
        ImportFindingKind.missing => 'Fehlt im Import',
        ImportFindingKind.notInDocument => 'Steht nicht im Dokument',
        ImportFindingKind.duplicate => 'Doppelt übernommen',
        ImportFindingKind.altered => 'Weicht vom Dokument ab',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    final small = TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35);
    return Card(
      key: const ValueKey('import-check-panel'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Prüfung durch zweite KI', style: Theme.of(context).textTheme.titleSmall),
                ),
                if (running)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  TextButton(
                    key: const ValueKey('import-check-run'),
                    onPressed: onRun,
                    child: Text(r == null ? 'Jetzt prüfen' : 'Erneut prüfen'),
                  ),
              ],
            ),
            if (running && progress != null) Text(progress!, style: small),
            if (r == null && !running)
              Text(
                'Eine zweite KI liest das Dokument selbst und prüft, ob alle Aufgaben übernommen wurden – '
                'zu wenige oder zu viele.',
                style: small,
              ),
            if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: small)),
            if (r != null) ...[
              const SizedBox(height: 6),
              Text(
                'Zweite KI zählt ${r.documentCount ?? '?'} ${r.documentCount == 1 ? 'Frage' : 'Fragen'} im Dokument · '
                'übernommen: ${r.importedCount}',
                key: const ValueKey('import-check-summary'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (r.agrees)
                Text('Beide KIs sehen dasselbe – nichts fehlt, nichts ist zu viel.',
                    style: TextStyle(fontSize: 12.5, color: c.good))
              else if (r.findings.isNotEmpty)
                Text(
                  '${r.findings.length} ${r.findings.length == 1 ? 'Abweichung' : 'Abweichungen'} '
                  '(${r.missingCount} fehlt, ${r.surplusCount} zu viel) – die zweite KI begründet sie unten, '
                  'du entscheidest.',
                  style: TextStyle(fontSize: 12.5, color: c.warn),
                ),
              for (final e in r.errors)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(e, style: TextStyle(fontSize: 12, color: c.danger)),
                ),
              if (r.uncheckedPages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Ohne lesbaren Text, nicht geprüft: Seite ${r.uncheckedPages.join(', ')}.',
                    style: small,
                  ),
                ),
              for (final n in r.notes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Hinweis der zweiten KI: $n', style: small),
                ),
              for (final (i, f) in r.findings.indexed) _finding(context, c, i, f),
            ],
          ],
        ),
      ),
    );
  }

  Widget _finding(BuildContext context, AppColors c, int i, ImportFinding f) {
    final decision = decisions[i] ?? FindingDecision.open;
    final working = busy.contains(i);
    final done = switch (decision) {
      FindingDecision.accepted => f.isMissing ? '✓ ergänzt' : '✓ entfernt',
      FindingDecision.dismissed => f.isMissing ? 'ignoriert' : 'behalten',
      FindingDecision.open => null,
    };
    return Container(
      key: ValueKey('import-finding-$i'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.warnSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_title(f)} · Seite ${f.page}${f.fileName == null ? '' : ' · ${f.fileName}'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.warn),
          ),
          const SizedBox(height: 4),
          MathText(f.text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Begründung der zweiten KI: ${f.reason}',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35)),
          const SizedBox(height: 6),
          if (working)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (done != null)
            Text(done, style: TextStyle(fontSize: 12.5, color: decision == FindingDecision.accepted ? c.good : c.inkMuted))
          else
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  key: ValueKey('import-finding-accept-$i'),
                  onPressed: () => onAccept(i),
                  child: Text(acceptLabel(f)),
                ),
                OutlinedButton(
                  key: ValueKey('import-finding-dismiss-$i'),
                  onPressed: () => onDismiss(i),
                  child: Text(dismissLabel(f)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
