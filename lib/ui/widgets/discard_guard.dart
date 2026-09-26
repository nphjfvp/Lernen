import 'package:flutter/material.dart';

/// Fragt vor dem Zurück-Navigieren nach, solange [active] gilt – für Screens
/// mit einem noch nicht gespeicherten, per KI erzeugten Ergebnis (Vorschau,
/// laufende Sitzung): eine versehentliche Zurück-Geste verwarf es sonst
/// kommentarlos, samt der dafür bezahlten KI-Anfragen. Programmatisches
/// `Navigator.pop` (z.B. nach dem Speichern) ist davon nicht betroffen.
class DiscardGuard extends StatelessWidget {
  const DiscardGuard({super.key, required this.active, required this.message, required this.child});

  final bool active;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !active,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ergebnis verwerfen?'),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Verwerfen')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: child,
    );
  }
}
