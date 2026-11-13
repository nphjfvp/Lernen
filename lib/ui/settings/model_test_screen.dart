import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/ai_usage.dart' show formatUsd;
import '../../models/material_item.dart';
import '../../models/model_test_result.dart';
import '../../models/visual_lesson.dart';
import '../../models/visual_scene3d.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/model_catalog_repository.dart';
import '../../repositories/model_test_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/material_file_store.dart';
import '../../services/model_test_runner.dart';
import '../../services/pdf_service.dart';
import '../../services/question_parsing.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import '../visual/visual_scene3d_view.dart';
import '../visual/visual_show_view.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';
import 'model_picker_sheet.dart';
import 'model_roles.dart';

/// Modelle ausprobieren, bevor man sich festlegt: dieselbe Eingabe an mehrere
/// Modelle schicken und die Ergebnisse untereinander vergleichen – mit Dauer
/// und Kosten. Die Ergebnisse dienen nur dem Vergleich: sie bleiben 30
/// Minuten, mit „Behalten“ dauerhaft, und nichts davon landet im Lernstoff.
class ModelTestScreen extends StatefulWidget {
  const ModelTestScreen({super.key, required this.role, this.repository});

  /// Modell-Rolle der Einstellungen (siehe model_roles.dart).
  final String role;
  final ModelTestRepository? repository;

  /// So viele Modelle laufen höchstens in einem Durchgang.
  static const maxModels = 4;

  /// Nur für Tests: KI-Zugang statt OpenRouter.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs (Name, Bytes).
  @visibleForTesting
  static Future<({String name, Uint8List bytes})?> Function()? pickFileHook;

  @override
  State<ModelTestScreen> createState() => _ModelTestScreenState();
}

enum _Source { none, pdf, text }

class _ModelTestScreenState extends State<ModelTestScreen> with SafeSetState<ModelTestScreen> {
  late final ModelTestRepository _repo = widget.repository ?? ModelTestRepository();
  late final List<ModelTestKind> _kinds = ModelTestKind.forRole(widget.role);
  late ModelTestKind _kind = _kinds.first;

  final List<String> _models = [];
  List<ModelTestResult> _results = const [];
  final Set<String> _running = {};
  String? _error;
  String? _status;
  Timer? _tick;

  // Eingabe: Seite oder Text
  _Source _source = _Source.none;
  String _docName = '';
  Uint8List? _pdfBytes;
  List<String> _pageTexts = const [];

  /// Gewählte Seite (0-basiert), -1 = alle.
  int _page = 0;
  String _plainText = '';
  bool _loadingDoc = false;
  final _text = TextEditingController();

  // Eingabe: Erklärung und 3D-Modell
  final _question = TextEditingController();
  final _answer = TextEditingController();
  final _description = TextEditingController();

