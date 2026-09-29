import 'ai_service.dart';

/// Eine übernommene Frage, wie die Prüfung sie sieht. [ref] ist der Bezug des
/// Aufrufers (z.B. die Position in seiner Liste) – die Prüfung gibt ihn in
/// den Befunden zurück.
class ImportedItem {
  const ImportedItem({required this.ref, required this.page, required this.front, this.answer = ''});

  final int ref;

  /// Seite im Dokument (1-basiert).
  final int page;
  final String front;
  final String answer;
}

enum ImportFindingKind {
  /// Steht im Dokument, aber keine übernommene Frage deckt sie ab.
  missing,

  /// Übernommen, steht aber nicht im Dokument (erfunden oder aus anderem
  /// Zusammenhang).
  notInDocument,

  /// Dieselbe Aufgabe wurde zweimal übernommen.
  duplicate,

  /// Die Aufgabe gibt es, die Frage ändert sie aber inhaltlich.
  altered;

  static ImportFindingKind fromSurplusKind(String kind) => switch (kind) {
        'duplicate' => duplicate,
        'altered' => altered,
        _ => notInDocument,
      };
}

/// Eine Abweichung, die die zweite KI gefunden hat – samt Begründung. Der
/// Nutzer entscheidet, was daraus wird.
class ImportFinding {
  const ImportFinding({
    required this.kind,
    required this.page,
    required this.text,
    required this.reason,
    this.fileName,
    this.ref,
  });

  final ImportFindingKind kind;
  final String? fileName;

  /// Seite im Dokument (1-basiert).
  final int page;

  /// [ImportFindingKind.missing]: die Aufgabe, wie sie im Dokument steht;
  /// sonst: die übernommene Frage.
  final String text;

  /// Begründung der zweiten KI.
  final String reason;

  /// Bezug des übernommenen Eintrags ([ImportedItem.ref]); bei `missing` null.
  final int? ref;

  bool get isMissing => kind == ImportFindingKind.missing;
}

/// Ergebnis der Prüfung eines Imports durch die zweite KI.
class ImportCheckReport {
  const ImportCheckReport({
    required this.documentCount,
    required this.importedCount,
    required this.findings,
    this.uncheckedPages = const [],
    this.errors = const [],
    this.notes = const [],
  });

  /// Wie viele Fragen die zweite KI im Dokument gezählt hat; null, wenn keine
  /// Zählung gelungen ist.
  final int? documentCount;

  /// Wie viele übernommene Fragen geprüft wurden.
  final int importedCount;
  final List<ImportFinding> findings;

  /// Seiten ohne lesbaren Text (z.B. Scans) – dort konnte nichts geprüft
  /// werden.
  final List<int> uncheckedPages;

  /// Pakete, deren Anfrage fehlschlug.
  final List<String> errors;

  /// Unsicherheiten der zweiten KI.
  final List<String> notes;

  /// Fasst die Berichte mehrerer Dateien zusammen. Ohne lesbaren Text
  /// übersprungene Seiten stehen dann je Datei in den Hinweisen (die
  /// Seitenzahlen allein wären nicht mehr zuzuordnen).
  static ImportCheckReport merge(List<({String fileName, ImportCheckReport report})> parts) {
    if (parts.length == 1) return parts.single.report;
    int? count;
    for (final p in parts) {
      if (p.report.documentCount != null) count = (count ?? 0) + p.report.documentCount!;
    }
    return ImportCheckReport(
      documentCount: count,
      importedCount: parts.fold(0, (sum, p) => sum + p.report.importedCount),
      findings: [for (final p in parts) ...p.report.findings],
      errors: [for (final p in parts) ...p.report.errors],
      notes: [
        for (final p in parts) ...p.report.notes,
        for (final p in parts)
          if (p.report.uncheckedPages.isNotEmpty)
            '${p.fileName}: ohne lesbaren Text, nicht geprüft: Seite ${p.report.uncheckedPages.join(', ')}.',
      ],
    );
  }

  int get missingCount => findings.where((f) => f.isMissing).length;
  int get surplusCount => findings.length - missingCount;

  /// Beide KIs sehen dasselbe und alles konnte geprüft werden.
  bool get agrees => findings.isEmpty && errors.isEmpty;
}

