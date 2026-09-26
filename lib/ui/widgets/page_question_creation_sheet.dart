import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/image_crop.dart';
import '../../services/question_parsing.dart';
import '../../theme/app_colors.dart';
import '../daily/question_answer_view.dart';
import 'page_region_picker.dart';
import 'safe_set_state.dart';

/// "Frage erstellen" im Lernmodus (siehe MaterialViewerScreen): erzeugt aus
/// GENAU der gerade betrachteten Seite 1–2 Fragen, jede in bis zu 3
/// Schwierigkeitsstufen (Leicht/Mittel/Schwer) desselben Fakts – immer
/// multimodal (Seiten-Screenshot ans Vision-Modell), da Folienseiten oft
/// Diagramme/Formeln enthalten, die reiner Text nicht wiedergibt.
///
/// Den Typ je Stufe wählt der Nutzer oder lässt die KI entscheiden. Worauf
/// sich die Fragen konzentrieren, ist optional und kombinierbar: ein auf dem
/// Screenshot markierter Bereich ([showPageRegionPicker]), eine Textstelle
/// bzw. eigene Anweisung (vorbelegt aus der Textauswahl im PDF, siehe
/// [initialQuestionText], oder einer roten Markierung) und die erwartete
/// Antwort. Ohne Vorgabe wählt die KI selbst. Die Ergebnisse lassen sich wie
/// im echten Quiz durchklicken ([QuestionAnswerView], ohne FSRS-Effekt),
/// per freier Anweisung überarbeiten und einzeln verwerfen.
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

  /// Wie viele Fragen auf einmal erstellt werden können.
  static const maxQuestions = 2;

  @override
  State<PageQuestionCreationSheet> createState() => _PageQuestionCreationSheetState();
}

class _DifficultySlot {
  _DifficultySlot(this.label, {required this.enabled});
  final String label;
  bool enabled;

  /// null = die KI wählt das Format passend zur Stufe.
  QuestionType? type;
}

class _GeneratedQuestion {
  _GeneratedQuestion(this.tiers);
  final List<Flashcard> tiers;
  bool keep = true;
}

