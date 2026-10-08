import 'package:flutter/material.dart';

import '../../models/step_task.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';
import 'math_input_field.dart';
import 'step_task_review_sheet.dart';

/// Ergebnis der App-Nachprüfung einer Rechenweg-Aufgabe: grün, wenn die
/// Musterlösung stimmt (Probe bestanden, alle Antworten lesbar), sonst die
/// gefundenen Probleme.
class StepTaskCheckCard extends StatelessWidget {
  const StepTaskCheckCard({super.key, required this.task, this.onAskAi});

  final StepTask task;

  /// „Was heißt das? KI fragen“ bei Unstimmigkeiten (null = kein Knopf).
  final ValueChanged<List<String>>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final check = StepChecker.verify(task);
    final probe = check.probe;
    final ok = check.ok;
    final finalField = task.finalField;
    return Container(
      key: const ValueKey('step-verify'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: ok ? c.goodSoft : c.warnSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.verified_outlined : Icons.report_problem_outlined, size: 18, color: ok ? c.good : c.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? (probe == null ? 'Alle Antworten lassen sich nachrechnen' : 'Musterlösung von der App nachgerechnet')
                      : 'Bitte prüfen – die App hat Unstimmigkeiten gefunden',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ok ? c.good : c.warn),
                ),
              ),
            ],
          ),
          if (finalField != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MathText(
                '${_math(finalField.label)} \$${StepChecker.preview(finalField, finalField.answer) ?? finalField.answer}\$',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          for (final p in check.problems)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('• $p', style: TextStyle(fontSize: 13, color: c.ink)),
            ),
          if (probe != null)
            for (final row in probe.rows)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(row.ok ? Icons.check_circle : Icons.cancel, size: 16, color: row.ok ? c.good : c.danger),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${row.label}: ${row.detail}', style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
          if (probe != null && probe.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(probe.note, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ),
          if (task.domainNote.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: MathText('Gilt ${task.domainNote}', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              ok
                  ? 'Vorgeschlagen hat die Lösung die KI, nachgerechnet hat sie die App.'
                  : 'Korrigiere die markierten Stellen unten – die Prüfung läuft bei jeder Änderung neu.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ),
          if (!ok && onAskAi != null && check.problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey('step-verify-ask-ai'),
                onPressed: () => onAskAi!(check.problems),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Was heißt das? KI erklären & prüfen lassen'),
              ),
            ),
        ],
      ),
    );
  }

  static String _math(String label) {
    final t = label.trim();
    if (t.isEmpty || t.contains(r'$')) return t;
    return '\$$t\$';
  }
}

class _EditField {
  _EditField(StepField f)
      : label = TextEditingController(text: f.label),
        answer = TextEditingController(text: f.answer),
        variables = TextEditingController(text: f.variables.join(', ')),
        constants = TextEditingController(text: f.constants.join(', ')),
        kind = f.kind,
        tolerance = f.tolerance,
        domain = f.domain,
        mistakes = [for (final m in f.mistakes) (TextEditingController(text: m.answer), TextEditingController(text: m.feedback))];

  final TextEditingController label;
  final TextEditingController answer;
  final TextEditingController variables;
  final TextEditingController constants;
  StepFieldKind kind;
  final double? tolerance;
  final Map<String, (double, double)> domain;
  final List<(TextEditingController, TextEditingController)> mistakes;

  static List<String> _names(String text) =>
      [for (final n in text.split(RegExp(r'[,;\s]+'))) if (n.trim().isNotEmpty) n.trim()];

  StepField build() => StepField(
        label: label.text.trim(),
        answer: answer.text.trim(),
        kind: kind,
        variables: _names(variables.text),
        constants: _names(constants.text),
        tolerance: tolerance,
        domain: domain,
        mistakes: [
          for (final (a, f) in mistakes)
            if (a.text.trim().isNotEmpty) StepMistake(answer: a.text.trim(), feedback: f.text.trim()),
        ],
      );

  void dispose() {
    for (final c in [label, answer, variables, constants, for (final (a, f) in mistakes) ...[a, f]]) {
      c.dispose();
    }
  }
}

class _EditOption {
  _EditOption(StepOption o)
      : text = TextEditingController(text: o.text),
        feedback = TextEditingController(text: o.feedback),
        correct = o.correct;

  final TextEditingController text;
  final TextEditingController feedback;
  bool correct;

  void dispose() {
    text.dispose();
    feedback.dispose();
  }
}

class _EditStep {
  _EditStep(TaskStep s)
      : title = TextEditingController(text: s.title),
        prompt = TextEditingController(text: s.prompt),
        result = TextEditingController(text: s.result),
        explanation = TextEditingController(text: s.explanation),
        hints = [for (var i = 0; i < 2; i++) TextEditingController(text: i < s.hints.length ? s.hints[i] : '')],
        fields = [for (final f in s.fields) _EditField(f)],
        options = [for (final o in s.options) _EditOption(o)];