/// Zweite Meinung zu einem Import: eine (bewusst andere) KI liest den Text
/// der PDF-Seiten selbst, zählt die dort stehenden Fragen und gleicht sie mit
/// den übernommenen ab – fehlt etwas oder ist etwas zu viel, begründet sie es
/// (siehe [ImportFinding]); übernommen wird nichts von allein.
class ImportVerifyService {
  ImportVerifyService({required this.ai, this.pagesPerRequest = 4, this.parallelRequests = 2});

  final AiService ai;

  /// Seiten je Anfrage – die Prüfung liest den vollen Text, deshalb wenige.
  final int pagesPerRequest;
  final int parallelRequests;

  /// Weniger Zeichen zählen als "kein Text" (Scan, leere Seite).
  static const minPageText = 15;

  /// Prüft [items] gegen die Seiten [firstPage]..[lastPage] von [pageTexts]
  /// (Index 0 = Seite 1). [contentOnly] wie beim Import: nur inhaltliche
  /// Fragen zählen.
  Future<ImportCheckReport> verify({
    required List<String> pageTexts,
    required List<ImportedItem> items,
    required bool contentOnly,
    String? fileName,
    int firstPage = 1,
    int? lastPage,
    void Function(int done, int total)? onProgress,
  }) async {
    final last = (lastPage ?? pageTexts.length).clamp(0, pageTexts.length);
    final readable = <int>[];
    final unchecked = <int>[];
    for (var p = firstPage; p <= last; p++) {
      (pageTexts[p - 1].trim().length >= minPageText ? readable : unchecked).add(p);
    }
    final batches = [
      for (var i = 0; i < readable.length; i += pagesPerRequest)
        readable.sublist(i, i + pagesPerRequest < readable.length ? i + pagesPerRequest : readable.length),
    ];
    final checked = items.where((i) => readable.contains(i.page)).toList();

    final results = <int, ImportVerification>{};
    final batchItems = <int, List<ImportedItem>>{};
    final errors = <String>[];
    var next = 0;
    var done = 0;
    onProgress?.call(0, batches.length);

    Future<void> worker() async {
      while (next < batches.length) {
        final index = next++;
        final pages = batches[index];
        final mine = [for (final i in checked) if (pages.contains(i.page)) i];
        batchItems[index] = mine;
        try {
          results[index] = await ai.verifyImportedQuestions(
            pageNumbers: pages,
            pageTexts: [for (final p in pages) pageTexts[p - 1]],
            imported: [
              for (final (k, i) in mine.indexed) (n: k + 1, page: i.page, front: i.front, answer: i.answer),
            ],
            contentOnly: contentOnly,
          );
        } catch (e) {
          errors.add('Seite ${pages.first}${pages.length > 1 ? '–${pages.last}' : ''}: '
              '${e is AiServiceException ? e.message : e}');
        }
        done++;
        onProgress?.call(done, batches.length);
      }
    }

    await Future.wait([for (var i = 0; i < parallelRequests; i++) worker()]);

    final findings = <ImportFinding>[];
    final notes = <String>[];
    int? count;
    for (var index = 0; index < batches.length; index++) {
      final verdict = results[index];
      if (verdict == null) continue;
      if (verdict.documentCount != null) count = (count ?? 0) + verdict.documentCount!;
      if (verdict.note.isNotEmpty && !notes.contains(verdict.note)) notes.add(verdict.note);
      for (final m in verdict.missing) {
        findings.add(ImportFinding(
          kind: ImportFindingKind.missing,
          fileName: fileName,
          page: m.page,
          text: m.task,
          reason: m.reason,
        ));
      }
      final mine = batchItems[index]!;
      final seen = <int>{};
      for (final s in verdict.surplus) {
        if (s.n < 1 || s.n > mine.length || !seen.add(s.n)) continue;
        final item = mine[s.n - 1];
        findings.add(ImportFinding(
          kind: ImportFindingKind.fromSurplusKind(s.kind),
          fileName: fileName,
          page: item.page,
          text: item.front,
          reason: s.reason,
          ref: item.ref,
        ));
      }
    }
    findings.sort((a, b) {
      final byPage = a.page.compareTo(b.page);
      return byPage != 0 ? byPage : (a.isMissing == b.isMissing ? 0 : (a.isMissing ? -1 : 1));
    });
    return ImportCheckReport(
      documentCount: count,
      importedCount: checked.length,
      findings: findings,
      uncheckedPages: unchecked,
      errors: errors,
      notes: notes,
    );
  }
}
