import '../models/material_item.dart';
import 'highlight_context.dart';

/// Baut den Material-Kontext für den Frage-Chat: alle Materialien eines
/// Fachs, chronologisch geordnet und mit Behandelt-Status markiert, begrenzt
/// auf ein Zeichenbudget (grobe Schätzung aus dem Kontextfenster des
/// gewählten Modells) – damit auch ein ganzes Halbjahr an hochgeladenen
/// Folien nicht die Anfrage sprengt.
///
/// Bereits behandelte Materialien haben Vorrang vor noch nicht behandelten.
/// Wird das Budget knapp, werden unbehandelte Materialien nur als kurzer
/// Anriss (Dateiname + Textausschnitt) statt vollständig eingebunden, damit
/// das Modell trotzdem WEISS, dass sie existieren (relevant für Fragen wie
/// "wie hängt das mit einem späteren Thema zusammen").
class ChatContextBuilder {
  ChatContextBuilder._();

  static const int stubPreviewChars = 400;

  /// Sehr grobe Heuristik: ~3.2 Zeichen pro Token bei deutsch-/englisch-
  /// sprachigem Fließtext, davon ~55% für das Material-Budget reserviert
  /// (der Rest bleibt für System-Prompt, Gesprächsverlauf und die
  /// Modellantwort selbst).
  static int charBudgetForContextTokens(int? contextLengthTokens) {
    final tokens = (contextLengthTokens != null && contextLengthTokens > 0)
        ? contextLengthTokens
        : 32000;
    return (tokens * 3.2 * 0.55).round();
  }

  /// Genügend Rohtext eines noch nicht indizierten Materials, um dem
  /// Auswahl-Schritt trotzdem einen groben Anhaltspunkt zu geben, statt es
  /// stillschweigend zu ignorieren.
  static const int _fallbackGistChars = 300;

  /// Baut den KOMPAKTEN Material-Index für den ersten Schritt des
  /// zweistufigen Frage-Chats (siehe [AiService.selectRelevantMaterials]):
  /// pro Material nur ID, Behandelt-Status und die kurze KI-generierte
  /// Themenangabe ([MaterialItem.topicIndex]) – nie der volle Text. Für
  /// noch nicht indizierte Materialien wird ersatzweise ein kurzer
  /// Rohtext-Anriss verwendet, damit sie trotzdem in der Auswahl auftauchen
  /// können (ModuleChatScreen holt die eigentliche Indizierung vor der
  /// ersten Frage nach; dieser Fallback greift nur, falls das für ein
  /// Material fehlschlägt).
  static String buildIndexContext(List<MaterialItem> materials) {
    final relevant = _excludingPracticeExam(materials);
    if (relevant.isEmpty) return '(Noch keine Materialien hochgeladen.)';

    final chronological = [...relevant]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final buffer = StringBuffer();
    for (final m in chronological) {
      final kindLabel = m.kind == MaterialKind.slide ? 'Folien' : 'Übungsaufgabe';
      final status = m.covered ? 'Behandelt' : 'Noch nicht behandelt';
      final gist = (m.topicIndex != null && m.topicIndex!.trim().isNotEmpty)
          ? m.topicIndex!.trim()
          : (m.extractedText.length > _fallbackGistChars
              ? '${m.extractedText.substring(0, _fallbackGistChars)}…'
              : m.extractedText);
      buffer.writeln('[id: ${m.id}] [$status] ${m.fileName} ($kindLabel): $gist');
    }
    return buffer.toString();
  }

  /// Übungsklausuren (siehe [MaterialKind.practiceExam]) dienen nur als
  /// Stil-Referenz für die KI-Generierung (siehe AiService.examContext-
  /// Parameter), sind aber kein normaler Fach-Stoff – im Frage-Chat würde
  /// "Behandelt/Noch nicht behandelt" für sie ohnehin keinen Sinn ergeben.
  static List<MaterialItem> _excludingPracticeExam(List<MaterialItem> materials) =>
      materials.where((m) => m.kind != MaterialKind.practiceExam).toList();

  static String build(List<MaterialItem> materials, {required int charBudget}) {
    final relevant = _excludingPracticeExam(materials);
    if (relevant.isEmpty) return '(Noch keine Materialien hochgeladen.)';

    final chronological = [...relevant]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final byPriority = [...chronological]
      ..sort((a, b) {
        if (a.covered != b.covered) return a.covered ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });

    final fullIds = <String>{};
    final stubIds = <String>{};
    var remaining = charBudget;
    for (final m in byPriority) {
      if (remaining <= 0) break;
      if (m.extractedText.length <= remaining) {
        fullIds.add(m.id);
        remaining -= m.extractedText.length;
      } else if (remaining > stubPreviewChars) {
        stubIds.add(m.id);
        remaining -= stubPreviewChars;
      }
    }

    final buffer = StringBuffer();
    for (final m in chronological) {
      final kindLabel = m.kind == MaterialKind.slide ? 'Folien' : 'Übungsaufgabe';
      final status = m.covered ? 'Behandelt' : 'Noch nicht behandelt';
      if (fullIds.contains(m.id)) {
        buffer
          ..writeln('--- [$status] ${m.fileName} ($kindLabel) ---')
          ..writeln(m.extractedText)
          ..writeln(HighlightContext.build(m))
          ..writeln();
      } else if (stubIds.contains(m.id)) {
        final preview = m.extractedText.length > stubPreviewChars
            ? '${m.extractedText.substring(0, stubPreviewChars)}…'
            : m.extractedText;
        buffer
          ..writeln('--- [$status] ${m.fileName} ($kindLabel) – nur Anriss, nicht vollständig geladen ---')
          ..writeln(preview)
          ..writeln(HighlightContext.build(m))
          ..writeln();
      }
      // sonst: Budget erschöpft, Material wird gar nicht erwähnt.
    }
    return buffer.toString();
  }
}
