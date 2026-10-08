import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/step_task.dart';
import '../../models/step_task_review.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Öffnet das Gespräch mit der KI über die Meldungen der Nachprüfung (siehe
/// [StepTaskReviewSheet]). Liefert die korrigierte Aufgabe, wenn der Nutzer
/// die Korrektur übernimmt, sonst null.
Future<StepTask?> showStepTaskReview(
  BuildContext context, {
  required String taskText,
  required StepTask task,
  required List<String> problems,
}) {
  return showModalBottomSheet<StepTask>(
    context: context,
    isScrollControlled: true,
    builder: (_) => StepTaskReviewSheet(taskText: taskText, task: task, problems: problems),
  );
}

/// „Was heißt das?“: die KI erklärt, was die App beim Nachrechnen gefunden
/// hat (z.B. ein „typischer Fehler“, der in Wahrheit richtig ist), sagt, ob
/// die Aufgabe oder nur eine Rückmeldung falsch ist, und schlägt bei Bedarf
/// eine Korrektur vor. Die App rechnet die Korrektur selbst nach, bevor man
/// sie übernimmt. Nachfragen sind möglich.
class StepTaskReviewSheet extends StatefulWidget {
  const StepTaskReviewSheet({super.key, required this.taskText, required this.task, required this.problems});

  final String taskText;
  final StepTask task;
  final List<String> problems;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  @override
  State<StepTaskReviewSheet> createState() => _StepTaskReviewSheetState();
}

class _StepTaskReviewSheetState extends State<StepTaskReviewSheet> {
  final _question = TextEditingController();
  final List<({String question, StepTaskReview review})> _turns = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask(null));
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  /// Die zuletzt vorgeschlagene Korrektur.
  StepTask? get _corrected => _turns.reversed.map((t) => t.review.corrected).nonNulls.firstOrNull;

  Future<void> _ask(String? question) async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final model = settings.effectiveHelpModelId;
    final ai = StepTaskReviewSheet.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final review = await ai.reviewStepTask(
        taskText: widget.taskText,
        task: widget.task,
        problems: widget.problems,
        question: question,
        history: [
          for (final t in _turns) (question: t.question.isEmpty ? 'Erkläre die Meldungen.' : t.question, answer: t.review.answer),
        ],
      );
      if (!mounted) return;
      setState(() {
        _turns.add((question: question ?? '', review: review));
        _question.clear();
      });
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Anfrage fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final corrected = _corrected;
    final recheck = corrected == null ? null : StepChecker.verify(corrected);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text('Was heißt das? – KI fragen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Divider(height: 1, color: c.border),
              Expanded(
                child: ListView(
                  key: const ValueKey('step-review-list'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Gefunden hat die App:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.warn)),
                          for (final p in widget.problems)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('• $p', style: TextStyle(fontSize: 12.5, color: c.ink)),
                            ),
                        ],
                      ),
                    ),
                    for (final (i, t) in _turns.indexed) ...[
                      if (t.question.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(top: 12, left: 40),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                            child: Text(t.question, style: const TextStyle(fontSize: 13.5)),
                          ),
                        ),
                      Container(
                        key: ValueKey('step-review-answer-$i'),
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (t.review.verdict != StepReviewVerdict.unclear)
                              Container(
                                key: ValueKey('step-review-verdict-$i'),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: t.review.verdict == StepReviewVerdict.solutionWrong ? c.dangerSoft : c.goodSoft,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  t.review.verdict.label,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.review.verdict == StepReviewVerdict.solutionWrong ? c.danger : c.good,
                                  ),
                                ),
                              ),
                            MathText(t.review.answer, style: const TextStyle(fontSize: 13.5, height: 1.45)),
                          ],
                        ),
                      ),
                    ],
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, key: const ValueKey('step-review-error'), style: TextStyle(color: c.danger)),
                      ),
                    if (corrected != null && recheck != null)
                      Container(
                        key: const ValueKey('step-review-fix'),
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: recheck.problems.isEmpty ? c.goodSoft : c.warnSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Korrektur der KI', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              recheck.problems.isEmpty
                                  ? 'Die App hat die korrigierte Aufgabe nachgerechnet: keine Unstimmigkeiten mehr.'
                                  : 'Die App findet in der Korrektur noch: ${recheck.problems.join(' · ')}',
                              style: TextStyle(fontSize: 12.5, color: c.ink),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              key: const ValueKey('step-review-apply'),
                              onPressed: () => Navigator.of(context).pop(corrected),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Korrektur übernehmen'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('step-review-question'),
                        controller: _question,
                        enabled: !_busy,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (v) => v.trim().isEmpty ? null : _ask(v),
                        decoration: const InputDecoration(
                          hintText: 'Nachfragen, z.B. „Ist die Aufgabe jetzt falsch?“',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const ValueKey('step-review-send'),
                      onPressed: _busy ? null : () => _question.text.trim().isEmpty ? null : _ask(_question.text),
                      icon: const Icon(Icons.send, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
