import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/flashcard.dart';
import 'ai_service.dart';
import 'pdf_service.dart';
import 'question_parsing.dart';

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

  QuestionType get type => QuestionParsing.parseType(data['type'] as String?);
  String get front => (data['front'] ?? '').toString();
}

/// Ergebnis eines Durchlaufs: gefundene Fragen (nach Seite sortiert), Seiten,
/// deren Anfrage fehlschlug (zum erneuten Versuch), und wie viele Einträge
/// der KI unbrauchbar waren.
class PdfQuestionScan {
  PdfQuestionScan({required this.questions, required this.failedBatches, required this.dropped, this.errors = const []});

  final List<ScannedQuestion> questions;
  final List<List<int>> failedBatches;
  final int dropped;
  final List<String> errors;
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
  }) : _pdf = pdf ?? PdfService();

  final AiService _ai;
  final PdfService _pdf;

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
  /// Pakete; [isCancelled] beendet nach den laufenden Paketen.
  Future<PdfQuestionScan> scan(
    Uint8List pdfBytes, {
    required int firstPage,
    required int lastPage,
    required bool contentOnly,
    required bool fillMissingSolutions,
    List<List<int>>? onlyBatches,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final todo = onlyBatches ?? batches(firstPage, lastPage, pagesPerRequest);
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
          final sub = _pdf.extractPages(pdfBytes, [for (final p in pages) p - 1]);
          final raw = await _ai.scanPdfPagesForQuestions(
            sub,
            pageNumbers: pages,
            contentOnly: contentOnly,
            fillMissingSolutions: fillMissingSolutions,
          );
          final questions = <ScannedQuestion>[];
          for (final entry in raw) {
            final fixed = QuestionParsing.normalizeGeneratedFlashcard(entry);
            if (fixed == null) {
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
    return PdfQuestionScan(questions: ordered, failedBatches: failed, dropped: dropped, errors: errors);
  }

  /// Die ausgewählten Fragen als neue Karten eines Fachs – in
  /// Dokument-Reihenfolge und sofort für das Daily Quiz vorgesehen
  /// (bewusst importiert, siehe Flashcard.priorityIntroduction).
  static List<Flashcard> toFlashcards(
    Iterable<ScannedQuestion> questions, {
    required String moduleId,
    String? unitId,
    required DateTime now,
  }) {
    final result = <Flashcard>[];
    for (final q in questions) {
      final f = q.data;
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
      ));
    }
    return result;
  }
}