  final TextEditingController title;
  final TextEditingController prompt;
  final TextEditingController result;
  final TextEditingController explanation;
  final List<TextEditingController> hints;
  final List<_EditField> fields;
  final List<_EditOption> options;

  TaskStep build() => TaskStep(
        title: title.text.trim().isEmpty ? 'Schritt' : title.text.trim(),
        prompt: prompt.text.trim(),
        fields: options.isEmpty ? [for (final f in fields) if (f.answer.text.trim().isNotEmpty) f.build()] : const [],
        options: [for (final o in options) if (o.text.text.trim().isNotEmpty) StepOption(text: o.text.text.trim(), correct: o.correct, feedback: o.feedback.text.trim())],
        hints: [for (final h in hints) if (h.text.trim().isNotEmpty) h.text.trim()],
        result: result.text.trim(),
        explanation: explanation.text.trim(),
      );

  void dispose() {
    for (final c in [title, prompt, result, explanation, ...hints]) {
      c.dispose();
    }
    for (final f in fields) {
      f.dispose();
    }
    for (final o in options) {
      o.dispose();
    }
  }
}

/// Rechenweg-Aufgabe bearbeiten: Schritte (Titel, Frage, Felder mit erwarteter
/// Antwort, Auswahl-Optionen, Tipps, typische Fehler). Jede Änderung geht über
/// [onChanged] hinaus; die Nachprüfung zeigt [StepTaskCheckCard].
class StepTaskEditor extends StatefulWidget {
  const StepTaskEditor({super.key, required this.task, required this.onChanged, this.taskText = ''});

  final StepTask task;
  final ValueChanged<StepTask> onChanged;

  /// Aufgabentext – für die Nachfrage bei der KI (siehe [showStepTaskReview]).
  final String taskText;

  @override
  State<StepTaskEditor> createState() => _StepTaskEditorState();
}

class _StepTaskEditorState extends State<StepTaskEditor> {
  late final List<_EditStep> _steps = [for (final s in widget.task.steps) _EditStep(s)];
  late final _domainNote = TextEditingController(text: widget.task.domainNote);
  late StepTask _current = widget.task;
  late StepProbe? _probe = widget.task.probe;
  late String _finalLabel = widget.task.finalLabel;

  /// Fragt die KI zu den Meldungen; eine übernommene Korrektur ersetzt alle Schritte.
  Future<void> _askAi(List<String> problems) async {
    final fixed = await showStepTaskReview(context, taskText: widget.taskText, task: _current, problems: problems);
    if (fixed == null || !mounted) return;
    setState(() {
      for (final s in _steps) {
        s.dispose();
      }
      _steps
        ..clear()
        ..addAll([for (final s in fixed.steps) _EditStep(s)]);
      _domainNote.text = fixed.domainNote;
      _probe = fixed.probe ?? _probe;
      _finalLabel = fixed.finalLabel.isEmpty ? _finalLabel : fixed.finalLabel;
    });
    _changed();
  }

  @override
  void dispose() {
    for (final s in _steps) {
      s.dispose();
    }
    _domainNote.dispose();
    super.dispose();
  }

  void _changed() {
    final task = StepTask(
      steps: [for (final s in _steps) s.build()],
      probe: _probe,
      domainNote: _domainNote.text.trim(),
      finalLabel: _finalLabel,
    );
    setState(() => _current = task);
    widget.onChanged(task);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTaskCheckCard(task: _current, onAskAi: _askAi),
        const SizedBox(height: 12),
        Text('SCHRITTE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.inkMuted)),
        const SizedBox(height: 6),
        for (final (i, s) in _steps.indexed) _stepTile(c, i, s),
        OutlinedButton.icon(
          key: const ValueKey('step-edit-add'),
          onPressed: () {
            setState(() => _steps.add(_EditStep(const TaskStep(
                  title: 'Neuer Schritt',
                  fields: [StepField(label: '', answer: '')],
                ))));
            _changed();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Schritt hinzufügen'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _domainNote,
          decoration: const InputDecoration(labelText: 'Gültigkeit (optional, z.B. „für x < 6“)', border: OutlineInputBorder()),
          onChanged: (_) => _changed(),
        ),
      ],
    );
  }

