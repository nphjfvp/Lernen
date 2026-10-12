import 'dart:convert';

import 'math_markup.dart';

/// Repariert JSON, wie es KI-Modelle gern liefern: mit Text oder Codefences
/// drumherum, einfachen Backslashes in LaTeX, echten Zeilenumbrüchen in
/// Texten, Anführungszeichen im Text, überzähligen Kommas oder – bei langen
/// Antworten – abgeschnitten mittendrin. Was sich so nicht retten lässt,
/// schickt AiService an die KI zurück (siehe AiService.repairJson).
class JsonRepair {
  JsonRepair._();

  /// Liest [raw] als JSON (Objekt oder Liste); wirft [FormatException], wenn
  /// es auch nach der Reparatur nicht geht.
  static Object? decode(String raw) {
    final block = extractBlock(raw);
    final first = _tryDecode(MathMarkup.escapeLatexInJson(block));
    if (first.ok) return first.value;
    final fixed = repairText(block);
    final second = _tryDecode(fixed);
    if (second.ok) return second.value;
    final closed = closeTruncated(fixed);
    if (closed != null) {
      final third = _tryDecode(closed);
      if (third.ok) return third.value;
    }
    throw first.error ?? const FormatException('Kein gültiges JSON');
  }

  static ({bool ok, Object? value, FormatException? error}) _tryDecode(String text) {
    try {
      return (ok: true, value: jsonDecode(text), error: null);
    } on FormatException catch (e) {
      return (ok: false, value: null, error: e);
    }
  }

  /// Der JSON-Teil einer Antwort (ohne Codefences, Text davor/danach).
  static String extractBlock(String text) {
    var t = text.trim();
    final fence = RegExp(r'```(?:json|JSON)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) {
      t = fence.group(1)!.trim();
    } else if (t.startsWith('```')) {
      // Abgeschnitten: öffnender Fence ohne schließenden.
      t = t.replaceFirst(RegExp(r'^```(?:json|JSON)?\s*'), '');
    }
    final start = t.indexOf(RegExp(r'[\{\[]'));
    if (start == -1) return t;
    final closing = t[start] == '{' ? '}' : ']';
    final end = t.lastIndexOf(closing);
    // Ohne schließende Klammer: abgeschnitten – alles ab dem Anfang behalten.
    if (end == -1 || end < start) return t.substring(start);
    return t.substring(start, end + 1);
  }

  /// Text-Reparaturen: LaTeX-Backslashes, Steuerzeichen und Anführungszeichen
  /// in Texten, überzählige Kommas.
  static String repairText(String json) {
    final escaped = MathMarkup.escapeLatexInJson(json);
    final out = StringBuffer();
    var inString = false;
    for (var i = 0; i < escaped.length; i++) {
      final ch = escaped[i];
      if (inString) {
        if (ch == '\\') {
          out.write(ch);
          if (i + 1 < escaped.length) out.write(escaped[++i]);
          continue;
        }
        if (ch == '"') {
          // Ende des Texts nur, wenn danach Struktur kommt – sonst ist es ein
          // Anführungszeichen im Text ("das sog. "Hebelgesetz"").
          var j = i + 1;
          while (j < escaped.length && ' \t\r\n'.contains(escaped[j])) {
            j++;
          }
          final next = j < escaped.length ? escaped[j] : '';
          if (next.isEmpty || ',}]:'.contains(next)) {
            inString = false;
            out.write(ch);
          } else {
            out.write(r'\"');
          }
          continue;
        }
        switch (ch) {
          case '\n':
            out.write(r'\n');
          case '\r':
            out.write(r'\r');
          case '\t':
            out.write(r'\t');
          default:
            out.write(ch.codeUnitAt(0) < 0x20 ? ' ' : ch);
        }
        continue;
      }
      if (ch == '"') inString = true;
      out.write(ch);
    }
    // Überzählige Kommas vor } und ] (außerhalb von Texten).
    return _outsideStrings(out.toString(), (s) => s.replaceAllMapped(RegExp(r',(\s*[\}\]])'), (m) => m[1]!));
  }

  /// Wendet [fix] nur auf die Teile außerhalb von Texten an.
  static String _outsideStrings(String json, String Function(String) fix) {
    final out = StringBuffer();
    final chunk = StringBuffer();
    var inString = false;
    for (var i = 0; i < json.length; i++) {
      final ch = json[i];
      if (inString) {
        out.write(ch);
        if (ch == '\\' && i + 1 < json.length) {
          out.write(json[++i]);
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        out.write(fix(chunk.toString()));
        chunk.clear();
        inString = true;
        out.write(ch);
        continue;
      }
      chunk.write(ch);
    }
    out.write(fix(chunk.toString()));
    return out.toString();
  }

  /// Schließt abgeschnittenes JSON: offenen Text beenden, unvollständigen
  /// letzten Eintrag weglassen, offene Klammern schließen. null, wenn nichts
  /// offen ist.
  static String? closeTruncated(String json) {
    final scan = _scan(json);
    if (scan.stack.isEmpty && !scan.inString) return null;
    // Erst den ganzen Text schließen, dann schrittweise bis zum letzten
    // vollständigen Eintrag zurück.
    final candidates = <String>[
      _close(json, scan),
      for (final cut in scan.commas.reversed.take(60)) _close(json.substring(0, cut), _scan(json.substring(0, cut))),
    ];
    for (final c in candidates) {
      if (_tryDecode(c).ok) return c;
    }
    return null;
  }

  static String _close(String json, ({List<String> stack, bool inString, List<int> commas}) scan) {
    var t = json;
    if (scan.inString) t = '$t"';
    t = t.trimRight();
    // Unvollständiges Ende: "schlüssel": ohne Wert, Komma oder Doppelpunkt.
    t = t.replaceFirst(RegExp(r'[,:]\s*$'), '');
    t = t.replaceFirst(RegExp(r',\s*"[^"]*"\s*$'), '');
    return t + scan.stack.reversed.map((c) => c == '{' ? '}' : ']').join();
  }

  static ({List<String> stack, bool inString, List<int> commas}) _scan(String json) {
    final stack = <String>[];
    final commas = <int>[];
    var inString = false;
    for (var i = 0; i < json.length; i++) {
      final ch = json[i];
      if (inString) {
        if (ch == '\\') {
          i++;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      switch (ch) {
        case '"':
          inString = true;
        case '{' || '[':
          stack.add(ch);
        case '}' || ']':
          if (stack.isNotEmpty) stack.removeLast();
        case ',':
          commas.add(i);
      }
    }
    return (stack: stack, inString: inString, commas: commas);
  }
}
