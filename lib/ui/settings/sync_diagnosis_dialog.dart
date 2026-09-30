import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/firestore_rules.dart';
import '../../services/sync_diagnostics.dart';
import '../../theme/app_colors.dart';

/// Ergebnis von "Verbindung prüfen": Zeile für Zeile, was am Sync klappt und
/// woran es hängt. Läuft die Prüfung noch (bis zu etwa einer Minute), steht
/// ein Ladehinweis da.
class SyncDiagnosisDialog extends StatelessWidget {
  const SyncDiagnosisDialog({super.key, required this.future});

  final Future<List<DiagLine>> future;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FutureBuilder<List<DiagLine>>(
      future: future,
      builder: (context, snapshot) {
        final lines = snapshot.data ??
            (snapshot.hasError ? [DiagLine(DiagLevel.error, 'Die Prüfung ist abgebrochen', '${snapshot.error}')] : null);
        return AlertDialog(
          title: const Text('Sync: Verbindung prüfen'),
          content: SizedBox(
            width: 460,
            child: lines == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 8),
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Prüfe Verbindung, Ziel und Cloud-Stand … (kann bis zu einer Minute dauern)'),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Text(
                                    line.symbol,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: switch (line.level) {
                                        DiagLevel.ok => c.good,
                                        DiagLevel.info => c.inkMuted,
                                        DiagLevel.warn => c.warn,
                                        DiagLevel.error => c.danger,
                                      },
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(line.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (line.detail.isNotEmpty)
                                        Text(line.detail, style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('copy-rules'),
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: firestoreRulesText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Firestore-Regeln kopiert – in der Firebase-Konsole unter Firestore → Regeln '
                        'einfügen und veröffentlichen.'),
                  ));
                }
              },
              child: const Text('Regeln kopieren'),
            ),
            if (lines != null)
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: lines.map((l) => l.asText()).join('\n')));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ergebnis kopiert.')));
                  }
                },
                child: const Text('Kopieren'),
              ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Schließen')),
          ],
        );
      },
    );
  }
}
