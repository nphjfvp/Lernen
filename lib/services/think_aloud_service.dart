import '../models/flashcard.dart';
import 'stage_gate_service.dart';

/// Wie die KI einen laut gedachten Lösungsweg liest (siehe
/// AiService.assessThinking).
enum ThinkStatus { correct, wrong, thinking }

/// Art eines Fehlers im Gedankengang.
enum ThinkError {
  none(''),
  gap('Lücke – es kam nichts'),
  confusion('Verwechslung'),
  slip('Flüchtigkeitsfehler'),
  misconception('Fehlvorstellung');

  const ThinkError(this.label);

  final String label;
}

/// Antwort der KI auf einen Gedankengang.
class ThinkVerdict {
  const ThinkVerdict({
    required this.status,
    required this.reply,
    this.level = 0,
    this.error = ThinkError.none,
    this.read = '',
  });

  final ThinkStatus status;

  /// Was der Lernende liest (Urteil, Anstoß bzw. Bestätigung).
  final String reply;

  /// Stufe des Anstoßes auf der Hilfe-Leiter (0 = keiner, siehe HintLadder).
  final int level;
  final ThinkError error;

  /// Ein Satz, wie der Lernende an die Frage herangeht (für die Auswertung).
  final String read;

  /// Ungeprüfte KI-Ausgabe tolerant lesen.
  static ThinkVerdict fromJson(Map<String, dynamic> json) {
    final rawStatus = '${json['status'] ?? json['verdict'] ?? ''}'.toLowerCase();
    final status = switch (rawStatus) {
      'correct' || 'richtig' || 'solved' => ThinkStatus.correct,
      'wrong' || 'falsch' || 'incorrect' => ThinkStatus.wrong,
      _ => ThinkStatus.thinking,
    };
    final rawError = '${json['error'] ?? ''}'.toLowerCase();
    final level = (json['level'] is num ? (json['level'] as num).toInt() : int.tryParse('${json['level']}') ?? 0)
        .clamp(0, 5);
    return ThinkVerdict(
      status: status,
      reply: '${json['reply'] ?? json['feedback'] ?? ''}'.trim(),
      level: status == ThinkStatus.correct ? 0 : level,
      error: ThinkError.values.firstWhere((e) => e != ThinkError.none && e.name == rawError, orElse: () => ThinkError.none),
      read: '${json['read'] ?? ''}'.trim(),
    );
  }
}

/// Modus „Laut denken“: Fragen aus gewählten Fächern, zu denen man seinen
/// Gedankengang spricht oder tippt; die KI liest den Weg, nicht nur das
/// Ergebnis (nach dem Vorbild von LearnHarness).
class ThinkAloudService {
  ThinkAloudService._();

  /// Fragetypen, die sich als offene Denkaufgabe stellen lassen (keine
  /// Bild-, Zuordnungs- oder Rechenweg-Aufgaben – die haben eigene Ansichten).
  static const supportedTypes = {
    QuestionType.flashcard,
    QuestionType.freeText,
    QuestionType.fillBlank,
    QuestionType.singleChoice,
    QuestionType.multipleChoice,
    QuestionType.learn,
  };

  static bool supports(Flashcard card) => supportedTypes.contains(card.type) && card.answerSummary.trim().isNotEmpty;

  /// Bis zu [count] Fragen aus [moduleIds]: zuerst fällige, dann wackelige
  /// (rot/gelb), dann neue – nur die freigeschaltete Stufe je Gruppe und nur
  /// behandelte Einheiten, Fächer abwechselnd.
  static List<Flashcard> pick(
    List<Flashcard> allCards, {
    required Set<String> moduleIds,
    Map<String, bool> unitCoveredById = const {},
    int count = 10,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final endOfToday = DateTime(at.year, at.month, at.day + 1);
    final inModules = allCards.where((c) => moduleIds.contains(c.moduleId)).toList();
    final candidates = StageGate.learnable(inModules).where((c) {
      if (!supports(c)) return false;
      final unit = c.unitId;
      return unit == null || c.priorityIntroduction || (unitCoveredById[unit] ?? true);
    }).toList();
    int rank(Flashcard c) {
      if (c.reps > 0 && c.due.isBefore(endOfToday)) return 0;
      if (c.reps > 0 && c.masteryBox <= 1) return 1;
      if (c.reps == 0) return 2;
      return 3;
    }

    candidates.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      return rank(a) == 2 ? a.createdAt.compareTo(b.createdAt) : a.due.compareTo(b.due);
    });
    // Fächer abwechseln, Rangfolge innerhalb eines Fachs beibehalten.
    final byModule = <String, List<Flashcard>>{};
    for (final c in candidates) {
      byModule.putIfAbsent(c.moduleId, () => []).add(c);
    }
    final queues = byModule.values.toList();
    final result = <Flashcard>[];
    var i = 0;
    while (result.length < count && queues.any((q) => q.isNotEmpty)) {
      final q = queues[i % queues.length];
      if (q.isNotEmpty) result.add(q.removeAt(0));
      i++;
    }
    return result;
  }

  /// Die Frage, wie sie gestellt wird – bei Auswahlfragen mit den Optionen
  /// zur Orientierung.
  static String questionText(Flashcard card) {
    final options = card.options ?? const <QuizOption>[];
    if ((card.type == QuestionType.singleChoice || card.type == QuestionType.multipleChoice) && options.isNotEmpty) {
      return '${card.promptText}\n\n${[for (final (i, o) in options.indexed) '${String.fromCharCode(97 + i)}) ${o.labelAt(i)}'].join('\n')}';
    }
    return card.promptText;
  }
}
