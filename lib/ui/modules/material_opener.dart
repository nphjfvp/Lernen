import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/material_item.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/auto_sync_service.dart';
import '../../services/pdf_cloud_store.dart';
import '../../services/pdf_cloud_sync_service.dart';
import 'material_viewer_screen.dart';

/// Kann das Material auf diesem Gerät angezeigt werden – lokal oder aus dem
/// eigenen Cloud-Speicher?
bool canOpenMaterial(BuildContext context, MaterialItem material) =>
    material.hasViewablePdf ||
    (material.hasRemotePdf && (context.read<SettingsRepository?>()?.settings.pdfStorage.isConfigured ?? false));

/// Liegt die PDF nur im eigenen Cloud-Speicher (von einem anderen Gerät
/// hochgeladen), wird sie einmalig heruntergeladen und lokal abgelegt.
/// Liefert das Material mit lokaler PDF oder `null` (mit Meldung).
Future<MaterialItem?> ensureLocalPdf(BuildContext context, MaterialItem material) async {
  if (material.hasViewablePdf) return material;
  final store = PdfCloudStore.fromConfig(context.read<SettingsRepository>().settings.pdfStorage);
  final autoSync = context.read<AutoSyncService?>();
  final repo = context.read<MaterialRepository>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  if (store == null || !material.hasRemotePdf) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('PDF wird aus deinem Speicher geladen …')),
        ],
      ),
    ),
  );
  MaterialItem? result;
  try {
    // Nur geräte-lokale Felder ändern sich – kein neuer Upload nötig.
    Future<MaterialItem?> download() => PdfCloudSyncService(store).download(material);
    result = autoSync == null ? await download() : await autoSync.runWithoutTrigger(download);
    if (result == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Die PDF liegt nicht (mehr) im Speicher.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('PDF konnte nicht geladen werden: $e')));
  } finally {
    navigator.pop();
  }
  await repo.loadForModule(material.moduleId);
  return result;
}

/// Öffnet das Material im PDF-Viewer, auf Wunsch direkt auf Seite [page].
Future<void> openMaterialAt(BuildContext context, MaterialItem material, {int? page}) async {
  final local = await ensureLocalPdf(context, material);
  if (local == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => MaterialViewerScreen(material: local, initialPage: page)),
  );
}
