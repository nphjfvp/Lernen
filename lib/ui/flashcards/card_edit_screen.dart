import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../services/question_parsing.dart';

/// Öffnet den Editor für den Inhalt einer Karte (jeder Fragetyp) und liefert
/// die geänderte Karte – oder `null` bei Abbruch. Lernstand, Typ und
/// Stufenkette bleiben unverändert (siehe [Flashcard.copyWithContent]).
Future<Flashcard?> showCardEditor(BuildContext context, Flashcard card) {
  return Navigator.of(context).push<Flashcard>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => CardEditScreen(card: card)),
  );
}

/// Von der KI erzeugte Fragen sind nicht immer richtig – hier lässt sich
/// jede Karte korrigieren statt sie nur löschen zu können: Frage, Antwort-
/// optionen und welche davon stimmen, Musterantwort, Lücken, Zuordnungs-
/// paare. Bildstellen/-bereiche bearbeitet der Bild-Editor.
class CardEditScreen extends StatefulWidget {
  const CardEditScreen({super.key, required this.card});

  final Flashcard card;

  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _OptionRow {
  _OptionRow(String text, this.isCorrect) : controller = TextEditingController(text: text);
  final TextEditingController controller;
  bool isCorrect;
}

class _PairRow {
  _PairRow(String source, String target)
      : source = TextEditingController(text: source),
        target = TextEditingController(text: target);
  final TextEditingController source;
  final TextEditingController target;
}

class _TableEditCell {
  _TableEditCell(String text, this.given) : controller = TextEditingController(text: text);
  final TextEditingController controller;

  /// true = vorgegeben (wird angezeigt), false = auszufüllen (Text ist die Lösung).
  bool given;
}

class _CardEditScreenState extends State<CardEditScreen> {
  late final TextEditingController _front;
  late final TextEditingController _back;
  late final TextEditingController _correctText;
  final List<_OptionRow> _options = [];
  final List<_PairRow> _pairs = [];
  final List<TextEditingController> _blanks = [];
  final List<List<_TableEditCell>> _table = [];
  String? _error;

  QuestionType get _type => widget.card.type;
  bool get _isChoice => _type == QuestionType.singleChoice || _type == QuestionType.multipleChoice;
  bool get _isDrag => _type == QuestionType.dragDrop || _type == QuestionType.dragCategory;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _front = TextEditingController(text: card.front);
    _back = TextEditingController(text: card.back);
    _correctText = TextEditingController(text: card.correctText ?? '');
    for (final o in card.options ?? const <QuizOption>[]) {
      _options.add(_OptionRow(o.text, o.isCorrect));
    }
    if (_isChoice) {
      while (_options.length < 2) {
        _options.add(_OptionRow('', false));
      }
    }
    for (final p in card.dragPairs ?? const <DragPair>[]) {
      _pairs.add(_PairRow(p.source, p.target));
    }
    if (_isDrag) {
      while (_pairs.length < 2) {
        _pairs.add(_PairRow('', ''));
      }
    }
    for (final b in card.blanks ?? const <String>[]) {
      _blanks.add(TextEditingController(text: b));
    }
    if (_type == QuestionType.fillBlank) {
      _front.addListener(_syncBlankCount);
      _syncBlankCount();
    }
    if (_type == QuestionType.table) {
      final rows = card.tableRows ?? const <List<QuestionTableCell>>[];
      final columns = rows.fold<int>(2, (n, r) => r.length > n ? r.length : n);
      for (final row in rows) {
        _table.add([
          for (var col = 0; col < columns; col++)
            col < row.length ? _TableEditCell(row[col].text, row[col].given) : _TableEditCell('', true),
        ]);
      }
      while (_table.length < 2) {
        _addTableRow();
      }
    }
  }

  int get _tableColumns => _table.isEmpty ? 2 : _table.first.length;

  void _addTableRow() =>
      _table.add([for (var col = 0; col < _tableColumns; col++) _TableEditCell('', _table.isEmpty || col == 0)]);

  void _addTableColumn() {
    for (final (r, row) in _table.indexed) {
      row.add(_TableEditCell('', r == 0));
    }
  }