  Widget _stepTile(AppColors c, int i, _EditStep s) {
    final step = s.build();
    final kind = step.isChoice
        ? 'Auswahl'
        : (step.fields.length > 1
            ? '${step.fields.length} Felder'
            : (step.fields.firstOrNull?.kind == StepFieldKind.number ? 'Zahl' : 'Formel'));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: c.border), borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        key: ValueKey('step-edit-$i'),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        leading: CircleAvatar(
          radius: 13,
          backgroundColor: c.accentSoft,
          child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
        ),
        title: Text(step.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: MathText(step.resultText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.inkMuted)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(10)),
          child: Text(kind, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.inkMuted)),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _text(s.title, 'Titel'),
          _text(s.prompt, 'Frage an dich', maxLines: 3),
          if (s.options.isNotEmpty) ...[
            Text('Antwortmöglichkeiten (Häkchen = richtig)', style: TextStyle(fontSize: 12, color: c.inkMuted)),
            for (final (k, o) in s.options.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: o.correct,
                      onChanged: (v) {
                        setState(() => o.correct = v ?? false);
                        _changed();
                      },
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _text(o.text, 'Option ${k + 1}', pad: false),
                          const SizedBox(height: 4),
                          _text(o.feedback, o.correct ? 'Rückmeldung (optional)' : 'Warum falsch?', pad: false),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Option entfernen',
                      onPressed: s.options.length <= 2
                          ? null
                          : () {
                              setState(() => s.options.removeAt(k).dispose());
                              _changed();
                            },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () {
                setState(() => s.options.add(_EditOption(const StepOption(text: ''))));
                _changed();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Option'),
            ),
          ] else
            for (final (k, f) in s.fields.indexed) _fieldEditor(c, i, k, s, f),
          const SizedBox(height: 4),
          _text(s.hints[0], 'Tipp 1 (Denkanstoß)', maxLines: 2),
          _text(s.hints[1], 'Tipp 2 (deutlicher)', maxLines: 2),
          _text(s.result, 'Ergebnis zum Anzeigen (LaTeX in \$…\$)'),
          _text(s.explanation, 'Erklärung', maxLines: 3),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('step-edit-delete-$i'),
              onPressed: _steps.length <= 1
                  ? null
                  : () {
                      setState(() => _steps.removeAt(i).dispose());
                      _changed();
                    },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Schritt löschen'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldEditor(AppColors c, int i, int k, _EditStep s, _EditField f) {
    final built = f.build();
    final verdict = built.answer.isEmpty ? null : StepChecker.check(built, built.answer);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _text(f.label, 'Beschriftung (z.B. u′ =)', pad: false)),
              const SizedBox(width: 8),
              DropdownButton<StepFieldKind>(
                value: f.kind,
                items: const [
                  DropdownMenuItem(value: StepFieldKind.formula, child: Text('Formel')),
                  DropdownMenuItem(value: StepFieldKind.number, child: Text('Zahl')),
                ],
                onChanged: (v) {
                  setState(() => f.kind = v ?? f.kind);
                  _changed();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            key: ValueKey('step-edit-answer-$i-$k'),
            controller: f.answer,
            decoration: const InputDecoration(
              labelText: 'Erwartete Antwort (z.B. -1/u, x - sqrt(12 - 2x))',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _changed(),
          ),
          if (built.answer.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: verdict != null && verdict.kind == FieldVerdictKind.correct
                  ? MathText('\$${StepChecker.preview(built, built.answer) ?? built.answer}\$', style: const TextStyle(fontSize: 14))
                  : Text(verdict?.message ?? '', style: TextStyle(fontSize: 12, color: c.warn)),
            ),
          if (f.kind == StepFieldKind.formula) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _text(f.variables, 'Größen (z.B. x)', pad: false)),
                const SizedBox(width: 8),
                Expanded(child: _text(f.constants, 'Konstanten (z.B. C)', pad: false)),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text('Typische Fehler mit eigener Rückmeldung', style: TextStyle(fontSize: 12, color: c.inkMuted)),
          for (final (m, (a, fb)) in f.mistakes.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _text(a, 'Falsche Antwort', pad: false)),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: _text(fb, 'Rückmeldung', pad: false, maxLines: 2)),
                  IconButton(
                    tooltip: 'Entfernen',
                    onPressed: () {
                      setState(() {
                        final removed = f.mistakes.removeAt(m);
                        removed.$1.dispose();
                        removed.$2.dispose();
                      });
                      _changed();
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() => f.mistakes.add((TextEditingController(), TextEditingController())));
                _changed();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Typischer Fehler'),
            ),
          ),
          if (s.fields.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() => s.fields.removeAt(k).dispose());
                  _changed();
                },
                child: const Text('Feld entfernen'),
              ),
            ),
          if (k == s.fields.length - 1 && s.fields.length < 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() => s.fields.add(_EditField(const StepField(label: '', answer: ''))));
                  _changed();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Weiteres Feld'),
              ),
            ),
          if (verdict != null && verdict.kind != FieldVerdictKind.correct)
            Padding(padding: const EdgeInsets.only(top: 6), child: VerdictBox(verdict: verdict)),
        ],
      ),
    );
  }

  Widget _text(TextEditingController controller, String label, {int maxLines = 1, bool pad = true}) {
    final field = TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: 1,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      onChanged: (_) => _changed(),
    );
    return pad ? Padding(padding: const EdgeInsets.only(bottom: 8), child: field) : field;
  }
}
