import 'highlight_matcher.dart';

/// Findet eine Aufgabe auf einer PDF-Seite wieder – über ihre Bezeichnung
/// ("Aufgabe 1a", "1 a)", "2b") oder einen wörtlichen Textausschnitt –, damit
/// der PDF-Viewer sie nach dem Erstellen der Frage markieren kann (siehe
/// MaterialViewerScreen). Rein auf Textzeilen, ohne PDF-Plugin testbar.
class TaskLabelLocator {
  TaskLabelLocator._();

  static final _label = RegExp(
    r'^(?:aufgabe|aufg\.?|nr\.?|task|teilaufgabe)?\s*(\d{1,2})\s*[.:)]?\s*([a-z])?\s*\)?\s*$',
    caseSensitive: false,
  );

  /// Bezeichnung aus einer kurzen Eingabe ("Aufgabe 1a" → (1, a)); null,
  /// wenn es keine ist.
  static ({String number, String? letter})? parseLabel(String query) {
    final q = query.trim();
    if (q.isEmpty || q.length > 30) return null;
    final m = _label.firstMatch(q);
    if (m == null) return null;
    return (number: m[1]!, letter: m[2]?.toLowerCase());
  }

  /// Indizes der Zeilen in [lines] (eine Seite, in Lesereihenfolge), die zu
  /// [query] gehören; null, wenn nichts passt.
  static List<int>? find(List<String> lines, String query) {
    final q = query.trim();
    if (q.isEmpty || lines.isEmpty) return null;
    final label = parseLabel(q);
    if (label == null) return _literal(lines, q);

    final n = RegExp.escape(label.number);
    final normalized = [for (final l in lines) l.trim().toLowerCase()];
    final letter = label.letter;
    if (letter != null) {
      // "1a)", "1 a)", "1.a", "Aufgabe 1a" in einer Zeile.
      final direct = RegExp('(^|[^0-9])(aufgabe\\s*)?$n\\s*[.)]?\\s*$letter(\\)|\\.|\\s|\$)');
      for (final (i, l) in normalized.indexed) {
        if (direct.hasMatch(l)) return [i];
      }
    }
    // Überschrift der Aufgabe, darunter ggf. die Teilaufgabe "a)".
    final heading = RegExp('^(aufgabe|aufg\\.?|task)\\s*$n(\\b|[.:)])|^$n\\s*[.:)]\\s');
    final h = normalized.indexWhere(heading.hasMatch);
    if (h < 0) return _literal(lines, q);
    if (letter == null) return [h];
    final sub = RegExp('^\\(?$letter[).]\\s*');
    for (var i = h; i < normalized.length; i++) {
      // Die nächste Aufgabe beginnt – dort nicht weitersuchen.
      if (i > h && RegExp(r'^(aufgabe|aufg\.?)\s*\d').hasMatch(normalized[i])) break;
      if (sub.hasMatch(normalized[i])) return [i];
    }
    return [h];
  }

  /// Wörtlich gesucht – auf die Zeilen gekürzt, die den Text wirklich
  /// enthalten (der Matcher liefert sonst ab Seitenanfang).
  static List<int>? _literal(List<String> lines, String q) {
    var range = HighlightMatcher.findLineRange(lines, q);
    if (range == null) return null;
    while (range!.length > 1) {
      final rest = range.sublist(1);
      if (HighlightMatcher.findLineRange([for (final i in rest) lines[i]], q) == null) break;
      range = rest;
    }
    return range;
  }
}