  static const _sceneExamples = [
    'Welle mit zwei Lagern und einer Kraft in der Mitte',
    'Sattelfläche z = x² − y² mit Tangentialebene',
    'Kubisch-raumzentrierte Elementarzelle',
  ];

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsRepository>().settings;
    final catalog = context.read<ModelCatalogRepository?>();
    _models.add(modelForRole(settings, widget.role, info: catalog?.byId));
    _load();
    // Restzeiten nachführen und Abgelaufenes ausblenden.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(
        () => _results = [
          for (final r in _results)
            if (!r.isExpired(now)) r,
        ],
      );
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _text.dispose();
    _question.dispose();
    _answer.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await _repo.all(kind: _kind);
    if (mounted) setState(() => _results = results);
  }

  void _selectKind(ModelTestKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _results = const [];
      _error = null;
    });
    _load();
  }

  String _modelName(String id) => context.read<ModelCatalogRepository?>()?.byId(id)?.name ?? id;

  // -- Eingabe ----------------------------------------------------------------

  Future<void> _upload() async {
    setState(() => _error = null);
    ({String name, Uint8List bytes})? picked;
    final hook = ModelTestScreen.pickFileHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      if (files.isNotEmpty) picked = (name: files.first.name, bytes: await files.first.readAsBytes());
    }
    if (picked == null || !mounted) return;
    _usePdf(picked.name, picked.bytes);
  }

  void _usePdf(String name, Uint8List bytes) {
    try {
      final texts = PdfService().extractPageTexts(bytes);
      if (texts.isEmpty) throw PdfExtractionException('Die PDF hat keine Seiten.');
      setState(() {
        _source = _Source.pdf;
        _docName = name;
        _pdfBytes = bytes;
        _pageTexts = texts;
        _page = 0;
        _error = null;
      });
    } on PdfExtractionException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _pickMaterial() async {
    final modules = context.read<ModuleRepository>().modules;
    final materials = context.read<MaterialRepository>();
    setState(() {
      _loadingDoc = true;
      _error = null;
    });
    try {
      for (final m in modules) {
        await materials.loadForModule(m.id);
      }
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
    }
    if (!mounted) return;
    final entries = [
      for (final m in modules)
        for (final item in materials.forModule(m.id))
          if (item.extractedText.trim().isNotEmpty || item.filePath != null || item.fileBytesBase64 != null)
            (module: m.name, item: item),
    ];
    if (entries.isEmpty) {
      setState(() => _error = 'Es gibt noch kein Material – lade eine kleine PDF hoch.');
      return;
    }
    final c = context.colors;
    final picked = await showModalBottomSheet<MaterialItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            key: const ValueKey('model-test-material-sheet'),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text('Seite aus Material', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              for (final e in entries)
                ListTile(
                  key: ValueKey('model-test-material-${e.item.id}'),
                  leading: Icon(Icons.description_outlined, color: c.inkMuted),
                  title: Text(e.item.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(e.module, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(ctx).pop(e.item),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _loadingDoc = true);
    Uint8List? bytes;
    try {
      if (picked.fileName.toLowerCase().endsWith('.pdf')) {
        bytes = await MaterialFileStore.load(filePath: picked.filePath, fileBytesBase64: picked.fileBytesBase64);
      }
    } catch (_) {
      bytes = null;
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
    }
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      _usePdf(picked.fileName, bytes);
      if (_source == _Source.pdf && _docName == picked.fileName) return;
    }
    // Keine (lesbare) PDF: der gespeicherte Text des Materials.
    setState(() {
      _source = _Source.text;
      _docName = picked.fileName;
      _pdfBytes = null;
      _pageTexts = const [];
      _plainText = picked.extractedText;
      _text.text = '';
      _error = null;
    });
  }

  void _useOwnText() => setState(() {
    _source = _Source.text;
    _docName = '';
    _pdfBytes = null;
    _pageTexts = const [];
    _plainText = '';
    _error = null;
  });

  String _short(String text, [int max = 70]) {
    final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return line.length > max ? '${line.substring(0, max)}…' : line;
  }

  /// Die Eingabe für den Test – oder null und [_error], wenn etwas fehlt.
  ModelTestInput? _input() {
    String? problem;
    ModelTestInput? input;
    switch (_kind) {
      case ModelTestKind.explain:
        final q = _question.text.trim();
        if (q.isEmpty) {
          problem = 'Gib eine Frage ein, die das Modell erklären soll.';
        } else {
          input = ModelTestInput(label: _short(q), text: q, answer: _answer.text);
        }
      case ModelTestKind.scene3d:
        final d = _description.text.trim();
        if (d.isEmpty) {
          problem = 'Beschreibe, was das 3D-Modell zeigen soll.';
        } else {
          input = ModelTestInput(label: _short(d), text: d);
        }
      case ModelTestKind.questions || ModelTestKind.lesson || ModelTestKind.crosscheck || ModelTestKind.vision:
        if (_source == _Source.pdf && _pdfBytes != null) {
          final pages = _page < 0 ? [for (var i = 0; i < _pageTexts.length; i++) i] : [_page];
          final text = [for (final p in pages) _pageTexts[p]].where((t) => t.isNotEmpty).join('\n\n');
          final label = _page < 0 ? '$_docName (${_pageTexts.length} Seiten)' : 'Seite ${_page + 1} von $_docName';
          if (_kind == ModelTestKind.vision) {
            input = ModelTestInput(
              label: label,
              text: text,
              pdfBytes: _pageTexts.length == 1 ? _pdfBytes : PdfService().extractPages(_pdfBytes!, pages),
              pageCount: pages.length,
            );
          } else if (text.trim().isEmpty) {
            problem =
                'Diese Seite hat keinen lesbaren Text (gescannt oder nur ein Bild). Nimm eine andere Seite – '
                'oder teste damit das Vision-Modell.';
          } else {
            input = ModelTestInput(label: label, text: text);
          }
        } else if (_kind == ModelTestKind.vision) {
          problem =
              'Für diesen Test braucht es eine PDF-Seite: lade eine kleine PDF hoch oder nimm eine aus dem Material.';
        } else if (_source == _Source.text) {
          final text = _docName.isEmpty ? _text.text.trim() : _plainText.trim();
          if (text.isEmpty) {
            problem = 'Füge einen Text ein – ein Absatz aus deinen Folien reicht.';
          } else {
            input = ModelTestInput(
              label: _docName.isEmpty ? 'Eigener Text: ${_short(text, 40)}' : _docName,
              text: text,
            );
          }
        } else {
          problem =
              'Wähle zuerst, woraus getestet wird: eine kleine PDF, eine Seite aus deinem Material oder eigener Text.';
        }
    }
    if (problem != null) setState(() => _error = problem);
    return input;
  }

  // -- Modelle ----------------------------------------------------------------

  Future<void> _addModel() async {
    final catalog = context.read<ModelCatalogRepository?>();
    if (catalog == null) return;
    final picked = await showModelPickerSheet(
      context,
      title: 'Modell zum Vergleichen',
      models: widget.role == 'vision' ? catalog.visionModels : catalog.models,
      selectedId: null,
    );
    if (picked == null || !mounted || _models.contains(picked)) return;
    setState(() => _models.add(picked));
  }

  // -- Lauf -------------------------------------------------------------------

  AiService _ai(String apiKey, String model) =>
      ModelTestScreen.aiFactory?.call(apiKey, model) ?? AiService(apiKey: apiKey, model: model);

  Future<void> _run() async {
    final settings = context.read<SettingsRepository>().settings;
    final catalog = context.read<ModelCatalogRepository?>();
    if (!settings.hasApiKey) {
      setState(() => _error = 'Trage zuerst deinen OpenRouter-Key in den Einstellungen ein.');
      return;
    }
    if (_models.isEmpty) {
      setState(() => _error = 'Wähle mindestens ein Modell.');
      return;
    }
    setState(() => _error = null);
    final input = _input();
    if (input == null) return;
    final key = settings.openRouterApiKey!;
    final kind = _kind;
    final models = List.of(_models);
    setState(() => _running.addAll(models));

    Map<String, dynamic>? generated;
    if (kind == ModelTestKind.crosscheck) {
      generated = await _questionsToCheck(input, key, settings.questionModelId, catalog);
      if (generated == null) {
        if (mounted) setState(() => _running.removeAll(models));
        return;
      }
    }

    await Future.wait([
      for (final model in models)
        () async {
          final result = await ModelTestRunner.run(
            id: const Uuid().v4(),
            kind: kind,
            ai: _ai(key, model),
            input: input,
            generated: generated,
            staged: settings.stagedLessons,
            modelInfo: catalog?.byId,
          );
          // Ein Ergebnis, das sich nicht speichern lässt, wird trotzdem gezeigt.
          try {
            await _repo.save(result);
          } catch (e) {
            debugPrint('Modell-Test nicht gespeichert ($e).');
          }
          setState(() {
            _running.remove(model);
            if (_kind == kind) _results = [result, ..._results];
          });
        }(),
    ]);
  }

  /// Die Fragen für den Gegenprüf-Test: die jüngsten, die zu derselben
  /// Eingabe schon erstellt wurden – sonst erstellt sie das Fragen-Modell.
  Future<Map<String, dynamic>?> _questionsToCheck(
    ModelTestInput input,
    String apiKey,
    String questionModel,
    ModelCatalogRepository? catalog,
  ) async {
    final earlier = await _repo.all(kind: ModelTestKind.questions);
    for (final r in earlier) {
      if (!r.failed && r.inputKey == input.key && ModelTestRunner.flashcardsOf(r.output).isNotEmpty) return r.output;
    }
    if (mounted) setState(() => _status = 'Erstelle zuerst Fragen mit ${_modelName(questionModel)} …');
    final made = await ModelTestRunner.run(
      id: const Uuid().v4(),
      kind: ModelTestKind.questions,
      ai: _ai(apiKey, questionModel),
      input: input,
      modelInfo: catalog?.byId,
    );
    await _repo.save(made);
    if (mounted) setState(() => _status = null);
    if (made.failed || ModelTestRunner.flashcardsOf(made.output).isEmpty) {
      if (mounted) {
        setState(() => _error = 'Es ließen sich keine Fragen zum Prüfen erstellen: ${made.error ?? 'leere Antwort'}');
      }
      return null;
    }
    return made.output;
  }

  Future<void> _togglePin(ModelTestResult r) async {
    await _repo.setPinned(r.id, !r.pinned);
    if (!mounted) return;
    setState(() => _results = [for (final x in _results) x.id == r.id ? x.copyWith(pinned: !r.pinned) : x]);
  }

  Future<void> _delete(ModelTestResult r) async {
    await _repo.delete(r.id);
    if (!mounted) return;
    setState(
      () => _results = [
        for (final x in _results)
          if (x.id != r.id) x,
      ],
    );
  }

  Future<void> _useModel(ModelTestResult r) async {
    final repo = context.read<SettingsRepository>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    await setModelForRole(repo, widget.role, r.modelId);
    if (!mounted) return;
    setState(() {});
    messenger?.showSnackBar(
      SnackBar(content: Text('${_modelName(r.modelId)} ist jetzt für ${modelRoleLabel(widget.role)} eingestellt.')),
    );
  }

  // -- Oberfläche -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = context.watch<SettingsRepository>().settings;
    final catalog = context.watch<ModelCatalogRepository?>();
    final current = modelForRole(settings, widget.role, info: catalog?.byId);
    final busy = _running.isNotEmpty;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text('Modell testen · ${modelRoleLabel(widget.role)}')),
      body: ListView(
        key: const ValueKey('model-test-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Schick dieselbe Eingabe an mehrere Modelle und vergleiche, was dir besser gefällt. Jeder Test kostet '
            'so viel wie eine normale Anfrage. Die Ergebnisse dienen nur dem Vergleich: sie bleiben 30 Minuten, mit '
            '„Behalten“ dauerhaft – im Lernstoff landet nichts davon.',
            style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_kinds.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in _kinds)
                  ChoiceChip(
                    key: ValueKey('model-test-kind-${k.name}'),
                    label: Text(k.label),
                    selected: k == _kind,
                    onSelected: busy ? null : (_) => _selectKind(k),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Text(_kind.hint, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          const SizedBox(height: 12),
          _card(c, child: _inputSection(c)),
          const SizedBox(height: 12),
          _card(c, child: _modelSection(c, catalog)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const ValueKey('model-test-error'),
              style: TextStyle(fontSize: 13, color: c.danger),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('model-test-run'),
            onPressed: busy ? null : _run,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text(
              busy
                  ? (_status ?? 'Läuft … (${_running.length} offen)')
                  : _models.length > 1
                  ? 'Test mit ${_models.length} Modellen starten'
                  : 'Test starten',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  _results.isEmpty ? 'Noch keine Ergebnisse' : 'Ergebnisse (${_results.length})',
                  key: const ValueKey('model-test-results-title'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (_results.isNotEmpty)
                TextButton(
                  key: const ValueKey('model-test-clear'),
                  onPressed: busy
                      ? null
                      : () async {
                          await _repo.clear(_kind);
                          if (mounted) setState(() => _results = const []);
                        },
                  child: const Text('Alle löschen'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final r in _results) ...[
            _ResultCard(
              key: ValueKey('model-test-result-${r.id}'),
              result: r,
              modelName: _modelName(r.modelId),
              isCurrent: r.modelId == current,
              roleLabel: modelRoleLabel(widget.role),
              onPin: () => _togglePin(r),
              onDelete: () => _delete(r),
              onUse: () => _useModel(r),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _card(AppColors c, {required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: c.surface,
      border: Border.all(color: c.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );

  InputDecoration _decoration(AppColors c, String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: c.surfaceAlt,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );

  Widget _inputSection(AppColors c) {
    const title = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600);
    switch (_kind) {
      case ModelTestKind.explain:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Frage', style: title),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('model-test-question'),
              controller: _question,
              minLines: 1,
              maxLines: 4,
              decoration: _decoration(c, 'Welche Frage soll erklärt werden?'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('model-test-answer'),
              controller: _answer,
              minLines: 1,
              maxLines: 3,
              decoration: _decoration(c, 'Lösung (wenn du sie kennst)'),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('model-test-example'),
                onPressed: () => setState(() {
                  _question.text = 'Warum ist die Ableitung von x² gleich 2x?';
                  _answer.text = "f'(x) = 2x";
                  _error = null;
                }),
                child: const Text('Beispiel einsetzen'),
              ),
            ),
          ],
        );
      case ModelTestKind.scene3d:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Beschreibung', style: title),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('model-test-description'),
              controller: _description,
              minLines: 2,
              maxLines: 5,
              decoration: _decoration(c, 'Was soll das 3D-Modell zeigen?'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, example) in _sceneExamples.indexed)
                  ActionChip(
                    key: ValueKey('model-test-example-$i'),
                    label: Text(example),
                    onPressed: () => setState(() {
                      _description.text = example;
                      _error = null;
                    }),
                  ),
              ],
            ),
          ],
        );
      case ModelTestKind.questions || ModelTestKind.lesson || ModelTestKind.crosscheck || ModelTestKind.vision:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Woraus wird getestet?', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('model-test-upload'),
                  onPressed: _loadingDoc ? null : _upload,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Kleine PDF hochladen'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('model-test-material'),
                  onPressed: _loadingDoc ? null : _pickMaterial,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('Seite aus Material'),
                ),
                if (_kind != ModelTestKind.vision)
                  OutlinedButton.icon(
                    key: const ValueKey('model-test-own-text'),
                    onPressed: _loadingDoc ? null : _useOwnText,
                    icon: const Icon(Icons.notes_outlined, size: 18),
                    label: const Text('Text einfügen'),
                  ),
              ],
            ),
            if (_loadingDoc) ...[const SizedBox(height: 10), const LinearProgressIndicator()],
            if (_source == _Source.pdf) ...[const SizedBox(height: 10), _pageChooser(c)],
            if (_source == _Source.text && _docName.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '$_docName – der gespeicherte Text'
                '${_plainText.length > ModelTestInput.maxChars ? ' (nur der Anfang, der Test soll klein bleiben)' : ''}',
                key: const ValueKey('model-test-source'),
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
            ],
            if (_source == _Source.text && _docName.isEmpty) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('model-test-text'),
                controller: _text,
                minLines: 3,
                maxLines: 8,
                decoration: _decoration(c, 'Text einfügen – ein Absatz aus deinen Folien reicht'),
              ),
            ],
            if (_kind == ModelTestKind.crosscheck) ...[
              const SizedBox(height: 10),
              Text(
                'Geprüft werden die Fragen, die zuletzt im Test „Fragen erstellen“ aus derselben Eingabe entstanden '
                'sind. Gibt es keine, erstellt sie zuerst dein Fragen-Modell (eine Anfrage mehr).',
                style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35),
              ),
            ],
          ],
        );
    }
  }

  Widget _pageChooser(AppColors c) {
    final count = _pageTexts.length;
    final all = _page < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _docName,
          key: const ValueKey('model-test-source'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('model-test-page-prev'),
              tooltip: 'Vorige Seite',
              onPressed: all || _page <= 0 ? null : () => setState(() => _page--),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text(
              all ? 'Alle $count Seiten' : 'Seite ${_page + 1} von $count',
              key: const ValueKey('model-test-page'),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            IconButton(
              key: const ValueKey('model-test-page-next'),
              tooltip: 'Nächste Seite',
              onPressed: all || _page >= count - 1 ? null : () => setState(() => _page++),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            // Ein Test soll klein bleiben: „alle“ nur bei wenigen Seiten.
            if (count > 1 && count <= 6)
              FilterChip(
                key: const ValueKey('model-test-page-all'),
                label: const Text('Alle Seiten'),
                selected: all,
                onSelected: (v) => setState(() => _page = v ? -1 : 0),
              ),
          ],
        ),
        if (!all && _pageTexts[_page].isNotEmpty)
          Text(
            _short(_pageTexts[_page], 140),
            key: const ValueKey('model-test-page-preview'),
            style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35),
          ),
        if (!all && _pageTexts[_page].isEmpty)
          Text(
            'Kein lesbarer Text auf dieser Seite (gescannt oder Bild).',
            style: TextStyle(fontSize: 12, color: c.inkMuted),
          ),
      ],
    );
  }

  Widget _modelSection(AppColors c, ModelCatalogRepository? catalog) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Modelle', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, id) in _models.indexed)
              InputChip(
                key: ValueKey('model-test-model-$i'),
                label: Text(catalog?.byId(id)?.name ?? id),
                onDeleted: _running.isNotEmpty ? null : () => setState(() => _models.removeAt(i)),
                deleteButtonTooltipMessage: 'Nicht mittesten',
              ),
            if (_models.length < ModelTestScreen.maxModels)
              ActionChip(
                key: const ValueKey('model-test-add-model'),
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Modell dazu'),
                onPressed: _running.isNotEmpty ? null : _addModel,
              ),
          ],
        ),
      ],
    );
  }
}

