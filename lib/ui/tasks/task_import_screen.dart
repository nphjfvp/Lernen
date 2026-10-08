import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/bom_task.dart';
import '../../models/crystal_task.dart';
import '../../models/sketch_task.dart';
import '../../models/flashcard.dart';
import '../../models/gantt_task.dart';
import '../../models/interactive_task.dart';
import '../../models/material_item.dart';
import '../../models/step_task.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/unsupported_task_repository.dart';
import '../../services/ai_service.dart';
import '../../services/bom_calculator.dart';
import '../../services/crystal_geometry.dart';
import '../../services/sketch_checker.dart';
import '../../services/fsrs_service.dart';
import '../../services/gantt_scheduler.dart';
import '../../services/image_crop.dart';
import '../../services/interactive_task_scan_service.dart';
import '../../services/plain_question_service.dart';
import '../../services/question_parsing.dart';
import '../../services/step_checker.dart';
import '../../theme/app_colors.dart';
import '../widgets/discard_guard.dart';
import '../widgets/page_question_creation_sheet.dart' show buildPageQuestionCards;
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'bom_task_editor.dart';
import 'bom_task_view.dart';
import 'crystal_task_editor.dart';
import 'crystal_task_view.dart';
import 'sketch_task_editor.dart';
import 'sketch_task_view.dart';
import 'gantt_task_editor.dart';
import 'gantt_task_view.dart';
import 'step_task_editor.dart';
import 'step_task_view.dart';
import 'unsupported_tasks_screen.dart';

enum _KindChoice { auto, steps, gantt, crystal, bom, sketch }

/// Eine von der KI gefundene (Teil-)Aufgabe im Bildschirm – bearbeitbar,
/// bis sie gespeichert wird.
class _Draft {
  _Draft(InteractiveTaskDraft d, String fallbackFront) {
    apply(d, fallbackFront);
  }

  InteractiveKind? kind;
  StepTask? steps;
  GanttTask? gantt;
  CrystalTask? crystal;
  BomTask? bom;
  SketchTask? sketch;
  final front = TextEditingController();
  final back = TextEditingController();
  String reason = '';
  String needs = '';
  bool incomplete = false;

  /// Passt als normale Quizfrage (siehe InteractiveTaskDraft.asQuestion).
  bool asQuestion = false;
  String questionType = '';

  /// Schon als normale Frage(n) angelegt (Anzahl Karten).
  int createdQuestions = 0;
  bool include = true;
  bool expanded = false;
  bool busy = false;
  String? error;

  /// Text, unter dem die Aufgabe auf der Sammelliste steht (null = nicht dort).
  String? listedText;

  /// Neu aufgebaute Editoren nach jedem KI-Ergebnis.
  int revision = 0;

  /// Aus einem ganzen Dokument gelesen: Seite, Seitenbild und Material
  /// (sonst gelten die des Bildschirms).
  int? page;
  Uint8List? image;
  String? materialId;
  String sourceName = '';

  bool get hasTask => switch (kind) {
    InteractiveKind.steps => steps != null,
    InteractiveKind.gantt => gantt != null,
    InteractiveKind.crystal => crystal != null,
    InteractiveKind.bom => bom != null,
    InteractiveKind.sketch => sketch != null,
    null => false,
  };

  void apply(InteractiveTaskDraft d, String fallbackFront) {
    kind = d.kind;
    steps = d.steps;
    gantt = d.gantt;
    crystal = d.crystal;
    bom = d.bom;
    sketch = d.sketch;
    front.text = d.front.trim().isNotEmpty ? d.front.trim() : fallbackFront;
    back.text = d.back.trim();
    reason = d.reason.trim();
    needs = d.needs.trim();
    incomplete = d.incomplete;
    asQuestion = d.asQuestion;
    questionType = d.questionType;
    include = hasTask;
    error = null;
    revision++;
  }

  void dispose() {
    front.dispose();
    back.dispose();
  }
}

/// Aufgabe übernehmen: aus einer Übungsaufgabe (Text und/oder Fotos, optional
/// mit vorhandener Lösung) werden interaktive Aufgaben – Rechenweg Schritt
/// für Schritt ([QuestionType.steps]), Terminierung im Gantt-Diagramm
/// ([QuestionType.gantt]), Kristallgitter im Würfel ([QuestionType.crystal]) oder
/// Stückliste aus einem Erzeugnisbaum ([QuestionType.bom]) oder Diagramm-Skizze
/// ([QuestionType.sketch]).
/// Stehen mehrere Teilaufgaben auf dem Foto, wird jede ein eigener Entwurf
/// (AiService.buildInteractiveTasks). Die KI schlägt Struktur und erwartete
/// Antworten vor, die App rechnet nach (StepChecker.verify, GanttScheduler,
/// CrystalGeometry). Was (noch) nicht passt, kommt mit Begründung und
/// fehlender Bedienart auf die Sammelliste „Noch nicht interaktiv“
/// (UnsupportedTaskRepository).
class TaskImportScreen extends StatefulWidget {
  const TaskImportScreen({
    super.key,
    required this.moduleId,
    this.moduleName = '',
    this.initialText = '',
    this.initialSolution = '',
    this.initialImages = const [],
    this.initialKind,
    this.sourceMaterialId,
    this.sourcePage,
    this.unitId,
    this.replaceCard,
    this.initialDrafts = const [],
    this.scanNotes = const [],
  });

  final String moduleId;
  final String moduleName;
  final String initialText;
  final String initialSolution;
  final List<Uint8List> initialImages;

  /// Vorgewählte Art; null = die KI entscheidet.
  final InteractiveKind? initialKind;

  /// Herkunft (Übungsblatt und Seite) – "Im Aufgabenblatt ansehen" führt dorthin.
  final String? sourceMaterialId;
  final int? sourcePage;
  final String? unitId;

  /// Aufgabe aus dem Aufgaben-Ordner, die hiermit interaktiv wird. Sie bleibt
  /// erhalten, außer man wählt beim Speichern "aus dem Ordner entfernen".
  final Flashcard? replaceCard;

  /// Schon aus einem ganzen Dokument gelesene Aufgaben (siehe
  /// InteractiveTaskScanService) – dann entfällt die Eingabe oben.
  final List<ScannedTaskDraft> initialDrafts;

