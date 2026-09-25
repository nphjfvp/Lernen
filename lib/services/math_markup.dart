/// Ein Stück Text, das entweder normal oder als Formel (LaTeX) dargestellt
/// wird – siehe [MathMarkup.split] und MathText.
class MathSegment {
  const MathSegment.text(this.content)
      : isMath = false,
        isDisplay = false;
  const MathSegment.inline(this.content)
      : isMath = true,
        isDisplay = false;
  const MathSegment.display(this.content)
      : isMath = true,
        isDisplay = true;

  final String content;
  final bool isMath;

  /// Abgesetzte Formel (eigene Zeile) statt im Satz.
  final bool isDisplay;

  @override
  bool operator ==(Object other) =>
      other is MathSegment && other.content == content && other.isMath == isMath && other.isDisplay == isDisplay;

  @override
  int get hashCode => Object.hash(content, isMath, isDisplay);

  @override
  String toString() => isMath ? (isDisplay ? '\$\$$content\$\$' : '\$$content\$') : content;
}

/// Erkennt Formeln in KI-/Nutzertexten: `$…$` und `\(…\)` im Satz,
/// `$$…$$` und `\[…\]` abgesetzt. Bewusst vorsichtig bei einzelnen
/// Dollarzeichen (Geldbeträge): wie bei Pandoc muss nach dem öffnenden `$`
/// direkt ein Zeichen folgen, vor dem schließenden darf kein Leerzeichen
/// stehen, danach keine Ziffer – "5 $ bis 10 $" bleibt so normaler Text.
/// `\$` ist ein wörtliches Dollarzeichen.
class MathMarkup {
  static bool containsMath(String text) => split(text).any((s) => s.isMath);

  static List<MathSegment> split(String text) {
    final segments = <MathSegment>[];
    final buffer = StringBuffer();

    void flushText() {
      if (buffer.isEmpty) return;
      segments.add(MathSegment.text(buffer.toString()));
      buffer.clear();
    }

    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      final next = i + 1 < text.length ? text[i + 1] : '';

      if (ch == '\\' && next == '\$') {
        buffer.write('\$');
        i += 2;
        continue;
      }
      if (ch == '\\' && (next == '(' || next == '[')) {
        final closing = next == '(' ? r'\)' : r'\]';
        final end = text.indexOf(closing, i + 2);
        if (end != -1) {
          final content = text.substring(i + 2, end).trim();
          if (content.isNotEmpty) {
            flushText();
            segments.add(next == '(' ? MathSegment.inline(content) : MathSegment.display(content));
            i = end + 2;
            continue;
          }
        }
      }
      if (ch == '\$' && next == '\$') {
        final end = text.indexOf('\$\$', i + 2);
        if (end != -1) {
          final content = text.substring(i + 2, end).trim();
          if (content.isNotEmpty) {
            flushText();
            segments.add(MathSegment.display(content));
            i = end + 2;
            continue;
          }
        }
        buffer.write('\$\$');
        i += 2;
        continue;
      }
      if (ch == '\$') {
        final end = _findInlineClose(text, i);
        if (end != -1) {
          flushText();
          segments.add(MathSegment.inline(text.substring(i + 1, end)));
          i = end + 1;
          continue;
        }
      }
      buffer.write(ch);
      i += 1;
    }
    flushText();
    return segments;
  }

  static int _findInlineClose(String text, int open) {
    if (open + 1 >= text.length) return -1;
    final first = text[open + 1];
    if (first.trim().isEmpty || first == '\$') return -1;
    for (var j = open + 1; j < text.length; j++) {
      final c = text[j];
      if (c == '\n') return -1;
      if (c == '\\' && j + 1 < text.length) {
        j += 1; // escaptes Zeichen innerhalb der Formel überspringen
        continue;
      }
      if (c != '\$') continue;
      final before = text[j - 1];
      final after = j + 1 < text.length ? text[j + 1] : '';
      if (before.trim().isEmpty) return -1;
      if (after.isNotEmpty && RegExp(r'[0-9]').hasMatch(after)) return -1;
      return j;
    }
    return -1;
  }

  /// Repariert LaTeX in KI-JSON, BEVOR es dekodiert wird: Modelle schreiben
  /// in Formeln oft einfache Backslashes ("$\frac{a}{b}$"). In JSON ist `\f`
  /// aber ein Seitenvorschub, `\t` ein Tab, `\n` ein Zeilenumbruch, `\r`/`\b`
  /// ebenso – aus `\frac`, `\theta`, `\nabla`, `\rho`, `\beta` würde still
  /// Datenmüll, `\{` oder `\,` machen das JSON sogar ungültig. Innerhalb von
  /// Formeln (`$…$`, `\(…\)`, `\[…\]`) in JSON-Strings wird deshalb jeder
  /// einzelne Backslash verdoppelt; bereits korrekt verdoppelte bleiben, wie
  /// sie sind. Außerhalb von Formeln werden nur ungültige JSON-Escapes
  /// verdoppelt (gültige wie `\n` bleiben Zeilenumbrüche).
  static String escapeLatexInJson(String json) {
    const validJsonEscapes = {'"', '\\', '/', 'b', 'f', 'n', 'r', 't', 'u'};
    final out = StringBuffer();
    var inString = false;
    var inMath = false;
    var i = 0;
    while (i < json.length) {
      final ch = json[i];
      if (!inString) {
        out.write(ch);
        if (ch == '"') {
          inString = true;
          inMath = false;
        }
        i += 1;
        continue;
      }
      if (ch == '"') {
        out.write(ch);
        inString = false;
        i += 1;
        continue;
      }
      if (ch == '\\') {
        final next = i + 1 < json.length ? json[i + 1] : '';
        if (next == '\\' || next == '"') {
          out
            ..write(ch)
            ..write(next);
          i += 2;
          continue;
        }
        if (next == '(' || next == '[') {
          inMath = true;
        } else if (next == ')' || next == ']') {
          inMath = false;
        }
        final isMathDelimiter = next == '(' || next == '[' || next == ')' || next == ']';
        if (inMath || isMathDelimiter || !validJsonEscapes.contains(next)) {
          out.write(r'\\');
        } else {
          out.write(ch);
        }
        i += 1;
        continue;
      }
      if (ch == '\$') inMath = !inMath;
      out.write(ch);
      i += 1;
    }
    return out.toString();
  }
}
