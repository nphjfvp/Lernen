import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/concept.dart';
import '../../models/material_item.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';
import 'safe_set_state.dart';

/// "Konzept speichern" im Lernmodus (siehe MaterialViewerScreen): erstellt
/// aus GENAU der gerade betrachteten Seite ein eigenständiges Lernkonzept
/// (Titel + Erklärung), das sich per Anweisung iterativ anpassen lässt
/// (umformulieren, kürzen, mehr Fokus auf einen Aspekt, ...) bevor es
/// gespeichert wird. Landet mit einem Quasi-Link zurück zu Material + Seite
/// (siehe Concept.linkedMaterialId/linkedPageNumber) in der normalen
/// Konzepte-Liste des Fachs.
class PageConceptSheet extends StatefulWidget {
  const PageConceptSheet({
    super.key,
    required this.material,
    required this.pageNumber,
    required this.pageText,
    this.previousPageText,
    this.nextPageText,
  });

  final MaterialItem material;
  final int pageNumber;
  final String pageText;
  final String? previousPageText;
  final String? nextPageText;

  @override
  State<PageConceptSheet> createState() => _PageConceptSheetState();
}

class _PageConceptSheetState extends State<PageConceptSheet> with SafeSetState<PageConceptSheet> {
  bool _includeNeighbors = true;
  bool _generating = false;
  bool _saving = false;
  bool _hasResult = false;
  String? _error;

  final _titleController = TextEditingController();
  final _explanationController = TextEditingController();
  final _instructionController = TextEditingController();

  bool get _hasNeighbors =>
      (widget.previousPageText != null && widget.previousPageText!.trim().isNotEmpty) ||
      (widget.nextPageText != null && widget.nextPageText!.trim().isNotEmpty);

  @override
  void dispose() {
    _titleController.dispose();
    _explanationController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  Future<void> _generate({bool refine = false}) async {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final result = await ai.generatePageConcept(
        pageText: widget.pageText,
        previousPageText: _includeNeighbors ? widget.previousPageText : null,
        nextPageText: _includeNeighbors ? widget.nextPageText : null,
        currentTitle: refine ? _titleController.text : null,
        currentExplanation: refine ? _explanationController.text : null,
        instruction: refine ? _instructionController.text.trim() : null,
      );
      if (!mounted) return;
      final title = (result['title'] as String?)?.trim();
      setState(() {
        _titleController.text = (title == null || title.isEmpty) ? 'Konzept' : title;
        _explanationController.text = (result['explanation'] as String?)?.trim() ?? '';
        _instructionController.clear();
        _hasResult = true;
        _generating = false;
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unerwarteter Fehler: $e';
        _generating = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final concept = Concept(
      id: const Uuid().v4(),
      moduleId: widget.material.moduleId,
      title: _titleController.text.trim().isEmpty ? 'Konzept' : _titleController.text.trim(),
      explanation: _explanationController.text.trim(),
      sourceMaterialIds: [widget.material.id],
      createdAt: DateTime.now(),
      unitId: widget.material.unitId,
      linkedMaterialId: widget.material.id,
      linkedPageNumber: widget.pageNumber,
    );
    await context.read<ConceptRepository>().saveAll([concept]);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text('Konzept aus Seite ${widget.pageNumber}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Divider(height: 1, color: c.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_hasNeighbors)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _includeNeighbors,
                        activeThumbColor: c.accent,
                        onChanged: _generating ? null : (v) => setState(() => _includeNeighbors = v),
                        title: const Text('Nachbarseiten einbeziehen, falls nötig',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          'Die KI nutzt sie nur, wenn diese Seite allein unklar/unvollständig wäre.',
                          style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                        ),
                      ),
                    if (!_hasResult) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _generating ? null : () => _generate(),
                        icon: _generating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Erklärung generieren'),
                      ),
                    ] else ...[
                      TextField(
                        controller: _titleController,
                        enabled: !_generating,
                        decoration: const InputDecoration(labelText: 'Titel'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _explanationController,
                        enabled: !_generating,
                        maxLines: null,
                        minLines: 6,
                        decoration: const InputDecoration(labelText: 'Erklärung', alignLabelWithHint: true),
                      ),
                      const SizedBox(height: 16),
                      Text('Anpassen', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
                      const SizedBox(height: 4),
                      Text(
                        'z.B. "umformulieren", "kürzer", "mehr Fokus auf die Formel"',
                        style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _instructionController,
                              enabled: !_generating,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Anweisung zur Überarbeitung …',
                                filled: true,
                                fillColor: c.surfaceAlt,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: (_generating || _instructionController.text.trim().isEmpty)
                                ? null
                                : () => _generate(refine: true),
                            icon: _generating
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
              if (_hasResult)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                          child: const Text('Verwerfen'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Speichern'),
                        ),
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
