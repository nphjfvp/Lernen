import 'package:flutter/material.dart';

import '../../models/formula_sheet.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Die Formelsammlung: Umschalter Grob/Mittel/Fein mit Erklärung, darunter die
/// Abschnitte mit ihren Formeln. Zeigt bei jeder Genauigkeit nur, was dazu
/// gehört (siehe [FormulaDetail.includes]); der Rest bleibt gespeichert.
///
/// Mit [editing] bekommt jeder Eintrag Knöpfe zum Bearbeiten/Löschen und jeder
/// Abschnitt "Formel hinzufügen" – die KI irrt sich auch bei Formeln, und eine
/// falsche in der Sammlung ist schlimmer als eine fehlende. Die Rückrufe
/// bekommen den Eintrag so, wie er in [sheet] steht (gleiche Instanz).
class FormulaSheetView extends StatelessWidget {
  const FormulaSheetView({
    super.key,
    required this.sheet,
    required this.onDetailChanged,
    this.editing = false,
    this.onEditEntry,
    this.onDeleteEntry,
    this.onAddEntry,
  });

  final FormulaSheet sheet;
  final void Function(FormulaDetail detail) onDetailChanged;
  final bool editing;
  final void Function(FormulaEntry entry)? onEditEntry;
  final void Function(FormulaEntry entry)? onDeleteEntry;
  final void Function(String sectionTitle)? onAddEntry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = sheet.visibleSections();
    final shown = sheet.visibleCount();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<FormulaDetail>(
          key: const ValueKey('formula-detail'),
          showSelectedIcon: false,
          segments: [
            for (final d in FormulaDetail.values)
              ButtonSegment(value: d, label: Text(d.label), tooltip: d.description),
          ],
          selected: {sheet.detail},
          onSelectionChanged: (v) => onDetailChanged(v.first),
        ),
        const SizedBox(height: 8),
        Text(sheet.detail.description, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted)),
        const SizedBox(height: 4),
        Text(
          key: const ValueKey('formula-count'),
          shown == sheet.totalCount ? '$shown Formeln' : '$shown von ${sheet.totalCount} Formeln',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.inkMuted),
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          Text('Bei dieser Genauigkeit gibt es keine Einträge.', style: TextStyle(color: c.inkMuted)),
        for (final section in visible) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(section.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          for (final entry in section.entries) _EntryCard(entry: entry, view: this),
          if (editing && onAddEntry != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('formula-add-${section.title}'),
                onPressed: () => onAddEntry!(section.title),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Formel hinzufügen'),
              ),
            ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.view});

  final FormulaEntry entry;
  final FormulaSheetView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(entry.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        if (entry.level != FormulaLevel.kern) _Tag(entry.level.label, c.accentSoft, c.accentOnSoft),
                        if (entry.supplemented)
                          _Tag('ergänzt – bitte prüfen', c.warnSoft, c.warn, key: const ValueKey('formula-supplemented')),
                      ],
                    ),
                  ),
                  if (view.editing) ...[
                    IconButton(
                      key: ValueKey('formula-edit-${entry.name}'),
                      tooltip: 'Bearbeiten',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => view.onEditEntry?.call(entry),
                    ),
                    IconButton(
                      key: ValueKey('formula-delete-${entry.name}'),
                      tooltip: 'Löschen',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => view.onDeleteEntry?.call(entry),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              MathText('\$\$${entry.formula}\$\$', style: const TextStyle(fontSize: 15)),
              if (entry.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: MathText(entry.note, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.bg, this.fg, {super.key});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
      );
}

/// Dialog zum Anlegen/Bearbeiten eines Eintrags; mit Vorschau der Formel.
/// Liefert den neuen Eintrag oder `null` bei Abbruch; die Markierung "ergänzt"
/// bleibt bei einem bearbeiteten Eintrag erhalten.
Future<FormulaEntry?> showFormulaEntryDialog(BuildContext context, {FormulaEntry? initial}) {
  return showDialog<FormulaEntry>(
    context: context,
    builder: (ctx) => _EntryDialog(initial: initial),
  );
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({this.initial});

  final FormulaEntry? initial;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _formula = TextEditingController(text: widget.initial?.formula ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.initial?.note ?? '');
  late FormulaLevel _level = widget.initial?.level ?? FormulaLevel.kern;

  @override
  void dispose() {
    _name.dispose();
    _formula.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid => _formula.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final formula = FormulaEntry.stripMathDelimiters(_formula.text);
    return AlertDialog(
      title: Text(widget.initial == null ? 'Formel hinzufügen' : 'Formel bearbeiten'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('formula-field-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'z.B. Partielle Integration'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('formula-field-formula'),
                controller: _formula,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Formel (LaTeX)', hintText: r'\int u\,v'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              if (formula.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(10)),
                  child: MathText('\$\$$formula\$\$'),
                ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('formula-field-note'),
                controller: _note,
                decoration: const InputDecoration(labelText: 'Hinweis (optional)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FormulaLevel>(
                key: const ValueKey('formula-field-level'),
                initialValue: _level,
                decoration: const InputDecoration(
                  labelText: 'Gehört zu',
                  helperText: 'Bestimmt, ab welcher Genauigkeit sie erscheint.',
                ),
                items: [
                  for (final l in FormulaLevel.values)
                    DropdownMenuItem(
                      value: l,
                      child: Text(switch (l) {
                        FormulaLevel.kern => 'Kernstoff (ab Grob)',
                        FormulaLevel.hilfsregel => 'Hilfsregel (ab Mittel)',
                        FormulaLevel.rechenregel => 'Rechenregel (nur Fein)',
                      }),
                    ),
                ],
                onChanged: (v) => setState(() => _level = v ?? _level),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(
          key: const ValueKey('formula-dialog-save'),
          onPressed: _valid
              ? () => Navigator.of(context).pop((widget.initial ?? const FormulaEntry(name: '', formula: '')).copyWith(
                    name: _name.text.trim().isEmpty ? 'Formel' : _name.text.trim(),
                    formula: formula,
                    note: _note.text.trim(),
                    level: _level,
                  ))
              : null,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
