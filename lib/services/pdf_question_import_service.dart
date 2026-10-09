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
import 'import_reference.dart';
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

  /// Datei, aus der die Frage stammt (beim Import mehrerer PDFs).
  String? sourceFile;

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
    this.revised = 0,
    this.windows = 0,
    this.notes = const [],
  });

  final List<ScannedQuestion> questions;
  final List<List<int>> failedBatches;
  final int dropped;
  final List<String> errors;

  /// Die KI hat die Seiten als Bild gesehen (Abbildungen konnten
  /// übernommen werden) – sonst nur als PDF-Datei.
  final bool usedPageImages;

  /// Bereits übernommene Fragen, die durch die nächste Seite vervollständigt
  /// wurden (fortlaufender Import).
  final int revised;

  /// Wie viele Abschnitte gelesen wurden.
  final int windows;

  /// Hinweise (z.B. Seiten, die die KI beim ersten Lesen ausgelassen hat).
  final List<String> notes;
}

/// Eine PDF für [PdfQuestionImportService.scanMany].
class ImportSource {
  const ImportSource({required this.name, required this.bytes, this.pageTexts, this.firstPage, this.lastPage});

  final String name;
  final Uint8List bytes;

  /// Text je Seite (Index 0 = Seite 1), falls schon gelesen.
  final List<String>? pageTexts;

  /// Seitenbereich; ohne Angabe das ganze Dokument.
  final int? firstPage;
  final int? lastPage;
}

/// "Fragen aus PDF importieren": liest PDFs fortlaufend in überlappenden
/// Abschnitten und übernimmt die dort vorhandenen Fragen und Aufgaben
/// (Altklausur, Übungsblatt, Fragen auf Folien) – statt neue zu erfinden.
///
/// Fortlaufend heißt: Ein Abschnitt besteht aus einer sinnvollen Anzahl neuer
/// Seiten (weniger bei viel Text, siehe [planScanWindows]) und beginnt mit der
/// LETZTEN Seite des vorigen Abschnitts. Dazu bekommt die KI die daraus schon
/// übernommenen Fragen und prüft, ob auf den neuen Seiten etwas steht, das zu
/// ihnen gehört (Fortsetzung der Aufgabe, Musterlösung, Abbildung) – dann wird
/// die Frage überarbeitet, sonst geht es einfach mit den neuen Seiten weiter.
/// So gibt es weder eine Grenze für Umfang noch für die Zahl der Dateien, und
/// eine Aufgabe, die über einen Seitenumbruch geht, wird nicht zerrissen.
/// Abschnitte einer Datei laufen nacheinander (sie bauen aufeinander auf),
/// verschiedene Dateien gleichzeitig ([scanMany]); ein fehlgeschlagener
/// Abschnitt bricht den Rest nicht ab.
class PdfQuestionImportService {
  PdfQuestionImportService({
    required this._ai,
    PdfService? pdf,
    this.pagesPerRequest = defaultPagesPerRequest,
    this.charBudget = defaultCharBudget,
    this.parallelRequests = 2,
    PageRendererFactory? renderer,
  })  : _pdf = pdf ?? PdfService(),
        _openRenderer = renderer ?? PdfPageRenderer.open;

  final AiService _ai;
  final PdfService _pdf;
  final PageRendererFactory _openRenderer;

  /// So viele NEUE Seiten höchstens je Abschnitt (dazu kommt die
  /// Überlappungsseite) – bei viel Text weniger, siehe [charBudget].
  static const int defaultPagesPerRequest = 4;
  final int pagesPerRequest;

  /// So viel Seitentext (Zeichen) höchstens je Abschnitt an neuen Seiten – eine
  /// Altklausur mit dicht beschriebenen Seiten hat oft viele Fragen pro Seite,
  /// die Antwort soll nicht abgeschnitten werden.
  static const int defaultCharBudget = 7000;
  final int charBudget;

  /// So viele PDFs gleichzeitig in [scanMany].
  final int parallelRequests;

