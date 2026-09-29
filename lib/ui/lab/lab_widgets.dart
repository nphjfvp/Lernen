import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/lab_experiment.dart';
import '../../services/lab_context_service.dart';
import '../../theme/app_colors.dart';

/// "heute", "morgen", "in 5 Tagen", "vor 2 Tagen" …
String labDayText(int days) => switch (days) {
      0 => 'heute',
      1 => 'morgen',
      -1 => 'gestern',
      > 1 => 'in $days Tagen',
      _ => 'vor ${-days} Tagen',
    };

/// Eine Zeile zum Stand des Versuchs (Fach-Abschnitt, Startseite).
String labStatusLine(LabExperiment e, DateTime now) {
  final days = e.daysUntilLab(now);
  final due = e.daysUntilReport(now);
  return switch (e.phase(now)) {
    LabPhase.done => 'Bericht abgegeben',
    LabPhase.preparation => [
        if (days != null) 'Versuch ${labDayText(days)}' else 'Noch kein Termin',
        if (e.prepTotal > 0) 'Vorbereitung ${e.prepAnswered}/${e.prepTotal}',
      ].join(' · '),
    LabPhase.labDay => [
        'Heute Versuch',
        if (e.stepsTotal > 0) 'Schritte ${e.stepsDone}/${e.stepsTotal}',
      ].join(' · '),
    LabPhase.report => [
        'Bericht ${e.reportWritten}/${e.reportTotal}',
        if (due != null) 'Abgabe ${labDayText(due)}',
      ].join(' · '),
  };
}

/// Was auf der Startseite zu einem Fach an Laborversuchen anliegt: die
/// Vorbereitung eines bald anstehenden Versuchs, die noch nicht komplett
/// beantwortet ist, oder ein bald fälliger, noch unfertiger Bericht. Der
/// dringendste (früheste) Fall gewinnt; `null`, wenn nichts anliegt.
String? labHomeHint(Iterable<LabExperiment> experiments, DateTime now, {int withinDays = 14}) {
  ({int days, String text})? best;
  void consider(int days, String text) {
    if (best == null || days < best!.days) best = (days: days, text: text);
  }

  for (final e in experiments) {
    if (e.finished) continue;
    if (e.preparationOverdue(now, withinDays: withinDays)) {
      final days = e.daysUntilLab(now)!;
      consider(days, 'Vorbereitung offen: ${e.title} · Versuch ${labDayText(days)}');
    }
    final due = e.daysUntilReport(now);
    final labPassed = (e.daysUntilLab(now) ?? 1) <= 0;
    if (labPassed && due != null && due <= 7 && e.reportWritten < e.reportTotal) {
      consider(due, 'Bericht offen: ${e.title} · Abgabe ${labDayText(due)}');
    }
  }
  return best?.text;
}

/// Kurzer Titel eines Einschätzungs-Urteils.
String labVerdictLabel(String verdict) => switch (verdict) {
      'gut' => 'Passt',
      'teilweise' => 'Teilweise',
      'leer' => 'Noch leer',
      _ => 'Noch nicht getroffen',
    };

({Color fg, Color bg}) _verdictColors(AppColors c, String verdict) => switch (verdict) {
      'gut' => (fg: c.good, bg: c.goodSoft),
      'teilweise' => (fg: c.warn, bg: c.warnSoft),
      'leer' => (fg: c.inkMuted, bg: c.surfaceAlt),
      _ => (fg: c.danger, bg: c.dangerSoft),
    };

/// Textfeld, das nach einer kurzen Pause (und beim Verlassen) von selbst
/// speichert – Eingaben gehen nicht verloren, auch wenn man den Bildschirm
/// sofort schließt.
class LabAnswerField extends StatefulWidget {
  const LabAnswerField({
    super.key,
    required this.initial,
    required this.onSave,
    this.hint,
    this.minLines = 3,
    this.maxLines = 14,
    this.dense = false,
    this.textAlign = TextAlign.start,
  });

