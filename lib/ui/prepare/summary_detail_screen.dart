import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/summary.dart';
import '../../repositories/summary_repository.dart';
import '../widgets/confirm_delete_dialog.dart';

/// Zeigt eine Zusammenfassung aus dem Vorbereiten-Modus an, mit einem
/// einfachen Bearbeiten-Modus (Titel/Kernkonzepte/Zusammenfassung als
/// Freitext) und einer Löschoption.
class SummaryDetailScreen extends StatefulWidget {
  const SummaryDetailScreen({super.key, required this.summary});

  final Summary summary;

  @override
  State<SummaryDetailScreen> createState() => _SummaryDetailScreenState();
}

class _SummaryDetailScreenState extends State<SummaryDetailScreen> {
  late Summary _summary;
  bool _editing = false;
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

  Future<void> _save() async {
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
      title: 'Zusammenfassung löschen?',
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
            ? [TextButton(onPressed: _save, child: const Text('Speichern'))]
            : [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() => _editing = true),
                ),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
              ],
      ),
      body: _editing ? _buildEditForm() : _buildView(),
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
                              Expanded(child: Text(k)),
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
        Text(_summary.overview),
      ],
    );
  }
}
