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
import '../daily/question_answer_view.dart';

/// "Frage erstellen" im Lernmodus (siehe MaterialViewerScreen): erzeugt aus
/// GENAU der gerade betrachteten Seite bis zu 3 Karteikarten-Varianten
/// desselben Fakts – je eine für Leicht/Mittel/Schwer (siehe
/// AiService.generateQuestionsFromPage/[_variantTypeRule]) – immer
/// multimodal (Seiten-Screenshot ans Vision-Modell), da Folienseiten oft
/// Diagramme/Formeln enthalten, die reiner Text nicht wiedergibt.
///
/// Was abgefragt werden soll, markiert der Nutzer entweder direkt vorher im
/// PDF (Textauswahl, siehe [initialQuestionText] – KEIN extra Klick auf
/// einen Markier-Button nötig) oder tippt es/passt es hier frei ein; eine
/// bereits gespeicherte Frage/Antwort-Markierung dient nur als Vorbelegung.
/// Die generierten Karten lassen sich wie im echten Quiz durchklicken
/// ([QuestionAnswerView], rein kosmetisch – ohne FSRS-Effekt) und per freier
/// Anweisung überarbeiten, bevor sie gespeichert werden.
class PageQuestionCreationSheet extends StatefulWidget {
  const PageQuestionCreationSheet({
    super.key,
    required this.material,
    required this.pageNumber,
    required this.pageText,
    required this.pageImageBytes,
    required this.highlightsOnPage,
    this.initialQuestionText,
    this.examContext,
  });

  final MaterialItem material;
  final int pageNumber;
  final String pageText;
  final Uint8List pageImageBytes;
  final List<MaterialHighlight> highlightsOnPage;

  /// Gerade im PDF ausgewählter Text (siehe MaterialViewerScreen), bevor
  /// dieses Sheet geöffnet wurde – die einfachste Art zu markieren, worauf
  /// sich die Frage beziehen soll: Text auswählen, dann "Frage erstellen"
  /// tippen, kein separater Markier-Schritt nötig.
  final String? initialQuestionText;
  final String? examContext;

  @override
  State<PageQuestionCreationSheet> createState() => _PageQuestionCreationSheetState();
}

class _DifficultySlot {
  _DifficultySlot({required this.label, required this.enabled, required this.type});
  final String label;
  bool enabled;
  QuestionType type;
}

class _PageQuestionCreationSheetState extends State<PageQuestionCreationSheet> {
  late final TextEditingController _questionController;
  late final TextEditingController _answerController;
  final _instructionController = TextEditingController();

  late final List<_DifficultySlot> _slots = [
    _DifficultySlot(label: 'Leicht', enabled: true, type: QuestionType.singleChoice),
    _DifficultySlot(label: 'Mittel', enabled: false, type: QuestionType.fillBlank),
    _DifficultySlot(label: 'Schwer', enabled: false, type: QuestionType.freeText),
  ];

  bool _generating = false;
  bool _saving = false;
  String? _error;
  List<Flashcard>? _previewCards;
  List<Map<String, dynamic>>? _previousRaw;
  int _previewIndex = 0;

  MaterialHighlight? _firstOfColor(HighlightColor color) {
    for (final h in widget.highlightsOnPage) {
      if (h.color == color) return h;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final question = widget.initialQuestionText ?? _firstOfColor(HighlightColor.red)?.text ?? '';
    _questionController = TextEditingController(text: question);
    _answerController = TextEditingController(text: _firstOfColor(HighlightColor.green)?.text ?? '');
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  List<QuestionType> get _selectedTypes =>
      _slots.where((s) => s.enabled).map((s) => s.type).toList();

  Future<void> _generate({bool refine = false}) async {
    final types = _selectedTypes;
    if (types.isEmpty) return;
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
      final question = _questionController.text.trim();
      final answer = _answerController.text.trim();
      final raw = await ai.generateQuestionsFromPage(
        pageImageBytes: widget.pageImageBytes,
        pageText: widget.pageText,
        types: types,
        questionHighlight: question.isEmpty ? null : question,
        answerHighlight: answer.isEmpty ? null : answer,
        examContext: widget.examContext,
        previousFlashcards: refine ? _previousRaw : null,
        instruction: refine ? _instructionController.text.trim() : null,
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
        _previousRaw = raw;
        _previewIndex = 0;
        _instructionController.clear();
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final previewCards = _previewCards;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
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
                child: previewCards == null ? _buildConfig(c) : _buildPreview(c, previewCards),
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

  Widget _buildConfig(AppColors c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Was soll abgefragt werden?', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
        const SizedBox(height: 4),
        Text(
          'Vorausgefüllt aus deiner Textauswahl im PDF bzw. einer vorhandenen '
          'Markierung – hier frei bearbeitbar.',
          style: TextStyle(fontSize: 11.5, color: c.inkMuted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _questionController,
          enabled: !_generating,
          maxLines: null,
          minLines: 2,
          decoration: InputDecoration(
            hintText: 'Worum geht es? (leer lassen = KI wählt selbst)',
            filled: true,
            fillColor: c.surfaceAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _answerController,
          enabled: !_generating,
          maxLines: null,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'Antwort/Fakt dazu (optional)',
            filled: true,
            fillColor: c.surfaceAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
        Text('Schwierigkeitsgrade', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
        const SizedBox(height: 4),
        Text(
          'Bis zu 3 Varianten desselben Fakts, eine je Stufe.',
          style: TextStyle(fontSize: 11.5, color: c.inkMuted),
        ),
        const SizedBox(height: 8),
        ..._slots.map((slot) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: slot.enabled,
                    onChanged: _generating ? null : (v) => setState(() => slot.enabled = v ?? false),
                  ),
                  SizedBox(width: 56, child: Text(slot.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<QuestionType>(
                      isExpanded: true,
                      value: slot.type,
                      onChanged: (!_generating && slot.enabled)
                          ? (t) => setState(() => slot.type = t ?? slot.type)
                          : null,
                      items: QuestionType.values
                          .map((t) => DropdownMenuItem(value: t, child: Text(t.label, style: const TextStyle(fontSize: 13.5))))
                          .toList(),
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (_generating || _selectedTypes.isEmpty) ? null : () => _generate(),
          icon: _generating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_outlined),
          label: const Text('Frage(n) erstellen'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
          ),
      ],
    );
  }

  Widget _buildPreview(AppColors c, List<Flashcard> cards) {
    final card = cards[_previewIndex];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _previewIndex > 0 ? () => setState(() => _previewIndex--) : null,
              ),
              Expanded(
                child: Text(
                  'Vorschau ${_previewIndex + 1}/${cards.length} · ${card.type.label}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _previewIndex < cards.length - 1 ? () => setState(() => _previewIndex++) : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: QuestionAnswerView(
            key: ValueKey(card.id),
            card: card,
            isNew: false,
            onComplete: ({selfGrade, isCorrect}) {
              if (_previewIndex < cards.length - 1) setState(() => _previewIndex++);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Anpassen', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _instructionController,
                      enabled: !_generating,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'z.B. "einfacher formulieren", "anderer Fokus"',
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
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
