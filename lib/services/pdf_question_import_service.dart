import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:uuid/uuid.dart';

import '../models/flashcard.dart';
import '../models/material_item.dart';
import 'ai_service.dart';
import 'image_crop.dart';
import 'image_edit.dart';
import 'pdf_page_renderer.dart';
import 'pdf_service.dart';
import 'question_parsing.dart';

/// Öffnet einen Seiten-Renderer für eine PDF (siehe [PdfPageRenderer.open]).
typedef PageRendererFactory = Future<PageImageRenderer?> Function(Uint8List pdfBytes);

/// Eine auf einer PDF-Seite gefundene Frage (siehe [PdfQuestionImportService]).
class ScannedQuestion {
  ScannedQuestion({required this.page, required this.data, required this.solutionByAi});

  /// Seite im Dokument (1-basiert).
  final int page;

  /// Normalisierte Rohkarte (siehe QuestionParsing.normalizeGeneratedFlashcard).
  final Map<String, dynamic> data;

  /// Die Lösung stand nicht im Dokument, die KI hat sie ergänzt.
  final bool solutionByAi;

  /// In der Vorschau zum Import ausgewählt.
  bool selected = true;

  /// Gehört diese Frage zu einer im Dokument gefundenen ([variantOf]), hat die
  /// KI sie als weitere Schwierigkeitsstufe DERSELBEN Sache ergänzt (siehe
  /// ImportStageService) – sie steht nicht im Dokument.
  ScannedQuestion? variantOf;
  bool get isStageVariant => variantOf != null;

  /// Erst nach der Prüfung durch die zweite KI nachgeholt (siehe
  /// ImportVerifyService).
  bool addedByCheck = false;

  /// Stufe der Frage (0 = leicht … 2 = schwer), falls die KI sie vergeben hat.
  int? get stageLevel => QuestionParsing.parseStageLevel(data['level']);

  QuestionType get type => QuestionParsing.parseType(data['type'] as String?);
  String get front => (data['front'] ?? '').toString();

  /// Die KI wollte einen präziseren Typ (single_choice/free_text/html/…),
  /// aber ihre Antwort war unvollständig – normalizeGeneratedFlashcard hat
  /// deshalb auf eine einfache Karteikarte zurückgestuft (siehe dort). Die
  /// Vorschau zeigt das an statt es stumm zu verschlucken.
  bool get typeDowngraded => data['typeDowngraded'] == true;
  QuestionType? get requestedType =>
      data['requestedType'] == null ? null : QuestionParsing.parseType(data['requestedType'] as String?);

  /// Aus der Seite ausgeschnittene Abbildung (PNG, Base64), falls die Frage
  /// eine braucht.
  String? get imageBase64 => data['imageBase64'] as String?;

  Uint8List? _imageBytes;
  Uint8List? get imageBytes {
    final encoded = imageBase64;
    return encoded == null ? null : (_imageBytes ??= base64Decode(encoded));
  }

  /// Bild weglassen (z.B. wenn die Frage auch ohne verständlich ist) – bei
  /// Bildfragen nicht möglich, die brauchen es.
  bool get canRemoveImage =>
      imageBase64 != null && type != QuestionType.diagramLabel && type != QuestionType.markImage;

  void removeImage() {
    if (!canRemoveImage) return;
    data.remove('imageBase64');
    _imageBytes = null;
  }
}

/// Ergebnis eines Durchlaufs: gefundene Fragen (nach Seite sortiert), Seiten,
/// deren Anfrage fehlschlug (zum erneuten Versuch), und wie viele Einträge
/// der KI unbrauchbar waren.
class PdfQuestionScan {
  PdfQuestionScan({
    required this.questions,
    required this.failedBatches,
    required this.dropped,
    this.errors = const [],
    this.usedPageImages = false,
  });

  final List<ScannedQuestion> questions;
  final List<List<int>> failedBatches;
  final int dropped;
  final List<String> errors;

  /// Die KI hat die Seiten als Bild gesehen (Abbildungen konnten
  /// übernommen werden) – sonst nur als PDF-Datei.
  final bool usedPageImages;
}

