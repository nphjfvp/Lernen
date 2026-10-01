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
      segments.addAll(_bareMath(buffer.toString()));
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
      if (ch == '`' && next != '`') {
        // Formel in Code-Backticks (Markdown der KI): `\frac{a}{b}`.
        final end = text.indexOf('`', i + 1);
        if (end != -1) {
          final content = text.substring(i + 1, end).trim();
          if (!content.contains('\n') && looksLikeLatex(content)) {
            flushText();
            segments.add(MathSegment.inline(content.replaceAll(RegExp(r'^\$+|\$+$'), '').trim()));
            i = end + 1;
            continue;
          }
        }
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
    if (first == '\$') return -1;
    // Leerzeichen innen ("$ U = R \cdot I $") nur, wenn es eindeutig eine Formel
    // ist – sonst bliebe "5 $ bis 10 $" kein Geldbetrag.
    final spacedOpen = first.trim().isEmpty;
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
      final spaced = spacedOpen || before.trim().isEmpty;
      if (spaced && !looksLikeLatex(text.substring(open + 1, j))) return -1;
      if (after.isNotEmpty && RegExp(r'[0-9]').hasMatch(after)) return -1;
      return j;
    }
    return -1;
  }

  /// Befehle, an denen LaTeX ohne Begrenzer sicher erkannt wird (ein Pfad wie
  /// `C:\Users` zählt nicht).
  static const latexCommands = {
    'frac', 'dfrac', 'tfrac', 'sqrt', 'cdot', 'times', 'div', 'pm', 'mp', 'approx', 'neq', 'ne', 'leq', 'le',
    'geq', 'ge', 'll', 'gg', 'equiv', 'propto', 'sim', 'infty', 'partial', 'nabla', 'sum', 'prod', 'int', 'iint',
    'oint', 'lim', 'log', 'ln', 'lg', 'exp', 'sin', 'cos', 'tan', 'cot', 'arcsin', 'arccos', 'arctan', 'sinh',
    'cosh', 'tanh', 'max', 'min', 'vec', 'hat', 'bar', 'dot', 'ddot', 'overline', 'underline', 'tilde', 'mathrm',
    'mathbf', 'mathit', 'mathcal', 'text', 'textbf', 'operatorname', 'left', 'right', 'big', 'Big', 'to',
    'rightarrow', 'leftarrow', 'Rightarrow', 'Leftarrow', 'leftrightarrow', 'Leftrightarrow', 'mapsto', 'degree',
    'circ', 'angle', 'perp', 'parallel', 'cdots', 'ldots', 'dots', 'forall', 'exists', 'in', 'notin', 'subset',
    'subseteq', 'cup', 'cap', 'emptyset', 'land', 'lor', 'neg', 'oplus', 'otimes', 'binom', 'quad', 'qquad',
    'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon', 'zeta', 'eta', 'theta', 'vartheta', 'iota',
    'kappa', 'lambda', 'mu', 'nu', 'xi', 'pi', 'rho', 'sigma', 'tau', 'upsilon', 'phi', 'varphi', 'chi', 'psi',
    'omega', 'Gamma', 'Delta', 'Theta', 'Lambda', 'Xi', 'Pi', 'Sigma', 'Phi', 'Psi', 'Omega', 'hbar', 'ell',
    'Re', 'Im', 'det', 'deg', 'arg',
  };

  static final _command = RegExp(r'\\([A-Za-z]+)');

  /// Ob [text] erkennbar LaTeX enthält: ein bekannter Befehl (`\frac`, `\alpha` …)
  /// oder Hoch-/Tiefstellung mit Klammern (`x^{2}`, `U_{0}`).
  static bool looksLikeLatex(String text) {
    for (final m in _command.allMatches(text)) {
      if (latexCommands.contains(m.group(1))) return true;
    }
    return RegExp(r'[\^_]\{').hasMatch(text);
  }

  static final _token = RegExp(r'\S+');
  static final _trailingPunctuation = RegExp(r'[.,;:!?]+$');
  static final _operatorToken = RegExp(r'^[=+\-*/<>≤≥≈≠±·×÷:()\[\]{}|]+$');
  static final _simpleToken = RegExp(r'^([A-Za-z][0-9]*|[-+]?\d+([.,]\d+)?)$');
  static final _powerToken = RegExp(r'^[A-Za-z0-9()]+\^[-+]?[A-Za-z0-9()]+$');

  /// Formeln ohne Begrenzer – die KI vergisst die Dollarzeichen öfter
  /// ("Es gilt U = R \cdot I."). Je Zeile werden Folgen von Formel-Stücken
  /// (LaTeX-Befehle, Hochstellungen, Operatoren, einzelne Buchstaben, Zahlen)
  /// gesucht, die mindestens einen LaTeX-Befehl enthalten, und als Formel
  /// gesetzt. Fließtext bleibt Text.
  static List<MathSegment> _bareMath(String text) {
    if (!looksLikeLatex(text)) return [MathSegment.text(text)];
    final result = <MathSegment>[];
    final plain = StringBuffer();
    void addPlain(String t) => plain.write(t);
    void flushPlain() {
      if (plain.isEmpty) return;
      result.add(MathSegment.text(plain.toString()));
      plain.clear();
    }

    final lines = text.split('\n');
    for (var l = 0; l < lines.length; l++) {
      final line = lines[l];
      if (l > 0) addPlain('\n');
      if (!looksLikeLatex(line)) {
        addPlain(line);
        continue;
      }
      final tokens = _token.allMatches(line).toList();
      // Je Token: Kern ohne Satzzeichen am Ende, und ob er zur Formel passt.
      final cores = <String>[];
      final isMath = <bool>[];
      final isTrigger = <bool>[];
      for (final t in tokens) {
        var core = t.group(0)!;
        if (!core.endsWith(r'\,') && !core.endsWith(r'\;')) core = core.replaceFirst(_trailingPunctuation, '');
        final trigger = looksLikeLatex(core);
        cores.add(core);
        isTrigger.add(trigger);
        isMath.add(core.isNotEmpty &&
            (trigger || _operatorToken.hasMatch(core) || _simpleToken.hasMatch(core) || _powerToken.hasMatch(core)));
      }
      var cursor = 0;
      var i = 0;
      while (i < tokens.length) {
        if (!isMath[i]) {
          i++;
          continue;
        }
        var j = i;
        var hasTrigger = false;
        while (j < tokens.length && isMath[j]) {
          hasTrigger |= isTrigger[j];
          // Satzzeichen am Token-Ende beendet die Formel.
          if (cores[j] != tokens[j].group(0)) {
            j++;
            break;
          }
          j++;
        }
        if (!hasTrigger) {
          i = j;
          continue;
        }
        final start = tokens[i].start;
        final last = tokens[j - 1];
        final end = last.start + cores[j - 1].length;
        addPlain(line.substring(cursor, start));
        flushPlain();
        result.add(MathSegment.inline(line.substring(start, end)));
        cursor = end;
        i = j;
      }
      addPlain(line.substring(cursor));
    }
    flushPlain();
    return result;
  }

  /// Repariert LaTeX in KI-JSON, BEVOR es dekodiert wird: Modelle schreiben
  /// in Formeln oft einfache Backslashes ("$\frac{a}{b}$"). In JSON ist `\f`
  /// aber ein Seitenvorschub, `\t` ein Tab, `\n` ein Zeilenumbruch, `\r`/`\b`
  /// ebenso – aus `\frac`, `\theta`, `\nabla`, `\rho`, `\beta` würde still
  /// Datenmüll, `\{` oder `\,` machen das JSON sogar ungültig. Innerhalb von
  /// Formeln (`$…$`, `\(…\)`, `\[…\]`) in JSON-Strings wird deshalb jeder
  /// einzelne Backslash verdoppelt; bereits korrekt verdoppelte bleiben, wie
  /// sie sind. Innerhalb von Formeln zählt `\n`/`\t`/… nur dann als
  /// LaTeX-Befehl, wenn direkt ein Buchstabe folgt – ein einzelnes `$` in
  /// normalem Text (z.B. `$HOME`) macht so aus "\n " keinen sichtbaren
  /// Backslash. Außerhalb von Formeln werden nur ungültige JSON-Escapes
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
        final afterNext = i + 2 < json.length ? json[i + 2] : '';
        final bool double;
        if (isMathDelimiter || !validJsonEscapes.contains(next)) {
          double = true; // sonst ungültiges JSON
        } else if (next == '/') {
          double = false;
        } else if (!inMath) {
          // Außerhalb einer Formel: \f und \b vor Buchstaben (Seitenvorschub,
          // Rückschritt) kommen in Text nie vor – das ist \frac, \beta, \bar …;
          // \t, \n, \r nur, wenn das Wort ein bekannter LaTeX-Befehl ist
          // (\theta, \nabla, \rho), sonst bleibt es ein Tab/Zeilenumbruch.
          final word = RegExp(r'^[A-Za-z]+').stringMatch(json.substring(i + 1)) ?? '';
          if (next == 'f' || next == 'b') {
            double = _isLetter(afterNext);
          } else if (next == 't' || next == 'n' || next == 'r') {
            double = latexCommands.contains(word) && word.length > 2;
          } else {
            double = false;
          }
        } else if (next == 'u') {
          // \u00e4 ist ein echtes Unicode-Escape, \underline ein LaTeX-Befehl.
          double = !_isUnicodeEscape(json, i + 2);
        } else {
          // \frac, \theta, \nabla, \rho, \beta: Befehl = Buchstabe folgt;
          // "\n " oder "\n2" bleibt ein echter Zeilenumbruch usw.
          double = _isLetter(afterNext);
        }
        out.write(double ? r'\\' : ch);
        i += 1;
        continue;
      }
      if (ch == '\$') {
        // `$$` ist EIN Begrenzer (abgesetzte Formel), nicht zwei – sonst stünde
        // der Formelinhalt fälschlich außerhalb des Formelmodus.
        final isDouble = i + 1 < json.length && json[i + 1] == '\$';
        inMath = !inMath;
        out.write(isDouble ? '\$\$' : ch);
        i += isDouble ? 2 : 1;
        continue;
      }
      out.write(ch);
      i += 1;
    }
    return out.toString();
  }

  static bool _isLetter(String c) => c.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(c);

  static bool _isUnicodeEscape(String s, int start) =>
      start + 4 <= s.length && RegExp(r'^[0-9A-Fa-f]{4}$').hasMatch(s.substring(start, start + 4));
}
