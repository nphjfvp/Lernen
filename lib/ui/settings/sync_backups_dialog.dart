import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/database_service.dart';
import '../../services/sync_backup_service.dart';
import '../../services/sync_diagnostics.dart';
import '../../theme/app_colors.dart';
import '../widgets/confirm_delete_dialog.dart';

/// Die automatischen Sicherungen dieses Geräts (siehe SyncBackupService):
/// ansehen und wiederherstellen. Schließt mit `true`, wenn eine wiederher-
/// gestellt wurde (die Fächerliste muss dann neu geladen werden).
class SyncBackupsDialog extends StatefulWidget {
  const SyncBackupsDialog({super.key});

  @override
  State<SyncBackupsDialog> createState() => _SyncBackupsDialogState();
}

class _SyncBackupsDialogState extends State<SyncBackupsDialog> {
  static final _format = DateFormat('dd.MM.yyyy HH:mm');

  late final Future<List<SyncBackup>> _backups = _load();
  bool _busy = false;
  String? _error;

  Future<List<SyncBackup>> _load() async => SyncBackupService.list(await DatabaseService.instance.database);

  static String _kindLabel(SyncBackup b) => switch (b.kind) {
        SyncBackupService.kindPull => 'Vor einem Download',
        SyncBackupService.kindDaily => 'Tägliche Sicherung',
        SyncBackupService.kindRestore => 'Vor einer Wiederherstellung',
        _ => b.reason,
      };

  Future<void> _restore(SyncBackup backup) async {
    final ok = await confirmDelete(
      context,
      title: 'Diese Sicherung wiederherstellen?',
      message: 'Stand vom ${_format.format(backup.createdAt)} (${backup.modules} Fächer, ${backup.flashcards} Karten) '
          'ersetzt den jetzigen Lernstand auf diesem Gerät. Vorher wird der jetzige Stand selbst gesichert – '
          'du kannst es also zurücknehmen. Die Cloud ändert sich dadurch nicht; danach unter Cloud-Sync '
          '"Hochladen", wenn dieser Stand der richtige ist.',
      confirmLabel: 'Wiederherstellen',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SyncBackupService.restore(await DatabaseService.instance.database, backup.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Wiederherstellen fehlgeschlagen: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Sicherungen auf diesem Gerät'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<SyncBackup>>(
          future: _backups,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return snapshot.hasError
                  ? Text('Die Sicherungen lassen sich nicht laden: ${snapshot.error}')
                  : const Center(heightFactor: 2, child: CircularProgressIndicator());
            }
            final backups = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vor jedem Download und einmal am Tag sichert die App deinen Lernstand hier auf dem Gerät. '
                    'Sie werden nie in die Cloud hochgeladen.',
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (backups.isEmpty) const Text('Noch keine Sicherung.'),
                  for (final b in backups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_format.format(b.createdAt), style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  '${_kindLabel(b)} · ${b.modules} Fächer, ${b.flashcards} Karten · ${SyncDiagnostics.size(b.bytes)}',
                                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            key: ValueKey('restore-${b.id}'),
                            onPressed: _busy ? null : () => _restore(b),
                            child: const Text('Wiederherstellen'),
                          ),
                        ],
                      ),
                    ),
                  if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Schließen'))],
    );
  }
}