  final String initial;
  final ValueChanged<String> onSave;
  final String? hint;
  final int minLines;
  final int maxLines;

  /// Einzeilig und klein, für Tabellenzellen.
  final bool dense;
  final TextAlign textAlign;

  @override
  State<LabAnswerField> createState() => _LabAnswerFieldState();
}

class _LabAnswerFieldState extends State<LabAnswerField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  late String _saved = widget.initial;
  Timer? _timer;

  void _schedule(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 700), _flush);
  }

  void _flush() {
    _timer?.cancel();
    if (_controller.text == _saved) return;
    _saved = _controller.text;
    widget.onSave(_saved);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Noch nicht Gespeichertes geht nicht verloren – aber erst nach dem Aufräumen
    // des Baums: Speichern benachrichtigt die Oberfläche, und das darf nicht
    // mitten im Abbau geschehen.
    if (_controller.text != _saved) {
      final text = _controller.text;
      final save = widget.onSave;
      scheduleMicrotask(() => save(text));
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        if (!focused) _flush();
      },
      child: TextField(
        controller: _controller,
        onChanged: _schedule,
        onEditingComplete: () {
          _flush();
          FocusScope.of(context).nextFocus();
        },
        textAlign: widget.textAlign,
        keyboardType: widget.dense ? TextInputType.text : TextInputType.multiline,
        minLines: widget.dense ? 1 : widget.minLines,
        maxLines: widget.dense ? 1 : widget.maxLines,
        style: TextStyle(fontSize: widget.dense ? 13 : 14.5, height: widget.dense ? 1.2 : 1.4),
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          contentPadding: widget.dense
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 9)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// Fortschrittsbalken mit Beschriftung ("3 von 8 beantwortet").
class LabProgressLine extends StatelessWidget {
  const LabProgressLine({super.key, required this.done, required this.total, required this.label});

  final int done;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
            backgroundColor: c.surfaceAlt,
            color: done >= total && total > 0 ? c.good : c.accent,
          ),
        ),
      ],
    );
  }
}

/// Karte mit abgerundetem Rand im Stil der übrigen Fach-Bildschirme.
class LabCard extends StatelessWidget {
  const LabCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.tint});

  final Widget child;
  final EdgeInsets padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      // Eigenes (durchsichtiges) Material: ListTile/Checkbox darin zeichnen ihre
      // Wischeffekte sonst unter dem Hintergrund der Karte.
      child: Material(type: MaterialType.transparency, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Die Einschätzung der KI zu einer Antwort bzw. einem Abschnitt.
class LabFeedbackView extends StatelessWidget {
  const LabFeedbackView({
    super.key,
    required this.feedback,
    required this.currentText,
    this.references = const [],
    this.onOpenReference,
  });

  final LabFeedback feedback;

  /// Aktueller Text – weicht er vom begutachteten ab, ist die Einschätzung veraltet.
  final String currentText;
  final List<LabReference> references;
  final ValueChanged<LabReference>? onOpenReference;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colors = _verdictColors(c, feedback.verdict);
    final stale = feedback.isStaleFor(currentText);
    return Container(
      key: const ValueKey('lab-feedback'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (feedback.verdict) {
                  'gut' => Icons.check_circle_outline,
                  'teilweise' => Icons.timelapse_rounded,
                  _ => Icons.help_outline_rounded,
                },
                size: 18,
                color: colors.fg,
              ),
              const SizedBox(width: 6),
              Text(labVerdictLabel(feedback.verdict),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: colors.fg)),
              if (stale) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text('· Text seither geändert',
                      overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                ),
              ],
            ],
          ),
          if (feedback.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(feedback.summary, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink)),
          ],
          if (feedback.missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Was noch fehlt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.fg)),
            for (final m in feedback.missing) _Bullet(m),
          ],
          if (feedback.hints.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Zum Nachschauen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.fg)),
            for (final h in feedback.hints) _Bullet(h),
          ],
          if (references.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in references)
                  ActionChip(
                    avatar: const Icon(Icons.menu_book_outlined, size: 15),
                    label: Text(r.label, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: onOpenReference == null ? null : () => onOpenReference!(r),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
          ],
        ),
      );
}

