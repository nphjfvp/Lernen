import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../models/page_note.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart' show FsrsService, Grade;
import '../../services/highlight_matcher.dart';
import '../../services/material_file_store.dart';
import '../../services/question_parsing.dart';
import '../../theme/app_colors.dart';
import '../daily/question_answer_view.dart';
import '../widgets/page_concept_sheet.dart';
import '../widgets/page_question_creation_sheet.dart';
import '../widgets/page_qa_panel.dart';
import '../widgets/safe_set_state.dart';

/// Zeigt eine hochgeladene PDF-Folie visuell an und erlaubt es, Textstellen
/// farblich zu markieren – rot: eignet sich als Prüfungsfrage, grün: die
/// Antwort/der Kernfakt dazu, gelb: sonst einfach wichtig/relevant. Sowohl
/// manuell (Text auswählen + Farbe antippen) als auch automatisch per
/// KI-Vorschlag (siehe AiService.suggestHighlights). Die Markierungen +
/// eine kurze Notiz fließen als "besonders relevant"-Kontext in
/// Vorbereiten/Nachbereiten/Chat ein (siehe MaterialItem.highlights/notes).
/// Zusätzlich der volle "Lernmodus": direkt aus einer Seite ein Konzept
/// (siehe [PageConceptSheet]) oder eine Frage (siehe
/// [PageQuestionCreationSheet]) erstellen, plus der periodische
/// Zwischen-Check (siehe [_handlePageChanged]).
class MaterialViewerScreen extends StatefulWidget {
  const MaterialViewerScreen({super.key, required this.material, this.initialPage});

  final MaterialItem material;

  /// Springt beim Öffnen direkt zu dieser Seite – Grundlage für den
  /// Quasi-Link von Konzepten zurück zu ihrer Ursprungsseite (siehe
  /// Concept.linkedMaterialId/linkedPageNumber).
  final int? initialPage;

  @override
  State<MaterialViewerScreen> createState() => _MaterialViewerScreenState();
}

class _MaterialViewerScreenState extends State<MaterialViewerScreen> with SafeSetState<MaterialViewerScreen> {
  final _pdfController = PdfViewerController();
  final _pdfViewerKey = GlobalKey<SfPdfViewerState>();

  /// Ein-/ausgeklappte Leisten – für die laufende App-Sitzung gemerkt, damit
  /// beim nächsten Öffnen einer PDF nicht wieder alles aufgeklappt ist.
  static bool _markToolsOpen = true;
  static bool _bottomPanelOpen = false;

  /// Zoom wie in Word, 10–800 %. 100 % = Seitenbreite. Darunter wird der
  /// Viewer schmaler (Syncfusion zoomt nicht unter die Seitenbreite),
  /// darüber zoomt der Viewer selbst.
  double _zoom = 1.0;
  static const double minZoom = 0.1;
  static const double maxZoom = 8.0;
  static const zoomSteps = [0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0];

  double get _viewerWidthFactor => _zoom < 1 ? _zoom : 1.0;

  void _setZoom(double zoom) {
    final z = zoom.clamp(minZoom, maxZoom).toDouble();
    setState(() => _zoom = z);
    _pdfController.zoomLevel = z > 1 ? z : 1.0;
  }

  void _stepZoom(int direction) {
    final next = direction > 0
        ? zoomSteps.firstWhere((s) => s > _zoom + 0.001, orElse: () => maxZoom)
        : zoomSteps.lastWhere((s) => s < _zoom - 0.001, orElse: () => minZoom);
    _setZoom(next);
  }

  /// Zoomen per Geste/Mausrad im Viewer – die Anzeige folgt. Eigene
  /// Änderungen über [_setZoom] kommen hier ebenfalls an und werden
  /// erkannt (dann passt der Viewer-Zoom bereits).
  void _handleViewerZoom(PdfZoomDetails details) {
    final expected = _zoom > 1 ? _zoom : 1.0;
    if ((details.newZoomLevel - expected).abs() < 0.01 || !mounted) return;
    setState(() => _zoom = details.newZoomLevel.clamp(1.0, maxZoom).toDouble());
  }
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

