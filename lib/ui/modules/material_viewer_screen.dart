import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:uuid/uuid.dart';

import '../../models/material_item.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/highlight_matcher.dart';
import '../../services/material_file_store.dart';
import '../../theme/app_colors.dart';

/// Zeigt eine hochgeladene PDF-Folie visuell an und erlaubt es, Textstellen
/// farblich zu markieren – rot: eignet sich als Prüfungsfrage, grün: die
/// Antwort/der Kernfakt dazu, gelb: sonst einfach wichtig/relevant. Sowohl
/// manuell (Text auswählen + Farbe antippen) als auch automatisch per
/// KI-Vorschlag (siehe AiService.suggestHighlights). Die Markierungen +
/// eine kurze Notiz fließen als "besonders relevant"-Kontext in
/// Vorbereiten/Nachbereiten/Chat ein (siehe MaterialItem.highlights/notes).
class MaterialViewerScreen extends StatefulWidget {
  const MaterialViewerScreen({super.key, required this.material});

  final MaterialItem material;

  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> {
  final _pdfController = PdfViewerController();
  final _pdfViewerKey = GlobalKey<SfPdfViewerState>();
  final _pdfBoundaryKey = GlobalKey();
  late List<MaterialHighlight> _highlights;
  late final TextEditingController _notesController;

  Uint8List? _bytes;
  bool _loading = true;
  String? _loadError;

  bool _hasSelection = false;
  bool _dirty = false;
  bool _saving = false;

  bool _suggesting = false;
  String? _suggestError;

  bool _capturingPageQuestion = false;

  @override
  void initState() {
    super.initState();
    _highlights = List.of(widget.material.highlights);
    _notesController = TextEditingController(text: widget.material.notes);
    _loadBytes();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _loadBytes() async {
    final bytes = await MaterialFileStore.load(
      filePath: widget.material.filePath,
      fileBytesBase64: widget.material.fileBytesBase64,
    );
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
      _loadError = bytes == null ? 'PDF konnte nicht geladen werden.' : null;
    });
  }

  Color _colorFor(HighlightColor color) {
    final c = context.colors;
    return switch (color) {
      HighlightColor.red => c.danger,
      HighlightColor.green => c.good,
      HighlightColor.yellow => c.warn,
    };
  }