/// Eine Aufgabe (Vorbereitung oder Auswertung) mit eigener Antwort, KI-Gegen-
/// lesen und Nachschlagen im Skript.
class LabQuestionCard extends StatelessWidget {
  const LabQuestionCard({
    super.key,
    required this.question,
    required this.canReview,
    required this.reviewing,
    required this.onAnswer,
    required this.onReview,
    required this.onLookup,
    this.references = const [],
    this.onOpenReference,
    this.onEdit,
    this.onDelete,
    this.hint = 'Deine Antwort in eigenen Worten …',
  });

  final LabQuestion question;
  final bool canReview;
  final bool reviewing;
  final ValueChanged<String> onAnswer;
  final VoidCallback onReview;
  final VoidCallback onLookup;
  final List<LabReference> references;
  final ValueChanged<LabReference>? onOpenReference;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final feedback = question.feedback;
    return LabCard(
      key: ValueKey('lab-question-${question.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (question.number.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 10, top: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(8)),
                  child: Text(question.number,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
                ),
              Expanded(
                child: Text(question.text,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35)),
              ),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  tooltip: 'Aufgabe',
                  icon: Icon(Icons.more_vert, size: 18, color: c.inkMuted),
                  onSelected: (v) => v == 'edit' ? onEdit?.call() : onDelete?.call(),
                  itemBuilder: (_) => [
                    if (onEdit != null) const PopupMenuItem(value: 'edit', child: Text('Aufgabe bearbeiten')),
                    if (onDelete != null) const PopupMenuItem(value: 'delete', child: Text('Aufgabe löschen')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          LabAnswerField(initial: question.answer, onSave: onAnswer, hint: hint),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: canReview && !reviewing && question.answered ? onReview : null,
                icon: reviewing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.rate_review_outlined, size: 18),
                label: Text(feedback == null ? 'Gegenlesen lassen' : 'Erneut gegenlesen'),
              ),
              TextButton.icon(
                onPressed: onLookup,
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Im Skript nachschlagen'),
              ),
            ],
          ),
          if (feedback != null) ...[
            const SizedBox(height: 8),
            LabFeedbackView(
              feedback: feedback,
              currentText: question.answer,
              references: references,
              onOpenReference: onOpenReference,
            ),
          ],
        ],
      ),
    );
  }
}

/// Messwerttabelle: Vorgaben aus der Anleitung fest, leere Zellen zum Ausfüllen.
class LabTableView extends StatelessWidget {
  const LabTableView({super.key, required this.tableKey, required this.table, required this.onCell});

  final String tableKey;
  final LabTable table;
  final void Function(int row, int col, String value) onCell;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final columns = table.columns.isNotEmpty
        ? table.columns.length
        : (table.rows.isEmpty ? 0 : table.rows.first.length);
    if (columns == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (table.title.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(table.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(118),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(color: c.border),
            children: [
              if (table.columns.isNotEmpty)
                TableRow(
                  decoration: BoxDecoration(color: c.surfaceAlt),
                  children: [
                    for (final col in table.columns)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(col, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              for (var r = 0; r < table.rows.length; r++)
                TableRow(
                  children: [
                    for (var col = 0; col < columns; col++)
                      col < table.rows[r].length && table.editable[r][col]
                          ? Padding(
                              padding: const EdgeInsets.all(3),
                              child: LabAnswerField(
                                key: ValueKey('cell-$tableKey-$r-$col'),
                                initial: table.rows[r][col],
                                dense: true,
                                textAlign: TextAlign.center,
                                onSave: (v) => onCell(r, col, v),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(col < table.rows[r].length ? table.rows[r][col] : '',
                                  style: TextStyle(fontSize: 13, color: c.inkMuted)),
                            ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
