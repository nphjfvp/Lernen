import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'page_qa_panel.dart';

/// Frage-Chat zu EINER konkreten, gerade betrachteten Seite (siehe
/// AiService.answerPageQuestion) als Bottom-Sheet: sieht den mitgegebenen
/// Screenshot dieser Seite und den Volltext des Dokuments ([documentText]).
/// Rein session-lokal. Losgelöst von einem gespeicherten MaterialItem – für
/// noch nicht gespeicherte Dateien (PdfPreviewScreen) und schmale Bildschirme;
/// im PDF-Viewer läuft auf breiten Bildschirmen stattdessen das angedockte
/// [PageQaPanel] mit Notizen.
class PageQuestionSheet extends StatefulWidget {
  const PageQuestionSheet({
    super.key,
    required this.documentText,
    required this.pageNumber,
    required this.totalPages,
    required this.pageImageBytes,
  });

  final String documentText;
  final int pageNumber;
  final int totalPages;
  final Uint8List pageImageBytes;

  @override
  State<PageQuestionSheet> createState() => _PageQuestionSheetState();
}

class _PageQuestionSheetState extends State<PageQuestionSheet> {
  final _controller = PageQaController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: PageQaPanel(
          controller: _controller,
          documentText: widget.documentText,
          capturePage: () async => (image: widget.pageImageBytes, page: widget.pageNumber, total: widget.totalPages),
          currentPage: widget.pageNumber,
          totalPages: widget.totalPages,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
