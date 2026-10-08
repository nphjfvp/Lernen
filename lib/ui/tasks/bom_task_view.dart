import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/bom_task.dart';
import '../../models/flashcard.dart';
import '../../services/bom_calculator.dart';
import '../../services/fsrs_service.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../widgets/math_text.dart';
import '../widgets/zoomable_image.dart';
import 'bom_tree.dart';

/// Eine eingetragene Zeile.
class _Row {
  _Row(this.number);

  String number;
  final level = TextEditingController();
  final qty = TextEditingController();
  int? ak;

  BomInput get input => BomInput(
    number: number,
    level: int.tryParse(level.text.trim()),
    quantity: qty.text.trim().isEmpty ? null : parseBomQuantity(qty.text),
    ak: ak,
  );

  void dispose() {
    level.dispose();
    qty.dispose();
  }
}

/// Stand einer Teilaufgabe.
class _PartState {
  final rows = <_Row>[];

  /// Baukasten: Listen (Sach-Nr. der Baugruppe → Zeilen), in Anlege-Reihenfolge.
  final lists = <String, List<_Row>>{};
  String? activeList;
  BomVerdict? verdict;
  bool solved = false;
  bool revealed = false;
  int wrong = 0;
  int hintsShown = 0;

  Iterable<_Row> get allRows => [...rows, for (final l in lists.values) ...l];

  void dispose() {
    for (final r in allRows) {
      r.dispose();
    }
  }
}

/// Stückliste beantworten ([QuestionType.bom]): die App zeichnet den
/// Erzeugnisbaum, der Nutzer füllt die Liste aus (Teil im Baum antippen
/// fügt eine Zeile hinzu), die App prüft jede Zeile mit konkreter
/// Rückmeldung (BomCalculator).
///
/// Bewertung beim "Weiter": ohne Fehlversuch und Tipp = gewusst, sonst
/// Schwer; eine Lösung angesehen oder aufgelöst = Nochmal. Probeklausur:
/// keine Rückmeldung, "Antwort abgeben" wertet alle Teile.
class BomTaskView extends StatefulWidget {
  const BomTaskView({
    super.key,
    required this.card,
    required this.task,
    required this.isNew,
    required this.onComplete,
    this.examMode = false,
    this.onSkip,
    this.canGiveUp = false,
  });

  final Flashcard card;
  final BomTask task;
  final bool isNew;
  final bool examMode;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  @override
  State<BomTaskView> createState() => _BomTaskViewState();
}

class _BomTaskViewState extends State<BomTaskView> {
  late final BomCalculator _calc = BomCalculator(widget.task);
  late final List<_PartState> _parts = [
    for (final p in widget.task.parts)
      _PartState()
        ..lists.addAll({for (final l in p.lists) l: <_Row>[]})
        ..activeList = p.lists.firstOrNull,
  ];
  late final Set<String> _assemblies = _calc.assemblies().toSet();
  int _current = 0;
  bool _gaveUp = false;
  bool _submitted = false;

  BomPart get _part => widget.task.parts[_current];
  _PartState get _state => _parts[_current];
  bool get _allDone => _gaveUp || _parts.every((p) => p.solved || p.revealed);

  @override
  void dispose() {
    for (final p in _parts) {
      p.dispose();
    }
    super.dispose();
  }

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _finish() {
    if (_gaveUp || _parts.any((p) => p.revealed)) return _submit(isCorrect: false);
    final clean = _parts.every((p) => p.wrong == 0 && p.hintsShown == 0);
    if (clean) return _submit(isCorrect: true);
    _submit(isCorrect: true, selfGrade: Grade.hard);
  }

  // ---------------------------------------------------------------------------
  // Eingaben
  // ---------------------------------------------------------------------------

  void _changed() {
    if (_state.verdict != null) setState(() => _state.verdict = null);
  }

  void _addRow(String number, {String? list}) {
    final s = _state;
    setState(() {
      s.verdict = null;
      if (_part.kind == BomListKind.modular) {
        final target = list ?? s.activeList;
        if (target == null) return;
        s.lists[target]!.add(_Row(number));
        s.activeList = target;
      } else {
        s.rows.add(_Row(number));
      }
    });
  }

