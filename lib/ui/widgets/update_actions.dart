import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_checker_service.dart';
import '../../services/update_installer.dart';

/// Beschriftung für den Update-Knopf: unter Windows installiert die App das
/// Update selbst, sonst öffnet sich der Download.
String get updateActionLabel => canInstallUpdateInApp ? 'Jetzt installieren' : 'Herunterladen';

/// Update anwenden: unter Windows Setup laden und still installieren (die
/// App schließt sich und startet danach neu), sonst bzw. wenn das scheitert
/// den Download im Browser öffnen.
Future<void> applyUpdate(BuildContext context, UpdateInfo update) async {
  Future<void> openInBrowser() =>
      launchUrl(Uri.parse(update.downloadUrl), mode: LaunchMode.externalApplication);
  if (!canInstallUpdateInApp) {
    await openInBrowser();
    return;
  }
  final progress = ValueNotifier<double?>(null);
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text('Update auf Build ${update.buildNumber}'),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (_, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: value),
            const SizedBox(height: 12),
            const Text('Wird geladen … Danach schließt sich die App kurz und startet mit der neuen Version. '
                'Deine Daten bleiben erhalten.'),
          ],
        ),
      ),
    ),
  );
  // Kehrt nur zurück, wenn es nicht geklappt hat – sonst beendet sich die App.
  await installUpdate(update.downloadUrl, onProgress: (p) => progress.value = p);
  navigator.pop();
  progress.dispose();
  messenger?.showSnackBar(const SnackBar(
    content: Text('Das Update ließ sich nicht direkt installieren – der Download öffnet sich im Browser.'),
  ));
  await openInBrowser();
}
