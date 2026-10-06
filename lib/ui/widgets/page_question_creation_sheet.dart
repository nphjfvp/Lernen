import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_settings.dart';
import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/image_crop.dart';
import '../../services/image_edit.dart';
import '../../services/question_parsing.dart';
import '../../theme/app_colors.dart';
import '../daily/question_answer_view.dart';
import '../study/script_match_runner.dart';
import 'confirm_delete_dialog.dart';
import 'image_editor_screen.dart';
import 'model_override_tile.dart';
import 'question_type_dropdown.dart';
import 'page_region_picker.dart';
import 'safe_set_state.dart';

/// "Frage erstellen" im Lernmodus (siehe MaterialViewerScreen): erzeugt aus
/// GENAU der gerade betrachteten Seite 1–5 Fragen, jede in bis zu 3
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
    this.aiFactory,
  });

  /// Nur für Tests: baut den KI-Zugang aus API-Key und Modell (sonst der
  /// echte [AiService]).
  final AiService Function(String apiKey, String model)? aiFactory;

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

  /// Wie viele Fragen auf einmal erstellt werden können – mehr gibt eine
  /// einzelne Seite selten her, und die Antwort der KI würde sehr lang.
  static const maxQuestions = 5;

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
  _GeneratedQuestion(this.tiers, {this.manual = false});
  final List<Flashcard> tiers;

  /// Selbst im Bild-Editor erstellt (nicht von der KI) – bleibt bei einer
  /// KI-Überarbeitung erhalten.
  final bool manual;
  bool keep = true;

  /// Bild ohne Abdeckungen/Texte und die Bearbeitungen darauf – so bleiben
  /// z.B. die von der KI gesetzten Abdeckungen im Bild-Editor einzeln
  /// verschieb- und entfernbar. [sharedImage] ist das daraus berechnete
  /// Bild, das die Stufen dieser Frage tragen.
  Uint8List? imageBase;
  List<ImageEdit> imageEdits = const [];
  String? sharedImage;
}

