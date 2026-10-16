import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/background_transport.dart';
import 'slow_ai_dialog.dart' show appNavigatorKey;

/// Zeigt Fehler mit klarem Fehlercode statt still: ungefangene Fehler der App
/// (Hinweis mit „Details“) und – beim nächsten Start – einen Absturz während
/// einer KI-Anfrage (siehe AiCrashGuard). Details lassen sich kopieren.
class AppErrorReporter {
  AppErrorReporter._();

  static final _shown = <String>{};

  /// Kurzer, stabiler Code je Fehlerart, z.B. APP-3F2A.
  static String codeOf(Object error) =>
      'APP-${(error.runtimeType.toString().hashCode & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0')}';

  static String firstLine(Object error) {
    final text = '$error'.trim().split('\n').first;
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  /// Ein ungefangener Fehler: Hinweis unten mit Code (jeder nur einmal).
  static void report(Object error, StackTrace? stack) {
    final code = codeOf(error);
    final line = firstLine(error);
    if (!_shown.add('$code|$line')) return;
    final details = [
      'Fehlercode $code',
      '${error.runtimeType}: $line',
      if (stack != null) ...'$stack'.split('\n').take(12),
    ].join('\n');
    _whenReady((context) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Fehler $code: $line', maxLines: 3, overflow: TextOverflow.ellipsis),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Details', onPressed: () => _dialog('Fehler $code', details)),
        ),
      );
    });
  }

  /// Nach einem Absturz während einer KI-Anfrage (beim nächsten Start).
  static void showAiCrash(List<PendingAiRequest> pending) {
    final report = aiCrashReport(pending);
    _whenReady(
      (_) => _dialog(
        'Die App wurde beim letzten Mal beendet',
        '$report\n\n'
            'Das passiert, wenn Android die App mitten in der Aufgabe schließt – z.B. durch einen Fehler im '
            'Hintergrund-Dienst oder zu wenig Speicher (sehr große PDFs). Für diese Sitzung laufen KI-Anfragen '
            'deshalb ohne Hintergrund-Dienst (bitte die App beim Erstellen geöffnet lassen). Wenn es wieder '
            'passiert: Fehlercode und Details kopieren und weitergeben.',
      ),
    );
  }

  static void _dialog(String title, String text) {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('app-error-dialog'),
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(text, key: const ValueKey('app-error-details'))),
        actions: [
          TextButton(
            key: const ValueKey('app-error-copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.of(ctx).pop();
            },
            child: const Text('Kopieren'),
          ),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  /// Wartet, bis die App steht (Navigator vorhanden), höchstens ~10 s.
  static void _whenReady(void Function(BuildContext context) show, [int tries = 0]) {
    final context = appNavigatorKey.currentContext;
    if (context != null) {
      show(context);
    } else if (tries < 20) {
      Timer(const Duration(milliseconds: 500), () => _whenReady(show, tries + 1));
    }
  }
}
