import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/question_parsing.dart';
import '../../theme/app_colors.dart';

/// "Frage erstellen" im Lernmodus (siehe MaterialViewerScreen): erzeugt aus
/// GENAU der gerade betrachteten Seite 1-3 Karteikarten-Varianten desselben
/// Fakts (unterschiedliche Typen/Schwierigkeitsgrade, siehe
/// AiService.generateQuestionsFromPage) – immer multimodal (Seiten-
/// Screenshot ans Vision-Modell), da Folienseiten oft Diagramme/Formeln
/// enthalten, die reiner Text nicht wiedergibt. Hat der Nutzer auf dieser
/// Seite bereits eine "Frage" (rot) markiert, wird sie als verbindliche
/// Grundlage angeboten statt die KI frei wählen zu lassen.
class PageQuestionCreationSheet extends StatefulWidget {
  const PageQuestionCreationSheet({
    super.key,
    required this.material,
    required this.pageNumber,
    required this.pageText,
    required this.pageImageBytes,
    required this.highlightsOnPage,
    this.examContext,
  });

  final MaterialItem material;
  final int pageNumber;
  final String pageText;
  final Uint8List pageImageBytes;
  final List<MaterialHighlight> highlightsOnPage;
  final String? examContext;

  @override
  State<PageQuestionCreationSheet> createState() => _PageQuestionCreationSheetState();
}

class _PageQuestionCreationSheetState extends State<PageQuestionCreationSheet> {
  static const _maxTypes = 3;

  final Set<QuestionType> _selectedTypes = {};
  bool _useHighlightPair = false;
  bool _generating = false;
  bool _saving = false;
  String? _error;
  List<Flashcard>? _previewCards;

  MaterialHighlight? _firstOfColor(HighlightColor color) {
    for (final h in widget.highlightsOnPage) {
      if (h.color == color) return h;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _useHighlightPair = _firstOfColor(HighlightColor.red) != null;
    _selectedTypes.add(QuestionType.singleChoice);
  }

  Future<void> _generate() async {
    if (_selectedTypes.isEmpty) return;
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
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId);
      final question = _useHighlightPair ? _firstOfColor(HighlightColor.red)?.text : null;
      final answer = _useHighlightPair ? _firstOfColor(HighlightColor.green)?.text : null;
      final raw = await ai.generateQuestionsFromPage(
        pageImageBytes: widget.pageImageBytes,
        pageText: widget.pageText,
        types: _selectedTypes.toList(),
        questionHighlight: question,
        answerHighlight: answer,
        examContext: widget.examContext,
      );

      final now = DateTime.now();
      final cards = <Flashcard>[];
      for (final entry in raw) {
        final fixed = QuestionParsing.normalizeGeneratedFlashcard(entry);
        if (fixed == null) continue;
        final type = QuestionParsing.parseType(fixed['type'] as String?);
        cards.add(Flashcard(
          id: const Uuid().v4(),
          moduleId: widget.material.moduleId,
          front: (fixed['front'] ?? '').toString(),
          back: (fixed['back'] ?? '').toString(),
          createdAt: now,
          due: now,
          type: type,
          unitId: widget.material.unitId,
          options: QuestionParsing.parseOptions(fixed['options']),
          correctText: fixed['correctText'] as String?,
          blanks: QuestionParsing.parseBlanks(fixed['blanks']),
          dragPairs: QuestionParsing.parseDragPairs(fixed['dragPairs']),
        ));
      }
      if (!mounted) return;
      setState(() {
        _previewCards = cards;
        _generating = false;
        if (cards.isEmpty) _error = 'Keine gültige Frage konnte erzeugt werden.';
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
    final cards = _previewCards;
    if (cards == null || cards.isEmpty) return;
    setState(() => _saving = true);
    await context.read<FlashcardRepository>().saveAll(cards);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(cards.length);
  }

  void _toggleType(QuestionType type, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedTypes.length < _maxTypes) _selectedTypes.add(type);
      } else {
        _selectedTypes.remove(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasRed = _firstOfColor(HighlightColor.red) != null;
    final previewCards = _previewCards;

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
                child: Text('Frage aus Seite ${widget.pageNumber}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Divider(height: 1, color: c.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (previewCards == null) ...[
                      if (hasRed)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _useHighlightPair,
                          onChanged: _generating ? null : (v) => setState(() => _useHighlightPair = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Auf markierte Frage/Antwort stützen',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '"${_firstOfColor(HighlightColor.red)!.text}" → '
                            '"${_firstOfColor(HighlightColor.green)?.text ?? '(keine Antwort markiert)'}"',
                            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text('Fragetyp(en) – bis zu $_maxTypes, mehrere ergeben Schwierigkeitsstufen '
                          'desselben Fakts:',
                          style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: QuestionType.values.map((t) {
                          final selected = _selectedTypes.contains(t);
                          return FilterChip(
                            label: Text(t.label),
                            selected: selected,
                            onSelected: _generating ? null : (v) => _toggleType(t, v),
                            selectedColor: c.accentSoft,
                            labelStyle: TextStyle(
                                fontSize: 12.5, color: selected ? c.accentOnSoft : c.ink, fontWeight: FontWeight.w600),
                            backgroundColor: c.surface,
                            side: BorderSide(color: selected ? c.accent : c.border),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: (_generating || _selectedTypes.isEmpty) ? null : _generate,
                        icon: _generating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome_outlined),
                        label: const Text('Frage(n) erstellen'),
                      ),
                    ] else ...[
                      Text('${previewCards.length} Frage${previewCards.length == 1 ? '' : 'n'} erzeugt',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...previewCards.map((card) => Card(
                            child: ListTile(
                              title: Text(card.front),
                              subtitle: Text('${card.type.label} · ${card.answerSummary}'),
                            ),
                          )),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
              if (previewCards != null && previewCards.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => Navigator.of(context).pop(0),
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