  /// Die Seiten [firstPage]..[lastPage] (1-basiert) in Paketen fester Größe
  /// (ohne Überlappung).
  static List<List<int>> batches(int firstPage, int lastPage, int size) {
    final result = <List<int>>[];
    for (var start = firstPage; start <= lastPage; start += size) {
      final end = start + size - 1 < lastPage ? start + size - 1 : lastPage;
      result.add([for (var p = start; p <= end; p++) p]);
    }
    return result;
  }

  /// Die Abschnitte, in denen [firstPage]..[lastPage] gelesen werden.
  List<ScanWindow> planWindows(List<String> pageTexts, {required int firstPage, required int lastPage}) =>
      planScanWindows(
        pageTexts,
        firstPage: firstPage,
        lastPage: lastPage,
        maxNewPages: pagesPerRequest,
        charBudget: charBudget,
      );

  List<String> _pageTextsOf(Uint8List pdfBytes) {
    try {
      return _pdf.extractPageTexts(pdfBytes);
    } catch (_) {
      return const [];
    }
  }

  /// Liest die Seiten [firstPage]..[lastPage] (bzw. genau [onlyBatches], z.B.
  /// für einen erneuten Versuch – ohne Überlappung) fortlaufend ab.
  /// [onProgress] meldet erledigte Abschnitte; [isCancelled] beendet nach dem
  /// laufenden Abschnitt.
  ///
  /// Mit [withPageImages] bekommt die KI jede Seite als Bild (plus deren
  /// Text) – so kann sie Abbildungen per Bereich angeben, die dann
  /// ausgeschnitten an der Frage hängen, und Bildfragen (beschriften,
  /// markieren) 1:1 übernehmen. Lässt sich die PDF auf dem Gerät nicht
  /// rendern, geht die PDF-Datei selbst an die KI (ohne Abbildungen).
  /// [reference] ist das Nachschlagewerk für Lösungen aus anderen Dateien
  /// ([owner] = diese Datei), [referenceText] ein einzelner Begleittext. Mit
  /// [focus] (Wortlaut einer Aufgabe) wird NUR diese eine Aufgabe übernommen –
  /// zum Nachholen einer übersehenen (siehe ImportVerifyService).
  Future<PdfQuestionScan> scan(
    Uint8List pdfBytes, {
    required int firstPage,
    required int lastPage,
    required bool contentOnly,
    required bool fillMissingSolutions,
    bool withPageImages = true,
    String? referenceText,
    ImportReference? reference,
    String? owner,
    List<String>? pageTexts,
    String? focus,
    List<List<int>>? onlyBatches,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final renderer = withPageImages ? await _openRenderer(pdfBytes) : null;
    try {
      final texts = pageTexts ?? _pageTextsOf(pdfBytes);
      final windows = onlyBatches != null
          ? [for (final b in onlyBatches) ScanWindow(pages: b)]
          : planWindows(texts, firstPage: firstPage, lastPage: lastPage);
      final ImportReference? lookup = reference ??
          ((referenceText ?? '').trim().isEmpty
              ? null
              : ImportReference(ImportReference.pagesOfText('Begleitdokument', referenceText!)));
      return await _scan(
        pdfBytes,
        renderer: renderer,
        pageTexts: texts,
        windows: windows,
        contentOnly: contentOnly,
        fillMissingSolutions: fillMissingSolutions,
        reference: lookup,
        owner: owner,
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
    required List<String> pageTexts,
    required List<ScanWindow> windows,
    required bool contentOnly,
    required bool fillMissingSolutions,
    ImportReference? reference,
    String? owner,
    String? focus,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var usedImages = false;
    final found = <ScannedQuestion>[];
    final covered = <int>{};
    final failedWindows = <List<int>>[];
    final errors = <String>[];
    final notes = <String>[];
    var dropped = 0;
    var revised = 0;
    var previousFailed = false;
    onProgress?.call(0, windows.length);

    String textOf(ScanWindow w) => [for (final p in w.shown) if (p - 1 < pageTexts.length) pageTexts[p - 1]].join('\n');

    /// Liest einen Abschnitt und arbeitet das Ergebnis in [found] ein.
    /// Wirft bei einem Fehler der Anfrage.
    Future<ScanWindowReply> readWindow(ScanWindow window, List<ScannedQuestion> previous) async {
      final images = renderer == null ? null : await _renderAll(renderer, window.shown);
      final texts = [for (final p in window.shown) p - 1 < pageTexts.length ? pageTexts[p - 1] : ''];
      final referenceText = reference?.forWindow(textOf(window), excludeOwner: owner) ?? '';
      final numbered = [
        for (final (i, q) in previous.indexed)
          (
            n: i + 1,
            type: (q.data['type'] ?? 'flashcard').toString(),
            front: q.front,
            answer: _answerOf(q),
          ),
      ];
      final ScanWindowReply reply;
      if (images != null) {
        usedImages = true;
        reply = await _ai.scanPdfWindow(
          null,
          pageNumbers: window.shown,
          overlapPage: window.overlap,
          previous: numbered,
          contentOnly: contentOnly,
          fillMissingSolutions: fillMissingSolutions,
          pageImages: [for (final image in images) await drawEdgeRuler(image) ?? image],
          pageTexts: texts,
          referenceText: referenceText,
          focus: focus,
        );
      } else {
        final sub = _pdf.extractPages(pdfBytes, [for (final p in window.shown) p - 1]);
        reply = await _ai.scanPdfWindow(
          sub,
          pageNumbers: window.shown,
          overlapPage: window.overlap,
          previous: numbered,
          contentOnly: contentOnly,
          fillMissingSolutions: fillMissingSolutions,
          referenceText: referenceText,
          focus: focus,
        );
      }
      final imagesByPage = images == null
          ? const <int, Uint8List>{}
          : {for (final (i, p) in window.shown.indexed) p: images[i]};

      // Neue Fragen (Doppelte der Überlappungsseite fallen weg).
      final added = <ScannedQuestion>[];
      for (final entry in reply.questions) {
        final fixed = QuestionParsing.normalizeGeneratedFlashcard(entry);
        if (fixed == null) {
          dropped++;
          continue;
        }
        final page = entry['page'] as int;
        if (imagesByPage[page] case final image?) await attachFigure(fixed, entry, image);
        // Eine Bildfrage ohne Bild ließe sich nicht beantworten.
        final type = QuestionParsing.parseType(fixed['type'] as String?);
        if ((type == QuestionType.diagramLabel || type == QuestionType.markImage) && fixed['imageBase64'] == null) {
          dropped++;
          continue;
        }
        final question = ScannedQuestion(page: page, data: fixed, solutionByAi: entry['solutionFromDocument'] == false);
        if (page == window.overlap && previous.any((q) => _sameQuestion(q.front, question.front))) continue;
        if (added.any((q) => q.page == page && _sameQuestion(q.front, question.front))) continue;
        added.add(question);
      }

      // Überarbeitungen bereits übernommener Fragen.
      for (final entry in reply.revisions.entries) {
        final index = entry.key - 1;
        if (index < 0 || index >= previous.length) continue;
        final old = previous[index];
        final raw = entry.value;
        final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
        // Eine halb ausgefüllte Überarbeitung ist schlechter als das Original.
        if (fixed == null || (fixed['typeDowngraded'] == true && !old.typeDowngraded)) continue;
        if (imagesByPage[raw['page'] as int] case final image?) await attachFigure(fixed, raw, image);
        for (final key in const ['imageBase64', 'imageTargets']) {
          if (fixed[key] == null && old.data[key] != null) fixed[key] = old.data[key];
        }
        final type = QuestionParsing.parseType(fixed['type'] as String?);
        if ((type == QuestionType.diagramLabel || type == QuestionType.markImage) && fixed['imageBase64'] == null) {
          continue;
        }
        final replacement = ScannedQuestion(page: old.page, data: fixed, solutionByAi: raw['solutionFromDocument'] == false)
          ..selected = old.selected;
        final at = found.indexOf(old);
        if (at >= 0) {
          found[at] = replacement;
          revised++;
        }
      }
      found.addAll(added);
      return reply;
    }

    for (var w = 0; w < windows.length; w++) {
      if (isCancelled?.call() ?? false) break;
      var window = windows[w];
      // Ist der vorige Abschnitt fehlgeschlagen, wurde seine letzte Seite noch
      // nicht bearbeitet: dann ist sie hier eine neue Seite.
      if (previousFailed && window.overlap != null) window = window.withoutOverlap;
      final previous = window.overlap == null ? <ScannedQuestion>[] : [for (final q in found) if (q.page == window.overlap) q];
      try {
        final reply = await readWindow(window, previous);
        covered.addAll(window.pages);
        previousFailed = false;
        // Seiten, die die KI nicht gelesen zu haben meldet (und aus denen sie
        // nichts übernommen hat), einzeln nachlesen.
        final seen = reply.pagesSeen;
        if (seen != null && focus == null) {
          for (final p in window.pages) {
            if (seen.contains(p) || found.any((q) => q.page == p)) continue;
            try {
              await readWindow(ScanWindow(pages: [p]), const []);
              notes.add('Seite $p wurde beim ersten Lesen ausgelassen und einzeln nachgelesen.');
            } catch (_) {
              failedWindows.add([p]);
              errors.add('Seite $p: konnte nicht nachgelesen werden.');
            }
          }
        }
      } catch (e) {
        failedWindows.add(window.pages);
        previousFailed = true;
        errors.add('${window.label}: ${e is AiServiceException ? e.message : e}');
      }
      onProgress?.call(w + 1, windows.length);
    }

    // Seiten, die ein späterer Abschnitt als Überlappung ohne Vorgänger doch
    // noch gelesen hat, sind nicht mehr offen.
    final openPages = {for (final pages in failedWindows) ...pages}..removeAll(covered);
    final failed = _groupConsecutive(openPages.toList()..sort());
    return PdfQuestionScan(
      questions: _sortedByPage(found),
      failedBatches: failed,
      dropped: dropped,
      errors: failed.isEmpty ? const [] : errors,
      usedPageImages: usedImages,
      revised: revised,
      windows: windows.length,
      notes: notes,
    );
  }

  /// Fragen mit gleichem Anfang (bis auf Groß-/Kleinschreibung und
  /// Satzzeichen) oder fast gleichem Wortlaut – dieselbe Aufgabe.
  static bool _sameQuestion(String a, String b) {
    String norm(String t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß]+'), ' ').trim();
    final x = norm(a);
    final y = norm(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    final wa = x.split(' ').toSet();
    final wb = y.split(' ').toSet();
    final inter = wa.intersection(wb).length;
    final union = wa.union(wb).length;
    return wa.length >= 4 && wb.length >= 4 && inter / union >= 0.85;
  }

  static List<List<int>> _groupConsecutive(List<int> sorted) {
    final result = <List<int>>[];
    for (final p in sorted) {
      if (result.isNotEmpty && result.last.last == p - 1) {
        result.last.add(p);
      } else {
        result.add([p]);
      }
    }
    return result;
  }

  /// Nach Seite, bei gleicher Seite in der Reihenfolge des Findens (List.sort
  /// ist nicht stabil).
  static List<ScannedQuestion> _sortedByPage(List<ScannedQuestion> questions) {
    final indexed = questions.indexed.toList()
      ..sort((a, b) {
        final byPage = a.$2.page.compareTo(b.$2.page);
        return byPage != 0 ? byPage : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  static String _answerOf(ScannedQuestion q) =>
      toFlashcards([q], moduleId: '', now: DateTime(2000)).single.answerSummary;

  /// Liest mehrere PDFs. Jede Datei wird für sich fortlaufend gelesen
  /// ([scan]); bis zu [parallelRequests] Dateien gleichzeitig. Zu jedem
  /// Abschnitt sucht ein gemeinsames Nachschlagewerk die passenden Seiten der
  /// ANDEREN Dateien (z.B. eine Musterlösung) sowie aus [extraReference] (Text
  /// von Dateien ohne Seiten) heraus – so gibt es keine Obergrenze für die
  /// Zahl der Dateien. [retry] (Dateiname → Seiten) liest nur diese Seiten
  /// erneut. Das Ergebnis steht in der Reihenfolge von [sources]; jede Frage
  /// trägt ihre Datei ([ScannedQuestion.sourceFile]).
  Future<List<PdfQuestionScan>> scanMany(
    List<ImportSource> sources, {
    required bool contentOnly,
    required bool fillMissingSolutions,
    List<ImportReferencePage> extraReference = const [],
    Map<String, List<List<int>>>? retry,
    void Function(int done, int total, String label)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final texts = [for (final s in sources) s.pageTexts ?? _pageTextsOf(s.bytes)];
    final reference = ImportReference([
      for (final (i, s) in sources.indexed)
        for (final (p, text) in texts[i].indexed)
          ImportReferencePage(owner: s.name, label: '${s.name}, Seite ${p + 1}', text: text),
      ...extraReference,
    ]);
    final plans = <List<ScanWindow>>[
      for (final (i, s) in sources.indexed)
        retry != null
            ? [for (final b in retry[s.name] ?? const <List<int>>[]) ScanWindow(pages: b)]
            : planWindows(
                texts[i],
                firstPage: s.firstPage ?? 1,
                lastPage: s.lastPage ?? texts[i].length,
              ),
    ];
    final total = plans.fold<int>(0, (sum, w) => sum + w.length);
    var done = 0;
    onProgress?.call(0, total, '');
    final results = List<PdfQuestionScan?>.filled(sources.length, null);
    var next = 0;

    Future<void> worker() async {
      while (next < sources.length) {
        if (isCancelled?.call() ?? false) return;
        final i = next++;
        final source = sources[i];
        if (plans[i].isEmpty) {
          results[i] = PdfQuestionScan(questions: [], failedBatches: const [], dropped: 0);
          continue;
        }
        var fileDone = 0;
        final scan = await this.scan(
          source.bytes,
          firstPage: source.firstPage ?? 1,
          lastPage: source.lastPage ?? texts[i].length,
          contentOnly: contentOnly,
          fillMissingSolutions: fillMissingSolutions,
          reference: reference,
          owner: source.name,
          pageTexts: texts[i],
          onlyBatches: retry == null ? null : [for (final w in plans[i]) w.pages],
          isCancelled: isCancelled,
          onProgress: (d, t) {
            done += d - fileDone;
            fileDone = d;
            onProgress?.call(done, total, '${source.name} · Abschnitt $d von $t');
          },
        );
        for (final q in scan.questions) {
          q.sourceFile = source.name;
        }
        results[i] = scan;
      }
    }

    await Future.wait([for (var k = 0; k < parallelRequests; k++) worker()]);
    return [for (final r in results) r ?? PdfQuestionScan(questions: [], failedBatches: const [], dropped: 0)];
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
    await attachOptionImages(data, pageImage);
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

  /// Bild-Antworten: schneidet bei Auswahlfragen das Bild jeder Option
  /// ("imageBox" in Seitenkoordinaten) aus dem Seitenbild aus und legt es als
  /// "image" an die Option.
  static Future<void> attachOptionImages(Map<String, dynamic> data, Uint8List pageImage) async {
    final options = data['options'];
    if (options is! List) return;
    final result = <Object?>[];
    var changed = false;
    for (final o in options) {
      if (o is! Map || o['imageBox'] == null) {
        result.add(o);
        continue;
      }
      final option = Map<String, dynamic>.from(o)..remove('imageBox');
      final box = _boxOf(o['imageBox']);
      if (box != null) {
        final rect = _clampUnit(box.inflate(0.01));
        if (rect.width >= 0.02 && rect.height >= 0.02) {
          final crop = await cropImageRelative(pageImage, rect);
          if (crop != null) option['image'] = base64Encode(await downscaleImage(crop, maxSide: 800) ?? crop);
        }
      }
      result.add(option);
      changed = true;
    }
    if (changed) data['options'] = result;
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
        needsCalculator: QuestionParsing.parseCalcFlag(f),
        options: QuestionParsing.parseOptions(f['options']),
        correctText: f['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(f['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(f['dragPairs']),
        htmlContent: f['htmlContent'] as String?,
        imageBase64: q.imageBase64,
        imageTargets: parseImageTargets(f['imageTargets']),
        tableRows: parseTableRows(f['tableRows']),
        taskData: parseTaskData(f['taskData']),
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
