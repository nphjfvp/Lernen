import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_checker_service.dart';
import '../../services/update_installer.dart';

/// Beschriftung für den Update-Knopf: unter Windows und Android installiert
/// die App das Update selbst, sonst öffnet sich der Download.
String get updateActionLabel => canInstallUpdateInApp ? 'Jetzt installieren' : 'Herunterladen';

bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

/// Update anwenden: Datei in der App laden und installieren – Windows still
/// (die App schließt sich und startet neu), Android über den System-Dialog
/// "Aktualisieren?". Sonst bzw. wenn das scheitert: Download im Browser.
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
            Text(_isAndroid
                ? 'Wird geladen … Danach fragt Android, ob Lernen aktualisiert werden soll. Deine Daten '
                    'bleiben erhalten.'
                : 'Wird geladen … Danach schließt sich die App kurz und startet mit der neuen Version. '
                    'Deine Daten bleiben erhalten.'),
          ],
        ),
      ),
    ),
  );
  final result = await installUpdate(
    update.downloadUrl,
    buildNumber: update.buildNumber,
    onProgress: (p) => progress.value = p,
  );
  navigator.pop();
  progress.dispose();
  switch (result) {
    case UpdateInstallResult.started:
      messenger?.showSnackBar(const SnackBar(
        duration: Duration(seconds: 8),
        content: Text('Tippe im Android-Dialog auf „Aktualisieren“ und öffne Lernen danach wieder.'),
      ));
    case UpdateInstallResult.needsPermission:
      if (!navigator.mounted) return;
      await showDialog<void>(
        context: navigator.context,
        builder: (ctx) => AlertDialog(
          title: const Text('Einmal erlauben'),
          content: const Text('Android fragt, ob Lernen Apps installieren darf. Schalte in der gerade geöffneten '
              'Einstellung „Dieser Quelle vertrauen“ bzw. „Apps aus dieser Quelle zulassen“ ein, komm zurück und '
              'tippe noch einmal auf „Jetzt installieren“. Das ist nur beim ersten Mal nötig.'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
    case UpdateInstallResult.failed:
      messenger?.showSnackBar(const SnackBar(
        content: Text('Das Update ließ sich nicht direkt installieren – der Download öffnet sich im Browser.'),
      ));
      await openInBrowser();
  }
}
