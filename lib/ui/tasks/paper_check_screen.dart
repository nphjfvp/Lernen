import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../models/paper_review.dart';
import '../../models/step_task.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/image_crop.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../study/explain_chat.dart';
import '../widgets/math_text.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'math_input_field.dart';

/// Was nach der Foto-Prüfung passieren soll.
class PaperCheckOutcome {
  const PaperCheckOutcome({this.grade, this.continueAtStep});

  /// Selbst gewählte Bewertung (Aufgabe damit erledigt).
  final Grade? grade;

  /// Ab diesem Schritt (0-basiert) Schritt für Schritt in der App weiter.
  final int? continueAtStep;
}

/// Auf Papier gerechneten Rechenweg fotografieren und prüfen lassen: die KI
/// liest jede Zeile und markiert Fehler und Folgefehler, die App prüft das
/// Endergebnis selbst (Probe + Vergleich mit der Musterlösung).
class PaperCheckScreen extends StatefulWidget {
  const PaperCheckScreen({super.key, required this.card, required this.task});

  final Flashcard card;
  final StepTask task;

  static const maxPhotos = 4;

  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  @visibleForTesting
  static Future<List<({String name, Uint8List bytes})>> Function()? pickImagesHook;

  @override
  State<PaperCheckScreen> createState() => _PaperCheckScreenState();
}

class _PaperCheckScreenState extends State<PaperCheckScreen> with SafeSetState<PaperCheckScreen> {
  final List<Uint8List> _images = [];
  bool _busy = false;
  String? _error;
  String? _raw;
  PaperReview? _review;
  int? _selected;
  bool _chat = false;
  PaperGrade? _grade;

  AiService? _ai() {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    return PaperCheckScreen.aiFactory?.call(settings.openRouterApiKey!, settings.visionModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId);
  }

