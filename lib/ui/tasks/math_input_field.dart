import 'package:flutter/material.dart';

import '../../models/step_task.dart';
import '../../services/math_input.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Eingabefeld für eine Formel oder Zahl eines Rechenwegs: Beschriftung
/// ("u′ ="), Textfeld, Vorschau "So lese ich deine Eingabe" (LaTeX) und
/// Hilfstasten für Zeichen, die auf der Handytastatur fehlen (√, ², π …).
class MathInputField extends StatefulWidget {
  const MathInputField({
    super.key,
    required this.field,
    required this.controller,
    this.enabled = true,
    this.verdict,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.fieldKey,
  });

  final StepField field;
  final TextEditingController controller;
  final bool enabled;

  /// Ergebnis der letzten Prüfung (färbt den Rahmen).
  final FieldVerdict? verdict;
  final VoidCallback? onSubmitted;
  final VoidCallback? onChanged;
  final bool autofocus;
  final Key? fieldKey;

  @override
  State<MathInputField> createState() => _MathInputFieldState();
}

class _MathInputFieldState extends State<MathInputField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Fügt [text] an der Cursorposition ein; `(` in [text] setzt den Cursor
  /// hinter die öffnende Klammer.
  void _insert(String text) {
    final c = widget.controller;
    final sel = c.selection;
    final value = c.text;
    final start = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    final next = value.replaceRange(start, end, text);
    c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + text.length));
    _focus.requestFocus();
    widget.onChanged?.call();
    setState(() {});
  }

  List<String> get _keys {
    final f = widget.field;
    final names = {...f.variables, ...f.constants};
    if (f.kind == StepFieldKind.number) return const ['√(', '(', ')', '^', '/', 'π', ','];
    return ['√(', '(', ')', '^', '²', '/', 'π', 'e^(', 'ln(', ...names];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = widget.controller.text;
    String? preview;
    String? error;
    if (text.trim().isNotEmpty) {
      try {
        preview = MathExpression.parse(text, names: widget.field.declaredNames).toLatex();
      } on MathInputException catch (e) {
        error = e.message;
      }
    }
    final verdict = widget.verdict;
    final borderColor = switch (verdict?.kind) {
      FieldVerdictKind.correct => c.good,
      FieldVerdictKind.wrong || FieldVerdictKind.mistake => c.danger,
      FieldVerdictKind.invalid => c.warn,
      _ => c.border,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (widget.field.label.trim().isNotEmpty) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: MathText(_asMath(widget.field.label), style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                key: widget.fieldKey,
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: widget.field.kind == StepFieldKind.number
                    ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                    : TextInputType.text,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.field.kind == StepFieldKind.number ? 'Zahl' : 'Formel',
                  filled: true,
                  fillColor: c.surfaceAlt,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor, width: verdict == null ? 1 : 1.6),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.accent, width: 1.6),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
                onChanged: (_) {
                  widget.onChanged?.call();
                  setState(() {});
                },
                onSubmitted: (_) => widget.onSubmitted?.call(),
              ),
            ),
          ],
        ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Row(
              children: [
                Text('So lese ich es: ', style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
                Flexible(child: MathText('\$$preview\$', style: const TextStyle(fontSize: 14))),
              ],
            ),
          )
        else if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(error, style: TextStyle(fontSize: 11.5, color: c.warn)),
          ),
        if (widget.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in _keys)
                  ActionChip(
                    key: ValueKey('math-key-$k'),
                    label: Text(k, style: const TextStyle(fontSize: 13.5)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _insert(k),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Beschriftungen ohne `$` als Formel setzen ("u' =" → $u' =$), damit
/// Striche und Hochzahlen sauber aussehen; Text mit `$` bleibt, wie er ist.
String _asMath(String label) {
  final t = label.trim();
  if (t.contains(r'$') || t.contains(r'\(')) return t;
  if (RegExp(r'[äöüÄÖÜß]').hasMatch(t) || t.split(' ').length > 4) return t;
  return '\$$t\$';
}

/// Rückmeldung zu einer Prüfung (grün/rot/gelb mit Text).
class VerdictBox extends StatelessWidget {
  const VerdictBox({super.key, required this.verdict});

  final FieldVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg, icon) = switch (verdict.kind) {
      FieldVerdictKind.correct => (c.good, c.goodSoft, Icons.check_circle_outline),
      FieldVerdictKind.wrong || FieldVerdictKind.mistake => (c.danger, c.dangerSoft, Icons.highlight_off),
      _ => (c.warn, c.warnSoft, Icons.info_outline),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: MathText(verdict.message, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink))),
        ],
      ),
    );
  }
}

/// Die Probe der App ("Anfangswert ✓, DGL an der Stelle x = 3 ✗").
class ProbeCard extends StatelessWidget {
  const ProbeCard({super.key, required this.report, this.title = 'Probe – rechnet die App', this.answer});

  final ProbeReport report;
  final String title;

  /// Das eingesetzte Ergebnis (LaTeX oder Text).
  final String? answer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('step-probe'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined, size: 16, color: c.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title.toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkMuted)),
              ),
            ],
          ),
          if (answer != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MathText(answer!, style: const TextStyle(fontSize: 16)),
            ),
          for (final row in report.rows)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(row.ok ? Icons.check_circle : Icons.cancel, size: 18, color: row.ok ? c.good : c.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(row.detail, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (report.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(report.note, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ),
        ],
      ),
    );
  }
}
