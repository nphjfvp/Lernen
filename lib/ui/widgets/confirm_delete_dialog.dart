import 'package:flutter/material.dart';

/// Einfacher Bestätigungsdialog vor einer endgültigen Löschung – zentral
/// statt pro Bildschirm dupliziert.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
      ],
    ),
  );
  return confirmed == true;
}
