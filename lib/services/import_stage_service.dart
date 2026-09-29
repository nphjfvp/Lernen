import '../models/flashcard.dart' show QuestionType;
import 'ai_service.dart';
import 'question_parsing.dart';
import 'stage_gate_service.dart';

/// Eine übernommene Original-Frage, zu der Stufen ergänzt werden sollen.
/// [ref] ist der Bezug des Aufrufers.
class StageInput {
  const StageInput({required this.ref, required this.type, required this.front, required this.answer});

  final int ref;

  /// Name des Fragetyps (z.B. `single_choice`) – hilft der KI, die Stufe des
  /// Originals einzuschätzen.
  final String type;
  final String front;
  final String answer;
}

/// Stufe/Ordner des Originals und die dazu erzeugten Fragen (Rohkarten,
/// bereits mit [QuestionParsing.normalizeGeneratedFlashcard] geprüft; "level"
/// ist der Stufenname, "group" der Ordnername).
class StageResult {
  const StageResult({required this.ref, required this.level, required this.group, required this.variants});

  final int ref;

  /// Stufe des Originals (0 = leicht … 2 = schwer).
  final int level;

  /// Ordnername (je Frage eindeutig) – null, wenn die KI keinen nannte und es
  /// keine Varianten gibt.
  final String? group;
  final List<Map<String, dynamic>> variants;
}

class StageRun {
  const StageRun({required this.results, required this.failedCards, required this.droppedVariants});

  final Map<int, StageResult> results;

  /// Karten, deren Anfrage fehlschlug (sie bleiben ohne Stufen).
  final int failedCards;

  /// Varianten, die die KI unvollständig lieferte.
  final int droppedVariants;
}

/// Ergänzt übernommene Fragen um Schwierigkeitsstufen: die KI schätzt die
/// Stufe des Originals, benennt den Ordner (dasselbe Wissen) und schreibt die
/// gewünschten weiteren Stufen dazu (siehe [AiService.expandQuestionStages]).
/// Das Original bleibt unverändert.
class ImportStageService {
  ImportStageService({required this.ai, this.batchSize = 8});

  final AiService ai;
  final int batchSize;

  Future<StageRun> expand(
    List<StageInput> cards, {
    required List<String> levels,
    Map<String, QuestionType> tierTypes = const {},
    Iterable<String> takenGroups = const [],
    void Function(int done, int total)? onProgress,
  }) async {
    // Jede Frage samt ihren Stufen ist EIN Ordner: gleich benannte Ordner
    // (auch aus einer anderen Portion oder einem früheren Lauf, [takenGroups])
    // würden sonst fremde Fragen zusammenlegen.
    final taken = {for (final g in takenGroups) g.trim().toLowerCase()};
    String uniqueGroup(String name) {
      var candidate = name;
      for (var n = 2; !taken.add(candidate.toLowerCase()); n++) {
        candidate = '$name $n';
      }
      return candidate;
    }

    final results = <int, StageResult>{};
    var failed = 0;
    var dropped = 0;
    final total = (cards.length / batchSize).ceil();
    onProgress?.call(0, total);
    for (var start = 0, batch = 0; start < cards.length; start += batchSize, batch++) {
      final chunk = cards.sublist(start, start + batchSize < cards.length ? start + batchSize : cards.length);
      try {
        final expansions = await ai.expandQuestionStages(
          [for (final (k, c) in chunk.indexed) (n: k + 1, type: c.type, front: c.front, answer: c.answer)],
          levels: levels,
          tierTypes: tierTypes,
        );
        for (final (k, card) in chunk.indexed) {
          final expansion = expansions[k + 1];
          if (expansion == null) {
            failed++;
            continue;
          }
          final level = expansion.level ?? StageGate.levelOfType(QuestionParsing.parseType(card.type)).index;
          final variants = <Map<String, dynamic>>[];
          for (final raw in expansion.variants) {
            final fixed = QuestionParsing.normalizeGeneratedFlashcard(raw);
            // Nur Varianten, die sich im gewünschten Typ vollständig ausfüllen
            // lassen (keine zurückgestufte Notlösung – die stünde in der
            // falschen Stufe), und keine in der Stufe des Originals.
            if (fixed == null ||
                fixed['typeDowngraded'] == true ||
                QuestionParsing.parseStageLevel(raw['level']) == level) {
              dropped++;
              continue;
            }
            variants.add({...fixed, 'level': raw['level']});
          }
          var group = expansion.group;
          if (group == null && variants.isNotEmpty) {
            group = card.front.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (group.length > 40) group = group.substring(0, 40);
          }
          results[card.ref] =
              StageResult(ref: card.ref, level: level, group: group == null ? null : uniqueGroup(group), variants: variants);
        }
      } catch (_) {
        failed += chunk.length;
      }
      onProgress?.call(batch + 1, total);
    }
    return StageRun(results: results, failedCards: failed, droppedVariants: dropped);
  }
}