  void _tapNode(String number) {
    if (_state.solved || _state.revealed || _gaveUp) return;
    if (_part.kind == BomListKind.modular && _state.activeList == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lege zuerst eine Liste an („Liste anlegen“), dann Teile antippen.')),
      );
      return;
    }
    _addRow(number);
  }

  void _addList(String number) => setState(() {
    _state.lists.putIfAbsent(number, () => []);
    _state.activeList = number;
    _state.verdict = null;
  });

  void _removeList(String number) => setState(() {
    for (final r in _state.lists.remove(number) ?? const <_Row>[]) {
      r.dispose();
    }
    if (_state.activeList == number) _state.activeList = _state.lists.keys.lastOrNull;
    _state.verdict = null;
  });

  void _removeRow(List<_Row> from, _Row row) => setState(() {
    from.remove(row);
    row.dispose();
    _state.verdict = null;
  });

  BomVerdict _judge(BomPart part, _PartState s) => switch (part.kind) {
    BomListKind.overview => _calc.checkOverview(part, [for (final r in s.rows) r.input]),
    BomListKind.structure => _calc.checkStructure(part, [for (final r in s.rows) r.input]),
    BomListKind.modular => _calc.checkModular(part, {
      for (final e in s.lists.entries) e.key: [for (final r in e.value) r.input],
    }),
  };

  void _check() {
    if (widget.examMode) {
      final ok = [for (final (i, p) in widget.task.parts.indexed) _judge(p, _parts[i]).ok].every((b) => b);
      _submit(isCorrect: ok);
      return;
    }
    final s = _state;
    final v = _judge(_part, s);
    setState(() {
      s.verdict = v;
      if (v.ok) {
        s.solved = true;
      } else {
        s.wrong++;
      }
    });
  }

  void _reveal() => setState(() => _state.revealed = true);

  void _giveUp() => setState(() {
    _gaveUp = true;
    for (final p in _parts) {
      if (!p.solved) p.revealed = true;
    }
  });

  // ---------------------------------------------------------------------------
  // Anzeige
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.card;
    final part = _part, s = _state;
    final hints = _calc.hints(part);
    final finishedPart = s.solved || s.revealed || _gaveUp;
    final nextIndex = [
      for (var i = 0; i < _parts.length; i++)
        if (i != _current && !_parts[i].solved && !_parts[i].revealed) i,
    ].firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (widget.isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
              child: Text(
                'NEU',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        QuestionType.bom.label,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (!widget.examMode) SourceLinkButton(card: card),
                ],
              ),
              const SizedBox(height: 10),
              if (card.imageBase64 != null) _image(card.imageBase64!),
              MathText(card.front, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.45)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        BomTreeView(root: widget.task.root, assemblies: _assemblies, onTapNode: finishedPart ? null : _tapNode),
        const SizedBox(height: 12),
        if (widget.task.parts.length > 1) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, p) in widget.task.parts.indexed)
                ChoiceChip(
                  key: ValueKey('bom-part-$i'),
                  selected: i == _current,
                  showCheckmark: false,
                  avatar: _parts[i].solved && !widget.examMode
                      ? Icon(Icons.check_circle, size: 16, color: c.good)
                      : (_parts[i].revealed ? Icon(Icons.visibility_outlined, size: 16, color: c.warn) : null),
                  label: Text('${String.fromCharCode(97 + i)}  ${p.kind.short}'),
                  onSelected: (_) => setState(() => _current = i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Container(
          key: const ValueKey('bom-prompt'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
          child: Text(
            '${part.promptText}${finishedPart ? '' : '\nTippe ein Teil im Baum an, um es als Zeile einzutragen.'}',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        if (s.revealed || (_gaveUp && !s.solved))
          Container(
            key: const ValueKey('bom-solution'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _gaveUp ? 'Aufgelöst – zählt als nicht gewusst.' : 'Lösung angesehen – zählt als „Nochmal“.',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                BomSolutionTables(calc: _calc, part: part),
              ],
            ),
          )
        else if (part.kind == BomListKind.modular)
          ..._modularEditor(c, s, finishedPart)
        else
          _rowsEditor(c, s.rows, finishedPart, verdictOffset: 0, prefix: 'bom-row'),
        if (s.verdict != null && !widget.examMode) ...[const SizedBox(height: 10), _verdictBox(c, s.verdict!)],
        if (!widget.examMode)
          for (var h = 0; h < s.hintsShown && h < hints.length; h++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                key: ValueKey('bom-hint-$h'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: c.warn),
                    const SizedBox(width: 8),
                    Expanded(child: Text(hints[h], style: const TextStyle(fontSize: 13.5, height: 1.4))),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        ..._buttons(c, hints.length, finishedPart, nextIndex),
      ],
    );
  }

  Widget _image(String base64) {
    try {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ZoomableImage(bytes: base64Decode(base64)),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  /// Auswahl einer Sach-Nr. aus dem Baum (für neue Zeilen / Listen).
  Widget _picker({
    required Key key,
    required Widget child,
    required ValueChanged<String> onPicked,
    Iterable<String>? only,
  }) {
    final numbers = only?.toList() ?? _calc.numbers();
    return PopupMenuButton<String>(
      key: key,
      tooltip: 'Sach-Nr. wählen',
      onSelected: onPicked,
      itemBuilder: (_) => [for (final n in numbers) PopupMenuItem(value: n, child: Text(_calc.label(n)))],
      child: child,
    );
  }

  /// Zeilen einer Liste. [verdictOffset]: Index der ersten Zeile in
  /// BomVerdict.rows (Baukasten: alle Listen hintereinander).
  Widget _rowsEditor(
    AppColors c,
    List<_Row> rows,
    bool locked, {
    required int verdictOffset,
    required String prefix,
    String? list,
  }) {
    final kind = _part.kind;
    final verdict = widget.examMode ? null : _state.verdict;
    final headers = [
      kind == BomListKind.structure ? 'Stufe' : 'Pos.',
      'Sach-Nr. / Bezeichnung',
      'Menge',
      if (kind == BomListKind.modular) 'AK',
    ];
    TextStyle head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.inkMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              SizedBox(width: 52, child: Text(headers[0], style: head)),
              Expanded(child: Text(headers[1], style: head)),
              SizedBox(width: 78, child: Text(headers[2], style: head)),
              if (kind == BomListKind.modular) SizedBox(width: 78, child: Text(headers[3], style: head)),
              const SizedBox(width: 36),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (final (i, row) in rows.indexed)
          _rowTile(
            c,
            rows,
            row,
            i,
            locked,
            verdict?.rows.elementAtOrNull(verdictOffset + i),
            verdict != null,
            '$prefix-$i',
          ),
        if (!locked)
          Align(
            alignment: Alignment.centerLeft,
            child: _picker(
              key: ValueKey('$prefix-add'),
              onPicked: (n) => _addRow(n, list: list),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: c.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Zeile hinzufügen',
                      style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _rowTile(AppColors c, List<_Row> rows, _Row row, int i, bool locked, String? error, bool checked, String key) {
    final kind = _part.kind;
    final ok = checked && error == null;
    final unit = _calc.unitOf(row.number);
    final dense = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.border),
      ),
    );
    return Container(
      key: ValueKey(key),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: !checked ? c.surfaceAlt : (ok ? c.goodSoft : c.dangerSoft),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 52,
                child: kind == BomListKind.structure
                    ? TextField(
                        key: ValueKey('$key-level'),
                        controller: row.level,
                        enabled: !locked,
                        keyboardType: TextInputType.number,
                        decoration: dense.copyWith(hintText: '1'),
                        onChanged: (_) => _changed(),
                      )
                    : Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(color: c.inkMuted, fontWeight: FontWeight.w600),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _picker(
                  key: ValueKey('$key-number'),
                  onPicked: locked
                      ? (_) {}
                      : (n) => setState(() {
                          row.number = n;
                          _state.verdict = null;
                        }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      _calc.label(row.number),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 78,
                child: TextField(
                  key: ValueKey('$key-qty'),
                  controller: row.qty,
                  enabled: !locked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: dense.copyWith(hintText: 'Menge', suffixText: unit.isEmpty ? null : unit),
                  onChanged: (_) => _changed(),
                ),
              ),
              if (kind == BomListKind.modular) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 72,
                  child: Row(
                    children: [
                      for (final ak in const [1, 2])
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Material(
                            color: row.ak == ak ? c.accentSoft : c.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: row.ak == ak ? c.accent : c.border,
                                width: row.ak == ak ? 1.6 : 1,
                              ),
                            ),
                            child: InkWell(
                              key: ValueKey('$key-ak-$ak'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: locked
                                  ? null
                                  : () => setState(() {
                                      row.ak = ak;
                                      _state.verdict = null;
                                    }),
                              child: SizedBox(
                                width: 30,
                                height: 34,
                                child: Center(
                                  child: Text(
                                    '$ak',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: row.ak == ak ? c.accentOnSoft : c.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              SizedBox(
                width: 36,
                child: locked
                    ? null
                    : IconButton(
                        key: ValueKey('$key-delete'),
                        tooltip: 'Zeile löschen',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                        onPressed: () => _removeRow(rows, row),
                      ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
              child: Text(
                error,
                key: ValueKey('$key-error'),
                style: TextStyle(fontSize: 12.5, height: 1.35, color: c.danger),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _modularEditor(AppColors c, _PartState s, bool locked) {
    final verdict = widget.examMode ? null : s.verdict;
    var offset = 0;
    final out = <Widget>[];
    for (final entry in s.lists.entries) {
      final list = entry.key;
      final active = s.activeList == list;
      final problem = verdict?.listProblems[list];
      out.add(
        Container(
          key: ValueKey('bom-list-$list'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: active && !locked ? c.accent : c.border, width: active && !locked ? 1.6 : 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey('bom-list-$list-select'),
                onTap: locked ? null : () => setState(() => s.activeList = list),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${BomListKind.modular.label} ${_calc.label(list)}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!locked && !_part.lists.contains(list))
                      IconButton(
                        key: ValueKey('bom-list-$list-remove'),
                        tooltip: 'Liste entfernen',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.delete_outline, size: 18, color: c.inkMuted),
                        onPressed: () => _removeList(list),
                      ),
                  ],
                ),
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    problem,
                    key: ValueKey('bom-list-$list-error'),
                    style: TextStyle(fontSize: 12.5, color: c.danger),
                  ),
                ),
              _rowsEditor(c, entry.value, locked, verdictOffset: offset, prefix: 'bom-$list-row', list: list),
            ],
          ),
        ),
      );
      offset += entry.value.length;
    }
    if (!locked && _part.lists.isEmpty) {
      final free = [
        for (final n in _calc.numbers())
          if (!s.lists.containsKey(n)) n,
      ];
      out.add(
        Align(
          alignment: Alignment.centerLeft,
          child: _picker(
            key: const ValueKey('bom-add-list'),
            only: free,
            onPicked: _addList,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                border: Border.all(color: c.accent),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_add, size: 18, color: c.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Liste anlegen',
                    style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _verdictBox(AppColors c, BomVerdict v) => Container(
    key: const ValueKey('bom-verdict'),
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: v.ok ? c.goodSoft : c.dangerSoft, borderRadius: BorderRadius.circular(14)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(v.ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: v.ok ? c.good : c.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            v.summary,
            style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w500, color: v.ok ? c.good : c.danger),
          ),
        ),
      ],
    ),
  );

  List<Widget> _buttons(AppColors c, int hintCount, bool finishedPart, int? nextIndex) {
    final s = _state;
    if (widget.examMode) {
      return [
        if (_parts.length > 1)
          OutlinedButton(
            key: const ValueKey('bom-next-part'),
            onPressed: () => setState(() => _current = (_current + 1) % _parts.length),
            child: const Text('Nächste Teilaufgabe'),
          ),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('bom-submit'), onPressed: _check, child: const Text('Antwort abgeben')),
      ];
    }
    if (_allDone) {
      final anyRevealed = _gaveUp || _parts.any((p) => p.revealed);
      final clean = !anyRevealed && _parts.every((p) => p.wrong == 0 && p.hintsShown == 0);
      return [
        Container(
          key: const ValueKey('bom-finished'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: clean ? c.goodSoft : (anyRevealed ? c.warnSoft : c.accentSoft),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _gaveUp
                ? 'Aufgelöst – zählt als nicht gewusst'
                : anyRevealed
                ? 'Mit angesehener Lösung – zählt als „Nochmal“'
                : (clean ? 'Alles gelöst – ohne Hilfe' : 'Alles gelöst – mit Hilfe, zählt als „Schwer“'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(key: const ValueKey('bom-next'), onPressed: _finish, child: const Text('Weiter')),
      ];
    }
    if (finishedPart) {
      return [
        FilledButton(
          key: const ValueKey('bom-next-part'),
          onPressed: nextIndex == null ? null : () => setState(() => _current = nextIndex),
          child: Text(
            nextIndex == null
                ? 'Weiter'
                : 'Weiter zu ${String.fromCharCode(97 + nextIndex)}  ${widget.task.parts[nextIndex].kind.short}',
          ),
        ),
      ];
    }
    return [
      Row(
        children: [
          OutlinedButton.icon(
            key: const ValueKey('bom-hint-button'),
            onPressed: s.hintsShown >= hintCount ? null : () => setState(() => s.hintsShown++),
            icon: const Icon(Icons.lightbulb_outline, size: 18),
            label: const Text('Tipp'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(key: const ValueKey('bom-check'), onPressed: _check, child: const Text('Prüfen')),
          ),
        ],
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(key: const ValueKey('bom-reveal'), onPressed: _reveal, child: const Text('Lösung zeigen')),
          if (widget.onSkip != null)
            TextButton(
              key: const ValueKey('question-skip'),
              onPressed: () {
                if (_submitted) return;
                _submitted = true;
                widget.onSkip!();
              },
              child: const Text('Überspringen'),
            ),
          if (widget.canGiveUp)
            TextButton(key: const ValueKey('question-give-up'), onPressed: _giveUp, child: const Text('Auflösen')),
        ],
      ),
    ];
  }
}