  Future<void> _pick() async {
    final room = PaperCheckScreen.maxPhotos - _images.length;
    if (room <= 0) return;
    final List<({String name, Uint8List bytes})> picked;
    final hook = PaperCheckScreen.pickImagesHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      picked = [for (final f in files.take(room)) (name: f.name, bytes: await f.readAsBytes())];
    }
    final prepared = [for (final p in picked.take(room)) await prepareImageForAi(p.bytes)];
    if (!mounted) return;
    setState(() => _images.addAll(prepared));
  }

  Future<void> _check() async {
    final ai = _ai();
    if (ai == null) {
      setState(() => _error = 'Zum Prüfen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _raw = null;
    });
    try {
      final review = await ai.reviewPaperSolution(
        task: widget.card.front,
        solution: widget.task,
        solutionText: widget.card.back,
        images: List.of(_images),
      );
      setState(() {
        _review = review;
        _grade = review.grade;
        _selected = review.lines.indexWhere((l) => l.status == PaperLineStatus.error);
        if (_selected == -1) _selected = null;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _raw = e.rawResponse;
      });
    } catch (e) {
      setState(() => _error = 'Prüfen fehlgeschlagen: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
        _review = null;
        _images.clear();
        _selected = null;
        _chat = false;
      });

  static Grade _toGrade(PaperGrade g) => switch (g) {
        PaperGrade.again => Grade.again,
        PaperGrade.hard => Grade.hard,
        PaperGrade.good => Grade.good,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final review = _review;
    return Scaffold(
      appBar: AppBar(title: const Text('Rechenweg prüfen lassen')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
              child: MathText(widget.card.front, style: const TextStyle(fontSize: 14.5, height: 1.4)),
            ),
            const SizedBox(height: 14),
            if (review == null) ..._buildCapture(c) else ..._buildReview(c, review),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCapture(AppColors c) {
    return [
      Text(
        'Rechne auf Papier, wie du es gewohnt bist, und fotografiere den Rechenweg – ganze Seite, gerade von oben, '
        'gutes Licht. Die KI liest jede Zeile und zeigt dir, wo es hakt; das Ergebnis rechnet die App selbst nach.',
        style: TextStyle(fontSize: 13.5, height: 1.45, color: c.inkMuted),
      ),
      const SizedBox(height: 12),
      if (_images.isNotEmpty)
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_images[i], height: 110, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton.filledTonal(
                    tooltip: 'Foto entfernen',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => setState(() => _images.removeAt(i)),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('paper-pick'),
            onPressed: _busy || _images.length >= PaperCheckScreen.maxPhotos ? null : _pick,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(_images.isEmpty ? 'Foto wählen' : 'Weiteres Foto'),
          ),
          FilledButton.icon(
            key: const ValueKey('paper-check'),
            onPressed: _busy || _images.isEmpty ? null : _check,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Prüfen lassen'),
          ),
        ],
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Column(
            children: [
              LinearProgressIndicator(minHeight: 2),
              SizedBox(height: 8),
              Text('Die KI liest deinen Rechenweg …'),
            ],
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!, key: const ValueKey('paper-error'), style: TextStyle(color: c.danger)),
              if (_raw != null)
                TextButton(onPressed: () => showRawResponseDialog(context, _raw!), child: const Text('KI-Antwort ansehen')),
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildReview(AppColors c, PaperReview review) {
    final finalField = widget.task.finalField;
    final answer = review.finalAnswer.trim();
    final finalVerdict = finalField == null || answer.isEmpty ? null : StepChecker.check(finalField, answer);
    final probe = answer.isEmpty ? null : StepChecker.probe(widget.task, answer);
    final selected = _selected;
    final errors = review.hasErrors;
    final grade = _grade ?? review.grade;
    return [
      Container(
        key: const ValueKey('paper-summary'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: errors ? c.dangerSoft : c.goodSoft, borderRadius: BorderRadius.circular(14)),
        child: Text(
          review.summary.isNotEmpty ? review.summary : (errors ? 'Da hakt es noch.' : 'Alles richtig gerechnet.'),
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: errors ? c.danger : c.good),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            for (final (i, line) in review.lines.indexed) ...[
              if (i > 0) Divider(height: 1, color: c.border),
              InkWell(
                key: ValueKey('paper-line-$i'),
                onTap: () => setState(() => _selected = selected == i ? null : i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Text('${line.n}', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                          ),
                          Expanded(child: MathText(line.text, style: const TextStyle(fontSize: 15))),
                          const SizedBox(width: 8),
                          _StatusChip(status: line.status),
                        ],
                      ),
                      if (selected == i && (line.comment.isNotEmpty || line.fix.isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(left: 22, top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (line.comment.isNotEmpty)
                                MathText(line.comment, style: const TextStyle(fontSize: 13.5, height: 1.45)),
                              if (line.fix.isNotEmpty && line.status != PaperLineStatus.ok)
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: c.goodSoft, borderRadius: BorderRadius.circular(10)),
                                  child: MathText('Richtig wäre: ${line.fix}', style: const TextStyle(fontSize: 14)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Zeile antippen für die Erklärung. Falsch gelesen? Neues Foto machen.',
            style: TextStyle(fontSize: 12, color: c.inkMuted)),
      ),
      if (review.firstErrorStep != null && review.firstErrorStep! <= widget.task.steps.length) ...[
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('paper-continue'),
          onPressed: () => Navigator.of(context).pop(PaperCheckOutcome(continueAtStep: review.firstErrorStep! - 1)),
          icon: const Icon(Icons.stairs_outlined, size: 18),
          label: Text('Ab Schritt ${review.firstErrorStep} Schritt für Schritt weiter'),
        ),
      ],
      if (finalVerdict != null) ...[
        const SizedBox(height: 10),
        VerdictBox(
          verdict: FieldVerdict(
            finalVerdict.kind,
            finalVerdict.isCorrect
                ? 'Dein Endergebnis stimmt mit der Musterlösung überein.'
                : 'Dein Endergebnis weicht von der Musterlösung ab.',
          ),
        ),
      ],
      if (probe != null && probe.rows.isNotEmpty) ...[
        const SizedBox(height: 10),
        ProbeCard(report: probe, title: 'Probe deines Ergebnisses – rechnet die App', answer: '\$${_latexOf(answer)}\$'),
      ],
      const SizedBox(height: 10),
      if (!_chat)
        OutlinedButton.icon(
          key: const ValueKey('paper-explain'),
          onPressed: () => setState(() => _chat = true),
          icon: const Icon(Icons.psychology_alt_outlined, size: 18),
          label: Text(errors ? 'Erklär mir den Fehler' : 'Frage zur Lösung stellen'),
        )
      else
        ExplainChat(
          question: widget.card.promptText,
          correctAnswer: widget.card.back.trim().isNotEmpty ? widget.card.back : (finalField?.answer ?? ''),
          userAnswer: review.readText,
          wasCorrect: !errors,
        ),
      const SizedBox(height: 16),
      Text('Wie zählt die Aufgabe?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.inkMuted)),
      const SizedBox(height: 6),
      Row(
        children: [
          for (final g in PaperGrade.values) ...[
            if (g != PaperGrade.values.first) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: ValueKey('paper-grade-${g.name}'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: grade == g ? c.accentSoft : null,
                  side: BorderSide(color: grade == g ? c.accent : c.border, width: grade == g ? 1.6 : 1),
                ),
                onPressed: () {
                  setState(() => _grade = g);
                  Navigator.of(context).pop(PaperCheckOutcome(grade: _toGrade(g)));
                },
                child: Text(switch (g) {
                  PaperGrade.again => 'Nochmal',
                  PaperGrade.hard => 'Schwer',
                  PaperGrade.good => 'Gut',
                }),
              ),
            ),
          ],
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Vorschlag: „${switch (review.grade) {
            PaperGrade.again => 'Nochmal',
            PaperGrade.hard => 'Schwer',
            PaperGrade.good => 'Gut',
          }}“ – du entscheidest.',
          style: TextStyle(fontSize: 12, color: c.inkMuted),
        ),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const ValueKey('paper-again'),
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt, size: 18),
        label: const Text('Neues Foto'),
      ),
    ];
  }

  static String _latexOf(String answer) {
    try {
      return StepChecker.preview(const StepField(label: '', answer: '0'), answer) ?? answer;
    } catch (_) {
      return answer;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PaperLineStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (fg, bg) = switch (status) {
      PaperLineStatus.ok => (c.good, c.goodSoft),
      PaperLineStatus.error => (c.danger, c.dangerSoft),
      PaperLineStatus.follow => (c.warn, c.warnSoft),
      PaperLineStatus.unclear => (c.inkMuted, c.surfaceAlt),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(status.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
