import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../services/answer_checker.dart';
import '../../services/fsrs_service.dart';
import '../../theme/app_colors.dart';

/// Rendert und beantwortet EINE Frage, passend zu ihrem [Flashcard.type].
///
/// Der einfache `flashcard`-Typ bleibt beim bisherigen Umdrehen +
/// Selbstbewertung (Nochmal/Schwer/Gut/Leicht). Alle anderen Typen werden
/// automatisch geprüft (siehe AnswerChecker): der Nutzer beantwortet,
/// bekommt sofort Feedback (richtig/falsch + Lösung) und tippt dann auf
/// "Weiter" – die FSRS-Bewertung leitet sich dabei aus der Korrektheit ab
/// (siehe FsrsService.gradeFromResult), keine manuelle Selbsteinschätzung
/// nötig.
///
/// Muss vom Aufrufer mit `key: ValueKey(card.id)` eingebunden werden, damit
/// bei einer neuen Frage ein frischer State (Auswahl/Texteingaben/Drag-
/// Zuordnungen) entsteht, statt alte Eingaben der vorherigen Frage zu zeigen.
class QuestionAnswerView extends StatefulWidget {
  const QuestionAnswerView({
    super.key,
    required this.card,
    required this.isNew,
    required this.onComplete,
  });

  final Flashcard card;
  final bool isNew;

  /// Genau eines von beidem wird gesetzt: [selfGrade] für den offenen
  /// `flashcard`-Typ, [isCorrect] für alle automatisch geprüften Typen.
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;

  @override
  State<QuestionAnswerView> createState() => _QuestionAnswerViewState();
}

class _QuestionAnswerViewState extends State<QuestionAnswerView> {
  bool _showBack = false;

  int? _selectedIndex;
  final Set<int> _selectedIndices = {};
  final _freeTextController = TextEditingController();
  late List<TextEditingController> _blankControllers;

  late List<String> _pool;
  final Map<String, String> _assignments = {};

  bool _checked = false;
  AnswerCheckResult? _result;

  bool get _isCategoryDrag => widget.card.type == QuestionType.dragCategory;

  @override
  void initState() {
    super.initState();
    final blanksCount = widget.card.blanks?.length ?? 0;
    _blankControllers = List.generate(blanksCount, (_) => TextEditingController());
    _pool = (widget.card.dragPairs ?? const []).map((p) => p.source).toList()..shuffle();
  }

