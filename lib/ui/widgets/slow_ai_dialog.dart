import 'dart:async';

import 'package:flutter/material.dart';

/// Navigator der App – damit die Rückfrage bei langsamer KI von überall
/// (auch aus Diensten ohne BuildContext) erscheinen kann.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Rückfrage, wenn OpenRouter lange nicht antwortet (Hook für
/// `AiService.onSlowResponse`): „Weiter warten“ oder „Abbrechen“. Laufen
/// mehrere Anfragen gleichzeitig, teilen sie sich einen Dialog; kommt eine
/// Antwort doch noch, schließt er sich selbst (= weiter warten).
class SlowAiPrompt {
  SlowAiPrompt._();

  static Future<bool>? _open;

  static Future<bool> ask(Duration waited, Future<void> done) {
    final open = _open;
    if (open != null) return open;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return Future.value(false);
    late final DialogRoute<bool> route;
    route = DialogRoute<bool>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => _SlowAiDialog(waited: waited),
    );
    unawaited(
      done.then((_) {
        if (route.isActive) route.navigator?.removeRoute(route, true);
      }),
    );
    final result = navigator.push(route).then((keepWaiting) {
      _open = null;
      return keepWaiting ?? true;
    });
    _open = result;
    return result;
  }
}

class _SlowAiDialog extends StatelessWidget {
  const _SlowAiDialog({required this.waited});

  final Duration waited;

  @override
  Widget build(BuildContext context) {
    final minutes = waited.inMinutes;
    return AlertDialog(
      key: const ValueKey('ai-slow-dialog'),
      icon: const Icon(Icons.hourglass_bottom),
      title: const Text('Die KI braucht länger'),
      content: Text(
        'OpenRouter hat seit ${minutes < 1 ? 'einer Weile' : (minutes == 1 ? '1 Minute' : '$minutes Minuten')} '
        'noch nicht geantwortet. Große Aufgaben (viele Seiten, Bilder, lange Antworten) oder ein '
        'ausgelastetes Modell brauchen manchmal länger.\n\n'
        'Die Anfrage läuft weiter – möchtest du warten?',
      ),
      actions: [
        TextButton(
          key: const ValueKey('ai-slow-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const ValueKey('ai-slow-wait'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Weiter warten'),
        ),
      ],
    );
  }
}