/// Abdeckungen etwas größer als der Kasten der KI, damit kein Rand der
/// Original-Beschriftung stehen bleibt.
Rect _paddedCover(ImageTarget c) {
  final padX = math.max(0.006, c.w * 0.08);
  final padY = math.max(0.006, c.h * 0.12);
  return Rect.fromLTRB(
    (c.x - c.w / 2 - padX).clamp(0.0, 1.0),
    (c.y - c.h / 2 - padY).clamp(0.0, 1.0),
    (c.x + c.w / 2 + padX).clamp(0.0, 1.0),
    (c.y + c.h / 2 + padY).clamp(0.0, 1.0),
  );
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
  Map<String, List<Rect>>? coversOut,
  String? sourceMaterialId,
  int? sourcePage,
  MaterialKind? sourceKind,
}) {
  final weight = defaultFlashcardWeightFor(sourceKind);
  final result = <List<Flashcard>>[];
  for (final group in groups.take(questionCount)) {
    final cards = <Flashcard>[];
    for (final entry in group.take(tierCount)) {
      final fixed = QuestionParsing.normalizeGeneratedFlashcard(entry);
      if (fixed == null) continue;
      final type = QuestionParsing.parseType(fixed['type'] as String?);
      // Bildfragen brauchen ihr Bild immer, andere nur, wenn die KI es für
      // nötig hält.
      final isImageType = type == QuestionType.diagramLabel || type == QuestionType.markImage;
      final targets = parseImageTargets(fixed['imageTargets']);
      final card = Flashcard(
        id: const Uuid().v4(),
        moduleId: moduleId,
        front: (fixed['front'] ?? '').toString(),
        back: (fixed['back'] ?? '').toString(),
        createdAt: now,
        due: now,
        type: type,
        unitId: unitId,
        // Bewusst gerade jetzt beim Betrachten dieser Seite gestellt –
        // soll unabhängig vom Einheiten-"behandelt"-Status zeitnah im
        // Daily Quiz auftauchen statt hinter einem Altbestand zu warten
        // (siehe Flashcard.priorityIntroduction).
        priorityIntroduction: true,
        needsCalculator: QuestionParsing.parseCalcFlag(fixed),
        options: QuestionParsing.parseOptions(fixed['options']),
        correctText: fixed['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(fixed['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(fixed['dragPairs']),
        htmlContent: fixed['htmlContent'] as String?,
        imageBase64: isImageType || entry['needsImage'] == true ? attachImageBase64 : null,
        imageTargets: targets,
        tableRows: parseTableRows(fixed['tableRows']),
        taskData: parseTaskData(fixed['taskData']),
        sourceMaterialId: sourceMaterialId,
        sourcePage: sourcePage,
        weight: weight,
      );
      cards.add(card);
      // Was abgedeckt werden soll: die Original-Beschriftungen der Stellen
      // (von der KI als Kasten geliefert) und weiterer verräterischer Text.
      if (isImageType && coversOut != null) {
        final covers = [
          ...QuestionParsing.imageCoversIn(fixed),
          if (type == QuestionType.diagramLabel)
            for (final t in targets ?? const <ImageTarget>[])
              if (t.w > 0 && t.h > 0) t,
        ];
        if (covers.isNotEmpty) coversOut[card.id] = [for (final c in covers) _paddedCover(c)];
      }
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
            imageTargets: t.imageTargets,
            tableRows: t.tableRows,
            taskData: t.taskData,
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
    imageTargets: base.imageTargets,
    tableRows: base.tableRows,
    taskData: base.taskData,
    variantChain: tiers.map((t) => t.type).toList(),
    pendingVariants: pending,
    unitId: base.unitId,
    priorityIntroduction: base.priorityIntroduction,
    needsCalculator: base.needsCalculator,
    sourceMaterialId: base.sourceMaterialId,
    sourcePage: base.sourcePage,
    miniLesson: base.miniLesson,
    weight: base.weight,
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

  /// Für DIESES Fenster gewähltes KI-Modell (null = Vision-Modell aus den
  /// Einstellungen) – z.B. ein stärkeres für Tabellen oder lange Aufgaben.
  String? _modelOverride;
  Rect? _focusRect;
  Uint8List? _focusImage;

  bool _generating = false;
  bool _saving = false;
  String? _error;
  List<_GeneratedQuestion>? _questions;
  List<String> _generatedLevels = const [];
  List<List<Map<String, dynamic>>>? _previousRaw;
  int _previewIndex = 0;

  /// Zählt Bild-Bearbeitungen hoch – die Vorschau braucht danach einen neuen
  /// Zustand (sie merkt sich das Bild).
  int _editRevision = 0;

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
    // Vorgaben aus den Einstellungen (Typ je Stufe) – vor dem Erstellen von
    // Hand weiter änderbar.
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings != null) {
      for (final slot in _slots) {
        final preferred = settings.pageTierType(slot.label);
        if (preferred != null && AiService.selectablePageQuestionTypes.contains(preferred)) {
          slot.type = preferred;
        }
      }
    }
  }

  /// Die aktuelle Typwahl aller drei Stufen als neue Vorgabe speichern.
  Future<void> _saveTypesAsDefault() async {
    final repo = context.read<SettingsRepository?>();
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final types = {
      for (final slot in _slots)
        if (slot.type != null) AppSettings.tierKey(slot.label): slot.type!.name,
    };
    await repo.update(repo.settings.copyWith(pageQuestionTierTypes: types));
    messenger.showSnackBar(const SnackBar(
      content: Text('Als Standard gespeichert – gilt beim nächsten "Frage erstellen" (änderbar in den Einstellungen).'),
    ));
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

  /// Hinweis, wann sich ein stärkeres Modell lohnt: Formate, die dem Modell
  /// viel abverlangen, oder eine Seite mit viel Inhalt.
  String? get _modelHint {
    final hard = _slots.any((s) =>
        s.enabled &&
        (s.type == QuestionType.table ||
            s.type == QuestionType.html ||
            s.type == QuestionType.diagramLabel ||
            s.type == QuestionType.markImage));
    if (hard) {
      return 'Tabellen, interaktive Seiten und Bildfragen gelingen mit einem stärkeren Modell meist besser.';
    }
    if (widget.pageText.length > 3000) {
      return 'Viel Inhalt auf der Seite – ein stärkeres Modell erfasst sie meist besser.';
    }
    return null;
  }

  String get _defaultModelId => context.read<SettingsRepository?>()?.settings.visionModelId ?? '';

  /// Mit dem (evtl. gewechselten) Modell alle KI-Fragen komplett neu
  /// erstellen – die Einstellungen darüber (Stufen, Fokus …) bleiben. Von
  /// Hand erstellte Bildfragen bleiben erhalten.
  Future<void> _regenerateWithModel() async {
    final ok = await confirmDelete(
      context,
      title: 'Alle Fragen neu erstellen?',
      message: 'Die aktuellen KI-Fragen werden durch neue ersetzt (selbst erstellte Bildfragen bleiben). '
          'Stufen, Fokus und Antwort-Vorgaben bleiben wie eingestellt.',
      confirmLabel: 'Neu erstellen',
    );
    if (!ok || !mounted) return;
    await _generate();
  }

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
      final modelId = _modelOverride ?? settings.visionModelId;
      final ai = widget.aiFactory?.call(settings.openRouterApiKey!, modelId) ??
          AiService(apiKey: settings.openRouterApiKey!, model: modelId);
      final focus = _focusController.text.trim();
      final answer = _answerController.text.trim();
      // Für Bildfragen bekommt die KI das Bild mit Koordinatenraster (auf
      // dem Ausschnitt, falls markiert – darauf beziehen sich dann die
      // Koordinaten), damit sie Stellen genauer setzt.
      final wantsPositions =
          slots.any((s) => s.type == QuestionType.diagramLabel || s.type == QuestionType.markImage);
      var pageImage = widget.pageImageBytes;
      var focusImage = _focusImage;
      if (wantsPositions) {
        if (focusImage != null) {
          focusImage = await drawCoordinateGrid(focusImage) ?? focusImage;
        } else {
          pageImage = await drawCoordinateGrid(pageImage) ?? pageImage;
        }
      }
      final groups = await ai.generateQuestionsFromPage(
        pageImageBytes: pageImage,
        pageText: widget.pageText,
        tiers: [for (final s in slots) (level: s.label, type: s.type)],
        questionCount: _questionCount,
        focusImageBytes: focusImage,
        focusText: focus.isEmpty ? null : focus,
        answerText: answer.isEmpty ? null : answer,
        examContext: widget.examContext,
        previousQuestions: refine ? _previousRaw : null,
        instruction: refine ? _instructionController.text.trim() : null,
        coordinateGrid: wantsPositions,
      );
      // Mit markiertem Bereich hängt an einer Bild-Frage genau dieser
      // Ausschnitt statt der ganzen Seite – verkleinert, weil das Bild in der
      // Datenbank liegt und bei jedem Sync mitreist.
      final attachSource = _focusImage ?? widget.pageImageBytes;
      final attach = await downscaleImage(attachSource) ?? attachSource;
      final attachBase64 = base64Encode(attach);
      final covers = <String, List<Rect>>{};
      final questions = buildPageQuestionCards(
        groups,
        moduleId: widget.material.moduleId,
        unitId: widget.material.unitId,
        questionCount: _questionCount == 0 ? AiService.maxAutoPageQuestions : _questionCount,
        tierCount: slots.length,
        attachImageBase64: attachBase64,
        now: DateTime.now(),
        coversOut: covers,
        sourceMaterialId: widget.material.id,
        sourcePage: widget.pageNumber,
        sourceKind: widget.material.kind,
      );
      final generated = [for (final tiers in questions) _GeneratedQuestion(tiers)];
      for (final question in generated) {
        await _applyAiCovers(question, attach, attachBase64, covers);
      }
      if (!mounted) return;
      if (refine && questions.isEmpty) {
        // Missglückte Überarbeitung: die bisherigen Fragen bleiben stehen.
        setState(() {
          _error = 'Die Überarbeitung hat keine gültige Frage geliefert.';
          _generating = false;
        });
        return;
      }
      final manual = (_questions ?? const <_GeneratedQuestion>[]).where((q) => q.manual).toList();
      setState(() {
        _questions = [...generated, ...manual];
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

  static ImageTargetMode? _targetModeFor(QuestionType type) => switch (type) {
        QuestionType.diagramLabel => ImageTargetMode.labels,
        QuestionType.markImage => ImageTargetMode.regions,
        _ => null,
      };

  /// Deckt die von der KI genannten Stellen (Original-Beschriftungen,
  /// verräterischer Text) im angehängten Bild ab – als bearbeitbare
  /// Abdeckungen, die sich im Bild-Editor noch verschieben oder entfernen
  /// lassen.
  Future<void> _applyAiCovers(
    _GeneratedQuestion question,
    Uint8List attach,
    String attachBase64,
    Map<String, List<Rect>> covers,
  ) async {
    final rects = [
      for (final t in question.tiers) ...?covers[t.id],
    ];
    if (rects.isEmpty) return;
    final edits = [for (final r in rects) CoverEdit(r)];
    final bytes = await applyImageEdits(attach, edits);
    if (bytes == null) return;
    final shown = base64Encode(bytes);
    question
      ..imageBase = attach
      ..imageEdits = edits
      ..sharedImage = shown;
    for (var i = 0; i < question.tiers.length; i++) {
      final t = question.tiers[i];
      if (t.imageBase64 == attachBase64) question.tiers[i] = t.copyWithImage(imageBase64: shown);
    }
  }

  /// Bild der Vorschau-Karte bearbeiten (abdecken, beschriften; bei
  /// Bildfragen auch Stellen/Bereiche). Die Abdeckung gilt für alle Stufen
  /// der Frage, die dasselbe Bild tragen. Kennt die Frage ihr Ausgangsbild
  /// (KI-Abdeckungen, selbst erstellte Bildfrage), bleiben die bisherigen
  /// Abdeckungen und Texte einzeln bearbeitbar.
  Future<void> _editPreviewImage(_GeneratedQuestion question, int tier) async {
    final card = question.tiers[tier];
    final base64 = card.imageBase64;
    if (base64 == null) return;
    final mode = _targetModeFor(card.type);
    final base = question.imageBase;
    final editable = base != null && base64 == question.sharedImage;
    final result = await showImageEditor(
      context,
      editable ? base : base64Decode(base64),
      targetMode: mode,
      targets: card.imageTargets ?? const [],
      edits: editable ? question.imageEdits : const [],
    );
    if (result == null || !mounted) return;
    // Vom Ausgangsbild aus ist das Ergebnis immer das neue Bild (auch wenn
    // alle Abdeckungen entfernt wurden); sonst nur, wenn sich etwas änderte.
    final newBase64 = editable || result.imageChanged ? base64Encode(result.bytes) : null;
    setState(() {
      for (var i = 0; i < question.tiers.length; i++) {
        final t = question.tiers[i];
        question.tiers[i] = t.copyWithImage(
          imageBase64: t.imageBase64 == base64 ? newBase64 : null,
          imageTargets: i == tier && mode != null ? result.targets : null,
        );
      }
      if (editable) {
        question
          ..imageEdits = result.edits
          ..sharedImage = newBase64;
      } else if (newBase64 != null) {
        question
          ..imageBase = base64Decode(base64)
          ..imageEdits = result.edits
          ..sharedImage = newBase64;
      }
      _editRevision++;
    });
  }

  /// Bildfrage ganz ohne KI: Seite bzw. markierten Bereich im Bild-Editor
  /// vorbereiten (Beschriftungen abdecken, Stellen/Bereich setzen), dann die
  /// Frage formulieren. Landet wie die KI-Fragen in der Vorschau.
  Future<void> _createImageQuestion(QuestionType type) async {
    final source = _focusImage ?? widget.pageImageBytes;
    final image = await downscaleImage(source) ?? source;
    if (!mounted) return;
    final result = await showImageEditor(context, image, targetMode: _targetModeFor(type), title: type.label);
    if (result == null || !mounted) return;
    final texts = await _askImageQuestionText(type);
    if (texts == null || !mounted) return;
    final now = DateTime.now();
    final card = Flashcard(
      id: const Uuid().v4(),
      moduleId: widget.material.moduleId,
      front: texts.front,
      back: texts.back,
      createdAt: now,
      due: now,
      type: type,
      unitId: widget.material.unitId,
      priorityIntroduction: true,
      imageBase64: base64Encode(result.bytes),
      imageTargets: result.targets,
      sourceMaterialId: widget.material.id,
      sourcePage: widget.pageNumber,
      weight: defaultFlashcardWeightFor(widget.material.kind),
    );
    final question = _GeneratedQuestion([card], manual: true)
      ..imageBase = image
      ..imageEdits = result.edits
      ..sharedImage = card.imageBase64;
    setState(() {
      _questions = [...?_questions, question];
      _previewIndex = _flat.length - 1;
      _error = null;
    });
  }

  Future<({String front, String back})?> _askImageQuestionText(QuestionType type) async {
    final front = TextEditingController(
      text: type == QuestionType.diagramLabel ? 'Beschrifte die nummerierten Stellen.' : '',
    );
    final back = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: front,
              autofocus: true,
              maxLines: null,
              decoration: InputDecoration(
                labelText: 'Frage',
                hintText: type == QuestionType.markImage ? 'Wo liegt …?' : null,
              ),
            ),
            if (type == QuestionType.markImage)
              TextField(
                controller: back,
                decoration: const InputDecoration(labelText: 'Was ist dort zu sehen? (optional)'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Übernehmen')),
        ],
      ),
    );
    final question = front.text.trim();
    if (ok != true || question.isEmpty) return null;
    return (front: question, back: back.text.trim());
  }

  Widget _manualImageButtons() => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          OutlinedButton.icon(
            onPressed: _generating ? null : () => _createImageQuestion(QuestionType.diagramLabel),
            icon: const Icon(Icons.label_outline, size: 18),
            label: const Text('Bild beschriften'),
          ),
          OutlinedButton.icon(
            onPressed: _generating ? null : () => _createImageQuestion(QuestionType.markImage),
            icon: const Icon(Icons.ads_click, size: 18),
            label: const Text('Bild markieren'),
          ),
        ],
      );

  Future<void> _save() async {
    final kept = (_questions ?? const <_GeneratedQuestion>[]).where((q) => q.keep).toList();
    if (kept.isEmpty) return;
    setState(() => _saving = true);
    final cards = [for (final q in kept) mergeTiersIntoChain(q.tiers)];
    await context.read<FlashcardRepository>().saveAll(cards);
    if (!mounted) return;
    // Stammt die Seite aus einem Übungsblatt: Erklärung im Skript suchen.
    unawaited(matchNewCardsToScript(context, cards));
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
        _sectionTitle(
          c,
          'Anzahl Fragen',
          'Mehrere Fragen prüfen unterschiedliche Aspekte der Seite. "KI" entscheidet selbst, wie viele '
              'die Seite hergibt (bis ${AiService.maxAutoPageQuestions}).',
        ),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: 0, label: Text('KI'), tooltip: 'KI entscheidet'),
            for (var n = 1; n <= PageQuestionCreationSheet.maxQuestions; n++)
              ButtonSegment(value: n, label: Text('$n')),
          ],
          selected: {_questionCount},
          onSelectionChanged: _generating ? null : (s) => setState(() => _questionCount = s.first),
        ),
        const SizedBox(height: 20),
        _sectionTitle(
          c,
          'Schwierigkeitsgrade',
          'Jede Frage in bis zu 3 Stufen, die nacheinander freigeschaltet werden. '
              '"KI entscheidet" wählt das passende Format je Stufe. "Interaktiv" ist nur '
              'auf Android/iOS eine interaktive Seite, sonst eine Karteikarte. Bei "Bild '
              'beschriften"/"Bild markieren" schätzt die KI die Stellen – in der Vorschau '
              'lassen sie sich im Bild-Editor korrigieren.',
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
                    child: QuestionTypeDropdown(
                      value: slot.type,
                      onChanged: (!_generating && slot.enabled) ? (t) => setState(() => slot.type = t) : null,
                    ),
                  ),
                ],
              ),
            )),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('save-tier-defaults'),
            onPressed: _generating ? null : _saveTypesAsDefault,
            icon: const Icon(Icons.push_pin_outlined, size: 16),
            label: const Text('Typ-Auswahl als Standard merken'),
          ),
        ),
        const SizedBox(height: 12),
        ModelOverrideTile(
          defaultId: _defaultModelId,
          overrideId: _modelOverride,
          vision: true,
          enabled: !_generating,
          hint: _modelHint,
          onChanged: (id) => setState(() => _modelOverride = id),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_generating || _enabledSlots.isEmpty) ? null : () => _generate(),
          icon: _generating
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome_outlined),
          label: Text(switch (_questionCount) {
            0 => 'Fragen erstellen (KI entscheidet)',
            1 => 'Frage erstellen',
            final n => '$n Fragen erstellen',
          }),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
          ),
        const SizedBox(height: 24),
        _sectionTitle(
          c,
          'Bildfrage selbst erstellen',
          'Ohne KI: Seite (bzw. markierten Bereich) öffnen, Beschriftungen abdecken und die Stellen '
              'zum Beschriften bzw. die richtige Stelle setzen.',
        ),
        _manualImageButtons(),
      ],
    );
  }

  Widget _buildPreview(AppColors c, List<_GeneratedQuestion> questions) {
    final flat = _flat;
    final index = _previewIndex.clamp(0, flat.length - 1);
    final position = flat[index];
    final question = questions[position.question];
    final card = question.tiers[position.tier];
    final level = question.manual
        ? 'Selbst erstellt'
        : (position.tier < _generatedLevels.length ? _generatedLevels[position.tier] : 'Stufe ${position.tier + 1}');
    final canEditImage = card.imageBase64 != null && !_generating;
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
        if (questions.length > 1) ...[
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (var q = 0; q < questions.length; q++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('Frage ${q + 1}', style: TextStyle(color: questions[q].keep ? null : c.inkMuted)),
                      selected: q == position.question,
                      // Springt zur leichtesten Stufe dieser Frage.
                      onSelected: (_) => setState(() => _previewIndex = flat.indexWhere((e) => e.question == q)),
                    ),
                  ),
              ],
            ),
          ),
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            value: question.keep,
            onChanged: (v) => setState(() => question.keep = v ?? true),
            title: Text('Frage ${position.question + 1} speichern', style: const TextStyle(fontSize: 13.5)),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (canEditImage && card.type != QuestionType.diagramLabel && card.type != QuestionType.markImage)
                IconButton(
                  tooltip: 'Bild entfernen',
                  onPressed: () => setState(() {
                    question.tiers[position.tier] = card.copyWithImage(clearImage: true);
                    _editRevision++;
                  }),
                  icon: const Icon(Icons.hide_image_outlined, size: 20),
                ),
              if (canEditImage)
                TextButton.icon(
                  onPressed: () => _editPreviewImage(question, position.tier),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(switch (card.type) {
                    QuestionType.diagramLabel => 'Bild & Stellen bearbeiten',
                    QuestionType.markImage => 'Bild & Bereich bearbeiten',
                    _ => 'Bild bearbeiten',
                  }),
                ),
              const Spacer(),
              PopupMenuButton<QuestionType>(
                tooltip: 'Bildfrage hinzufügen',
                enabled: !_generating,
                onSelected: _createImageQuestion,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: QuestionType.diagramLabel, child: Text('Bild beschriften (selbst)')),
                  PopupMenuItem(value: QuestionType.markImage, child: Text('Bild markieren (selbst)')),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.add_photo_alternate_outlined, size: 18), SizedBox(width: 4), Text('Bildfrage')],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: QuestionAnswerView(
            key: ValueKey('${card.id}-$_editRevision'),
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
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ModelOverrideTile(
                      defaultId: _defaultModelId,
                      overrideId: _modelOverride,
                      vision: true,
                      enabled: !_generating,
                      hint: _modelHint,
                      onChanged: (id) => setState(() => _modelOverride = id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Alle Fragen mit dem gewählten Modell neu erstellen',
                    child: OutlinedButton.icon(
                      key: const ValueKey('regenerate-with-model'),
                      onPressed: _generating ? null : _regenerateWithModel,
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Neu'),
                    ),
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
