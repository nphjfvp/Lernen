import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../models/paper_review.dart';
import '../../models/step_task.dart';
import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';
import 'hand_math.dart';

/// Gespräch über EINEN Schritt eines selbst gerechneten Rechenwegs – vor oder
/// nach dem Prüfen. Der Verlauf je Zeile bleibt erhalten, solange die Aufgabe
/// offen ist ([history] gehört dem Aufrufer).
class StepLineChat extends StatefulWidget {
  const StepLineChat({
    super.key,
    required this.card,
    required this.task,
    required this.previous,
    required this.line,
    required this.lineNumber,
    required this.history,
    this.check,
    this.ai,
  });

  final Flashcard card;
  final StepTask task;
  final List<String> previous;
  final String line;
  final int lineNumber;
  final PaperLine? check;
  final AiService? ai;

  /// Gespräch über diese Zeile (wird hier ergänzt).
  final List<({bool user, String text})> history;

  /// Vorschläge vor dem Prüfen bzw. nach einem Fehler / nach „richtig“.
  static const before = [
    'Was mache ich in diesem Schritt eigentlich?',
    'Ist mein Ansatz hier sinnvoll?',
    'Erklär mir die Formel bzw. Regel dahinter',
    'Gib mir einen Tipp – ohne die Lösung',
  ];
  static const afterError = [
    'Warum ist das falsch?',
    'Erklär mir die Regel dahinter',
    'Gib mir einen Tipp, wie ich es selbst korrigiere',
  ];
  static const afterOk = ['Warum stimmt das?', 'Wie geht es weiter? Nur ein Tipp, bitte', 'Geht das auch anders?'];

  @override
  State<StepLineChat> createState() => _StepLineChatState();
}

class _StepLineChatState extends State<StepLineChat> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  List<String> get _suggestions => switch (widget.check?.status) {
    null || PaperLineStatus.unclear => StepLineChat.before,
    PaperLineStatus.error || PaperLineStatus.follow => StepLineChat.afterError,
    PaperLineStatus.ok => StepLineChat.afterOk,
  };

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    final ai = widget.ai;
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final history = List.of(widget.history);
    setState(() {
      _busy = true;
      _error = null;
      widget.history.add((user: true, text: q));
      _input.clear();
    });
    try {
      final answer = await ai.discussStep(
        task: widget.card.front,
        solution: widget.task,
        solutionText: widget.card.back,
        previous: widget.previous,
        line: widget.line,
        check: widget.check,
        history: history,
        question: q,
      );
      if (mounted) setState(() => widget.history.add((user: false, text: answer)));
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Das hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final check = widget.check;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Schritt ${widget.lineNumber} besprechen',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
              child: widget.line.trim().isEmpty
                  ? Text('(Zeile noch leer)', style: TextStyle(color: c.inkMuted))
                  : HandMath(widget.line, fontSize: 22, color: const Color(0xFF1F3A93)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                check == null
                    ? 'Noch nicht geprüft – frag ruhig, die KI verrät die Lösung nicht ungefragt.'
                    : 'Geprüft: ${check.status.label}',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, m) in widget.history.indexed)
                    Align(
                      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        key: ValueKey('step-chat-msg-$i'),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 560),
                        decoration: BoxDecoration(
                          color: m.user ? c.accentSoft : c.surface,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: MathText(m.text, style: const TextStyle(fontSize: 14, height: 1.4)),
                      ),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const ValueKey('step-chat-error'),
                      style: TextStyle(color: c.danger),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, s) in _suggestions.indexed)
                  ActionChip(
                    key: ValueKey('step-chat-suggest-$i'),
                    label: Text(s, style: const TextStyle(fontSize: 12.5)),
                    onPressed: _busy ? null : () => _send(s),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('step-chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Deine Frage zu diesem Schritt …',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const ValueKey('step-chat-send'),
                  onPressed: _busy ? null : () => _send(),
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