  @override
  void dispose() {
    _freeTextController.dispose();
    for (final c in _blankControllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _dropZones {
    final pairs = widget.card.dragPairs ?? const [];
    if (_isCategoryDrag) {
      final seen = <String>{};
      final zones = <String>[];
      for (final p in pairs) {
        if (seen.add(p.target)) zones.add(p.target);
      }
      return zones;
    }
    return pairs.map((p) => p.target).toList();
  }

  void _placeInZone(String source, String zone) {
    if (_checked) return;
    setState(() {
      _assignments.removeWhere((k, v) => _isCategoryDrag ? k == source : v == source);
      _pool.remove(source);
      if (_isCategoryDrag) {
        _assignments[source] = zone;
      } else {
        _assignments[zone] = source;
      }
    });
  }

  void _returnToPool(String source) {
    if (_checked) return;
    setState(() {
      _assignments.removeWhere((k, v) => _isCategoryDrag ? k == source : v == source);
      if (!_pool.contains(source)) _pool.add(source);
    });
  }

  bool get _canCheck {
    switch (widget.card.type) {
      case QuestionType.flashcard:
        return false;
      case QuestionType.singleChoice:
        return _selectedIndex != null;
      case QuestionType.multipleChoice:
        return true;
      case QuestionType.freeText:
        return _freeTextController.text.trim().isNotEmpty;
      case QuestionType.fillBlank:
        return _blankControllers.every((c) => c.text.trim().isNotEmpty);
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return _pool.isEmpty;
    }
  }

  void _check() {
    final card = widget.card;
    final AnswerCheckResult result;
    switch (card.type) {
      case QuestionType.singleChoice:
        result = AnswerChecker.checkSingleChoice(card, _selectedIndex);
      case QuestionType.multipleChoice:
        result = AnswerChecker.checkMultipleChoice(card, _selectedIndices);
      case QuestionType.freeText:
        result = AnswerChecker.checkFreeText(card, _freeTextController.text);
      case QuestionType.fillBlank:
        result = AnswerChecker.checkFillBlank(card, _blankControllers.map((c) => c.text).toList());
      case QuestionType.dragDrop:
        result = AnswerChecker.checkDragDrop(card, Map.of(_assignments));
      case QuestionType.dragCategory:
        result = AnswerChecker.checkDragCategory(card, Map.of(_assignments));
      case QuestionType.flashcard:
        return;
    }
    setState(() {
      _checked = true;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.card.type == QuestionType.flashcard) {
      return _buildFlashcard(c);
    }
    return _buildInteractive(c);
  }

  // ---------------------------------------------------------------------
  // Flashcard: unverändert Umdrehen + Selbstbewertung.
  // ---------------------------------------------------------------------
  Widget _buildFlashcard(AppColors c) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: _showBack ? null : () => setState(() => _showBack = true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _newBadge(c),
                      Text(
                        widget.card.front,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.45),
                      ),
                      if (_showBack) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1, color: c.border),
                        ),
                        Text(
                          widget.card.back,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, height: 1.6, color: c.inkMuted),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        Text('Zum Umdrehen tippen', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            child: Row(
              children: [
                Expanded(
                    child: _ActionButton(
                        label: 'Nochmal',
                        fg: c.danger,
                        bg: c.dangerSoft,
                        onTap: () => widget.onComplete(selfGrade: Grade.again))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: 'Schwer',
                        fg: c.warn,
                        bg: c.warnSoft,
                        onTap: () => widget.onComplete(selfGrade: Grade.hard))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: 'Gut',
                        fg: c.good,
                        bg: c.goodSoft,
                        onTap: () => widget.onComplete(selfGrade: Grade.good))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: 'Leicht',
                        fg: c.accentOnSoft,
                        bg: c.accentSoft,
                        onTap: () => widget.onComplete(selfGrade: Grade.easy))),
              ],
            ),
          )
        else
          const SizedBox(height: 30),
      ],
    );
  }

  Widget _newBadge(AppColors c) {
    if (!widget.isNew) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
        child: Text('NEU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn, letterSpacing: 0.03)),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Automatisch geprüfte Typen: Frage + typspezifische Eingabe + Prüfen/Weiter.
  // ---------------------------------------------------------------------
  Widget _buildInteractive(AppColors c) {
    final card = widget.card;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        _newBadge(c),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                child: Text(card.type.label,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft, letterSpacing: 0.03)),
              ),
              const SizedBox(height: 12),
              if (card.type != QuestionType.fillBlank)
                Text(card.front, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
              const SizedBox(height: 16),
              _buildAnswerInput(c),
            ],
          ),
        ),
        if (_checked) ...[
          const SizedBox(height: 16),
          _buildFeedback(c),
        ],
        const SizedBox(height: 20),
        if (_checked)
          FilledButton(
            onPressed: () => widget.onComplete(isCorrect: _result!.isCorrect),
            child: const Text('Weiter'),
          )
        else
          FilledButton(
            onPressed: _canCheck ? _check : null,
            child: const Text('Prüfen'),
          ),
      ],
    );
  }

  Widget _buildAnswerInput(AppColors c) {
    switch (widget.card.type) {
      case QuestionType.flashcard:
        return const SizedBox.shrink();
      case QuestionType.singleChoice:
        return _buildChoiceOptions(c, multiple: false);
      case QuestionType.multipleChoice:
        return _buildChoiceOptions(c, multiple: true);
      case QuestionType.freeText:
        return TextField(
          controller: _freeTextController,
          enabled: !_checked,
          decoration: InputDecoration(
            hintText: 'Antwort eingeben …',
            filled: true,
            fillColor: c.surfaceAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() {}),
        );
      case QuestionType.fillBlank:
        return _buildFillBlank(c);
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return _buildDragDrop(c);
    }
  }

  Widget _buildChoiceOptions(AppColors c, {required bool multiple}) {
    final options = widget.card.options ?? const [];
    return Column(
      children: List.generate(options.length, (i) {
        final option = options[i];
        final selected = multiple ? _selectedIndices.contains(i) : _selectedIndex == i;
        Color? tileColor;
        IconData? trailingIcon;
        Color? trailingColor;
        if (_checked) {
          if (option.isCorrect) {
            tileColor = c.goodSoft;
            trailingIcon = Icons.check_circle;
            trailingColor = c.good;
          } else if (selected) {
            tileColor = c.dangerSoft;
            trailingIcon = Icons.cancel;
            trailingColor = c.danger;
          }
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _checked
                ? null
                : () => setState(() {
                      if (multiple) {
                        if (_selectedIndices.contains(i)) {
                          _selectedIndices.remove(i);
                        } else {
                          _selectedIndices.add(i);
                        }
                      } else {
                        _selectedIndex = i;
                      }
                    }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: tileColor ?? (selected ? c.accentSoft : c.surfaceAlt),
                border: Border.all(color: selected && tileColor == null ? c.accent : c.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    multiple
                        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                        : (selected ? Icons.radio_button_checked : Icons.radio_button_off),
                    size: 20,
                    color: c.inkMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(option.text)),
                  if (trailingIcon != null) Icon(trailingIcon, size: 18, color: trailingColor),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFillBlank(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.card.front, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 16),
        ...List.generate(_blankControllers.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _blankControllers[i],
              enabled: !_checked,
              decoration: InputDecoration(
                labelText: 'Lücke ${i + 1}',
                filled: true,
                fillColor: c.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDragDrop(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isCategoryDrag ? 'Ordne jeden Begriff der richtigen Kategorie zu.' : 'Ziehe die Begriffe auf die passenden Ziele.',
          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _pool.map((source) => _dragChip(c, source)).toList(),
        ),
        const SizedBox(height: 16),
        ..._dropZones.map((zone) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _dropZone(c, zone),
            )),
      ],
    );
  }

  Widget _dragChip(AppColors c, String source) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
      child: Text(source, style: TextStyle(fontSize: 13, color: c.accentOnSoft, fontWeight: FontWeight.w600)),
    );
    if (_checked) return chip;
    return Draggable<String>(
      data: source,
      feedback: Material(color: Colors.transparent, child: chip),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }

  Widget _dropZone(AppColors c, String zone) {
    final assignedSource = _isCategoryDrag
        ? _assignments.entries.firstWhere((e) => e.value == zone, orElse: () => const MapEntry('', '')).key
        : _assignments[zone];
    final hasAssignment = assignedSource != null && assignedSource.isNotEmpty;

    Color? tileColor;
    if (_checked) {
      final pairs = widget.card.dragPairs ?? const [];
      final correctSource = _isCategoryDrag
          ? null
          : pairs.firstWhere((p) => p.target == zone, orElse: () => const DragPair(source: '', target: '')).source;
      final isRight = _isCategoryDrag
          ? pairs.any((p) => p.source == assignedSource && p.target == zone)
          : assignedSource == correctSource;
      tileColor = isRight ? c.goodSoft : c.dangerSoft;
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => !_checked,
      onAcceptWithDetails: (details) => _placeInZone(details.data, zone),
      builder: (context, candidateData, rejectedData) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: tileColor ?? (candidateData.isNotEmpty ? c.accentSoft : c.surfaceAlt),
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(zone, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (hasAssignment)
                GestureDetector(
                  onTap: _checked ? null : () => _returnToPool(assignedSource),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
                    child: Text(assignedSource, style: TextStyle(fontSize: 12.5, color: c.ink)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeedback(AppColors c) {
    final result = _result!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: result.isCorrect ? c.goodSoft : c.dangerSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: result.isCorrect ? c.good : c.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.isCorrect ? 'Richtig!' : 'Nicht ganz.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: result.isCorrect ? c.good : c.danger)),
                if (!result.isCorrect && result.correctAnswerLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Richtige Antwort: ${result.correctAnswerLabel}', style: TextStyle(fontSize: 13, color: c.ink)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.fg, required this.bg, required this.onTap});
  final String label;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}
