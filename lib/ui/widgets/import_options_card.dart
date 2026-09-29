import 'package:flutter/material.dart';

import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';

/// Wahl vor einem Fragen-Import aus einem Dokument: eine zweite KI prüft die
/// Vollständigkeit, und/oder zu jeder übernommenen Frage kommen weitere
/// Schwierigkeitsstufen dazu.
class ImportOptions {
  const ImportOptions({this.verify = false, this.levels = const {}});

  /// Eine zweite KI liest das Dokument selbst und prüft, ob alle Fragen
  /// übernommen wurden (siehe ImportVerifyService).
  final bool verify;

  /// Zusätzlich gewünschte Stufen (Namen aus [AiService.stageLevelNames]);
  /// leer = die Fragen 1:1 wie im Dokument, ohne Stufen.
  final Set<String> levels;

  bool get expandStages => levels.isNotEmpty;

  ImportOptions copyWith({bool? verify, Set<String>? levels}) =>
      ImportOptions(verify: verify ?? this.verify, levels: levels ?? this.levels);
}

/// Die beiden Import-Optionen als Karte (siehe [ImportOptions]).
class ImportOptionsCard extends StatelessWidget {
  const ImportOptionsCard({
    super.key,
    required this.options,
    required this.onChanged,
    this.verifyAvailable = true,
    this.enabled = true,
  });

  final ImportOptions options;
  final ValueChanged<ImportOptions> onChanged;

  /// Die Prüfung liest den Text von PDF-Seiten – ohne PDF gibt es nichts zu
  /// prüfen.
  final bool verifyAvailable;
  final bool enabled;

  static const _levelLabels = {'leicht': 'Leicht', 'mittel': 'Mittel', 'schwer': 'Schwer'};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final small = TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Genauigkeit und Schwierigkeit', style: Theme.of(context).textTheme.titleSmall),
            SwitchListTile(
              key: const ValueKey('import-opt-verify'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: options.verify && verifyAvailable,
              onChanged: enabled && verifyAvailable ? (v) => onChanged(options.copyWith(verify: v)) : null,
              title: const Text('Zweite KI prüft die Vollständigkeit'),
              subtitle: Text(
                verifyAvailable
                    ? 'Eine zweite KI (Zweitmeinungs-Modell aus den Einstellungen) liest das Dokument selbst '
                        'und zählt, ob alle Aufgaben übernommen wurden – zu wenige oder zu viele. Sieht sie '
                        'etwas anderes als die erste, begründet sie es, und du entscheidest.'
                    : 'Nur für PDFs möglich – die zweite KI liest den Text der Seiten.',
                style: small,
              ),
            ),
            SwitchListTile(
              key: const ValueKey('import-opt-stages'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: options.expandStages,
              onChanged: enabled
                  ? (v) => onChanged(options.copyWith(levels: v ? {...AiService.stageLevelNames} : <String>{}))
                  : null,
              title: const Text('Verschiedene Schwierigkeitsstufen'),
              subtitle: Text(
                'Zu jeder übernommenen Frage ergänzt die KI dasselbe Wissen in den gewählten Stufen. Beim '
                'Lernen kommt erst die leichte, wenn sie sitzt die nächste. Die Original-Frage bleibt '
                'unverändert; ergänzte Fragen sind in der Vorschau gekennzeichnet.',
                style: small,
              ),
            ),
            if (options.expandStages)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final level in AiService.stageLevelNames)
                      FilterChip(
                        key: ValueKey('import-level-$level'),
                        label: Text(_levelLabels[level]!),
                        selected: options.levels.contains(level),
                        onSelected: !enabled
                            ? null
                            : (on) {
                                final next = {...options.levels};
                                on ? next.add(level) : next.remove(level);
                                // Ohne jede Stufe gibt es nichts zu ergänzen.
                                onChanged(options.copyWith(levels: next));
                              },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