/// "Fragen aus PDF importieren": schickt die Seiten einer PDF paketweise an
/// das Vision-Modell, das auf jeder Seite nach den dort vorhandenen Fragen
/// und Aufgaben sucht (Altklausur, Übungsblatt, Fragen auf Folien) – statt
/// neue zu erfinden. Mehrere Pakete laufen gleichzeitig; ein fehlgeschlagenes
/// Paket bricht den Rest nicht ab.
class PdfQuestionImportService {
  PdfQuestionImportService({
    required this._ai,
    PdfService? pdf,
    this.pagesPerRequest = defaultPagesPerRequest,
    this.parallelRequests = 3,
    PageRendererFactory? renderer,
  })  : _pdf = pdf ?? PdfService(),
        _openRenderer = renderer ?? PdfPageRenderer.open;

  final AiService _ai;
  final PdfService _pdf;
  final PageRendererFactory _openRenderer;

  /// Wenige Seiten je Anfrage – eine Altklausur hat oft viele Fragen pro
  /// Seite, die Antwort soll nicht abgeschnitten werden.
  static const int defaultPagesPerRequest = 3;
  final int pagesPerRequest;
  final int parallelRequests;

  /// Die Seiten [firstPage]..[lastPage] (1-basiert) in Paketen.
  static List<List<int>> batches(int firstPage, int lastPage, int size) {
    final result = <List<int>>[];
    for (var start = firstPage; start <= lastPage; start += size) {
      final end = start + size - 1 < lastPage ? start + size - 1 : lastPage;
      result.add([for (var p = start; p <= end; p++) p]);
    }
    return result;
  }

