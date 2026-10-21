import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../../repositories/settings_repository.dart';
import '../../services/sync_codes.dart';
import '../../theme/app_colors.dart';
import 'claude_inbox_screen.dart';

/// Einstellungen → Claude-Postfach: Code erzeugen, kopieren, Postfach öffnen.
class ClaudeInboxSettings extends StatelessWidget {
  const ClaudeInboxSettings({super.key});

  Future<void> _setCode(BuildContext context, String? code) {
    final repo = context.read<SettingsRepository>();
    // copyWith übernimmt null nicht – zum Entfernen ein leerer Code.
    return repo.update(repo.settings.copyWith(inboxCode: code ?? ''));
  }

  Future<void> _renew(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neuen Postfach-Code?'),
        content: const Text(
          'Lieferungen unter dem alten Code sind danach hier nicht mehr zu sehen. Gib Claude künftig den neuen Code.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Neuer Code')),
        ],
      ),
    );
    if (ok == true && context.mounted) await _setCode(context, SyncCodes.generate());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final code = context.watch<SettingsRepository>().settings.inboxCode;
    return Column(
      key: const ValueKey('inbox-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CLAUDE-POSTFACH',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.04, color: c.inkMuted),
        ),
        const SizedBox(height: 6),
        Text(
          'Claude baut in einer Claude-Code-Sitzung Aufgaben genau im Format der App und legt sie unter diesem '
          'Code ab. Du siehst sie hier im Postfach, prüfst sie und übernimmst sie in ein Fach. Der Code ist wie ein '
          'Passwort – nur Claude und dir geben.',
          style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (code == null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('inbox-generate'),
              onPressed: () => _setCode(context, SyncCodes.generate()),
              icon: const Icon(Icons.password, size: 18),
              label: const Text('Postfach-Code erzeugen'),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code,
                    key: const ValueKey('inbox-code'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink, letterSpacing: 0.5),
                  ),
                ),
                IconButton(
                  key: const ValueKey('inbox-copy'),
                  tooltip: 'Kopieren',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Postfach-Code kopiert.')));
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                key: const ValueKey('inbox-open'),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClaudeInboxScreen())),
                icon: const Icon(Icons.inbox_outlined, size: 18),
                label: const Text('Postfach öffnen'),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('inbox-renew'),
                onPressed: () => _renew(context),
                child: const Text('Neuer Code'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
