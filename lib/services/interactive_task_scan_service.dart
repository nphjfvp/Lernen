import 'dart:typed_data';

import '../models/interactive_task.dart';
import 'ai_service.dart';
import 'pdf_page_renderer.dart';
import 'pdf_question_import_service.dart';
import 'pdf_service.dart';

/// Eine im Dokument gefundene (Teil-)Aufgabe mit Herkunft.
class ScannedTaskDraft {
  const ScannedTaskDraft({required this.draft, required this.page, required this.sourceName, this.pageImage, this.materialId});

  final InteractiveTaskDraft draft;

  /// Seite im Dokument (1-basiert).
  final int page;
  final String sourceName;

  /// Die Seite als Bild (Foto der Aufgabe, z.B. für Skizzen oder den
  /// Erzeugnisbaum) – null, wenn sich die PDF nicht rendern ließ.
  final Uint8List? pageImage;

  /// Material im Fach, aus dem die Aufgabe stammt.
  final String? materialId;
}

/// Ergebnis eines Dokuments.
class InteractiveTaskScan {
  const InteractiveTaskScan({required this.drafts, this.errors = const [], this.windows = 0});

  final List<ScannedTaskDraft> drafts;

  /// Abschnitte, die nicht gelesen werden konnten (verständlich formuliert).
  final List<String> errors;
  final int windows;
}

/// "Interaktive Aufgaben aus einem Dokument": liest eine PDF fortlaufend in
/// kleinen Abschnitten (ein paar neue Seiten plus die letzte Seite davor als
/// Kontext, damit eine Aufgabe über den Seitenumbruch nicht zerrissen wird)
/// und lässt die KI daraus interaktive Aufgaben bauen (AiService.
/// buildInteractiveTasks) – auf Wunsch nur bestimmte, z.B. "alle
/// Mathe-Aufgaben als Rechenweg". Ein fehlgeschlagener Abschnitt bricht den
/// Rest nicht ab.
class InteractiveTaskScanService {
  InteractiveTaskScanService({
    required this._ai,
    PdfService? pdf,
    PageRendererFactory? renderer,
    this.pagesPerRequest = defaultPagesPerRequest,
  })  : _pdf = pdf ?? PdfService(),
        _openRenderer = renderer ?? PdfPageRenderer.open;

  final AiService _ai;
  final PdfService _pdf;
  final PageRendererFactory _openRenderer;

  /// Neue Seiten je Anfrage – interaktive Aufgaben sind aufwendig (Rechenweg
  /// mit Schritten, Feldern, Tipps), mehr würde die Antwort abschneiden.
  static const defaultPagesPerRequest = 2;
  final int pagesPerRequest;

  /// Die Abschnitte für [firstPage]..[lastPage]: je [pagesPerRequest] neue
  /// Seiten, ab dem zweiten mit der Seite davor als Kontext.
  static List<({List<int> pages, int? context})> windowsFor(int firstPage, int lastPage, int size) => [
        for (final batch in PdfQuestionImportService.batches(firstPage, lastPage, size))
          (pages: batch, context: batch.first > firstPage ? batch.first - 1 : null),
      ];

  Future<InteractiveTaskScan> scan(
    ImportSource source, {
    String instruction = '',
    InteractiveKind? kind,
    String? materialId,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var texts = source.pageTexts;
    if (texts == null) {
      try {
        texts = _pdf.extractPageTexts(source.bytes);
      } catch (_) {
        texts = const [];
      }
    }
    final pageCount = texts.length;
    if (pageCount == 0) {
      return InteractiveTaskScan(drafts: const [], errors: ['„${source.name}“ hat keine lesbaren Seiten.']);
    }
    final first = (source.firstPage ?? 1).clamp(1, pageCount);
    final last = (source.lastPage ?? pageCount).clamp(first, pageCount);
    final windows = windowsFor(first, last, pagesPerRequest);
    final renderer = await _openRenderer(source.bytes);
    final drafts = <ScannedTaskDraft>[];
    final errors = <String>[];
    final images = <int, Uint8List?>{};
    Future<Uint8List?> imageOf(int page) async {
      if (renderer == null) return null;
      if (images.containsKey(page)) return images[page];
      final png = await renderer.renderPng(page);
      images[page] = png;
      return png;
    }

    try {
      onProgress?.call(0, windows.length);
      for (final (i, w) in windows.indexed) {
        if (isCancelled?.call() ?? false) break;
        final shown = [?w.context, ...w.pages];
        final pageImages = [for (final p in shown) await imageOf(p)];
        final usable = pageImages.every((img) => img != null);
        final text = [
          for (final p in shown)
            '--- Seite $p${p == w.context ? ' (nur Kontext)' : ''} ---\n${p - 1 < texts.length ? texts[p - 1] : ''}',
        ].join('\n\n');
        try {
          final found = await _ai.buildInteractiveTasks(
            text: text,
            images: usable ? [for (final img in pageImages) img!] : const [],
            kind: kind,
            instruction: instruction,
            pages: w.pages,
            contextPage: w.context,
            allowEmpty: true,
          );
          for (final d in found) {
            // Ohne Seitenangabe: die erste neue Seite des Abschnitts.
            final page = d.page != null && w.pages.contains(d.page) ? d.page! : w.pages.first;
            // Leere Einträge ohne Aufgabe und ohne Begründung sind kein Fund.
            if (d.front.trim().isEmpty && d.kind == null && d.reason.trim().isEmpty) continue;
            drafts.add(ScannedTaskDraft(
              draft: d.withPage(page),
              page: page,
              sourceName: source.name,
              pageImage: await imageOf(page),
              materialId: materialId,
            ));
          }
        } on AiServiceException catch (e) {
          errors.add('${_pagesLabel(w.pages)}: ${e.message}');
        } catch (e) {
          errors.add('${_pagesLabel(w.pages)}: $e');
        }
        onProgress?.call(i + 1, windows.length);
      }
    } finally {
      await renderer?.close();
    }
    return InteractiveTaskScan(drafts: drafts, errors: errors, windows: windows.length);
  }

  static String _pagesLabel(List<int> pages) =>
      pages.length == 1 ? 'Seite ${pages.first}' : 'Seiten ${pages.first}–${pages.last}';
}