  /// Sucht die Seiten [firstPage]..[lastPage] (bzw. genau [onlyBatches],
  /// z.B. für einen erneuten Versuch) ab. [onProgress] meldet erledigte
  /// Pakete; [isCancelled] beendet nach den laufenden Paketen. Mit [focus]
  /// (Wortlaut einer Aufgabe) wird NUR diese eine Aufgabe übernommen – zum
  /// Nachholen einer übersehenen (siehe ImportVerifyService).
  ///
  /// Mit [withPageImages] bekommt die KI jede Seite als Bild (plus deren
  /// Text) – so kann sie Abbildungen per Bereich angeben, die dann
  /// ausgeschnitten an der Frage hängen, und Bildfragen (beschriften,
  /// markieren) 1:1 übernehmen. Lässt sich die PDF auf dem Gerät nicht
  /// rendern, geht die PDF-Datei selbst an die KI (ohne Abbildungen).
  Future<PdfQuestionScan> scan(
    Uint8List pdfBytes, {
    required int firstPage,
    required int lastPage,
    required bool contentOnly,
    required bool fillMissingSolutions,
    bool withPageImages = true,
    String? referenceText,
    String? focus,
    List<List<int>>? onlyBatches,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final renderer = withPageImages ? await _openRenderer(pdfBytes) : null;
    try {
      return await _scan(
        pdfBytes,
        renderer: renderer,
        todo: onlyBatches ?? batches(firstPage, lastPage, pagesPerRequest),
        contentOnly: contentOnly,
        fillMissingSolutions: fillMissingSolutions,
        referenceText: referenceText,
        focus: focus,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      await renderer?.close();
    }
  }

  Future<PdfQuestionScan> _scan(
    Uint8List pdfBytes, {
    required PageImageRenderer? renderer,
    required List<List<int>> todo,
    required bool contentOnly,
    required bool fillMissingSolutions,
    String? referenceText,
    String? focus,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    List<String>? pageTexts;
    if (renderer != null) {
      try {
        pageTexts = _pdf.extractPageTexts(pdfBytes);
      } catch (_) {}
    }
    var usedImages = false;
    final found = <int, List<ScannedQuestion>>{};
    final failed = <List<int>>[];
    final errors = <String>[];
    var dropped = 0;
    var next = 0;
    var done = 0;
    onProgress?.call(0, todo.length);

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        if (next >= todo.length) return;
        final index = next++;
        final pages = todo[index];
        try {
          final images = renderer == null ? null : await _renderAll(renderer, pages);
          final List<Map<String, dynamic>> raw;
          if (images != null) {
            usedImages = true;
            raw = await _ai.scanPdfPagesForQuestions(
              null,
              pageNumbers: pages,
              contentOnly: contentOnly,
              fillMissingSolutions: fillMissingSolutions,
              pageImages: [for (final image in images) await drawEdgeRuler(image) ?? image],
              pageTexts: [for (final p in pages) p - 1 < (pageTexts?.length ?? 0) ? pageTexts![p - 1] : ''],
              referenceText: referenceText,
              focus: focus,
            );
          } else {
            final sub = _pdf.extractPages(pdfBytes, [for (final p in pages) p - 1]);
            raw = await _ai.scanPdfPagesForQuestions(
              sub,
              pageNumbers: pages,
              contentOnly: contentOnly,
              fillMissingSolutions: fillMissingSolutions,
              referenceText: referenceText,
              focus: focus,
            );
          }
          final questions = <ScannedQuestion>[];
          for (final entry in raw) {
            final fixed = QuestionParsing.normalizeGeneratedFlashcard(entry);
            if (fixed == null) {
              dropped++;
              continue;
            }
            if (images != null) {
              await attachFigure(fixed, entry, images[pages.indexOf(entry['page'] as int)]);
            }
            // Eine Bildfrage ohne Bild ließe sich nicht beantworten.
            final type = QuestionParsing.parseType(fixed['type'] as String?);
            if ((type == QuestionType.diagramLabel || type == QuestionType.markImage) &&
                fixed['imageBase64'] == null) {
              dropped++;
              continue;
            }
            questions.add(ScannedQuestion(
              page: entry['page'] as int,
              data: fixed,
              solutionByAi: entry['solutionFromDocument'] == false,
            ));
          }
          found[index] = questions;
        } catch (e) {
          failed.add(pages);
          errors.add('Seite ${pages.first}${pages.length > 1 ? '–${pages.last}' : ''}: '
              '${e is AiServiceException ? e.message : e}');
        }
        done++;
        onProgress?.call(done, todo.length);
      }
    }

    await Future.wait([for (var i = 0; i < parallelRequests; i++) worker()]);
    // Reihenfolge wie im Dokument, auch wenn die Pakete durcheinander fertig
    // wurden.
    final ordered = [
      for (var i = 0; i < todo.length; i++) ...?found[i],
    ]..sort((a, b) => a.page.compareTo(b.page));
    failed.sort((a, b) => a.first.compareTo(b.first));
    return PdfQuestionScan(
      questions: ordered,
      failedBatches: failed,
      dropped: dropped,
      errors: errors,
      usedPageImages: usedImages,
    );
  }

  /// Alle Seiten eines Pakets als Bild – oder `null`, wenn eine fehlt (dann
  /// geht das Paket als PDF an die KI).
  static Future<List<Uint8List>?> _renderAll(PageImageRenderer renderer, List<int> pages) async {
    final images = <Uint8List>[];
    for (final page in pages) {
      final png = await renderer.renderPng(page);
      if (png == null) return null;
      images.add(png);
    }
    return images;
  }

  /// Ein Bereich `[links, oben, rechts, unten]` (oder als Map) relativ zur
  /// Seite; `null` ohne Fläche.
  static Rect? _boxOf(Object? value) {
    final ImageTarget t;
    if (value is List && value.length == 4 && value.every((v) => v is num)) {
      t = ImageTarget.fromMap({'box': value});
    } else if (value is Map) {
      t = ImageTarget.fromMap(Map<String, dynamic>.from(value));
    } else {
      return null;
    }
    if (t.w <= 0 || t.h <= 0) return null;
    return Rect.fromLTRB(t.x - t.w / 2, t.y - t.h / 2, t.x + t.w / 2, t.y + t.h / 2);
  }

  static Rect _clampUnit(Rect r) => Rect.fromLTRB(
        r.left.clamp(0.0, 1.0),
        r.top.clamp(0.0, 1.0),
        r.right.clamp(0.0, 1.0),
        r.bottom.clamp(0.0, 1.0),
      );

  /// Schneidet die Abbildung einer Frage aus dem Seitenbild aus und hängt
  /// sie an [data] ("imageBase64"): den Bereich "imageBox" der KI (etwas
  /// größer, damit nichts abgeschnitten ist), bei Bildfragen mindestens so
  /// groß, dass alle Stellen darin liegen, ohne Angabe die ganze Seite.
  /// Stellen und Abdeckungen kommen in Seitenkoordinaten und werden auf den
  /// Ausschnitt umgerechnet; Abdeckungen werden fest eingezeichnet.
  static Future<void> attachFigure(Map<String, dynamic> data, Map<String, dynamic> entry, Uint8List pageImage) async {
    final type = QuestionParsing.parseType(data['type'] as String?);
    final isImageType = type == QuestionType.diagramLabel || type == QuestionType.markImage;
    final box = _boxOf(entry['imageBox'] ?? entry['figureBox'] ?? entry['imageRegion']);
    if (box == null && !isImageType && entry['needsImage'] != true) return;

    final targets = isImageType ? (QuestionParsing.imageTargetsIn(data) ?? const <ImageTarget>[]) : const <ImageTarget>[];
    var rect = box ?? const Rect.fromLTRB(0, 0, 1, 1);
    for (final t in targets) {
      rect = rect.expandToInclude(Rect.fromLTRB(t.x - t.w / 2, t.y - t.h / 2, t.x + t.w / 2, t.y + t.h / 2));
    }
    rect = _clampUnit(rect.inflate(0.02));
    if (rect.width < 0.03 || rect.height < 0.03) return;

    final crop = await cropImageRelative(pageImage, rect);
    if (crop == null) return;
    ImageTarget toCrop(ImageTarget t) => t.copyWith(
          x: (t.x - rect.left) / rect.width,
          y: (t.y - rect.top) / rect.height,
          w: t.w / rect.width,
          h: t.h / rect.height,
        );

    final covers = [
      for (final c in QuestionParsing.imageCoversIn(entry))
        () {
          final r = toCrop(c);
          final padX = math.max(0.006, r.w * 0.08);
          final padY = math.max(0.006, r.h * 0.12);
          return _clampUnit(Rect.fromLTRB(
            r.x - r.w / 2 - padX,
            r.y - r.h / 2 - padY,
            r.x + r.w / 2 + padX,
            r.y + r.h / 2 + padY,
          ));
        }(),
    ].where((r) => r.width > 0 && r.height > 0).toList();
    var image = crop;
    if (covers.isNotEmpty) image = await applyImageEdits(crop, [for (final r in covers) CoverEdit(r)]) ?? crop;
    image = await downscaleImage(image) ?? image;
    data['imageBase64'] = base64Encode(image);
    if (targets.isNotEmpty) {
      data['imageTargets'] = [
        for (final t in targets.map(toCrop))
          if (t.x >= 0 && t.x <= 1 && t.y >= 0 && t.y <= 1) t.toMap(),
      ];
    }
  }

  /// Die ausgewählten Fragen als neue Karten eines Fachs – in
  /// Dokument-Reihenfolge und sofort für das Daily Quiz vorgesehen
  /// (bewusst importiert, siehe Flashcard.priorityIntroduction).
  /// [sourceKind] bestimmt das Standard-Gewicht (siehe
  /// defaultFlashcardWeightFor): eine neu hochgeladene PDF landet als Übung,
  /// Fragen von Folien eines schon vorhandenen Skripts zählen wie Folien.
  static List<Flashcard> toFlashcards(
    Iterable<ScannedQuestion> questions, {
    required String moduleId,
    String? unitId,
    String? sourceMaterialId,
    MaterialKind sourceKind = MaterialKind.exercise,
    required DateTime now,
  }) {
    final result = <Flashcard>[];
    for (final q in questions) {
      final f = q.data;
      final stageGroup = QuestionParsing.parseStageGroup(f['group']);
      result.add(Flashcard(
        id: const Uuid().v4(),
        moduleId: moduleId,
        front: q.front,
        back: (f['back'] ?? '').toString(),
        // Aufsteigend, damit die Reihenfolge der PDF beim Einführen bleibt.
        createdAt: now.add(Duration(milliseconds: result.length)),
        due: now,
        type: q.type,
        unitId: unitId,
        priorityIntroduction: true,
        options: QuestionParsing.parseOptions(f['options']),
        correctText: f['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(f['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(f['dragPairs']),
        htmlContent: f['htmlContent'] as String?,
        imageBase64: q.imageBase64,
        imageTargets: parseImageTargets(f['imageTargets']),
        tableRows: parseTableRows(f['tableRows']),
        // Leicht/Mittel/Schwer derselben Sache (siehe StageGate) – je Import
        // eindeutig, damit gleich benannte Ordner aus einem späteren Import
        // nicht mit diesen verschmelzen.
        stageLevel: stageGroup == null ? null : q.stageLevel,
        stageGroup: stageGroup == null ? null : '$stageGroup#${now.millisecondsSinceEpoch}',
        sourceMaterialId: sourceMaterialId,
        sourcePage: sourceMaterialId == null ? null : q.page,
        weight: defaultFlashcardWeightFor(sourceKind),
      ));
    }
    return result;
  }
}