  /// Hinweise vom Lesen des Dokuments (z.B. Abschnitte, die nicht gelesen
  /// werden konnten).
  final List<String> scanNotes;

  bool get fromDocument => initialDrafts.isNotEmpty;

  static const maxImages = 4;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs.
  @visibleForTesting
  static Future<List<({String name, Uint8List bytes})>> Function()? pickImagesHook;

  @override
  State<TaskImportScreen> createState() => _TaskImportScreenState();
}

class _TaskImportScreenState extends State<TaskImportScreen> with SafeSetState<TaskImportScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  late final _solution = TextEditingController(text: widget.initialSolution);
  late final List<({String name, Uint8List bytes})> _images = [
    for (final (i, bytes) in widget.initialImages.indexed) (name: 'Seite ${widget.sourcePage ?? i + 1}', bytes: bytes),
  ];
  late _KindChoice _choice = switch (widget.initialKind) {
    InteractiveKind.steps => _KindChoice.steps,
    InteractiveKind.gantt => _KindChoice.gantt,
    InteractiveKind.crystal => _KindChoice.crystal,
    InteractiveKind.bom => _KindChoice.bom,
    InteractiveKind.sketch => _KindChoice.sketch,
    null => _KindChoice.auto,
  };

  bool _busy = false;
  bool _saving = false;
  String? _error;
  String? _raw;
  final List<_Draft> _drafts = [];

  bool _attachImage = false;
  bool _removeReplaced = false;

  bool get _hasTasks => _drafts.any((d) => d.hasTask);
  List<_Draft> get _toSave => [
    for (final d in _drafts)
      if (d.hasTask && d.include) d,
  ];

  @override
  void initState() {
    super.initState();
    // Bei einem Seitenbild gehört die Abbildung meist zur Aufgabe.
    _attachImage = widget.initialImages.length == 1 && widget.sourcePage != null;
    if (widget.fromDocument) {
      for (final scanned in widget.initialDrafts) {
        _drafts.add(
          _Draft(scanned.draft, '')
            ..page = scanned.page
            ..image = scanned.pageImage
            ..materialId = scanned.materialId
            ..sourceName = scanned.sourceName
            ..expanded = false,
        );
      }
      (_drafts.where((d) => d.hasTask).firstOrNull ?? _drafts.first).expanded = true;
      _attachImage = _drafts.any((d) => d.image != null);
      WidgetsBinding.instance.addPostFrameCallback((_) => _collectUnsupported(_drafts));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _solution.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  AiService? _ai({required bool vision}) {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    final model = vision ? settings.visionModelId : settings.questionModelId;
    return TaskImportScreen.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
  }

  InteractiveKind? get _wanted => switch (_choice) {
    _KindChoice.auto => null,
    _KindChoice.steps => InteractiveKind.steps,
    _KindChoice.gantt => InteractiveKind.gantt,
    _KindChoice.crystal => InteractiveKind.crystal,
    _KindChoice.bom => InteractiveKind.bom,
    _KindChoice.sketch => InteractiveKind.sketch,
  };

  Future<void> _pickImages() async {
    final room = TaskImportScreen.maxImages - _images.length;
    if (room <= 0) return;
    final List<({String name, Uint8List bytes})> picked;
    final hook = TaskImportScreen.pickImagesHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      picked = [for (final f in files.take(room)) (name: f.name, bytes: await f.readAsBytes())];
    }
    final prepared = [for (final p in picked.take(room)) (name: p.name, bytes: await prepareImageForAi(p.bytes))];
    if (!mounted) return;
    setState(() => _images.addAll(prepared));
  }

  /// Text, unter dem eine Aufgabe ohne eigenen Wortlaut gesammelt wird.
  String get _fallbackFront {
    final text = _text.text.trim();
    if (text.isNotEmpty) return text;
    if (_images.isEmpty) return '';
    return widget.sourcePage != null ? 'Aufgabe von Seite ${widget.sourcePage}' : 'Aufgabe von einem Foto';
  }

  Future<void> _build() async {
    if (_text.text.trim().isEmpty && _images.isEmpty) {
      setState(() => _error = 'Gib die Aufgabe als Text ein oder füge ein Foto hinzu.');
      return;
    }
    final ai = _ai(vision: _images.isNotEmpty);
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _raw = null;
    });
    try {
      final result = await ai.buildInteractiveTasks(
        text: _text.text,
        images: [for (final i in _images) i.bytes],
        solution: _solution.text,
        kind: _wanted,
      );
      final fallback = _fallbackFront;
      final drafts = [for (final r in result) _Draft(r, fallback)];
      // Aufklappen: bei einer Aufgabe diese, sonst die erste brauchbare.
      (drafts.where((d) => d.hasTask).firstOrNull ?? drafts.first).expanded = true;
      // Bei Stücklisten gehört der Original-Erzeugnisbaum dazu.
      if (_images.isNotEmpty && drafts.any((d) => d.kind == InteractiveKind.bom)) _attachImage = true;
      setState(() {
        for (final d in _drafts) {
          d.dispose();
        }
        _drafts
          ..clear()
          ..addAll(drafts);
      });
      await _collectUnsupported(drafts);
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _raw = e.rawResponse;
      });
    } catch (e) {
      setState(() => _error = 'Erstellen fehlgeschlagen: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  String? _materialOf(_Draft d) => d.materialId ?? widget.sourceMaterialId ?? widget.replaceCard?.sourceMaterialId;
  int? _pageOf(_Draft d) => d.page ?? widget.sourcePage ?? widget.replaceCard?.sourcePage;

  /// Die Bilder einer Teilaufgabe: ihre Dokumentseite bzw. die Fotos oben.
  List<Uint8List> _imagesOf(_Draft d) => d.image != null ? [d.image!] : [for (final i in _images) i.bytes];

  /// Was die KI als "passt nicht" eingestuft hat (nicht bloß unvollständig),
  /// kommt automatisch auf die Sammelliste.
  Future<void> _collectUnsupported(List<_Draft> drafts) async {
    if (!mounted) return;
    final list = context.read<UnsupportedTaskRepository?>();
    if (list == null) return;
    for (final d in drafts) {
      if (d.kind != null || d.incomplete || d.asQuestion || d.listedText != null) continue;
      final text = d.front.text.trim();
      if (text.isEmpty) continue;
      try {
        await list.add(
          moduleId: widget.moduleId,
          text: text,
          reason: d.reason,
          needs: d.needs,
          sourceMaterialId: _materialOf(d),
          sourcePage: _pageOf(d),
        );
        d.listedText = text;
      } catch (_) {
        // Die Sammelliste ist nur eine Hilfe – der Import geht trotzdem weiter.
      }
    }
    if (mounted) setState(() {});
  }

  /// Eine Teilaufgabe neu erstellen lassen (optional als bestimmte Art).
  Future<void> _retry(_Draft d, {InteractiveKind? force}) async {
    final images = _imagesOf(d);
    final ai = _ai(vision: images.isNotEmpty);
    if (ai == null) return _snack('Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
    final listed = d.listedText;
    setState(() {
      d.busy = true;
      d.error = null;
    });
    try {
      final result = await ai.buildInteractiveTasks(
        text: d.front.text.trim().isNotEmpty ? d.front.text : _text.text,
        images: images,
        solution: _solution.text,
        kind: force ?? _wanted,
      );
      final best = result.where((r) => r.isUsable).firstOrNull ?? result.first;
      setState(() {
        d.apply(best, d.front.text.trim().isNotEmpty ? d.front.text.trim() : _fallbackFront);
        d.expanded = true;
        // Bleibt sie auf der Liste, wird nur die Begründung aktualisiert.
        d.listedText = listed;
      });
      if (d.kind == null && !d.incomplete) {
        d.listedText = null;
        await _collectUnsupported([d]);
      }
    } on AiServiceException catch (e) {
      setState(() => d.error = e.message);
    } catch (e) {
      setState(() => d.error = 'Erstellen fehlgeschlagen: $e');
    } finally {
      setState(() => d.busy = false);
    }
  }

  /// Karte aus dem aktuellen Stand – zum Ausprobieren und Speichern.
  Flashcard _card(_Draft d, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final kind = d.kind!;
    final materialId = _materialOf(d);
    final material = materialId == null
        ? null
        : context
              .read<MaterialRepository?>()
              ?.forModule(widget.moduleId)
              .where((m) => m.id == materialId)
              .firstOrNull;
    final back = switch (kind) {
      InteractiveKind.gantt => GanttScheduler.solutionText(d.gantt!),
      InteractiveKind.crystal =>
        d.back.text.trim().isNotEmpty ? d.back.text.trim() : CrystalGeometry.solutionText(d.crystal!),
      InteractiveKind.steps => d.back.text.trim(),
      InteractiveKind.bom => BomCalculator(d.bom!).fullSolution(),
      InteractiveKind.sketch =>
        d.back.text.trim().isNotEmpty ? d.back.text.trim() : SketchChecker.solutionText(d.sketch!),
    };
    return Flashcard(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      front: d.front.text.trim(),
      back: back,
      createdAt: at,
      due: at,
      type: kind.type,
      taskData: switch (kind) {
        InteractiveKind.steps => d.steps?.toMap(),
        InteractiveKind.gantt => d.gantt?.confirmed().toMap(),
        InteractiveKind.crystal => d.crystal?.confirmed().toMap(),
        InteractiveKind.bom => d.bom?.confirmed().toMap(),
        InteractiveKind.sketch => d.sketch?.confirmed().toMap(),
      },
      imageBase64: _attachImage && _imagesOf(d).isNotEmpty && (kind == InteractiveKind.steps || kind == InteractiveKind.bom)
          ? base64Encode(_imagesOf(d).first)
          : null,
      unitId: widget.unitId ?? widget.replaceCard?.unitId,
      sourceMaterialId: _materialOf(d),
      sourcePage: _pageOf(d),
      // Selbst übernommene Aufgaben sollen bald drankommen, unabhängig vom
      // Einheiten-Gate (siehe Flashcard.priorityIntroduction).
      priorityIntroduction: true,
      weight: defaultFlashcardWeightFor(material?.kind ?? MaterialKind.exercise),
    );
  }

  /// Was vor dem Speichern noch fehlt (null = alles da).
  String? _missing(_Draft d) {
    if (d.front.text.trim().isEmpty) return 'Die Aufgabe (Text) darf nicht leer sein.';
    switch (d.kind) {
      case InteractiveKind.steps:
        final steps = d.steps;
        if (steps == null || !steps.isUsable) {
          return 'Jeder Schritt braucht ein Eingabefeld oder eine richtige Auswahl-Antwort.';
        }
        if (steps.finalField == null && steps.steps.every((s) => s.isChoice)) {
          return 'Es fehlt ein Feld für das Endergebnis.';
        }
      case InteractiveKind.gantt:
        final gantt = d.gantt;
        if (gantt == null || !gantt.isValid) {
          return 'Die Teile passen nicht zusammen (fehlende Arbeitsgänge oder ein Kreis in der Reihenfolge).';
        }
        if (!gantt.drawChart && gantt.questions.isEmpty) {
          return 'Wähle, was gefragt ist, oder lass das Diagramm zeichnen.';
        }
      case InteractiveKind.crystal:
        final crystal = d.crystal;
        if (crystal == null || !crystal.isUsable) return 'Jede Teilaufgabe braucht drei Indizes (nicht alle 0).';
        final problems = CrystalGeometry.problems(crystal);
        if (problems.isNotEmpty) return problems.first;
      case InteractiveKind.bom:
        final bom = d.bom;
        if (bom == null || !bom.isUsable) {
          return 'Der Erzeugnisbaum braucht ein Erzeugnis mit Bestandteilen und mindestens eine gefragte Liste.';
        }
        final problems = BomCalculator(bom).problems();
        if (problems.isNotEmpty) return problems.first;
      case InteractiveKind.sketch:
        final sketch = d.sketch;
        if (sketch == null || !sketch.isUsable) {
          return 'Die Skizze braucht Achsen (von < bis), eine Musterkurve und gültige Merkmale.';
        }
      case null:
        return 'Erst eine Aufgabe erstellen.';
    }
    return null;
  }

  /// Hinweise, bei denen man bewusst trotzdem speichern kann.
  List<String> _warnings(_Draft d) => switch (d.kind) {
    InteractiveKind.steps => StepChecker.verify(d.steps!).problems,
    InteractiveKind.gantt => [
      if (d.gantt!.hasUncertain) 'Manche Werte waren schlecht lesbar und sind noch nicht bestätigt.',
      ...GanttScheduler.plan(d.gantt!).problems,
    ],
    InteractiveKind.crystal => [
      if (d.crystal!.hasUncertain) 'Manche Indizes waren schlecht lesbar und sind noch nicht bestätigt.',
    ],
    InteractiveKind.bom => [
      if (d.bom!.hasUncertain) 'Manche Mengen oder Sach-Nr. waren schlecht lesbar und sind noch nicht bestätigt.',
    ],
    InteractiveKind.sketch => [
      if (d.sketch!.uncertain) 'Achsen oder Merkmale waren unklar und sind noch nicht bestätigt.',
      ...SketchChecker.selfCheck(d.sketch!),
    ],
    null => const [],
  };

  String _title(int i) {
    final d = _drafts[i];
    final first = d.front.text.trim().split('\n').first.trim();
    final label = first.isEmpty ? 'Teilaufgabe' : first;
    final page = d.page == null ? '' : 'S. ${d.page} · ';
    return _drafts.length == 1 ? '$page$label' : '${i + 1}. $page$label';
  }

  /// Kurzer Stand in der Kopfzeile der Teilaufgabe.
  ({String text, bool ok}) _status(_Draft d) {
    if (d.busy) return (text: 'KI liest …', ok: true);
    if (!d.hasTask) {
      if (d.incomplete) return (text: 'unvollständig', ok: false);
      if (d.createdQuestions > 0) return (text: 'als normale Frage erstellt', ok: true);
      if (d.asQuestion) {
        return d.listedText != null ? (text: 'auf der Liste', ok: false) : (text: 'passt als normale Frage', ok: true);
      }
      return (text: d.listedText != null ? 'auf der Liste' : 'passt nicht', ok: false);
    }
    if (_missing(d) != null) return (text: 'unvollständig', ok: false);
    if (_warnings(d).isNotEmpty) return (text: 'bitte prüfen', ok: false);
    return (text: d.kind == InteractiveKind.steps ? 'nachgerechnet' : 'bereit', ok: true);
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _try(_Draft d) async {
    final missing = _missing(d);
    if (missing != null) return _snack(missing);
    final card = _card(d);
    final outcome = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => _TryTaskScreen(card: card)));
    if (outcome != null && mounted) _snack(outcome);
  }

  Future<void> _save() async {
    final drafts = _toSave;
    if (drafts.isEmpty) {
      setState(() => _error = 'Wähle mindestens eine Aufgabe zum Speichern aus.');
      return;
    }
    for (final d in drafts) {
      final missing = _missing(d);
      if (missing != null) {
        setState(() {
          d.expanded = true;
          _error = drafts.length == 1 ? missing : '${_title(_drafts.indexOf(d))}: $missing';
        });
        return;
      }
    }
    final warnings = [
      for (final d in drafts)
        for (final w in _warnings(d)) _drafts.length == 1 ? w : '${_title(_drafts.indexOf(d))}: $w',
    ];
    if (warnings.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Trotzdem speichern?'),
          content: SingleChildScrollView(
            child: Text(
              'Die App hat noch etwas gefunden:\n\n${warnings.map((w) => '• $w').join('\n')}'
              '\n\nUnsicher, was das bedeutet? Mit „Prüfen“ zurück – in der Prüf-Box des Rechenwegs erklärt '
              '„Was heißt das? KI erklären & prüfen lassen“ es und schlägt bei Bedarf eine Korrektur vor.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Prüfen')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Speichern')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final repo = context.read<FlashcardRepository>();
    final list = context.read<UnsupportedTaskRepository?>();
    final cards = [for (final d in drafts) _card(d)];
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await repo.saveAll(cards);
      final replaced = widget.replaceCard;
      if (_removeReplaced && replaced != null) await repo.delete(replaced.id, replaced.moduleId);
      // Doch noch interaktiv geworden: von der Sammelliste nehmen.
      for (final d in drafts) {
        final listed = d.listedText;
        if (listed != null && list != null) await list.removeText(widget.moduleId, listed);
      }
      if (!mounted) return;
      _snack(
        cards.length == 1
            ? '${cards.single.type.label}-Aufgabe gespeichert – sie kommt bald im Lernplan dran.'
            : '${cards.length} Aufgaben gespeichert – sie kommen bald im Lernplan dran.',
      );
      Navigator.of(context).pop(cards);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Speichern fehlgeschlagen: $e';
      });
    }
  }

  void _openList() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => UnsupportedTasksScreen(moduleId: widget.moduleId, moduleName: widget.moduleName),
    ),
  );

  String get _saveLabel {
    final n = _toSave.length;
    return n == 1 ? 'Speichern' : '$n Aufgaben speichern';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    return DiscardGuard(
      active: _hasTasks && !_saving,
      message: _drafts.length == 1
          ? 'Die erstellte Aufgabe ist noch nicht gespeichert.'
          : 'Die erstellten Aufgaben sind noch nicht gespeichert.',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aufgabe übernehmen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (widget.moduleName.isNotEmpty)
                Text(widget.moduleName, style: TextStyle(fontSize: 12, color: c.inkMuted)),
            ],
          ),
          actions: [
            IconButton(
              key: const ValueKey('task-import-list'),
              tooltip: 'Liste „Noch nicht interaktiv“',
              onPressed: _openList,
              icon: const Icon(Icons.playlist_add_check),
            ),
            if (_hasTasks)
              TextButton(
                key: const ValueKey('task-import-save-top'),
                onPressed: _saving || _toSave.isEmpty ? null : _save,
                child: Text(_saveLabel),
              ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                children: [
                  if (widget.fromDocument) _documentCard(c) else _inputCard(c, hasKey),
                  if (_error != null) ...[const SizedBox(height: 12), _errorCard(c)],
                  if (_drafts.isNotEmpty) ..._draftList(c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(AppColors c, {required Widget child, Color? tint, Key? key, EdgeInsets? padding}) => Container(
    key: key,
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: tint ?? c.surface,
      border: tint == null ? Border.all(color: c.border) : null,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  /// Statt der Eingabe: woher die Aufgaben stammen.
  Widget _documentCard(AppColors c) {
    final names = {for (final d in _drafts) if (d.sourceName.isNotEmpty) d.sourceName};
    return _panel(
      c,
      key: const ValueKey('task-import-document'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aus ${names.isEmpty ? 'dem Dokument' : names.join(', ')}: jede gefundene Aufgabe steht unten mit ihrer '
            'Seite. Prüf sie mit dem Blatt, wähl ab, was du nicht willst, und speichere den Rest auf einmal.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
          ),
          for (final note in widget.scanNotes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(note, style: TextStyle(fontSize: 12, height: 1.35, color: c.warn)),
            ),
        ],
      ),
    );
  }

  Widget _inputCard(AppColors c, bool hasKey) {
    return _panel(
      c,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Aus einer Übungsaufgabe wird eine interaktive Aufgabe: ein Rechenweg Schritt für Schritt (z. B. '
            'Differentialgleichungen, Integrale, Werkstoff- oder BWL-Rechnungen), eine Terminierung im '
            'Gantt-Diagramm, Richtungen und Ebenen im Kristallgitter, Stücklisten aus einem Erzeugnisbaum oder '
            'Kurven in einem Diagramm skizzieren. '
            'Die KI liest die Aufgabe – auch mehrere Teilaufgaben von einem Foto –, die App rechnet und zeichnet '
            'alles nach.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_KindChoice>(
              key: const ValueKey('task-import-kind'),
              segments: const [
                ButtonSegment(value: _KindChoice.auto, label: Text('Automatisch')),
                ButtonSegment(value: _KindChoice.steps, label: Text('Rechenweg')),
                ButtonSegment(value: _KindChoice.gantt, label: Text('Terminierung')),
                ButtonSegment(value: _KindChoice.crystal, label: Text('Kristall')),
                ButtonSegment(value: _KindChoice.bom, label: Text('Stückliste')),
                ButtonSegment(value: _KindChoice.sketch, label: Text('Skizze')),
              ],
              selected: {_choice},
              showSelectedIcon: false,
              onSelectionChanged: _busy ? null : (s) => setState(() => _choice = s.first),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('task-import-text'),
            controller: _text,
            minLines: 3,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Aufgabe',
              hintText: 'Aufgabentext einfügen – bei einem Foto reicht, welche Aufgabe (z. B. „Aufgabe 2b“), sonst werden alle übernommen',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('task-import-add-image'),
                onPressed: _busy || _images.length >= TaskImportScreen.maxImages ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(_images.isEmpty ? 'Foto der Aufgabe' : 'Weiteres Foto'),
              ),
              for (final (i, image) in _images.indexed)
                InputChip(
                  key: ValueKey('task-import-image-$i'),
                  avatar: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      image.bytes,
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.image_outlined, size: 18),
                    ),
                  ),
                  label: Text(image.name, overflow: TextOverflow.ellipsis),
                  onDeleted: _busy ? null : () => setState(() => _images.removeAt(i)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('task-import-solution'),
            controller: _solution,
            minLines: 1,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Lösung (optional)',
              hintText: 'Vorhandene Musterlösung – hilft der KI, die Schritte richtig aufzuteilen',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('task-import-build'),
            onPressed: hasKey && !_busy ? _build : null,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_drafts.isNotEmpty ? Icons.refresh : Icons.auto_awesome_outlined, size: 18),
            label: Text(
              _busy ? 'KI liest die Aufgabe …' : (_drafts.isNotEmpty ? 'Neu erstellen' : 'Aufgabe erstellen'),
            ),
          ),
          if (!hasKey)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).',
                style: TextStyle(fontSize: 12.5, color: c.warn),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorCard(AppColors c) => _panel(
    c,
    tint: c.dangerSoft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _error!,
          key: const ValueKey('task-import-error'),
          style: TextStyle(color: c.danger, height: 1.35),
        ),
        if (_raw != null)
          TextButton(onPressed: () => showRawResponseDialog(context, _raw!), child: const Text('Rohantwort anzeigen')),
      ],
    ),
  );

  List<Widget> _draftList(AppColors c) {
    final usable = _drafts.where((d) => d.hasTask).length;
    final listed = _drafts.where((d) => d.listedText != null).length;
    return [
      const SizedBox(height: 20),
      Text(
        _drafts.length == 1
            ? 'Vorschau'
            : 'Die KI hat ${_drafts.length} ${widget.fromDocument ? 'Aufgaben im Dokument' : 'Teilaufgaben'} gefunden'
                  '${usable == _drafts.length ? '' : ' – $usable davon interaktiv'}.',
        key: const ValueKey('task-import-found'),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        'Prüf jede Aufgabe mit dem Blatt – was gezeichnet oder gerechnet wird, prüft die App selbst nach.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
      ),
      if (listed > 0) ...[const SizedBox(height: 10), _listNote(c, listed)],
      for (final (i, d) in _drafts.indexed) ...[const SizedBox(height: 12), _draftCard(c, i, d)],
      if (_hasTasks) ...[
        if (_toSave.any((d) => _imagesOf(d).isNotEmpty && (d.kind == InteractiveKind.steps || d.kind == InteractiveKind.bom)))
          SwitchListTile(
            key: const ValueKey('task-import-attach-image'),
            contentPadding: EdgeInsets.zero,
            value: _attachImage,
            onChanged: (v) => setState(() => _attachImage = v),
            title: const Text('Foto bei Rechenweg- und Stücklisten-Aufgaben anzeigen'),
            subtitle: const Text('Sinnvoll, wenn eine Skizze, Tabelle oder der Erzeugnisbaum zur Aufgabe gehört.'),
          ),
        if (widget.replaceCard != null)
          CheckboxListTile(
            key: const ValueKey('task-import-remove-replaced'),
            contentPadding: EdgeInsets.zero,
            value: _removeReplaced,
            onChanged: (v) => setState(() => _removeReplaced = v ?? false),
            title: const Text('Aus dem Aufgaben-Ordner entfernen'),
            subtitle: const Text('Sonst bleibt die Aufgabe zusätzlich dort mit ihrer Erklärung.'),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('task-import-save'),
            onPressed: _saving || _toSave.isEmpty ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 18),
            label: Text(_saveLabel),
          ),
        ),
      ],
    ];
  }

  Widget _listNote(AppColors c, int listed) => _panel(
    c,
    key: const ValueKey('task-import-listed'),
    tint: c.warnSoft,
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    child: Row(
      children: [
        Icon(Icons.playlist_add_check, color: c.warn, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            listed == 1
                ? '1 Aufgabe passt noch nicht und steht jetzt auf der Liste „Noch nicht interaktiv“.'
                : '$listed Aufgaben passen noch nicht und stehen jetzt auf der Liste „Noch nicht interaktiv“.',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: c.ink),
          ),
        ),
        TextButton(
          key: const ValueKey('task-import-open-list'),
          onPressed: _openList,
          child: const Text('Liste ansehen'),
        ),
      ],
    ),
  );

  IconData _icon(InteractiveKind? kind) => switch (kind) {
    InteractiveKind.steps => Icons.functions,
    InteractiveKind.gantt => Icons.view_timeline_outlined,
    InteractiveKind.crystal => Icons.view_in_ar_outlined,
    InteractiveKind.bom => Icons.account_tree_outlined,
    InteractiveKind.sketch => Icons.show_chart,
    null => Icons.block_outlined,
  };

  Widget _draftCard(AppColors c, int i, _Draft d) {
    final status = _status(d);
    // Material statt Container: die Editoren enthalten ListTiles, die ihren
    // Hintergrund auf dem nächsten Material malen.
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('task-import-draft-$i'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => d.expanded = !d.expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
              child: Row(
                children: [
                  if (d.hasTask)
                    Checkbox(
                      key: ValueKey('task-import-include-$i'),
                      value: d.include,
                      onChanged: _saving ? null : (v) => setState(() => d.include = v ?? false),
                    )
                  else
                    const SizedBox(width: 12),
                  Icon(d.asQuestion ? Icons.quiz_outlined : _icon(d.kind), size: 20, color: d.hasTask ? c.accent : c.inkMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title(i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${d.kind?.label ?? (d.asQuestion ? 'Normale Frage' : 'Noch nicht interaktiv')} · ${status.text}',
                          key: ValueKey('task-import-status-$i'),
                          style: TextStyle(fontSize: 12, color: status.ok ? c.good : c.warn),
                        ),
                      ],
                    ),
                  ),
                  Icon(d.expanded ? Icons.expand_less : Icons.expand_more, color: c.inkMuted),
                ],
              ),
            ),
          ),
          if (d.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: d.hasTask ? _taskBody(c, i, d) : _unsuitableBody(c, i, d),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _taskBody(AppColors c, int i, _Draft d) {
    final kind = d.kind!;
    return [
      Text(switch (kind) {
        InteractiveKind.steps =>
          'Prüf die Schritte und erwarteten Antworten. Die App setzt jede Antwort selbst ein und meldet Widersprüche.',
        InteractiveKind.gantt => 'Vergleiche Teile, Dauern und Termine mit dem Blatt – die Musterlösung rechnet die App bei jeder Änderung neu.',
        InteractiveKind.crystal => 'Vergleiche Gitter und Indizes mit dem Blatt (Striche über den Zahlen!) – die Musterlösung zeichnet die App selbst.',
        InteractiveKind.bom =>
          'Vergleiche den Baum (Sach-Nr., Mengen an den Linien) mit dem Blatt – die Stücklisten rechnet die App selbst.',
        InteractiveKind.sketch =>
          'Prüf Achsen, Musterkurve und Merkmale – die App prüft Skizzen grob an diesen Merkmalen, nicht pixelgenau.',
      }, style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted)),
      const SizedBox(height: 12),
      TextField(
        key: ValueKey('task-import-front-$i'),
        controller: d.front,
        minLines: 2,
        maxLines: 12,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Aufgabe (wie im Dokument)', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 14),
      switch (kind) {
        InteractiveKind.steps => StepTaskEditor(
          key: ValueKey('task-import-steps-$i-${d.revision}'),
          task: d.steps!,
          taskText: d.front.text,
          onChanged: (t) => setState(() => d.steps = t),
        ),
        InteractiveKind.gantt => GanttTaskEditor(
          key: ValueKey('task-import-gantt-$i-${d.revision}'),
          task: d.gantt!,
          onChanged: (t) => setState(() => d.gantt = t),
        ),
        InteractiveKind.crystal => CrystalTaskEditor(
          key: ValueKey('task-import-crystal-$i-${d.revision}'),
          task: d.crystal!,
          onChanged: (t) => setState(() => d.crystal = t),
        ),
        InteractiveKind.bom => BomTaskEditor(
          key: ValueKey('task-import-bom-$i-${d.revision}'),
          task: d.bom!,
          onChanged: (t) => setState(() => d.bom = t),
        ),
        InteractiveKind.sketch => SketchTaskEditor(
          key: ValueKey('task-import-sketch-$i-${d.revision}'),
          task: d.sketch!,
          onChanged: (t) => setState(() => d.sketch = t),
        ),
      },
      if (kind != InteractiveKind.gantt && kind != InteractiveKind.bom) ...[
        const SizedBox(height: 12),
        TextField(
          key: ValueKey('task-import-back-$i'),
          controller: d.back,
          minLines: 2,
          maxLines: 14,
          decoration: InputDecoration(
            labelText: kind == InteractiveKind.steps
                ? 'Lösungsweg als Text (für „Lösung ansehen“)'
                : 'Erklärung (optional – sonst schreibt die App die Lösung)',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          key: ValueKey('task-import-try-$i'),
          onPressed: _saving ? null : () => _try(d),
          icon: const Icon(Icons.play_arrow_outlined, size: 18),
          label: const Text('Ausprobieren'),
        ),
      ),
    ];
  }

  /// Fragetyp-Vorschlag der KI lesbar ("free_text" → "Freitext").
  static String _typeLabel(String raw) {
    if (raw.trim().isEmpty) return '';
    final type = QuestionParsing.parseType(raw);
    return type == QuestionType.flashcard && !raw.toLowerCase().contains('flash') ? raw : type.label;
  }

  /// Aufgabe, die als normale Quizfrage passt: Karten wie beim Fragen-Import anlegen.
  Future<void> _createAsQuestion(_Draft d) async {
    final images = _imagesOf(d);
    final ai = _ai(vision: images.isNotEmpty);
    if (ai == null) return _snack('Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
    final text = d.front.text.trim().isNotEmpty ? d.front.text.trim() : _fallbackFront;
    if (text.isEmpty) return _snack('Die Aufgabe (Text) darf nicht leer sein.');
    final repo = context.read<FlashcardRepository>();
    final list = context.read<UnsupportedTaskRepository?>();
    setState(() {
      d.busy = true;
      d.error = null;
    });
    try {
      // Mit Foto: die KI sieht die Aufgabe samt Tabellen/Abbildungen (oft
      // steht das Entscheidende nur im Bild); sonst bzw. wenn das nichts
      // ergibt, nur aus dem Text.
      var cards = images.isEmpty ? <Flashcard>[] : await _questionFromImage(ai, d, text);
      if (cards.isEmpty) {
        cards = await PlainQuestionService.build(
          images.isEmpty ? ai : (_ai(vision: false) ?? ai),
          text: text,
          moduleId: widget.moduleId,
          sourceMaterialId: _materialOf(d),
          sourcePage: _pageOf(d),
          unitId: widget.unitId ?? widget.replaceCard?.unitId,
        );
      }
      if (cards.isEmpty) {
        throw AiServiceException(
          'Die KI hat keine Frage daraus gemacht – erneut versuchen oder mit „Auf die Liste setzen“ vormerken.',
        );
      }
      await repo.saveAll(cards);
      final listed = d.listedText;
      if (listed != null && list != null) await list.removeText(widget.moduleId, listed);
      if (!mounted) return;
      setState(() {
        d.createdQuestions = cards.length;
        d.listedText = null;
      });
      _snack(cards.length == 1
          ? '1 Frage erstellt – sie kommt bald im Lernplan dran.'
          : '${cards.length} Fragen erstellt – sie kommen bald im Lernplan dran.');
    } on AiServiceException catch (e) {
      if (mounted) setState(() => d.error = e.message);
    } catch (e) {
      if (mounted) setState(() => d.error = 'Erstellen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => d.busy = false);
    }
  }

  /// Eine Frage aus dem Foto der Aufgabe (wie „Frage erstellen“ im PDF), mit
  /// dem Aufgabentext als Fokus und dem von der KI vorgeschlagenen Typ.
  Future<List<Flashcard>> _questionFromImage(AiService ai, _Draft d, String text) async {
    final image = _imagesOf(d).first;
    final type = d.questionType.trim().isEmpty ? null : QuestionParsing.parseType(d.questionType);
    final groups = await ai.generateQuestionsFromPage(
      pageImageBytes: image,
      pageText: '',
      tiers: [(level: 'mittel', type: type == QuestionType.flashcard ? null : type)],
      focusText: text,
    );
    final attach = await downscaleImage(image) ?? image;
    return [
      for (final group in buildPageQuestionCards(
        groups,
        moduleId: widget.moduleId,
        unitId: widget.unitId ?? widget.replaceCard?.unitId,
        questionCount: 1,
        tierCount: 1,
        attachImageBase64: base64Encode(attach),
        now: DateTime.now(),
        sourceMaterialId: _materialOf(d),
        sourcePage: _pageOf(d),
      ))
        ...group,
    ];
  }

  /// Von Hand auf die Sammelliste setzen (die KI meinte, es ginge, tut es
  /// aber nicht) – mit der fehlenden Bedienart als Gruppe.
  Future<void> _addToList(_Draft d) async {
    final list = context.read<UnsupportedTaskRepository?>();
    final text = d.front.text.trim().isNotEmpty ? d.front.text.trim() : _fallbackFront;
    if (list == null || text.isEmpty) return;
    final need = await showDialog<String>(context: context, builder: (_) => _ListNeedsDialog(initial: d.needs));
    if (need == null || !mounted) return;
    try {
      await list.add(
        moduleId: widget.moduleId,
        text: text,
        reason: d.error != null
            ? 'Von Hand vorgemerkt: ${d.error}'
            : (d.reason.isNotEmpty ? d.reason : 'Von Hand auf die Liste gesetzt.'),
        needs: need,
        sourceMaterialId: _materialOf(d),
        sourcePage: _pageOf(d),
      );
      if (!mounted) return;
      setState(() {
        d.listedText = text;
        if (need.isNotEmpty) d.needs = need;
        d.error = null;
      });
      _snack('Auf die Liste „Noch nicht interaktiv“ gesetzt.');
    } catch (e) {
      if (mounted) setState(() => d.error = 'Auf die Liste setzen fehlgeschlagen: $e');
    }
  }

  /// Knopf „Auf die Liste setzen“ bzw. Hinweis, dass sie dort steht.
  Widget _listButton(AppColors c, int i, _Draft d) => d.listedText != null
      ? Text(
          '✓ Auf der Liste „Noch nicht interaktiv“',
          key: ValueKey('task-import-listed-$i'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.inkMuted),
        )
      : OutlinedButton.icon(
          key: ValueKey('task-import-to-list-$i'),
          onPressed: d.busy ? null : () => _addToList(d),
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('Auf die Liste setzen'),
        );

  List<Widget> _unsuitableBody(AppColors c, int i, _Draft d) {
    final text = d.front.text.trim();
    if (d.asQuestion) return _asQuestionBody(c, i, d, text);
    return [
      Container(
        key: ValueKey('task-import-unsuitable-$i'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.incomplete ? 'Nicht vollständig erkannt' : 'Passt noch nicht als interaktive Aufgabe',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.warn),
            ),
            if (d.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(d.reason, style: TextStyle(fontSize: 13, height: 1.4, color: c.ink)),
            ],
            if (d.needs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Fehlt in der App: ${d.needs}', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ],
            if (d.listedText != null) ...[
              const SizedBox(height: 4),
              Text('Steht auf der Liste „Noch nicht interaktiv“.', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ],
          ],
        ),
      ),
      if (text.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          text,
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, height: 1.4, color: c.ink),
        ),
      ],
      if (d.error != null) ...[
        const SizedBox(height: 8),
        Text(
          d.error!,
          key: ValueKey('task-import-retry-error-$i'),
          style: TextStyle(fontSize: 12.5, color: c.danger),
        ),
      ],
      const SizedBox(height: 10),
      Text(
        d.incomplete
            ? 'Noch einmal versuchen (ggf. mit einem stärkeren Modell) oder eine Art vorgeben:'
            : widget.replaceCard != null
            ? 'Die Aufgabe bleibt im Aufgaben-Ordner. Du kannst es trotzdem versuchen:'
            : 'Du kannst es trotzdem versuchen:',
        style: TextStyle(fontSize: 12.5, color: c.inkMuted),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (d.incomplete)
            OutlinedButton.icon(
              key: ValueKey('task-import-retry-$i'),
              onPressed: d.busy ? null : () => _retry(d),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Erneut versuchen'),
            ),
          for (final k in InteractiveKind.values)
            OutlinedButton(
              key: ValueKey('task-import-force-$i-${k.name}'),
              onPressed: d.busy ? null : () => _retry(d, force: k),
              child: Text('Als ${k.label}'),
            ),
          if (d.listedText == null) _listButton(c, i, d),
          if (d.busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    ];
  }

  List<Widget> _asQuestionBody(AppColors c, int i, _Draft d, String text) {
    final type = _typeLabel(d.questionType);
    return [
      Container(
        key: ValueKey('task-import-as-question-info-$i'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              type.isEmpty ? 'Passt als normale Frage' : 'Passt als normale Frage ($type)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.accentOnSoft),
            ),
            if (d.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(d.reason, style: TextStyle(fontSize: 13, height: 1.4, color: c.ink)),
            ],
            const SizedBox(height: 4),
            Text(
              'Dafür gibt es in der App schon einen Fragetyp – sie kommt nicht von selbst auf die Liste „Noch nicht '
              'interaktiv“. Klappt es doch nicht, setz sie mit „Auf die Liste setzen“ selbst drauf.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
          ],
        ),
      ),
      if (text.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(text, maxLines: 8, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.4, color: c.ink)),
      ],
      if (d.error != null) ...[
        const SizedBox(height: 8),
        Text(d.error!, key: ValueKey('task-import-retry-error-$i'), style: TextStyle(fontSize: 12.5, color: c.danger)),
      ],
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (d.createdQuestions > 0)
            Text(
              d.createdQuestions == 1 ? '✓ Als Frage erstellt' : '✓ ${d.createdQuestions} Fragen erstellt',
              key: ValueKey('task-import-as-question-done-$i'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.good),
            )
          else
            FilledButton.icon(
              key: ValueKey('task-import-as-question-$i'),
              onPressed: d.busy ? null : () => _createAsQuestion(d),
              icon: const Icon(Icons.quiz_outlined, size: 18),
              label: const Text('Als normale Frage erstellen'),
            ),
          for (final k in InteractiveKind.values)
            OutlinedButton(
              key: ValueKey('task-import-force-$i-${k.name}'),
              onPressed: d.busy ? null : () => _retry(d, force: k),
              child: Text('Als ${k.label}'),
            ),
          if (d.createdQuestions == 0) _listButton(c, i, d),
          if (d.busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    ];
  }
}

/// Die Aufgabe so lösen, wie sie später im Quiz erscheint – ohne dass etwas
/// gespeichert oder bewertet wird. Gibt eine kurze Rückmeldung zurück.
class _TryTaskScreen extends StatelessWidget {
  const _TryTaskScreen({required this.card});

  final Flashcard card;

  static String _outcome({Grade? selfGrade, bool? isCorrect}) {
    if (isCorrect == false || selfGrade == Grade.again) return 'Ausprobiert: wäre als „Nochmal“ gewertet worden.';
    if (selfGrade == Grade.hard) return 'Ausprobiert: wäre als „Schwer“ gewertet worden.';
    return 'Ausprobiert: wäre als gewusst gewertet worden.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void done({Grade? selfGrade, bool? isCorrect}) =>
        Navigator.of(context).pop(_outcome(selfGrade: selfGrade, isCorrect: isCorrect));
    final steps = card.type == QuestionType.steps ? StepTask.fromMap(card.taskData) : null;
    final gantt = card.type == QuestionType.gantt ? GanttTask.fromMap(card.taskData) : null;
    final crystal = card.type == QuestionType.crystal ? CrystalTask.fromMap(card.taskData) : null;
    final bom = card.type == QuestionType.bom ? BomTask.fromMap(card.taskData) : null;
    final sketch = card.type == QuestionType.sketch ? SketchTask.fromMap(card.taskData) : null;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Ausprobieren')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: steps != null
                  ? StepTaskView(card: card, task: steps, isNew: true, onComplete: done)
                  : gantt != null
                  ? GanttTaskView(card: card, task: gantt, isNew: true, onComplete: done)
                  : crystal != null
                  ? CrystalTaskView(card: card, task: crystal, isNew: true, onComplete: done)
                  : bom != null
                  ? BomTaskView(card: card, task: bom, isNew: true, onComplete: done)
                  : sketch != null
                  ? SketchTaskView(card: card, task: sketch, isNew: true, onComplete: done)
                  : const Center(child: Text('Die Aufgabe ist noch nicht vollständig.')),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fragt beim Vormerken, welche Bedienart der App fehlt (Gruppe auf der
/// Sammelliste). Gibt null zurück, wenn abgebrochen.
class _ListNeedsDialog extends StatefulWidget {
  const _ListNeedsDialog({required this.initial});

  final String initial;

  @override
  State<_ListNeedsDialog> createState() => _ListNeedsDialogState();
}

class _ListNeedsDialogState extends State<_ListNeedsDialog> {
  late final _needs = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _needs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Auf die Liste setzen'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Die Aufgabe kommt auf die Liste „Noch nicht interaktiv“ (Einstellungen).'),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('task-import-to-list-needs'),
          controller: _needs,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Was fehlt der App? (optional)',
            hintText: 'z.B. Kriterien-Tabelle ankreuzen',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
      FilledButton(
        key: const ValueKey('task-import-to-list-confirm'),
        onPressed: () => Navigator.of(context).pop(_needs.text.trim()),
        child: const Text('Auf die Liste'),
      ),
    ],
  );
}
