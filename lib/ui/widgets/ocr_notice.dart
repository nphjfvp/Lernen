import 'package:flutter/material.dart';

/// Fortschritts-Callback für PdfOcrService: zeigt beim Start einer
/// Texterkennung einmalig einen Hinweis, damit die längere Wartezeit (und die
/// KI-Kosten) nicht überraschen.
///
/// Nimmt den ScaffoldMessenger statt eines BuildContext, damit Aufrufer ihn
/// VOR ihren awaits auslesen können.
void Function(int done, int total) ocrStartNotice(ScaffoldMessengerState? messenger, String fileName) {
  var shown = false;
  return (done, total) {
    if (shown || done != 0 || total == 0) return;
    shown = true;
    messenger?.showSnackBar(SnackBar(
      content: Text('„$fileName“ ist gescannt – Texterkennung per KI läuft ($total Anfrage${total == 1 ? '' : 'n'}) …'),
      duration: const Duration(seconds: 4),
    ));
  };
}
