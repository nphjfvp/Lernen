import 'package:flutter/material.dart';

import '../../services/sync_codes.dart';
import '../../theme/app_colors.dart';

/// Unter dem Sync-Code-Feld: ohne Code „Sicheren Code erzeugen“, bei einem
/// kurzen (erratbaren) Code der Hinweis samt „Auf sicheren Code umziehen“.
class SyncCodeHint extends StatelessWidget {
  const SyncCodeHint({super.key, required this.controller, required this.onGenerate, required this.onMove});

  final TextEditingController controller;
  final VoidCallback? onGenerate;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final code = value.text.trim();
        if (code.isEmpty) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('sync-code-generate'),
              onPressed: onGenerate,
              icon: const Icon(Icons.password, size: 18),
              label: const Text('Sicheren Code erzeugen'),
            ),
          );
        }
        if (SyncCodes.isStrong(code)) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('sync-code-weak'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dieser Code ist kurz und lässt sich erraten – wer ihn errät, kann deine Lerndaten lesen und '
                'überschreiben. Zieh auf einen sicheren, zufälligen Code um und gib ihn danach auf den anderen '
                'Geräten ein (dort „Herunterladen“ oder „Abgleichen“). Sind alle Geräte umgezogen: unter '
                '„Verbindung prüfen“ die Regeln kopieren und in Firebase neu veröffentlichen – dann sind kurze '
                'Codes gesperrt.',
                style: TextStyle(fontSize: 12, color: c.warn, height: 1.4),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('sync-code-move'),
                onPressed: onMove,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Auf sicheren Code umziehen'),
              ),
            ],
          ),
        );
      },
    );
  }
}