  /// Je "___" im Fragetext ein Lösungsfeld.
  void _syncBlankCount() {
    final count = QuestionParsing.blankMarkerCount(_front.text);
    if (count == _blanks.length) return;
    setState(() {
      while (_blanks.length < count) {
        _blanks.add(TextEditingController());
      }
      while (_blanks.length > count) {
        _blanks.removeLast().dispose();
      }
    });
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _correctText.dispose();
    for (final o in _options) {
      o.controller.dispose();
    }
    for (final p in _pairs) {
      p.source.dispose();
      p.target.dispose();
    }
    for (final b in _blanks) {
      b.dispose();
    }
    for (final cell in _table.expand((r) => r)) {
      cell.controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final front = _front.text.trim();
    if (front.isEmpty) return setState(() => _error = 'Die Frage darf nicht leer sein.');
    List<QuizOption>? options;
    List<DragPair>? pairs;
    List<String>? blanks;
    String? correctText;

    if (_isChoice) {
      options = [
        for (final o in _options)
          if (o.controller.text.trim().isNotEmpty) QuizOption(text: o.controller.text.trim(), isCorrect: o.isCorrect),
      ];
      final correct = options.where((o) => o.isCorrect).length;
      if (options.length < 2) return setState(() => _error = 'Mindestens zwei Antwortoptionen eintragen.');
      if (_type == QuestionType.singleChoice && correct != 1) {
        return setState(() => _error = 'Bei Single-Choice genau eine Option als richtig markieren.');
      }
      if (correct == 0) return setState(() => _error = 'Mindestens eine Option als richtig markieren.');
    }
    if (_isDrag) {
      pairs = [
        for (final p in _pairs)
          if (p.source.text.trim().isNotEmpty && p.target.text.trim().isNotEmpty)
            DragPair(source: p.source.text.trim(), target: p.target.text.trim()),
      ];
      if (pairs.length < 2) return setState(() => _error = 'Mindestens zwei vollständige Paare eintragen.');
    }
    if (_type == QuestionType.fillBlank) {
      blanks = [for (final b in _blanks) b.text.trim()];
      if (blanks.isEmpty) return setState(() => _error = 'Markiere die Lücken im Text mit ___ (drei Unterstriche).');
      if (blanks.any((b) => b.isEmpty)) return setState(() => _error = 'Für jede Lücke eine Lösung eintragen.');
    }
    if (_type == QuestionType.freeText) {
      correctText = _correctText.text.trim();
      if (correctText.isEmpty) return setState(() => _error = 'Eine Musterantwort eintragen.');
    }
    List<List<QuestionTableCell>>? tableRows;
    if (_type == QuestionType.table) {
      tableRows = [
        for (final row in _table)
          if (row.any((c) => c.controller.text.trim().isNotEmpty))
            [for (final c in row) QuestionTableCell(text: c.controller.text.trim(), given: c.given)],
      ];
      if (!tableRows.any((r) => r.any((c) => !c.given && c.text.isNotEmpty))) {
        return setState(() => _error = 'Mindestens eine Zelle zum Ausfüllen (mit Lösung) anlegen.');
      }
    }
    Navigator.of(context).pop(widget.card.copyWithContent(
      front: front,
      back: _back.text.trim(),
      options: options,
      correctText: correctText,
      blanks: blanks,
      dragPairs: pairs,
      tableRows: tableRows,
    ));
  }

  String get _backLabel => switch (_type) {
        QuestionType.flashcard => 'Rückseite',
        QuestionType.markImage => 'Was ist dort zu sehen? (optional)',
        QuestionType.html => 'Antwort (wenn die Seite nicht angezeigt werden kann)',
        _ => 'Erklärung (optional)',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${_type.label} bearbeiten'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('card-edit-front'),
            controller: _front,
            maxLines: null,
            decoration: InputDecoration(
              labelText: 'Frage',
              helperText: _type == QuestionType.fillBlank ? 'Lücken mit ___ (drei Unterstriche) markieren.' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_isChoice) ..._buildOptions(theme),
          if (_isDrag) ..._buildPairs(theme),
          if (_type == QuestionType.fillBlank) ..._buildBlanks(),
          if (_type == QuestionType.table) ..._buildTable(theme),
          if (_type == QuestionType.freeText) ...[
            TextField(
              key: const ValueKey('card-edit-correct-text'),
              controller: _correctText,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Musterantwort', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
          ],
          if (_type != QuestionType.diagramLabel)
            TextField(
              key: const ValueKey('card-edit-back'),
              controller: _back,
              maxLines: null,
              decoration: InputDecoration(labelText: _backLabel, border: const OutlineInputBorder()),
            ),
          if (_type == QuestionType.diagramLabel || _type == QuestionType.markImage)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Stellen und Bereiche im Bild änderst du in der Kartenliste über den Bild-Knopf.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_type == QuestionType.html)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Die interaktive Seite selbst lässt sich hier nicht bearbeiten.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildOptions(ThemeData theme) => [
        Text(
          _type == QuestionType.singleChoice
              ? 'Antwortoptionen – die richtige antippen'
              : 'Antwortoptionen – alle richtigen abhaken',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                if (_type == QuestionType.singleChoice)
                  IconButton(
                    key: ValueKey('card-edit-correct-$i'),
                    tooltip: 'Als richtig markieren',
                    icon: Icon(_options[i].isCorrect ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    onPressed: () => setState(() {
                      for (var j = 0; j < _options.length; j++) {
                        _options[j].isCorrect = j == i;
                      }
                    }),
                  )
                else
                  Checkbox(
                    key: ValueKey('card-edit-correct-$i'),
                    value: _options[i].isCorrect,
                    onChanged: (v) => setState(() => _options[i].isCorrect = v ?? false),
                  ),
                Expanded(
                  child: TextField(
                    key: ValueKey('card-edit-option-$i'),
                    controller: _options[i].controller,
                    maxLines: null,
                    decoration: InputDecoration(labelText: 'Option ${i + 1}', border: const OutlineInputBorder()),
                  ),
                ),
                IconButton(
                  tooltip: 'Option entfernen',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _options.length <= 2
                      ? null
                      : () => setState(() => _options.removeAt(i).controller.dispose()),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _options.add(_OptionRow('', false))),
            icon: const Icon(Icons.add),
            label: const Text('Option hinzufügen'),
          ),
        ),
        const SizedBox(height: 16),
      ];

  List<Widget> _buildPairs(ThemeData theme) => [
        Text(
          _type == QuestionType.dragCategory ? 'Begriff → Kategorie' : 'Begriff → passendes Gegenstück',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _pairs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pairs[i].source,
                    decoration: const InputDecoration(labelText: 'Begriff', border: OutlineInputBorder()),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 18)),
                Expanded(
                  child: TextField(
                    controller: _pairs[i].target,
                    decoration: InputDecoration(
                      labelText: _type == QuestionType.dragCategory ? 'Kategorie' : 'Gegenstück',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Paar entfernen',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _pairs.length <= 2
                      ? null
                      : () => setState(() {
                            final removed = _pairs.removeAt(i);
                            removed.source.dispose();
                            removed.target.dispose();
                          }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _pairs.add(_PairRow('', ''))),
            icon: const Icon(Icons.add),
            label: const Text('Paar hinzufügen'),
          ),
        ),
        const SizedBox(height: 16),
      ];

  List<Widget> _buildBlanks() => [
        for (var i = 0; i < _blanks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: ValueKey('card-edit-blank-$i'),
              controller: _blanks[i],
              decoration: InputDecoration(
                labelText: 'Lösung Lücke ${i + 1}',
                helperText: i == 0 ? 'Mehrere richtige Schreibweisen mit ; trennen.' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ];

  void _removeTableRow() {
    if (_table.length <= 2) return;
    setState(() {
      for (final cell in _table.removeLast()) {
        cell.controller.dispose();
      }
    });
  }

  void _removeTableColumn() {
    if (_tableColumns <= 1) return;
    setState(() {
      for (final row in _table) {
        row.removeLast().controller.dispose();
      }
    });
  }

  /// Raster aus Textfeldern; das Schloss je Zelle schaltet zwischen
  /// vorgegeben (wird angezeigt) und auszufüllen (Text = Lösung).
  List<Widget> _buildTable(ThemeData theme) => [
        Text('Tabelle', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Schloss zu = Zelle wird vorgegeben. Schloss offen = Zelle wird beim Lernen ausgefüllt, '
          'dort die Lösung eintragen (mehrere richtige Schreibweisen mit ; trennen).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (r, row) in _table.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (col, cell) in row.indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 170,
                            child: TextField(
                              key: ValueKey('card-edit-table-$r-$col'),
                              controller: cell.controller,
                              maxLines: null,
                              style: TextStyle(fontWeight: r == 0 && cell.given ? FontWeight.w700 : null),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: !cell.given,
                                fillColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                                hintText: cell.given ? 'Text' : 'Lösung',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  key: ValueKey('card-edit-table-toggle-$r-$col'),
                                  tooltip: cell.given ? 'Zum Ausfüllen machen' : 'Vorgeben',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(cell.given ? Icons.lock_outline : Icons.edit_note, size: 18),
                                  onPressed: () => setState(() => cell.given = !cell.given),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => setState(_addTableRow),
              icon: const Icon(Icons.add),
              label: const Text('Zeile'),
            ),
            TextButton.icon(
              onPressed: () => setState(_addTableColumn),
              icon: const Icon(Icons.add),
              label: const Text('Spalte'),
            ),
            TextButton.icon(
              onPressed: _table.length <= 2 ? null : _removeTableRow,
              icon: const Icon(Icons.remove),
              label: const Text('Zeile'),
            ),
            TextButton.icon(
              onPressed: _tableColumns <= 1 ? null : _removeTableColumn,
              icon: const Icon(Icons.remove),
              label: const Text('Spalte'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ];
}