  /// KI-Frage-Panel: das Gespräch bleibt erhalten, auch wenn das Panel zu und
  /// wieder aufgeht. Auf breiten Bildschirmen dockt es neben dem PDF an (die
  /// Wahl von Seite und offen/zu merkt sich die Sitzung), auf schmalen kommt es
  /// als Bottom-Sheet.
  final _qa = PageQaController();
  static bool _qaPanelOpen = false;
  static bool _qaDockRight = true;
  static const _qaDockMinWidth = 900.0;
  late List<PageNote> _pageNotes;

  /// Seite, ab der die nächsten [AppSettings.checkpointQuizPageInterval]
  /// gelesenen Seiten für den nächsten "Lernmodus"-Zwischen-Check zählen
  /// (siehe [_handlePageChanged]). Null, bevor der Viewer die erste Seite
  /// gemeldet hat.
  int? _checkpointStartPage;
  bool _checkpointBusy = false;

  /// Aktuell sichtbare Seite – Grundlage für "Konzept speichern"/"Frage
  /// erstellen" (siehe [_saveConceptFromPage]/[_createQuestionFromPage]).
  /// Startet bei [MaterialViewerScreen.initialPage] bzw. 1, wird über
  /// [_handlePageChanged] aktuell gehalten.
  late int _currentPage = widget.initialPage ?? 1;
  bool _creatingConcept = false;
  bool _creatingQuestion = false;

  @override
  void initState() {
    super.initState();
    _highlights = List.of(widget.material.highlights);
    _pageNotes = List.of(widget.material.pageNotes);
    _notesController = TextEditingController(text: widget.material.notes);
    _loadBytes();
  }