/// Wandelt die KI-Antwort (je Frage die Rohkarten in Stufen-Reihenfolge, siehe
/// AiService.generateQuestionsFromPage) in Karteikarten um. Mehr Fragen oder
/// Stufen als bestellt werden abgeschnitten, unbrauchbare Karten verworfen,
/// Fragen ohne brauchbare Karte fallen weg.
@visibleForTesting
List<List<Flashcard>> buildPageQuestionCards(
  List<List<Map<String, dynamic>>> groups, {
  required String moduleId,
  String? unitId,
  required int questionCount,
  required int tierCount,
  required String attachImageBase64,
  required DateTime now,
}) {
  final result = <List<Flashcard>>[];
  for (final group in groups.take(questionCount)) {
    final cards = <Flashcard>[];
    for (final entry in group.take(tierCount)) {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(entry);
      if (fixed == null) continue;
      cards.add(Flashcard(
        id: const Uuid().v4(),
        moduleId: moduleId,
        front: (fixed['front'] ?? '').toString(),
        back: (fixed['back'] ?? '').toString(),
        createdAt: now,
        due: now,
        type: QuestionParsing.parseType(fixed['type'] as String?),
        unitId: unitId,
        // Bewusst gerade jetzt beim Betrachten dieser Seite gestellt –
        // soll unabhängig vom Einheiten-"behandelt"-Status zeitnah im
        // Daily Quiz auftauchen statt hinter einem Altbestand zu warten
        // (siehe Flashcard.priorityIntroduction).
        priorityIntroduction: true,
        options: QuestionParsing.parseOptions(fixed['options']),
        correctText: fixed['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(fixed['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(fixed['dragPairs']),
        htmlContent: fixed['htmlContent'] as String?,
        imageBase64: entry['needsImage'] == true ? attachImageBase64 : null,
      ));
    }
    if (cards.isNotEmpty) result.add(cards);
  }
  return result;
}

/// Mehrere Schwierigkeitsstufen einer Frage wollen NACHEINANDER gelernt
/// werden, nicht gleichzeitig als unabhängige Karten im selben Pool (siehe
/// [Flashcard.variantChain]/[Flashcard.pendingVariants]) – deshalb werden sie
/// zu EINER Karte zusammengeführt: die leichteste Stufe ist sofort aktiv, die
/// anderen liegen bereits fertig ausformuliert als [Flashcard.pendingVariants]
/// bereit und werden erst bei Beförderung sichtbar – ohne erneuten KI-Aufruf.
/// Eine einzelne Stufe bleibt unverändert eine eigenständige Karte.
@visibleForTesting
Flashcard mergeTiersIntoChain(List<Flashcard> tiers) {
  final base = tiers.first;
  if (tiers.length == 1) return base;
  final pending = tiers
      .sublist(1)
      .map((t) => VariantSnapshot(
            type: t.type,
            front: t.front,
            back: t.back,
            options: t.options,
            correctText: t.correctText,
            blanks: t.blanks,
            dragPairs: t.dragPairs,
            htmlContent: t.htmlContent,
            imageBase64: t.imageBase64,
          ))
      .toList();
  return Flashcard(
    id: base.id,
    moduleId: base.moduleId,
    conceptId: base.conceptId,
    front: base.front,
    back: base.back,
    createdAt: base.createdAt,
    due: base.due,
    type: base.type,
    options: base.options,
    correctText: base.correctText,
    blanks: base.blanks,
    dragPairs: base.dragPairs,
    htmlContent: base.htmlContent,
    imageBase64: base.imageBase64,
    variantChain: tiers.map((t) => t.type).toList(),
    pendingVariants: pending,
    unitId: base.unitId,
    priorityIntroduction: base.priorityIntroduction,
  );
}

class _PageQuestionCreationSheetState extends State<PageQuestionCreationSheet>
    with SafeSetState<PageQuestionCreationSheet> {
  late final TextEditingController _focusController;
  late final TextEditingController _answerController;
  final _instructionController = TextEditingController();

  final List<_DifficultySlot> _slots = [
    _DifficultySlot('Leicht', enabled: true),
    _DifficultySlot('Mittel', enabled: false),
    _DifficultySlot('Schwer', enabled: false),
  ];
  int _questionCount = 1;
  Rect? _focusRect;
  Uint8List? _focusImage;

  bool _generating = false;
  bool _saving = false;
  String? _error;
  List<_GeneratedQuestion>? _questions;
  List<String> _generatedLevels = const [];
  List<List<Map<String, dynamic>>>? _previousRaw;
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
    final focus = widget.initialQuestionText ?? _firstOfColor(HighlightColor.red)?.text ?? '';
    _focusController = TextEditingController(text: focus);
    _answerController = TextEditingController(text: _firstOfColor(HighlightColor.green)?.text ?? '');
  }

  @override
  void dispose() {
    _focusController.dispose();
    _answerController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  List<_DifficultySlot> get _enabledSlots => _slots.where((s) => s.enabled).toList();

  /// Alle Vorschau-Karten der Reihe nach: (Frage, Stufe).
  List<({int question, int tier})> get _flat => [
        for (var q = 0; q < (_questions?.length ?? 0); q++)
          for (var t = 0; t < _questions![q].tiers.length; t++) (question: q, tier: t),
      ];

  Future<void> _pickRegion() async {
    final rect = await showPageRegionPicker(context, widget.pageImageBytes, initial: _focusRect);
    if (rect == null || !mounted) return;
    final crop = await cropImageRelative(widget.pageImageBytes, rect);
    setState(() {
      _focusRect = crop == null ? null : rect;
      _focusImage = crop;
      _error = crop == null ? 'Der Bereich konnte nicht ausgeschnitten werden.' : null;
    });
  }

  Future<void> _generate({bool refine = false}) async {
    final slots = _enabledSlots;
    if (slots.isEmpty) return;
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
      final focus = _focusController.text.trim();
      final answer = _answerController.text.trim();
      final groups = await ai.generateQuestionsFromPage(
        pageImageBytes: widget.pageImageBytes,
        pageText: widget.pageText,
        tiers: [for (final s in slots) (level: s.label, type: s.type)],
        questionCount: _questionCount,
        focusImageBytes: _focusImage,
        focusText: focus.isEmpty ? null : focus,
        answerText: answer.isEmpty ? null : answer,
        examContext: widget.examContext,
        previousQuestions: refine ? _previousRaw : null,
        instruction: refine ? _instructionController.text.trim() : null,
      );
      final questions = buildPageQuestionCards(
        groups,
        moduleId: widget.material.moduleId,
        unitId: widget.material.unitId,
        questionCount: _questionCount,
        tierCount: slots.length,
        // Mit markiertem Bereich hängt an einer Bild-Frage genau dieser
        // Ausschnitt statt der ganzen Seite.
        attachImageBase64: base64Encode(_focusImage ?? widget.pageImageBytes),
        now: DateTime.now(),
      );
      if (!mounted) return;
      if (refine && questions.isEmpty) {
        // Missglückte Überarbeitung: die bisherigen Fragen bleiben stehen.
        setState(() {
          _error = 'Die Überarbeitung hat keine gültige Frage geliefert.';
          _generating = false;
        });
        return;
      }
      setState(() {
        _questions = [for (final tiers in questions) _GeneratedQuestion(tiers)];
        _generatedLevels = [for (final s in slots) s.label];
        _previousRaw = groups;
        _previewIndex = 0;
        _instructionController.clear();
        _generating = false;
        if (questions.isEmpty) _error = 'Keine gültige Frage konnte erzeugt werden.';
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
    final kept = (_questions ?? const <_GeneratedQuestion>[]).where((q) => q.keep).toList();
    if (kept.isEmpty) return;
    setState(() => _saving = true);
    await context.read<FlashcardRepository>().saveAll([for (final q in kept) mergeTiersIntoChain(q.tiers)]);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(kept.length);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final questions = _questions;
    final keptCount = questions?.where((q) => q.keep).length ?? 0;

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
                child: questions == null || questions.isEmpty ? _buildConfig(c) : _buildPreview(c, questions),
              ),
              if (questions != null && questions.isNotEmpty)
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
                          onPressed: (_saving || keptCount == 0) ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(questions.length > 1 ? 'Speichern ($keptCount)' : 'Speichern'),
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

  InputDecoration _fieldDecoration(AppColors c, String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: c.surfaceAlt,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  Widget _sectionTitle(AppColors c, String title, String hint) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(fontSize: 11.5, color: c.inkMuted)),
          const SizedBox(height: 8),
        ],
      );

  Widget _buildConfig(AppColors c) {
    final focusImage = _focusImage;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(
          c,
          'Fokus (optional)',
          'Markiere einen Bereich der Seite, gib vor, worum es gehen soll – oder lass alles leer, '
              'dann wählt die KI das Wichtigste der Seite.',
        ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _generating ? null : _pickRegion,
              icon: const Icon(Icons.crop_free, size: 18),
              label: Text(focusImage == null ? 'Bereich markieren' : 'Bereich ändern'),
            ),
            if (focusImage != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Markierung entfernen',
                onPressed: _generating
                    ? null
                    : () => setState(() {
                          _focusRect = null;
                          _focusImage = null;
                        }),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
        if (focusImage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: c.surfaceAlt,
                constraints: const BoxConstraints(maxHeight: 160),
                alignment: Alignment.center,
                child: Image.memory(focusImage, fit: BoxFit.contain),
              ),
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _focusController,
          enabled: !_generating,
          maxLines: null,
          minLines: 2,
          decoration: _fieldDecoration(c, 'Worum soll es gehen? Textauswahl aus dem PDF oder eigene Anweisung'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _answerController,
          enabled: !_generating,
          maxLines: null,
          minLines: 1,
          decoration: _fieldDecoration(c, 'Antwort/Fakt dazu (optional)'),
        ),
        const SizedBox(height: 20),
        _sectionTitle(c, 'Anzahl Fragen', 'Mehrere Fragen prüfen unterschiedliche Aspekte.'),
        SegmentedButton<int>(
          segments: [
            for (var n = 1; n <= PageQuestionCreationSheet.maxQuestions; n++)
              ButtonSegment(value: n, label: Text(n == 1 ? '1 Frage' : '$n Fragen')),
          ],
          selected: {_questionCount},
          onSelectionChanged: _generating ? null : (s) => setState(() => _questionCount = s.first),
        ),
        const SizedBox(height: 20),
        _sectionTitle(
          c,
          'Schwierigkeitsgrade',
          'Jede Frage in bis zu 3 Stufen, die nacheinander freigeschaltet werden. '
              '"KI entscheidet" wählt das passende Format je Stufe.',
        ),
        ..._slots.map((slot) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: slot.enabled,
                    onChanged: _generating ? null : (v) => setState(() => slot.enabled = v ?? false),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(slot.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<QuestionType?>(
                      isExpanded: true,
                      value: slot.type,
                      hint: const Text('KI entscheidet', style: TextStyle(fontSize: 13.5)),
                      disabledHint: Text(slot.type?.label ?? 'KI entscheidet', style: const TextStyle(fontSize: 13.5)),
                      onChanged: (!_generating && slot.enabled) ? (t) => setState(() => slot.type = t) : null,
                      items: [
                        const DropdownMenuItem<QuestionType?>(
                          value: null,
                          child: Text('KI entscheidet', style: TextStyle(fontSize: 13.5)),
                        ),
                        for (final t in AiService.pageQuestionTypes)
                          DropdownMenuItem<QuestionType?>(
                            value: t,
                            child: Text(t.label, style: const TextStyle(fontSize: 13.5)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (_generating || _enabledSlots.isEmpty) ? null : () => _generate(),
          icon: _generating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_outlined),
          label: Text(_questionCount == 1 ? 'Frage erstellen' : '$_questionCount Fragen erstellen'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
          ),
      ],
    );
  }

  Widget _buildPreview(AppColors c, List<_GeneratedQuestion> questions) {
    final flat = _flat;
    final index = _previewIndex.clamp(0, flat.length - 1);
    final position = flat[index];
    final question = questions[position.question];
    final card = question.tiers[position.tier];
    final level =
        position.tier < _generatedLevels.length ? _generatedLevels[position.tier] : 'Stufe ${position.tier + 1}';
    final label = [
      if (questions.length > 1) 'Frage ${position.question + 1}/${questions.length}',
      level,
      card.type.label,
    ].join(' · ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Vorherige',
                icon: const Icon(Icons.chevron_left),
                onPressed: index > 0 ? () => setState(() => _previewIndex = index - 1) : null,
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Nächste',
                icon: const Icon(Icons.chevron_right),
                onPressed: index < flat.length - 1 ? () => setState(() => _previewIndex = index + 1) : null,
              ),
            ],
          ),
        ),
        if (questions.length > 1)
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            value: question.keep,
            onChanged: (v) => setState(() => question.keep = v ?? true),
            title: Text('Frage ${position.question + 1} speichern', style: const TextStyle(fontSize: 13.5)),
          ),
        Expanded(
          child: QuestionAnswerView(
            key: ValueKey(card.id),
            card: card,
            isNew: false,
            onComplete: ({selfGrade, isCorrect}) {
              if (index < flat.length - 1) setState(() => _previewIndex = index + 1);
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
                      decoration: _fieldDecoration(c, 'z.B. "einfacher formulieren", "anderer Fokus"'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Überarbeiten',
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
