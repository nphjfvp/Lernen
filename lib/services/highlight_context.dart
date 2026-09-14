import '../models/material_item.dart';

/// Baut aus den Markierungen + der Notiz eines Materials (siehe
/// MaterialViewerScreen) einen zusätzlichen Textblock, der der KI mitteilt,
/// welche Stellen der Nutzer selbst als besonders wichtig markiert hat –
/// eingesetzt sowohl im Frage-Chat (ChatContextBuilder) als auch beim
/// Vorbereiten/Nachbereiten (dort wird frisch hochgeladener Text mit den
/// Markierungen des gleichnamigen, bereits gespeicherten Materials
/// angereichert, siehe PrepareScreen/ReviewScreen).
class HighlightContext {
  HighlightContext._();

  /// Leerer String, wenn nichts markiert/notiert wurde – nichts anzuhängen.
  static String build(MaterialItem material) {
    if (material.highlights.isEmpty && material.notes.trim().isEmpty) return '';

    final buffer = StringBuffer()
      ..writeln('[Vom Nutzer in "${material.fileName}" als besonders wichtig markiert]');
    for (final h in material.highlights) {
      buffer.writeln('- (${_label(h.color)}) "${h.text}"');
    }
    final notes = material.notes.trim();
    if (notes.isNotEmpty) {
      buffer.writeln('Notiz des Nutzers: $notes');
    }
    return buffer.toString();
  }

  static String _label(HighlightColor color) => switch (color) {
        HighlightColor.red => 'eignet sich als Prüfungsfrage',
        HighlightColor.green => 'Antwort/Schlüsselfakt',
        HighlightColor.yellow => 'wichtig/relevant',
      };
}
