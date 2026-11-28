import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../services/answer_signals.dart';
import '../../services/panik_import.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Rechenaufgabe des Panik-Modus, auf Papier gelöst: Die App kann die
/// Handschrift nicht lesen – also deckt man nach dem Rechnen die Lösung
/// Schritt für Schritt auf und markiert jeden Schritt mit „stimmt“ oder
/// „hier falsch“. Beim ersten Fehler wählt man die Ursache (Fehlerprotokoll,
/// siehe [ErrorCause]), danach ist der ganze Lösungsweg zu sehen.
///
/// Ergebnis über [onComplete]:
/// - alles gestimmt → richtig, „ging leicht“ = Sicherheit „sicher“
///   (Wechselkriterium: danach keine Beispiele mehr für diesen Typ);
/// - ein Fehler → falsch mit Ursache und Schritt;
/// - „Ich komme nicht weiter“ → „Weiß ich nicht“.
class PanikPaperView extends StatefulWidget {
  const PanikPaperView({
    super.key,
    required this.card,
    required this.info,
    required this.onComplete,
    this.isNew = false,
    this.onSkip,
  });

  final Flashcard card;
  final PanikCardInfo info;
  final void Function({required bool isCorrect, required AnswerSignals signals}) onComplete;
  final bool isNew;
  final VoidCallback? onSkip;

  @override
  State<PanikPaperView> createState() => _PanikPaperViewState();
}

/// Wo man gerade ist.
enum _Phase { solving, checking, chooseCause, finished }

class _PanikPaperViewState extends State<PanikPaperView> {
  _Phase _phase = _Phase.solving;

  /// Wie viele Schritte aufgedeckt sind.
  int _shown = 0;

  /// Index des ersten falschen Schritts (null = bisher alles richtig).
  int? _wrongAt;
  ErrorCause? _cause;
  bool _stuck = false;
  bool _sent = false;

  int get _total => widget.info.steps.length;

  void _reveal() => setState(() {
        _phase = _Phase.checking;
        _shown = 1;
      });

  void _stepOk() => setState(() {
        if (_shown < _total) {
          _shown++;
        } else {
          _phase = _Phase.finished;
        }
      });

  void _stepWrong() => setState(() {
        _wrongAt = _shown - 1;
        _phase = _Phase.chooseCause;
      });

  void _chooseCause(ErrorCause cause) => setState(() {
        _cause = cause;
        _shown = _total;
        _phase = _Phase.finished;
      });

  void _giveUp() => setState(() {
        _stuck = true;
        _shown = _total;
        _phase = _Phase.finished;
      });

  void _send({required bool isCorrect, AnswerSignals signals = AnswerSignals.none}) {
    if (_sent) return;
    _sent = true;
    widget.onComplete(isCorrect: isCorrect, signals: signals);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allRight = _phase == _Phase.finished && _wrongAt == null && !_stuck;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (widget.isNew) _chip(c, 'NEU', c.warnSoft, c.warn),
            _chip(c, 'Auf Papier rechnen', c.accentSoft, c.accentOnSoft),
            if (!widget.info.verified) _chip(c, 'Lösung ungeprüft', c.dangerSoft, c.danger),
          ],
        ),
        const SizedBox(height: 10),
        _box(c, MathText(widget.card.front, style: TextStyle(fontSize: 16, color: c.ink, height: 1.4))),
        const SizedBox(height: 16),
        if (_phase == _Phase.solving) ...[
          Text('Rechne die Aufgabe vollständig auf Papier. Danach deckst du die Lösung Schritt für Schritt auf.',
              style: TextStyle(color: c.inkMuted, height: 1.4)),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('panik-reveal'),
            onPressed: _reveal,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Gerechnet – Lösung aufdecken'),
          ),
          TextButton(
            key: const ValueKey('panik-stuck'),
            onPressed: _giveUp,
            child: const Text('Ich komme nicht weiter – ganze Lösung zeigen'),
          ),
          if (widget.onSkip != null) TextButton(onPressed: widget.onSkip, child: const Text('Überspringen')),
        ],
        for (var i = 0; i < _shown; i++) _stepTile(c, i),
        if (_phase == _Phase.checking) ...[
          const SizedBox(height: 4),
          Text('Stimmt dieser Schritt mit deiner Rechnung überein?', style: TextStyle(color: c.inkMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('panik-ok'),
                  onPressed: _stepOk,
                  icon: const Icon(Icons.check),
                  label: const Text('Stimmt'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('panik-wrong'),
                  onPressed: _stepWrong,
                  icon: const Icon(Icons.close),
                  label: const Text('Hier falsch'),
                ),
              ),
            ],
          ),
        ],
        if (_phase == _Phase.chooseCause) ...[
          const SizedBox(height: 4),
          Text('Was ist in Schritt ${_wrongAt! + 1} schiefgegangen?', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cause in ErrorCause.values)
                ActionChip(key: ValueKey('panik-cause-${cause.name}'), label: Text(cause.label), onPressed: () => _chooseCause(cause)),
            ],
          ),
        ],
        if (_phase == _Phase.finished) ...[
          _box(c, MathText('Ergebnis: \$${widget.info.answer}\$', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
              color: allRight ? c.goodSoft : c.surfaceAlt),
          const SizedBox(height: 12),
          if (allRight) ...[
            Text('Alles richtig! Wie lief es?', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('panik-easy'),
              onPressed: () => _send(isCorrect: true, signals: const AnswerSignals(confidence: AnswerConfidence.sure)),
              child: const Text('Ging leicht – ohne Hilfe'),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              key: const ValueKey('panik-hard'),
              onPressed: () => _send(isCorrect: true, signals: const AnswerSignals(confidence: AnswerConfidence.unsure)),
              child: const Text('Ging, aber mühsam'),
            ),
          ] else ...[
            Text(
              _stuck
                  ? 'Kein Problem: Geh den Lösungsweg durch – die Aufgabe kommt bald in ähnlicher Form wieder.'
                  : 'Fehler in Schritt ${_wrongAt! + 1} (${_cause!.label}) – notiert. Eine ähnliche Aufgabe kommt in ein paar Tagen wieder.',
              style: TextStyle(color: c.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('panik-done'),
              onPressed: () => _send(
                isCorrect: false,
                signals: _stuck ? const AnswerSignals(dontKnow: true) : AnswerSignals(errorCause: _cause, errorStep: _wrongAt! + 1),
              ),
              child: const Text('Weiter'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _stepTile(AppColors c, int i) {
    final step = widget.info.steps[i];
    final wrong = _wrongAt == i;
    return Container(
      key: ValueKey('panik-step-$i'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: wrong ? c.dangerSoft : c.surface,
        border: Border.all(color: wrong ? c.danger : c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prinzip-Etikett: WARUM dieser Schritt (kurz).
          Text('${i + 1}. ${step.label}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
          const SizedBox(height: 6),
          MathText('\$${step.result}\$', style: TextStyle(fontSize: 15, color: c.ink)),
        ],
      ),
    );
  }

  Widget _box(AppColors c, Widget child, {Color? color}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color ?? c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  Widget _chip(AppColors c, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}
