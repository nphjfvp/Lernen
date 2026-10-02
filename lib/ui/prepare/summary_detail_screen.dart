import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/formula_sheet.dart';
import '../../models/summary.dart';
import '../../repositories/summary_repository.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/math_text.dart';
import 'formula_sheet_view.dart';

/// Zeigt eine Zusammenfassung aus dem Vorbereiten-Modus an, mit einem
/// einfachen Bearbeiten-Modus (Titel/Kernkonzepte/Zusammenfassung als
/// Freitext) und einer Löschoption. Bei einer Formelsammlung (siehe
/// [Summary.formulaSheet]) stattdessen die Formeln mit Umschalter Grob/Mittel/
/// Fein; "Bearbeiten" erlaubt dort, Einträge zu ändern, zu löschen und zu
/// ergänzen.
class SummaryDetailScreen extends StatefulWidget {
  const SummaryDetailScreen({super.key, required this.summary});

  final Summary summary;

  @override
  State<SummaryDetailScreen> createState() => _SummaryDetailScreenState();
}

class _SummaryDetailScreenState extends State<SummaryDetailScreen> {
  late Summary _summary;
  bool _editing = false;
  bool get _isSheet => _summary.formulaSheet != null;
  late final TextEditingController _titleController;
  late final TextEditingController _overviewController;
  late final TextEditingController _keyPointsController;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
    _titleController = TextEditingController(text: _summary.title);
    _overviewController = TextEditingController(text: _summary.overview);
    _keyPointsController = TextEditingController(text: _summary.keyPoints.join('\n'));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _overviewController.dispose();
    _keyPointsController.dispose();
    super.dispose();
  }

  /// Speichert eine geänderte Formelsammlung sofort (Genauigkeit, Einträge).
  Future<void> _saveSheet(FormulaSheet sheet, {String? title}) async {
    final updated = _summary.copyWith(formulaSheet: sheet, title: title);
    await context.read<SummaryRepository>().save(updated);
    if (!mounted) return;
    setState(() => _summary = updated);
  }

  Future<void> _copySheet() async {
    final sheet = _summary.formulaSheet!;
    await Clipboard.setData(ClipboardData(text: sheet.asText(title: _summary.title)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Formelsammlung (${sheet.detail.label}) kopiert.')),
    );
  }

  /// Ersetzt [old] in der vollständigen Sammlung (gleiche Instanz) durch [next]
  /// bzw. entfernt sie bei `next == null`; leere Abschnitte fallen weg.
  FormulaSheet _replaceEntry(FormulaSheet sheet, FormulaEntry old, FormulaEntry? next) {
    final sections = [
      for (final s in sheet.sections)
        s.copyWith(entries: [
          for (final e in s.entries)
            if (identical(e, old)) ...[?next] else e,
        ]),
    ];
    return sheet.withSections([for (final s in sections) if (s.entries.isNotEmpty) s]);
  }

  Future<void> _editEntry(FormulaEntry entry) async {
    final edited = await showFormulaEntryDialog(context, initial: entry);
    if (edited == null || !mounted) return;
    await _saveSheet(_replaceEntry(_summary.formulaSheet!, entry, edited));
  }

  Future<void> _deleteEntry(FormulaEntry entry) async {
    await _saveSheet(_replaceEntry(_summary.formulaSheet!, entry, null));
  }

  Future<void> _addEntry(String sectionTitle) async {
    final added = await showFormulaEntryDialog(context);
    if (added == null || !mounted) return;
    final sheet = _summary.formulaSheet!;
    // Neue Einträge landen bei der gerade gewählten Genauigkeit sichtbar.
    final level = sheet.detail.includes(added.level) ? added.level : FormulaLevel.kern;
    final entry = added.copyWith(level: level);
    await _saveSheet(sheet.withSections([
      for (final s in sheet.sections)
        if (s.title == sectionTitle) s.copyWith(entries: [...s.entries, entry]) else s,
    ]));
  }

  Future<void> _save() async {
    if (_isSheet) {
      final title = _titleController.text.trim();
      await _saveSheet(_summary.formulaSheet!, title: title.isEmpty ? null : title);
      if (mounted) setState(() => _editing = false);
      return;
    }
    final updated = Summary(
      id: _summary.id,
      moduleId: _summary.moduleId,
      sourceMaterialIds: _summary.sourceMaterialIds,
      title: _titleController.text.trim().isEmpty ? _summary.title : _titleController.text.trim(),
      overview: _overviewController.text.trim(),
      keyPoints: _keyPointsController.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(),
      createdAt: _summary.createdAt,
      unitId: _summary.unitId,
      formulaSheet: _summary.formulaSheet,
    );
    await context.read<SummaryRepository>().save(updated);
    if (!mounted) return;
    setState(() {
      _summary = updated;
      _editing = false;
    });
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: _isSheet ? 'Formelsammlung löschen?' : 'Zusammenfassung löschen?',
      message: '"${_summary.title}" wird endgültig gelöscht.',
    );
    if (ok && mounted) {
      await context.read<SummaryRepository>().delete(_summary.id, _summary.moduleId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Bearbeiten' : _summary.title),
        actions: _editing
            ? [TextButton(onPressed: _save, child: Text(_isSheet ? 'Fertig' : 'Speichern'))]
            : [
                if (_isSheet)
                  IconButton(
                    key: const ValueKey('formula-copy'),
                    tooltip: 'Kopieren',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: _copySheet,
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() => _editing = true),
                ),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
              ],
      ),
      body: _isSheet ? _buildSheet() : (_editing ? _buildEditForm() : _buildView()),
    );
  }

  Widget _buildSheet() {
    final sheet = _summary.formulaSheet!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_editing) ...[
          TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Titel')),
          const SizedBox(height: 16),
        ],
        FormulaSheetView(
          sheet: sheet,
          editing: _editing,
          onDetailChanged: (d) => _saveSheet(sheet.withDetail(d)),
          onEditEntry: _editEntry,
          onDeleteEntry: _deleteEntry,
          onAddEntry: _addEntry,
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Titel')),
        const SizedBox(height: 16),
        TextField(
          controller: _keyPointsController,
          decoration: const InputDecoration(labelText: 'Kernkonzepte (ein Punkt pro Zeile)'),
          minLines: 3,
          maxLines: 8,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _overviewController,
          decoration: const InputDecoration(labelText: 'Zusammenfassung'),
          minLines: 6,
          maxLines: 20,
        ),
      ],
    );
  }

  Widget _buildView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_summary.keyPoints.isNotEmpty) ...[
          Text('Kernkonzepte', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _summary.keyPoints
                    .map((k) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(child: MathText(k)),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text('Zusammenfassung', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        MathText(_summary.overview),
      ],
    );
  }
}
