import 'package:flutter/material.dart';

/// Einfacher Dialog zum Bearbeiten von zwei Textfeldern (z.B. Konzept-Titel
/// + Erklärung, Karteikarten-Vorderseite + Rückseite). Gibt die
/// bearbeiteten Werte als `(field1, field2)` zurück, oder `null` bei
/// Abbruch.
Future<(String, String)?> editTwoFieldsDialog(
  BuildContext context, {
  required String title,
  required String label1,
  required String initial1,
  required String label2,
  required String initial2,
}) async {
  final controller1 = TextEditingController(text: initial1);
  final controller2 = TextEditingController(text: initial2);

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller1,
              decoration: InputDecoration(labelText: label1),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller2,
              decoration: InputDecoration(labelText: label2),
              minLines: 3,
              maxLines: 10,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Speichern')),
      ],
    ),
  );

  if (saved != true) return null;
  return (controller1.text.trim(), controller2.text.trim());
}