  @override
  void dispose() {
    _qa.dispose();
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
    final id = const Uuid().v4();
    final annotation = HighlightAnnotation(textBoundsCollection: lines)
      ..color = _colorFor(color).withAlpha(110)
      ..subject = id;
    _pdfController.addAnnotation(annotation);
    setState(() {
      _highlights.add(MaterialHighlight(
        id: id,
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
    // Auch die farbige Annotation entfernen: "Speichern" bettet alle
    // Annotationen ins PDF ein, eine entfernte Markierung bliebe sonst
    // dauerhaft sichtbar. Zugeordnet über die Markierungs-ID im Feld
    // `subject` (übersteht Speichern und Neu-Öffnen). Markierungen aus
    // älteren Versionen tragen sie nicht – dort bleibt die Farbe stehen.
    final annotations =
        _pdfController.getAnnotations().where((a) => a.subject == highlight.id).toList();
    for (final annotation in annotations) {
      _pdfController.removeAnnotation(annotation);
    }
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
          final id = const Uuid().v4();
          final annotation = HighlightAnnotation(textBoundsCollection: pdfTextLines)
            ..color = _colorFor(color).withAlpha(90)
            ..subject = id;
          _pdfController.addAnnotation(annotation);
          matched++;
          newHighlights.add(MaterialHighlight(
            id: id,
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
      // Bei verkleinerter Ansicht höher auflösen, damit die KI die Seite
      // trotzdem lesen kann.
      final image = await boundary.toImage(pixelRatio: (2.0 / _viewerWidthFactor).clamp(2.0, 6.0));
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Seite, Seitenzahl und Bild der AKTUELL sichtbaren Seite für eine Frage an
  /// die KI (siehe AiService.answerPageQuestion) – bei jeder Frage neu, denn das
  /// Panel bleibt beim Blättern offen. `null`, wenn sich die Seite nicht
  /// erfassen ließ.
  Future<PageCapture?> _capturePage() async {
    final image = await _capturePageImage();
    if (image == null) return null;
    final page = _pdfController.pageNumber;
    final total = _pdfController.pageCount;
    return (image: image, page: page < 1 ? 1 : page, total: total < 1 ? 1 : total);
  }

  PageQaPanel _qaPanel({VoidCallback? onClose, VoidCallback? onSwapSide}) {
    final total = _pdfController.pageCount;
    return PageQaPanel(
      controller: _qa,
      documentText: widget.material.extractedText,
      capturePage: _capturePage,
      currentPage: _currentPage,
      totalPages: total < 1 ? 1 : total,
      notes: _pageNotes,
      onSaveNote: _saveNote,
      onDeleteNote: _deleteNote,
      onJumpToPage: (page) => _pdfController.jumpToPage(page),
      onClose: onClose,
      onSwapSide: onSwapSide,
    );
  }

  Future<void> _saveNote(PageNote note) async {
    final repo = context.read<MaterialRepository>();
    setState(() => _pageNotes = [..._pageNotes, note]);
    _qa.touch();
    await repo.savePageNotes(widget.material.id, widget.material.moduleId, _pageNotes);
  }

  Future<void> _deleteNote(PageNote note) async {
    final repo = context.read<MaterialRepository>();
    setState(() => _pageNotes = [for (final n in _pageNotes) if (n.id != note.id) n]);
    _qa.touch();
    await repo.savePageNotes(widget.material.id, widget.material.moduleId, _pageNotes);
  }

  /// "Frage zur Seite": auf breiten Bildschirmen das Panel neben dem PDF
  /// ein-/ausblenden (bleibt dann dauerhaft offen, auch beim Blättern), auf
  /// schmalen ein Bottom-Sheet.
  Future<void> _askAboutPage() async {
    if (MediaQuery.sizeOf(context).width >= _qaDockMinWidth) {
      setState(() => _qaPanelOpen = !_qaPanelOpen);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.8,
          child: ListenableBuilder(
            listenable: _qa,
            builder: (_, _) => _qaPanel(onClose: () => Navigator.of(ctx).pop()),
          ),
        ),
      ),
    );
  }

  /// Reagiert auf jeden Seitenwechsel im "Lernmodus": wurden seit dem
  /// letzten Zwischen-Check [AppSettings.checkpointQuizPageInterval] (oder
  /// mehr, z.B. bei Sprüngen) Seiten gelesen, wird ein kurzer,
  /// überspringbarer Zwischen-Check angeboten (siehe [_offerCheckpointQuiz])
  /// – rein informativ, blockiert das Weiterlesen nicht.
  void _handlePageChanged(int newPage) {
    setState(() => _currentPage = newPage);
    final interval = context.read<SettingsRepository>().settings.checkpointQuizPageInterval;
    final start = _checkpointStartPage ??= newPage;
    if (interval <= 0 || _checkpointBusy) return;
    if (newPage - start >= interval) {
      _checkpointStartPage = newPage;
      _offerCheckpointQuiz(fromPage: start, toPage: newPage);
    }
  }

  void _offerCheckpointQuiz({required int fromPage, required int toPage}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('Kurzer Zwischen-Check zu Seite $fromPage–$toPage?'),
      action: SnackBarAction(
        label: 'Quiz starten',
        onPressed: () => _startCheckpointQuiz(fromPage: fromPage, toPage: toPage),
      ),
    ));
  }

  /// Extrahiert NUR den Text der zuletzt gelesenen Seiten (0-basierte
  /// Indizes bei Syncfusion, daher -1) – Grundlage für den Zwischen-Check,
  /// damit er sich wirklich auf den gerade gelesenen Abschnitt bezieht statt
  /// auf das gesamte Dokument.
  String _textForPageRange(int fromPage, int toPage) {
    final bytes = _bytes;
    if (bytes == null) return '';
    final document = sf_pdf.PdfDocument(inputBytes: bytes);
    try {
      final lines = sf_pdf.PdfTextExtractor(document)
          .extractTextLines(startPageIndex: fromPage - 1, endPageIndex: toPage - 1);
      return lines.map((l) => l.text).join('\n');
    } finally {
      document.dispose();
    }
  }

  Future<void> _startCheckpointQuiz({required int fromPage, required int toPage}) async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Kein OpenRouter-API-Key hinterlegt.')));
      return;
    }
    setState(() => _checkpointBusy = true);
    try {
      final pageText = _textForPageRange(fromPage, toPage);
      if (pageText.trim().isEmpty) return;

      final examContext = MaterialItem.practiceExamTextFrom(
          context.read<MaterialRepository>().forModule(widget.material.moduleId));
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final raw = await ai.generateCheckpointQuiz(pageText, examContext: examContext);
      final cards = _parseCheckpointCards(raw, fromPage: fromPage);
      if (cards.isEmpty || !mounted) return;

      // Vor dem await auslesen: die Fehlantworten sollen auch dann
      // gespeichert werden, wenn der Viewer inzwischen geschlossen wurde.
      final flashcardRepo = context.read<FlashcardRepository>();
      final missed = await Navigator.of(context).push<List<Flashcard>>(
        MaterialPageRoute(builder: (_) => _CheckpointQuizScreen(cards: cards)),
      );
      if (missed != null && missed.isNotEmpty) {
        // Die Fehlantwort tatsächlich als solche verbuchen (Ampel rot, morgen
        // fällig) statt die Karte als unbeantwortet "Neu" abzulegen, wo sie
        // hinter dem Neu-Karten-Budget auf unbestimmte Zeit warten würde.
        final fsrs = FsrsService();
        await flashcardRepo.saveAll(missed.map((c) => fsrs.review(c, Grade.again)).toList());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${missed.length} Frage${missed.length == 1 ? '' : 'n'} fürs Daily Quiz vorgemerkt.'),
        ));
      }
    } on AiServiceException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Zwischen-Check fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _checkpointBusy = false);
    }
  }

  /// Wandelt die von der KI gelieferten rohen Flashcard-Maps (siehe
  /// AiService.generateCheckpointQuiz) in echte, aber noch NICHT
  /// gespeicherte [Flashcard]-Objekte um (siehe QuestionParsing für die
  /// Feld-Normalisierung) – erst falsch beantwortete Karten werden nach dem
  /// Quiz tatsächlich persistiert (siehe [_startCheckpointQuiz]).
  List<Flashcard> _parseCheckpointCards(List<Map<String, dynamic>> raw, {required int fromPage}) {
    final now = DateTime.now();
    final cards = <Flashcard>[];
    for (final entry in raw) {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(entry);
      if (fixed == null) continue;
      final type = QuestionParsing.parseType(fixed['type'] as String?);
      cards.add(Flashcard(
        id: const Uuid().v4(),
        moduleId: widget.material.moduleId,
        front: (fixed['front'] ?? '').toString(),
        back: (fixed['back'] ?? '').toString(),
        createdAt: now,
        due: now,
        type: type,
        unitId: widget.material.unitId,
        // Nur falsch beantwortete Karten werden überhaupt gespeichert – eine
        // gerade beim Lesen aufgedeckte Lücke soll nicht am Einheiten-
        // "behandelt"-Gate hängen bleiben (siehe Flashcard.priorityIntroduction).
        priorityIntroduction: true,
        needsCalculator: QuestionParsing.parseCalcFlag(fixed),
        options: QuestionParsing.parseOptions(fixed['options']),
        correctText: fixed['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(fixed['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(fixed['dragPairs']),
        htmlContent: fixed['htmlContent'] as String?,
        // Anfang des gerade gelesenen Abschnitts – "Im Skript ansehen"
        // führt dorthin zurück.
        sourceMaterialId: widget.material.id,
        sourcePage: fromPage,
        weight: defaultFlashcardWeightFor(widget.material.kind),
      ));
    }
    return cards;
  }

  /// Öffnet [PageConceptSheet] für die aktuell sichtbare Seite: liest deren
  /// Text sowie (rein optional, die KI entscheidet selbst ob nötig) den
  /// Text der Nachbarseiten aus.
  Future<void> _saveConceptFromPage() async {
    if (_bytes == null || _creatingConcept) return;
    setState(() => _creatingConcept = true);
    try {
      final totalPages = _pdfController.pageCount;
      final page = _currentPage;
      final pageText = _textForPageRange(page, page);
      final previousText = page > 1 ? _textForPageRange(page - 1, page - 1) : null;
      final nextText = totalPages > 0 && page < totalPages ? _textForPageRange(page + 1, page + 1) : null;
      if (!mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PageConceptSheet(
          material: widget.material,
          pageNumber: page,
          pageText: pageText,
          previousPageText: previousText,
          nextPageText: nextText,
        ),
      );
      if (saved == true && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Konzept gespeichert.')));
      }
    } finally {
      if (mounted) setState(() => _creatingConcept = false);
    }
  }

  /// Öffnet [PageQuestionCreationSheet] für die aktuell sichtbare Seite:
  /// erfasst zusätzlich einen Screenshot (immer an ein Vision-Modell
  /// gesendet, siehe AiService.generateQuestionsFromPage) und übergibt die
  /// gerade im PDF ausgewählte Textstelle (falls vorhanden – die einfachste
  /// Art zu markieren, worauf sich die Frage beziehen soll, siehe
  /// [_addManualHighlight]) sowie die auf DIESER Seite bereits vorhandenen
  /// Markierungen als Vorbelegung.
  Future<void> _createQuestionFromPage() async {
    if (_bytes == null || _creatingQuestion) return;
    // VOR dem Erfassen des Screenshots/Öffnen des Sheets lesen: der
    // PDF-Viewer verliert seine Textauswahl, sobald der Fokus wechselt.
    final selectedLines = _pdfViewerKey.currentState?.getSelectedTextLines() ?? const [];
    final liveSelectionText = selectedLines.map((l) => l.text).join(' ').trim();
    setState(() => _creatingQuestion = true);
    try {
      final page = _currentPage;
      final imageBytes = await _capturePageImage();
      if (!mounted) return;
      if (imageBytes == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Seite konnte nicht erfasst werden.')));
        return;
      }
      final pageText = _textForPageRange(page, page);
      final highlightsOnPage = _highlights.where((h) => h.pageNumber == page).toList();
      final examContext = MaterialItem.practiceExamTextFrom(
          context.read<MaterialRepository>().forModule(widget.material.moduleId));
      if (!mounted) return;
      final savedCount = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PageQuestionCreationSheet(
          material: widget.material,
          pageNumber: page,
          pageText: pageText,
          pageImageBytes: imageBytes,
          highlightsOnPage: highlightsOnPage,
          initialQuestionText: liveSelectionText.isEmpty ? null : liveSelectionText,
          examContext: examContext,
        ),
      );
      if (savedCount != null && savedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$savedCount Frage${savedCount == 1 ? '' : 'n'} gespeichert.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _creatingQuestion = false);
    }
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
              tooltip: 'Konzept speichern',
              icon: _creatingConcept
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.note_add_outlined),
              onPressed: (_creatingConcept || _bytes == null) ? null : _saveConceptFromPage,
            ),
            IconButton(
              tooltip: 'Frage erstellen',
              icon: _creatingQuestion
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.quiz_outlined),
              onPressed: (_creatingQuestion || _bytes == null) ? null : _createQuestionFromPage,
            ),
            IconButton(
              key: const ValueKey('viewer-ask'),
              tooltip: _qaPanelOpen ? 'KI-Fragen ausblenden' : 'Frage zur Seite',
              icon: Icon(_qaPanelOpen ? Icons.forum : Icons.forum_outlined),
              onPressed: _bytes == null ? null : _askAboutPage,
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
                      _ViewerToolbar(
                        markToolsOpen: _markToolsOpen,
                        onToggleMarkTools: () => setState(() => _markToolsOpen = !_markToolsOpen),
                        hasSelection: _hasSelection,
                        onMark: _addManualHighlight,
                        zoom: _zoom,
                        onZoom: _setZoom,
                        onStepZoom: _stepZoom,
                        panelOpen: _bottomPanelOpen,
                        highlightCount: _highlights.length,
                        onTogglePanel: () => setState(() => _bottomPanelOpen = !_bottomPanelOpen),
                      ),
                      Expanded(
                        child: LayoutBuilder(builder: (context, outer) {
                          final docked = _qaPanelOpen && outer.maxWidth >= _qaDockMinWidth;
                          final panelWidth = (outer.maxWidth * 0.34).clamp(340.0, 480.0);
                          final panel = docked
                              ? SizedBox(
                                  key: const ValueKey('qa-docked'),
                                  width: panelWidth,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: _qaDockRight ? BorderSide(color: c.border) : BorderSide.none,
                                        right: _qaDockRight ? BorderSide.none : BorderSide(color: c.border),
                                      ),
                                    ),
                                    child: _qaPanel(
                                      onClose: () => setState(() => _qaPanelOpen = false),
                                      onSwapSide: () => setState(() => _qaDockRight = !_qaDockRight),
                                    ),
                                  ),
                                )
                              : null;
                          final viewer = LayoutBuilder(
                          builder: (context, constraints) => Center(
                            child: SizedBox(
                              width: constraints.maxWidth * _viewerWidthFactor,
                              child: RepaintBoundary(
                                key: _pdfBoundaryKey,
                                child: SfPdfViewer.memory(
                                  _bytes!,
                                  key: _pdfViewerKey,
                                  controller: _pdfController,
                                  initialPageNumber: widget.initialPage ?? 1,
                                  maxZoomLevel: maxZoom,
                                  onZoomLevelChanged: _handleViewerZoom,
                                  onTextSelectionChanged: (details) {
                                    setState(() =>
                                        _hasSelection = (details.selectedText ?? '').trim().isNotEmpty);
                                  },
                                  onPageChanged: (details) => _handlePageChanged(details.newPageNumber),
                                ),
                              ),
                            ),
                          ),
                        );
                          return Row(
                            children: [
                              if (panel != null && !_qaDockRight) panel,
                              Expanded(child: viewer),
                              if (panel != null && _qaDockRight) panel,
                            ],
                          );
                        }),
                      ),
                      if (_bottomPanelOpen)
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

