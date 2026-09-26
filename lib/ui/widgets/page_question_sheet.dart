import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';
import 'safe_set_state.dart';

/// Frage-Chat zu EINER konkreten, gerade betrachteten Seite (siehe
/// AiService.answerPageQuestion) – sieht sowohl den mitgegebenen Screenshot
/// dieser Seite als auch den Volltext des gesamten Dokuments ([documentText])
/// als Kontext. Rein session-lokal (nicht persistiert). Losgelöst von einem
/// konkreten (gespeicherten) MaterialItem, damit sich das Sheet sowohl in
/// MaterialViewerScreen (gespeichertes Material) als auch in PdfPreviewScreen
/// (noch nicht gespeicherte Datei während Vorbereiten/Nachbereiten) nutzen
/// lässt.
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

class _PageQuestionSheetState extends State<PageQuestionSheet> with SafeSetState<PageQuestionSheet> {
  final _controller = TextEditingController();
  final List<({String question, String answer})> _turns = [];
  bool _asking = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }

    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId);
      final history = _turns
          .expand((t) => [(isUser: true, content: t.question), (isUser: false, content: t.answer)])
          .toList();
      final answer = await ai.answerPageQuestion(
        question: question,
        pageImageBytes: widget.pageImageBytes,
        pageNumber: widget.pageNumber,
        totalPages: widget.totalPages,
        documentText: widget.documentText,
        history: history,
      );
      if (!mounted) return;
      setState(() {
        _turns.add((question: question, answer: answer));
        _controller.clear();
        _asking = false;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _asking = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unerwarteter Fehler: $e';
        _asking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(widget.pageImageBytes, width: 44, height: 58, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Frage zu Seite ${widget.pageNumber}',
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                          Text('von ${widget.totalPages} · sieht Bild dieser Seite + gesamten Dokumenttext',
                              style: TextStyle(fontSize: 11, color: c.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_turns.isEmpty)
                      Text('Stell eine Frage zu genau dieser Seite.',
                          style: TextStyle(fontSize: 13, color: c.inkMuted)),
                    ..._turns.map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.question, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(t.answer, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4)),
                            ],
                          ),
                        )),
                    if (_asking)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !_asking,
                          decoration: InputDecoration(
                            hintText: 'Frage zu dieser Seite …',
                            filled: true,
                            fillColor: c.surfaceAlt,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onSubmitted: (_) => _asking ? null : _ask(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(onPressed: _asking ? null : _ask, icon: const Icon(Icons.send_rounded)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
