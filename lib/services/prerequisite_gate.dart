import '../models/concept.dart';
import '../models/flashcard.dart';
import 'mastery_service.dart';

/// „Nie auf Ungefestigtem aufbauen“: Neue Karten eines Konzepts kommen erst,
/// wenn die Konzepte sitzen, auf denen es direkt aufbaut
/// ([Concept.prerequisiteIds]). „Sitzt“ heißt: keine der lernbaren Karten
/// des Voraussetzungs-Konzepts ist noch neu oder rot. Fällige Wiederholungen
/// und gezielt erstellte Fragen (priorityIntroduction) sind nie gesperrt.
///
/// Gegen Verklemmungen: Abhängigkeiten im Kreis (A braucht B, B braucht A)
/// werden ignoriert, und ein Konzept ohne lernbare Karten (z.B. Einheit noch
/// nicht behandelt) hält nichts auf.
class PrerequisiteGate {
  PrerequisiteGate._();

  /// IDs der Konzepte, deren NEUE Karten heute noch warten. [learnableCards]
  /// sind die Karten, die überhaupt eingeplant werden dürfen (Einheiten- und
  /// Stufen-Freigabe schon angewendet).
  static Set<String> blockedConcepts(
    Iterable<Concept> concepts,
    Iterable<Flashcard> learnableCards, {
    DateTime? now,
    MasteryService? mastery,
  }) {
    final byId = {for (final c in concepts) c.id: c};
    final edges = <String, Set<String>>{
      for (final c in byId.values)
        c.id: {for (final p in c.prerequisiteIds) if (p != c.id && byId.containsKey(p)) p},
    };
    final m = mastery ?? MasteryService();
    final cardsByConcept = <String, List<Flashcard>>{};
    for (final card in learnableCards) {
      final id = card.conceptId;
      if (id != null && byId.containsKey(id)) cardsByConcept.putIfAbsent(id, () => []).add(card);
    }
    bool held(String conceptId) => (cardsByConcept[conceptId] ?? const []).every((card) {
          final level = m.levelFor(card, now: now);
          return level == MasteryLevel.yellow || level == MasteryLevel.green;
        });

    final blocked = <String>{};
    for (final entry in edges.entries) {
      for (final prerequisite in entry.value) {
        // Kreis: die Voraussetzung baut ihrerseits (über Umwege) auf diesem
        // Konzept auf – diese Kante zählt nicht.
        if (_reaches(edges, prerequisite, entry.key)) continue;
        if (!held(prerequisite)) {
          blocked.add(entry.key);
          break;
        }
      }
    }
    return blocked;
  }

  static bool _reaches(Map<String, Set<String>> edges, String from, String target) {
    final seen = <String>{};
    final stack = [from];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node == target) return true;
      if (!seen.add(node)) continue;
      stack.addAll(edges[node] ?? const {});
    }
    return false;
  }

  /// Darf diese Karte heute neu eingeführt werden?
  static bool mayIntroduce(Flashcard card, Set<String> blocked) =>
      card.reps > 0 || card.priorityIntroduction || card.conceptId == null || !blocked.contains(card.conceptId);
}
