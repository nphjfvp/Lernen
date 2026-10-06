/// Ergebnis der Foto-Prüfung eines auf Papier gerechneten Rechenwegs (siehe
/// AiService.reviewPaperSolution): Zeilen so, wie die KI sie gelesen hat, je
/// Zeile richtig / Fehler / Folgefehler, dazu das Endergebnis in
/// Eingabe-Schreibweise – das prüft die App danach selbst (Probe).
library;

enum PaperLineStatus {
  ok('richtig'),
  error('Fehler'),

  /// Aus einer früheren falschen Zeile richtig weitergerechnet.
  follow('Folgefehler'),
  unclear('unklar');

  const PaperLineStatus(this.label);
  final String label;
}

PaperLineStatus paperLineStatusFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().trim();
  if (v.contains('folge') || v.contains('follow') || v.contains('consequen')) return PaperLineStatus.follow;
  if (v.contains('fehler') || v.contains('error') || v.contains('wrong') || v.contains('falsch')) return PaperLineStatus.error;
  if (v.contains('unklar') || v.contains('unclear') || v.contains('unles') || v.contains('illegible')) {
    return PaperLineStatus.unclear;
  }
  return PaperLineStatus.ok;
}

class PaperLine {
  const PaperLine({required this.n, required this.text, this.status = PaperLineStatus.ok, this.comment = '', this.fix = ''});

  final int n;

  /// Die Zeile, wie sie auf dem Papier steht (LaTeX in `$…$` erlaubt).
  final String text;
  final PaperLineStatus status;

  /// Was an der Zeile (nicht) stimmt.
  final String comment;

  /// Wie die Zeile richtig lauten würde.
  final String fix;
}

/// Bewertungsvorschlag der KI für die ganze Aufgabe.
enum PaperGrade { again, hard, good }

class PaperReview {
  const PaperReview({
    this.lines = const [],
    this.summary = '',
    this.finalAnswer = '',
    this.firstErrorStep,
    this.grade = PaperGrade.hard,
  });

  final List<PaperLine> lines;
  final String summary;

  /// Endergebnis des Nutzers als Formel (z.B. `x - sqrt(2x - 4)`), leer ohne.
  final String finalAnswer;

  /// In welchem Schritt der Musterlösung (1-basiert) der erste Fehler
  /// passiert ist; null = kein Fehler.
  final int? firstErrorStep;
  final PaperGrade grade;

  bool get hasErrors => lines.any((l) => l.status == PaperLineStatus.error || l.status == PaperLineStatus.follow);

  /// Die gelesenen Zeilen als Text (für die KI-Erklärung).
  String get readText => lines.map((l) => '${l.n}: ${l.text}').join('\n');

  static PaperReview fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] ?? json['zeilen'];
    final lines = <PaperLine>[];
    for (final (i, r) in (rawLines is List ? rawLines : const []).indexed) {
      if (r is! Map) continue;
      final text = '${r['text'] ?? r['zeile'] ?? r['line'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      final n = r['n'] is num ? (r['n'] as num).toInt() : int.tryParse('${r['n']}') ?? i + 1;
      lines.add(PaperLine(
        n: n,
        text: text,
        status: paperLineStatusFrom(r['status'] ?? r['bewertung']),
        comment: '${r['comment'] ?? r['kommentar'] ?? r['erklaerung'] ?? ''}'.trim(),
        fix: '${r['fix'] ?? r['korrektur'] ?? r['richtig'] ?? ''}'.trim(),
      ));
    }
    final step = json['firstErrorStep'] ?? json['ersterFehlerSchritt'];
    final firstErrorStep = step is num ? step.toInt() : int.tryParse('${step ?? ''}');
    final gradeText = '${json['grade'] ?? json['bewertung'] ?? ''}'.toLowerCase();
    final grade = gradeText.contains('gut') || gradeText.contains('good')
        ? PaperGrade.good
        : (gradeText.contains('nochmal') || gradeText.contains('again') ? PaperGrade.again : PaperGrade.hard);
    return PaperReview(
      lines: lines,
      summary: '${json['summary'] ?? json['zusammenfassung'] ?? ''}'.trim(),
      finalAnswer: '${json['finalAnswer'] ?? json['ergebnis'] ?? ''}'.trim(),
      firstErrorStep: firstErrorStep != null && firstErrorStep >= 1 ? firstErrorStep : null,
      grade: lines.isNotEmpty && !lines.any((l) => l.status != PaperLineStatus.ok) && firstErrorStep == null
          ? PaperGrade.good
          : grade,
    );
  }
}
