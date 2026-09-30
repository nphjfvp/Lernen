import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/sync_cloud_history.dart';
import '../../services/sync_diagnostics.dart';
import '../../services/sync_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/confirm_delete_dialog.dart';

/// Die früheren Stände in der Cloud (siehe planCloudHistory): ansehen und einen
/// davon wieder zum aktuellen machen. Schließt mit der neuen `pushId`, wenn einer
/// wiederhergestellt wurde (Fächerliste und Einstellungen müssen dann neu laden),
/// sonst mit `null`.
class SyncCloudHistoryDialog extends StatefulWidget {
  const SyncCloudHistoryDialog({super.key, required this.service, required this.target, required this.deviceId});

  final SyncService service;
  final SyncTarget target;
  final String deviceId;

  @override
  State<SyncCloudHistoryDialog> createState() => _SyncCloudHistoryDialogState();
}

class _SyncCloudHistoryDialogState extends State<SyncCloudHistoryDialog> {
  static final _format = DateFormat('dd.MM.yyyy HH:mm');

  late final Future<({CloudSyncMeta? current, List<CloudStateEntry> previous})> _history =
      widget.service.cloudHistory(widget.target);
  bool _busy = false;
  String? _error;

  String _describe(int? modules, int? flashcards, String? deviceId) {
    final counts = modules == null && flashcards == null
        ? 'Umfang unbekannt'
        : '${modules ?? '?'} Fächer, ${flashcards ?? '?'} Karten';
    return '$counts · ${deviceId == widget.deviceId ? 'von diesem Gerät' : 'von einem anderen Gerät'}';
  }

  Future<void> _restore(CloudStateEntry entry) async {
    final when = entry.at == null ? 'unbekannter Zeit' : _format.format(entry.at!);
    final ok = await confirmDelete(
      context,
      title: 'Diesen Cloud-Stand wiederherstellen?',
      message: 'Stand vom $when (${_describe(entry.modules, entry.flashcards, entry.deviceId)}) wird wieder der '
          'aktuelle – auf diesem Gerät und in der Cloud; deine anderen Geräte gleichen sich beim nächsten '
          'Abgleich daran an.\n\nVorher wird der jetzige Stand auf diesem Gerät gesichert, und der Stand, der '
          'jetzt in der Cloud liegt, landet selbst in dieser Liste – du kannst es also zurücknehmen.',
      confirmLabel: 'Wiederherstellen',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pushId = await widget.service.restoreCloudState(widget.target, entry, deviceId: widget.deviceId);
      if (mounted) Navigator.of(context).pop(pushId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Wiederherstellen fehlgeschlagen: ${e is SyncException ? e.message : SyncDiagnostics.describeError(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Frühere Cloud-Stände'),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<({CloudSyncMeta? current, List<CloudStateEntry> previous})>(
          future: _history,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return snapshot.hasError
                  ? Text('Die Stände lassen sich nicht laden: ${SyncDiagnostics.describeError(snapshot.error!)}')
                  : const Center(heightFactor: 2, child: CircularProgressIndicator());
            }
            final current = snapshot.data!.current;
            final previous = snapshot.data!.previous;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wenn ein Gerät hochlädt, bleibt der Stand, den es ersetzt, in der Cloud liegen – die letzten '
                    'fünf, mindestens einer pro Gerätewechsel. So lässt sich ein Stand zurückholen, der aus Versehen '
                    'überschrieben wurde.',
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (current != null) ...[
                    Text(
                      'Aktuell in der Cloud',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current.updatedAt == null ? 'unbekannte Zeit' : _format.format(current.updatedAt!),
                      key: const ValueKey('cloud-current'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _describe(current.modules, current.flashcards, current.deviceId),
                      style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    'Frühere Stände',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted),
                  ),
                  const SizedBox(height: 6),
                  if (previous.isEmpty)
                    const Text('Noch keine – sie entstehen, sobald ein Upload einen anderen Stand ersetzt.'),
                  for (final e in previous)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.at == null ? 'unbekannte Zeit' : _format.format(e.at!),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  _describe(e.modules, e.flashcards, e.deviceId),
                                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            key: ValueKey('cloud-restore-${e.pushId}'),
                            onPressed: _busy ? null : () => _restore(e),
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
      actions: [TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Schließen'))],
    );
  }
}
