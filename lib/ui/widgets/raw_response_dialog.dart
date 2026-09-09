import 'package:flutter/material.dart';

/// Zeigt die rohe KI-Antwort an, wenn das JSON-Parsing fehlgeschlagen ist –
/// hilfreich, um zu sehen, ob das gewählte Modell sich einfach nicht an das
/// Format gehalten hat.
void showRawResponseDialog(BuildContext context, String rawResponse) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('KI-Antwort (roh)'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: SelectableText(rawResponse)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Schließen')),
      ],
    ),
  );
}