String _seconds(Duration d) => d.inMilliseconds < 10000
    ? '${(d.inMilliseconds / 1000).toStringAsFixed(1).replaceAll('.', ',')} s'
    : '${d.inSeconds} s';

String _ago(Duration d) => d.inMinutes < 1
    ? 'gerade eben'
    : d.inMinutes < 60
    ? 'vor ${d.inMinutes} Min.'
    : d.inHours < 24
    ? 'vor ${d.inHours} Std.'
    : 'vor ${d.inDays} Tagen';

/// Ein Ergebnis: Modell, Messwerte, die Antwort und was man damit tun kann.
class _ResultCard extends StatefulWidget {
  const _ResultCard({
    super.key,
    required this.result,
    required this.modelName,
    required this.isCurrent,
    required this.roleLabel,
    required this.onPin,
    required this.onDelete,
    required this.onUse,
  });

  final ModelTestResult result;
  final String modelName;
  final bool isCurrent;
  final String roleLabel;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onUse;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _showAll = false;

  ModelTestResult get r => widget.result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final left = r.remaining(now);
    final cost = r.cost;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: r.failed ? c.danger : c.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.modelName,
                  key: ValueKey('model-test-name-${r.id}'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: ValueKey('model-test-delete-${r.id}'),
                tooltip: 'Ergebnis löschen',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onDelete,
                icon: Icon(Icons.delete_outline, size: 20, color: c.inkMuted),
              ),
            ],
          ),
          Wrap(
            key: ValueKey('model-test-stats-${r.id}'),
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill(c, _seconds(r.duration)),
              _pill(c, cost == null ? 'Kosten unbekannt' : '${r.costEstimated ? '≈ ' : ''}${formatUsd(cost)}'),
              if (r.promptTokens + r.completionTokens > 0) _pill(c, '${r.promptTokens} → ${r.completionTokens} Tokens'),
              if (r.calls > 1) _pill(c, '${r.calls} Anfragen'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${r.inputLabel} · ${_ago(now.difference(r.createdAt))}',
            style: TextStyle(fontSize: 12, color: c.inkMuted),
          ),
          const SizedBox(height: 10),
          if (r.failed)
            Text(
              r.error!,
              key: ValueKey('model-test-failed-${r.id}'),
              style: TextStyle(fontSize: 13, color: c.danger),
            )
          else
            _body(context, c),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  key: ValueKey('model-test-pin-${r.id}'),
                  onPressed: widget.onPin,
                  icon: Icon(r.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
                  label: Text(
                    r.pinned
                        ? 'Wird behalten'
                        : 'Behalten (sonst weg in ${left == null || left.inMinutes < 1 ? 'unter 1' : left.inMinutes} Min.)',
                  ),
                ),
                if (widget.isCurrent)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Ist eingestellt',
                      key: ValueKey('model-test-current-${r.id}'),
                      style: TextStyle(fontSize: 12.5, color: c.good, fontWeight: FontWeight.w600),
                    ),
                  )
                else if (!r.failed)
                  FilledButton.tonal(
                    key: ValueKey('model-test-use-${r.id}'),
                    onPressed: widget.onUse,
                    child: const Text('Dieses Modell nehmen'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(AppColors c, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(10)),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: c.ink, fontWeight: FontWeight.w600),
    ),
  );

  Widget _body(BuildContext context, AppColors c) {
    switch (r.kind) {
      case ModelTestKind.questions:
        return _questions(c, ModelTestRunner.conceptsOf(r.output), ModelTestRunner.flashcardsOf(r.output));
      case ModelTestKind.lesson:
        return _lesson(context, c);
      case ModelTestKind.explain:
        return MathText('${r.output['text'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.45));
      case ModelTestKind.vision:
        final pages = [
          if (r.output['pages'] is List)
            for (final p in r.output['pages'] as List) '$p',
        ];
        final text = pages.where((p) => p.trim().isNotEmpty).join('\n\n— nächste Seite —\n\n');
        final long = text.length > 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${text.length} Zeichen erkannt', style: TextStyle(fontSize: 12, color: c.inkMuted)),
            const SizedBox(height: 6),
            SelectableText(
              long && !_showAll ? '${text.substring(0, 900)}…' : text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            if (long) _moreButton('Ganzen Text zeigen'),
          ],
        );
      case ModelTestKind.crosscheck:
        return _crosscheck(c);
      case ModelTestKind.scene3d:
        final scene = VisualScene3D.fromMap(r.output['scene3d']);
        if (scene == null) {
          return Text(
            'Die Antwort lässt sich nicht als 3D-Modell darstellen.',
            style: TextStyle(fontSize: 13, color: c.danger),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${scene.objects.length} Bauteil${scene.objects.length == 1 ? '' : 'e'}',
              key: ValueKey('model-test-scene-count-${r.id}'),
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
            const SizedBox(height: 6),
            VisualScene3DView(scene: scene, autoplay: false, height: 260, title: widget.modelName),
          ],
        );
    }
  }

  Widget _moreButton(String label) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      key: ValueKey('model-test-more-${r.id}'),
      onPressed: () => setState(() => _showAll = !_showAll),
      child: Text(_showAll ? 'Weniger zeigen' : label),
    ),
  );

  Widget _questionTile(AppColors c, int number, Map<String, dynamic> raw) {
    final entry = QuestionParsing.canonicalize(raw);
    final front = '${entry['front'] ?? ''}'.trim();
    final answer = QuestionParsing.answerPreview(raw);
    final type = QuestionParsing.parseType(entry['type']?.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number · ${QuestionParsing.aiTypeName(type)}',
            style: TextStyle(fontSize: 11, color: c.inkMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          MathText(front.isEmpty ? '(ohne Fragetext)' : front, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          if (answer != null) ...[
            const SizedBox(height: 2),
            MathText('→ $answer', style: TextStyle(fontSize: 13, height: 1.4, color: c.accentOnSoft)),
          ],
        ],
      ),
    );
  }

  Widget _questions(AppColors c, List<Map<String, dynamic>> concepts, List<Map<String, dynamic>> cards) {
    const preview = 4;
    final shown = _showAll ? cards : cards.take(preview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${concepts.length} Konzept${concepts.length == 1 ? '' : 'e'} · ${cards.length} Frage${cards.length == 1 ? '' : 'n'}',
          key: ValueKey('model-test-count-${r.id}'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        if (concepts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            concepts.map((k) => '${k['title'] ?? ''}'.trim()).where((t) => t.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35),
          ),
        ],
        const SizedBox(height: 10),
        for (final (i, card) in shown.indexed) _questionTile(c, i + 1, card),
        if (cards.length > preview) _moreButton('Alle ${cards.length} Fragen zeigen'),
      ],
    );
  }

  Widget _crosscheck(AppColors c) {
    final issues = ModelTestRunner.issuesOf(r.output);
    final generated = r.output['generated'];
    final cards = generated is Map ? ModelTestRunner.flashcardsOf(Map<String, dynamic>.from(generated)) : const [];
    if (issues.isEmpty) {
      return Text(
        'Keine Fehler in ${cards.length} Frage${cards.length == 1 ? '' : 'n'} gefunden.',
        key: ValueKey('model-test-count-${r.id}'),
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${issues.length} Beanstandung${issues.length == 1 ? '' : 'en'} in ${cards.length} Frage${cards.length == 1 ? '' : 'n'}',
          key: ValueKey('model-test-count-${r.id}'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'${issue['targetType']}'.contains('concept') ? 'Konzept' : 'Frage'} '
                  '${(issue['targetIndex'] is num ? (issue['targetIndex'] as num).toInt() : 0) + 1}',
                  style: TextStyle(fontSize: 11, color: c.inkMuted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                MathText('${issue['problem'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.4)),
                if (issue['fix'] is Map) ...[
                  const SizedBox(height: 2),
                  MathText(
                    'Vorschlag: ${_fixText(Map<String, dynamic>.from(issue['fix'] as Map))}',
                    style: TextStyle(fontSize: 13, height: 1.4, color: c.accentOnSoft),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static String _fixText(Map<String, dynamic> fix) {
    if (fix['explanation'] != null) return '${fix['title'] ?? ''}: ${fix['explanation']}'.trim();
    final front = '${QuestionParsing.canonicalize(fix)['front'] ?? ''}'.trim();
    final answer = QuestionParsing.answerPreview(fix);
    return answer == null ? front : '$front → $answer';
  }

  Widget _lesson(BuildContext context, AppColors c) {
    final lesson = VisualLesson.fromMap(r.output['lesson'], id: 'test-${r.id}', moduleId: '', createdAt: r.createdAt);
    if (lesson == null) {
      return Text('Die Antwort ist keine vollständige Lektion.', style: TextStyle(fontSize: 13, color: c.danger));
    }
    final drawn = lesson.steps.where((s) => VisualShowView.hasContent(s.show)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lesson.title,
          key: ValueKey('model-test-lesson-title-${r.id}'),
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          '${lesson.steps.length} Schritte · $drawn mit Darstellung',
          key: ValueKey('model-test-count-${r.id}'),
          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
        ),
        const SizedBox(height: 6),
        for (final (i, s) in lesson.steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('${i + 1}. ${s.title}', style: const TextStyle(fontSize: 13, height: 1.35)),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: ValueKey('model-test-open-${r.id}'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ModelTestLessonPreview(lesson: lesson, modelName: widget.modelName),
            ),
          ),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('Lektion ansehen'),
        ),
      ],
    );
  }
}

/// Die Lektion eines Tests zum Durchsehen: alle Schritte untereinander, mit
/// ihren Darstellungen. Nur Ansicht – gespeichert wird sie nicht.
class ModelTestLessonPreview extends StatelessWidget {
  const ModelTestLessonPreview({super.key, required this.lesson, required this.modelName});

  final VisualLesson lesson;
  final String modelName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final math = VisualMath(lesson);
    final steps = [...lesson.steps, if (lesson.result != null) lesson.result!];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lesson.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('Test · $modelName', style: TextStyle(fontSize: 12, color: c.inkMuted)),
          ],
        ),
      ),
      body: ListView.builder(
        key: const ValueKey('model-test-lesson-preview'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: steps.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return lesson.intro.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MathText(lesson.intro, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.inkMuted)),
                  );
          }
          final i = index - 1;
          final s = steps[i];
          final isResult = i >= lesson.steps.length;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isResult ? 'Ergebnis · ${s.title}' : '${i + 1}. ${s.title}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                if (s.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  MathText(s.text, style: const TextStyle(fontSize: 13.5, height: 1.45)),
                ],
                if (s.formula.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  MathText('\$${s.formula}\$', style: const TextStyle(fontSize: 14)),
                ],
                if (VisualShowView.hasContent(s.show)) ...[
                  const SizedBox(height: 10),
                  VisualShowView(math: math, show: s.show),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