  void _addManualHighlight(HighlightColor color) {
    final lines = _pdfViewerKey.currentState?.getSelectedTextLines() ?? const [];
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Zuerst Text in der Folie auswählen.')));
      return;
    }
    final text = lines.map((l) => l.text).join(' ').trim();
    final annotation = HighlightAnnotation(textBoundsCollection: lines)
      ..color = _colorFor(color).withAlpha(110);
    _pdfController.addAnnotation(annotation);
    setState(() {
      _highlights.add(MaterialHighlight(
        id: const Uuid().v4(),
        text: text,
        color: color,
        source: HighlightSource.manual,
        pageNumber: lines.first.pageNumber,
      ));
      _hasSelection = false;
      _dirty = true;
    });
  }

  void _removeHighlight(MaterialHighlight highlight) {
    // Entfernt die Markierung aus der an die KI weitergereichten Liste. Die
    // visuelle Annotation im PDF bleibt bis zum nächsten Öffnen bestehen –
    // ein gezieltes Zurückverfolgen einzelner Annotationen bräuchte ein
    // highlight<->Annotation-Mapping, das für den eigentlichen Zweck hier
    // (Markierung aus dem KI-Kontext nehmen) nicht nötig ist.
    setState(() {
      _highlights.removeWhere((h) => h.id == highlight.id);
      _dirty = true;
    });
  }

  Future<void> _suggestFromAi() async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() =>
          _suggestError = 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }
    final bytes = _bytes;
    if (bytes == null) return;

    setState(() {
      _suggesting = true;
      _suggestError = null;
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final suggestions = await ai.suggestHighlights(widget.material.extractedText);

      final document = sf_pdf.PdfDocument(inputBytes: bytes);
      final List<sf_pdf.TextLine> textLines;
      try {
        textLines = sf_pdf.PdfTextExtractor(document).extractTextLines();
      } finally {
        document.dispose();
      }
      final byPage = <int, List<sf_pdf.TextLine>>{};
      for (final line in textLines) {
        byPage.putIfAbsent(line.pageIndex, () => []).add(line);
      }

      var matched = 0;
      var unmatched = 0;
      final newHighlights = <MaterialHighlight>[];
      for (final s in suggestions) {
        final text = (s['text'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        final color = highlightColorFromString(s['color'] as String?);
        final reason = (s['reason'] as String?)?.trim();

        int? matchedPage;
        List<int>? matchedRange;
        for (final entry in byPage.entries) {
          final range =
              HighlightMatcher.findLineRange(entry.value.map((l) => l.text).toList(), text);
          if (range != null) {
            matchedPage = entry.key;
            matchedRange = range;
            break;
          }
        }

        if (matchedPage != null && matchedRange != null) {
          final pageLines = byPage[matchedPage]!;
          final pdfTextLines = matchedRange
              .map((i) => PdfTextLine(pageLines[i].bounds, pageLines[i].text, matchedPage! + 1))
              .toList();
          final annotation = HighlightAnnotation(textBoundsCollection: pdfTextLines)
            ..color = _colorFor(color).withAlpha(90)
            ..subject = 'ai';
          _pdfController.addAnnotation(annotation);
          matched++;
          newHighlights.add(MaterialHighlight(
            id: const Uuid().v4(),
            text: text,
            color: color,
            source: HighlightSource.ai,
            reason: reason,
            pageNumber: matchedPage + 1,
          ));
        } else {
          unmatched++;
          newHighlights.add(MaterialHighlight(
            id: const Uuid().v4(),
            text: text,
            color: color,
            source: HighlightSource.ai,
            reason: reason,
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        _highlights.addAll(newHighlights);
        _dirty = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(unmatched == 0
            ? '$matched Vorschläge markiert.'
            : '$matched Vorschläge markiert, $unmatched im PDF-Text nicht exakt gefunden (unten als Kontext gelistet).'),
      ));
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _suggestError = e.message);
    } catch (e) {
      if (mounted) setState(() => _suggestError = 'Unerwarteter Fehler: $e');
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  /// Erfasst genau das, was gerade sichtbar im PDF-Viewer angezeigt wird
  /// (Screenshot, keine PDF-Rasterung – entspricht also 1:1 dem, was der
  /// Nutzer gerade vor sich hat, inkl. Zoom/Ausschnitt), als PNG. `null` bei
  /// jedem Fehlschlag statt zu werfen – siehe [_askAboutPage].
  Future<Uint8List?> _capturePageImage() async {
    try {
      final boundary = _pdfBoundaryKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Öffnet den Frage-Chat zur AKTUELL sichtbaren Seite (siehe
  /// AiService.answerPageQuestion): erfasst einen Screenshot der Seite,
  /// merkt sich Seitenzahl/Gesamtseiten vom Controller und zeigt dann das
  /// Bottom-Sheet mit Text-Eingabe. Der Screenshot wird EINMALIG beim Öffnen
  /// erfasst und für alle Rückfragen innerhalb desselben Sheets
  /// wiederverwendet, statt bei jeder Frage neu zu erfassen.
  Future<void> _askAboutPage() async {
    if (_capturingPageQuestion) return;
    setState(() => _capturingPageQuestion = true);
    final imageBytes = await _capturePageImage();
    final pageNumber = _pdfController.pageNumber;
    final totalPages = _pdfController.pageCount;
    if (!mounted) return;
    setState(() => _capturingPageQuestion = false);
    if (imageBytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Seite konnte nicht erfasst werden.')));
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PageQuestionSheet(
        material: widget.material,
        pageNumber: pageNumber < 1 ? 1 : pageNumber,
        totalPages: totalPages < 1 ? 1 : totalPages,
        pageImageBytes: imageBytes,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final savedBytes = Uint8List.fromList(await _pdfController.saveDocument());
      final stored = await MaterialFileStore.store(widget.material.id, savedBytes);
      if (!mounted) return;
      await context.read<MaterialRepository>().saveHighlights(
            widget.material.id,
            widget.material.moduleId,
            highlights: _highlights,
            notes: _notesController.text.trim(),
            filePath: stored.$1,
            fileBytesBase64: stored.$2,
          );
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ungespeicherte Änderungen'),
        content: const Text('Markierungen/Notiz wurden noch nicht gespeichert. Trotzdem verlassen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Verlassen')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(widget.material.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Frage zur Seite',
              icon: _capturingPageQuestion
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.forum_outlined),
              onPressed: (_capturingPageQuestion || _bytes == null) ? null : _askAboutPage,
            ),
            IconButton(
              tooltip: 'KI-Vorschläge',
              icon: _suggesting
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome_outlined),
              onPressed: (_suggesting || _bytes == null) ? null : _suggestFromAi,
            ),
            IconButton(
              tooltip: 'Speichern',
              icon: _saving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              onPressed: (_saving || !_dirty) ? null : _save,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_loadError!)))
                : Column(
                    children: [
                      if (_suggestError != null)
                        Container(
                          width: double.infinity,
                          color: c.dangerSoft,
                          padding: const EdgeInsets.all(10),
                          child: Text(_suggestError!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Text('Auswahl markieren:',
                                style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                            const SizedBox(width: 10),
                            Opacity(
                              opacity: _hasSelection ? 1 : 0.45,
                              child: Row(
                                children: [
                                  _ColorButton(
                                      label: 'Frage',
                                      color: c.danger,
                                      onTap: () => _addManualHighlight(HighlightColor.red)),
                                  const SizedBox(width: 6),
                                  _ColorButton(
                                      label: 'Antwort',
                                      color: c.good,
                                      onTap: () => _addManualHighlight(HighlightColor.green)),
                                  const SizedBox(width: 6),
                                  _ColorButton(
                                      label: 'Relevant',
                                      color: c.warn,
                                      onTap: () => _addManualHighlight(HighlightColor.yellow)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RepaintBoundary(
                          key: _pdfBoundaryKey,
                          child: SfPdfViewer.memory(
                            _bytes!,
                            key: _pdfViewerKey,
                            controller: _pdfController,
                            onTextSelectionChanged: (details) {
                              setState(
                                  () => _hasSelection = (details.selectedText ?? '').trim().isNotEmpty);
                            },
                          ),
                        ),
                      ),
                      _BottomPanel(
                        highlights: _highlights,
                        colorFor: _colorFor,
                        onRemove: _removeHighlight,
                        notesController: _notesController,
                        onNotesChanged: () => setState(() => _dirty = true),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// Frage-Chat zu EINER konkreten, gerade betrachteten Seite (siehe
/// AiService.answerPageQuestion) – sieht sowohl den mitgegebenen Screenshot
/// dieser Seite als auch den Volltext des gesamten Materials als Kontext.
/// Rein session-lokal (nicht persistiert): für eine dauerhafte Notiz kann
/// das Ergebnis wie bisher manuell ins Notiz-Feld des Materials übernommen
/// werden.
class _PageQuestionSheet extends StatefulWidget {
  const _PageQuestionSheet({
    required this.material,
    required this.pageNumber,
    required this.totalPages,
    required this.pageImageBytes,
  });

  final MaterialItem material;
  final int pageNumber;
  final int totalPages;
  final Uint8List pageImageBytes;

  @override
  State<_PageQuestionSheet> createState() => _PageQuestionSheetState();
}

class _PageQuestionSheetState extends State<_PageQuestionSheet> {
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
        documentText: widget.material.extractedText,
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

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.highlights,
    required this.colorFor,
    required this.onRemove,
    required this.notesController,
    required this.onNotesChanged,
  });

  final List<MaterialHighlight> highlights;
  final Color Function(HighlightColor) colorFor;
  final ValueChanged<MaterialHighlight> onRemove;
  final TextEditingController notesController;
  final VoidCallback onNotesChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meine Markierungen (${highlights.length})',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (highlights.isEmpty)
                  Text('Noch keine Markierungen.', style: TextStyle(fontSize: 12, color: c.inkMuted))
                else
                  ...highlights.map((h) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(color: colorFor(h.color), shape: BoxShape.circle),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  if (h.source == HighlightSource.ai)
                                    Text(
                                      [
                                        'KI-Vorschlag',
                                        if (h.pageNumber == null) 'im PDF nicht gefunden',
                                        if (h.reason != null && h.reason!.isNotEmpty) h.reason!,
                                      ].join(' · '),
                                      style: TextStyle(fontSize: 11, color: c.inkMuted),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: c.inkMuted,
                              onPressed: () => onRemove(h),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 8),
                Text('Notiz', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Eigene Notiz, die die KI ebenfalls als relevant berücksichtigt…',
                    hintStyle: TextStyle(fontSize: 12, color: c.inkMuted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onChanged: (_) => onNotesChanged(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