/// Schmale Werkzeugzeile über der PDF: Markieren-Farben (einklappbar), Zoom
/// 10–800 % und der Schalter für "Meine Markierungen/Notiz" unten.
class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar({
    required this.markToolsOpen,
    required this.onToggleMarkTools,
    required this.hasSelection,
    required this.onMark,
    required this.zoom,
    required this.onZoom,
    required this.onStepZoom,
    required this.panelOpen,
    required this.highlightCount,
    required this.onTogglePanel,
  });

  final bool markToolsOpen;
  final VoidCallback onToggleMarkTools;
  final bool hasSelection;
  final ValueChanged<HighlightColor> onMark;
  final double zoom;
  final ValueChanged<double> onZoom;
  final ValueChanged<int> onStepZoom;
  final bool panelOpen;
  final int highlightCount;
  final VoidCallback onTogglePanel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final percent = '${(zoom * 100).round()} %';
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('toggle-mark-tools'),
              tooltip: markToolsOpen ? 'Markieren ausblenden' : 'Auswahl markieren',
              isSelected: markToolsOpen,
              icon: const Icon(Icons.border_color_outlined, size: 20),
              onPressed: onToggleMarkTools,
            ),
            Expanded(
              child: markToolsOpen
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Opacity(
                        opacity: hasSelection ? 1 : 0.45,
                        child: Row(
                          children: [
                            _ColorButton(label: 'Frage', color: c.danger, onTap: () => onMark(HighlightColor.red)),
                            const SizedBox(width: 6),
                            _ColorButton(label: 'Antwort', color: c.good, onTap: () => onMark(HighlightColor.green)),
                            const SizedBox(width: 6),
                            _ColorButton(
                                label: 'Relevant', color: c.warn, onTap: () => onMark(HighlightColor.yellow)),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(
              tooltip: 'Verkleinern',
              icon: const Icon(Icons.zoom_out, size: 20),
              onPressed: zoom <= _MaterialViewerScreenState.minZoom + 0.001 ? null : () => onStepZoom(-1),
            ),
            PopupMenuButton<double>(
              key: const ValueKey('zoom-menu'),
              tooltip: 'Zoom',
              onSelected: onZoom,
              itemBuilder: (_) => [
                for (final step in _MaterialViewerScreenState.zoomSteps)
                  PopupMenuItem(
                    value: step,
                    child: Text(step == 1.0 ? '100 % (Seitenbreite)' : '${(step * 100).round()} %'),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(percent, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
            IconButton(
              tooltip: 'Vergrößern',
              icon: const Icon(Icons.zoom_in, size: 20),
              onPressed: zoom >= _MaterialViewerScreenState.maxZoom - 0.001 ? null : () => onStepZoom(1),
            ),
            const SizedBox(width: 4),
            if (MediaQuery.sizeOf(context).width > 600)
              TextButton.icon(
                key: const ValueKey('toggle-bottom-panel'),
                onPressed: onTogglePanel,
                icon: Icon(panelOpen ? Icons.expand_more : Icons.expand_less, size: 18),
                label: Text('Markierungen & Notiz ($highlightCount)', style: const TextStyle(fontSize: 12.5)),
              )
            else
              IconButton(
                key: const ValueKey('toggle-bottom-panel'),
                tooltip: panelOpen ? 'Markierungen & Notiz ausblenden' : 'Markierungen & Notiz ($highlightCount)',
                isSelected: panelOpen,
                icon: const Icon(Icons.sticky_note_2_outlined, size: 20),
                onPressed: onTogglePanel,
              ),
          ],
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

/// Zwischen-Check im "Lernmodus" (siehe [_MaterialViewerScreenState.
/// _startCheckpointQuiz]): 2-3 kurze Fragen zum gerade gelesenen Abschnitt,
/// nacheinander über [QuestionAnswerView] (dieselbe UI wie Daily
/// Quiz/Üben). Bewusst OHNE FSRS-Auswirkung auf diese frischen Karten
/// (reps=0 wäre ohnehin bedeutungslos) – stattdessen werden nur die FALSCH
/// beantworteten Karten zurückgegeben (siehe [onFinish]/Aufrufer), damit sie
/// dort erst gespeichert (und so Teil des Daily Quiz) werden: "die KI merkt
/// sich, wo es Schwächen gibt", ohne dass richtig beantwortete Fragen
/// unnötig im Datenbestand landen. Jederzeit über "Später" abbrechbar –
/// kein Zwang, den Check zu Ende zu führen.
class _CheckpointQuizScreen extends StatefulWidget {
  const _CheckpointQuizScreen({required this.cards});

  final List<Flashcard> cards;

  @override
  State<_CheckpointQuizScreen> createState() => _CheckpointQuizScreenState();
}

class _CheckpointQuizScreenState extends State<_CheckpointQuizScreen> {
  int _index = 0;
  final List<Flashcard> _missed = [];

  void _handleComplete(Flashcard card, {Grade? selfGrade, bool? isCorrect}) {
    final wasMissed = selfGrade == Grade.again || isCorrect == false;
    if (wasMissed) _missed.add(card);
    if (_index + 1 >= widget.cards.length) {
      Navigator.of(context).pop(_missed);
    } else {
      setState(() => _index += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.cards[_index];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text('Zwischen-Check ${_index + 1}/${widget.cards.length}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_missed),
            child: const Text('Später'),
          ),
        ],
      ),
      body: SafeArea(
        child: QuestionAnswerView(
          key: ValueKey(card.id),
          card: card,
          isNew: true,
          onComplete: ({selfGrade, isCorrect}) =>
              _handleComplete(card, selfGrade: selfGrade, isCorrect: isCorrect),
        ),
      ),
    );
  }
}
