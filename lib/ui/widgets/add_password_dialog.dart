import 'package:flutter/material.dart';

/// Fragt ein neues Passwort (mit Bestätigung) für [email] ab – zum
/// Verknüpfen mit dem aktuell angemeldeten Konto (siehe
/// AuthService.linkEmailPassword). Gibt das Passwort zurück, oder `null`
/// bei Abbruch.
Future<String?> addPasswordDialog(BuildContext context, {required String email}) {
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  String? error;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('Passwort hinzufügen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Für "$email" – damit kannst du dich mit diesem Passwort auch dort '
                  'anmelden, wo Google-Anmeldung nicht funktioniert (z.B. Windows/Desktop) '
                  '– derselbe Cloud-Sync wie mit Google.',
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Neues Passwort'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Passwort wiederholen'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () {
                if (passwordController.text.length < 6) {
                  setState(() => error = 'Mindestens 6 Zeichen.');
                  return;
                }
                if (passwordController.text != confirmController.text) {
                  setState(() => error = 'Passwörter stimmen nicht überein.');
                  return;
                }
                Navigator.of(ctx).pop(passwordController.text);
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        );
      },
    ),
  );
}
