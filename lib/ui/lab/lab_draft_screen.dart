import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/lab_experiment.dart';
import '../../models/material_item.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/image_crop.dart';
import '../../services/lab_context_service.dart';
import '../../services/material_file_store.dart';
import '../../services/material_text_extractor.dart';
import '../../services/pdf_ocr_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/existing_material_picker.dart';
import '../widgets/ocr_notice.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'lab_widgets.dart';

/// Berichtsentwurf zur Inspiration: aus Vorlage bzw. Vorgaben und den Daten des
/// Versuchs (Messwerte, Notizen mit Rechenwegen, Antworten) schreibt die KI einen
/// groben Entwurf je Berichtsabschnitt. Er liegt getrennt vom eigenen Text im
/// Abschnitt (siehe LabReportSection.draft) – übernommen wird, was der Nutzer will.
/// Mit [onlySectionId] entsteht nur der Entwurf dieses einen Abschnitts.
class LabDraftScreen extends StatefulWidget {
  const LabDraftScreen({super.key, required this.experimentId, required this.moduleName, this.onlySectionId});

  final String experimentId;
  final String moduleName;
  final String? onlySectionId;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs (Name, Bytes).
  @visibleForTesting
  static Future<List<({String name, Uint8List bytes})>> Function({required bool images})? pickFilesHook;

  @override
  State<LabDraftScreen> createState() => _LabDraftScreenState();
}

class _LabDraftScreenState extends State<LabDraftScreen> with SafeSetState<LabDraftScreen> {
  late final LabExperimentRepository _repo = context.read<LabExperimentRepository>();
  final _context = LabContextService();
  final List<({String name, Uint8List bytes})> _images = [];

  bool _outline = false;
  bool _adoptStructure = true;
  bool _useOwnTexts = true;
  bool _busy = false;
  String? _progress;
  String? _error;
  String? _raw;
  List<String>? _missing;

  LabExperiment? get _e => _repo.byId(widget.experimentId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final e = _e;
      if (e != null) context.read<MaterialRepository>().loadForModule(e.moduleId);
    });
  }

  Future<void> _update(LabExperiment Function(LabExperiment) change) async {
    final current = _e;
    if (current == null) return;
    await _repo.save(change(current));
  }

  List<MaterialItem> _templates(LabExperiment e) {
    final byId = {for (final m in context.read<MaterialRepository>().forModule(e.moduleId)) m.id: m};
    return [
      for (final id in e.reportTemplateIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<List<({String name, Uint8List bytes})>> _pick({required bool images}) async {
    final hook = LabDraftScreen.pickFilesHook;
    if (hook != null) return hook(images: images);
    final files = images
        ? await FilePicker.pickFiles(type: FileType.image)
        : await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: MaterialTextExtractor.supportedExtensions);
    return [for (final f in files) (name: f.name, bytes: await f.readAsBytes())];
  }

  /// Neue Vorlage: Text auslesen und – wie beim Anlegen des Versuchs – als
  /// Material des Fachs ablegen.
  Future<void> _uploadTemplate() async {
    final e = _e;
    if (e == null) return;
    final picked = await _pick(images: false);
    if (picked.isEmpty || !mounted) return;
    final repo = context.read<MaterialRepository>();
    final ocr = PdfOcrService.fromSettings(context.read<SettingsRepository>().settings);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Vorlage wird gelesen …';
    });
    final errors = <String>[];
    final added = <String>[];
    for (final file in picked) {
      try {
        final text = await MaterialTextExtractor()
            .extractTextWithOcr(file.name, file.bytes, ocr: ocr, onProgress: ocrStartNotice(messenger, file.name));
        if (text.isEmpty) {
          errors.add('${file.name}: kein Text gefunden.');
          continue;
        }
        final id = const Uuid().v4();
        String? filePath;
        String? fileBytesBase64;
        if (file.name.toLowerCase().endsWith('.pdf')) {
          (filePath, fileBytesBase64) = await MaterialFileStore.store(id, file.bytes);
        }
        await repo.save(MaterialItem(
          id: id,
          moduleId: e.moduleId,
          fileName: file.name,
          kind: MaterialKind.slide,
          extractedText: text,
          createdAt: DateTime.now(),
          filePath: filePath,
          fileBytesBase64: fileBytesBase64,
        ));
        added.add(id);
      } catch (err) {
        errors.add('${file.name}: $err');
      }
    }
    if (added.isNotEmpty) await _update((cur) => cur.copyWith(reportTemplateIds: [...cur.reportTemplateIds, ...added]));
    setState(() {
      _busy = false;
      _progress = null;
      if (errors.isNotEmpty) _error = errors.join('\n');
    });
  }

  Future<void> _pickExisting() async {
    final e = _e;
    if (e == null) return;
    final selected = await showExistingMaterialPicker(
      context,
      available: context.read<MaterialRepository>().forModule(e.moduleId),
      alreadyPickedIds: {...e.reportTemplateIds},
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _update((cur) => cur.copyWith(reportTemplateIds: [...cur.reportTemplateIds, for (final m in selected) m.id]));
  }

  Future<void> _pickImages() async {
    final picked = await _pick(images: true);
    if (picked.isEmpty) return;
    final prepared = <({String name, Uint8List bytes})>[];
    for (final p in picked.take(4 - _images.length)) {
      prepared.add((name: p.name, bytes: await prepareImageForAi(p.bytes)));
    }
    setState(() => _images.addAll(prepared));
  }

  Future<void> _create() async {
    final e = _e;
    if (e == null) return;
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _error = 'Für den Entwurf braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final model = _images.isNotEmpty ? settings.visionModelId : settings.questionModelId;
    final ai = LabDraftScreen.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
    setState(() {
      _busy = true;
      _error = null;
      _raw = null;
      _missing = null;
      _progress = 'Der Entwurf wird geschrieben …';
    });
    try {
      final materials = context.read<MaterialRepository>().forModule(e.moduleId);
      final ctx = await _context.contextFor(
        experiment: e,
        materials: materials,
        question: '${e.title} ${e.parts.map((p) => p.title).join(' ')}',
      );
      final draft = await ai.draftLabReport(
        experimentTitle: e.title,
        sections: [
          for (final s in e.report) (id: s.id, title: s.title, hint: s.hint, partTitle: e.partById(s.partId)?.title),
        ],
        templates: [for (final m in _templates(e)) (label: m.fileName, text: m.extractedText)],
        images: [for (final i in _images) i.bytes],
        specs: e.reportSpecs,
        data: LabContextService.reportData(e),
        context: ctx.text,
        ownTexts: _useOwnTexts ? LabContextService.ownReportTexts(e) : '',
        onlySectionId: widget.onlySectionId,
        outline: _outline,
        adoptStructure: _adoptStructure,
      );
      // Auf den neuesten Stand anwenden – währenddessen Getipptes bleibt.
      await _update((cur) => draft.applyTo(cur, adoptStructure: _adoptStructure, onlySectionId: widget.onlySectionId));
      setState(() => _missing = draft.missing);
    } on AiServiceException catch (err) {
      setState(() {
        _error = err.message;
        _raw = err.rawResponse;
      });
    } catch (err) {
      setState(() => _error = 'Entwurf fehlgeschlagen: $err');
    } finally {
      setState(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    context.watch<LabExperimentRepository>();
    context.watch<MaterialRepository>();
    final e = _e;
    if (e == null) return const Scaffold(body: Center(child: Text('Versuch nicht gefunden.')));
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    final only = widget.onlySectionId == null ? null : e.report.where((s) => s.id == widget.onlySectionId).firstOrNull;
    final templates = _templates(e);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(only == null ? 'Entwurf zur Inspiration' : 'Entwurf: ${only.title}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(e.title, style: TextStyle(fontSize: 12, color: c.inkMuted)),
          ],
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                LabCard(
                  child: Text(
                    'Ein grober Entwurf je Abschnitt – aus deinen Messwerten, Notizen (auch gespeicherten '
                    'Rechenwegen), Antworten und der Vorlage. Er ist nur Inspiration: Zahlen und Aussagen prüfst du '
                    'selbst, und was fehlt, steht als „[ergänzen: …]“ darin. Er landet neben deinem Text im '
                    'Abschnitt; deinen eigenen Text ändert er nie.',
                    style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                LabCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vorlage und Vorgaben',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
                      const SizedBox(height: 4),
                      Text(
                        'Optional: eine Berichtsvorlage (Word, PDF, PowerPoint) oder ein Foto davon, dazu eigene Vorgaben '
                        'wie Umfang, Gliederung oder Formalia. Die KI richtet sich danach.',
                        style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final m in templates)
                            InputChip(
                              key: ValueKey('draft-template-${m.id}'),
                              avatar: const Icon(Icons.description_outlined, size: 16),
                              label: Text(m.fileName, overflow: TextOverflow.ellipsis),
                              onDeleted: _busy
                                  ? null
                                  : () => _update((cur) =>
                                      cur.copyWith(reportTemplateIds: [for (final id in cur.reportTemplateIds) if (id != m.id) id])),
                            ),
                          for (final (i, image) in _images.indexed)
                            InputChip(
                              key: ValueKey('draft-image-$i'),
                              avatar: const Icon(Icons.image_outlined, size: 16),
                              label: Text(image.name, overflow: TextOverflow.ellipsis),
                              onDeleted: _busy ? null : () => setState(() => _images.removeAt(i)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('draft-upload'),
                            onPressed: _busy ? null : _uploadTemplate,
                            icon: const Icon(Icons.upload_file_outlined, size: 18),
                            label: const Text('Vorlage hochladen'),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('draft-existing'),
                            onPressed: _busy ? null : _pickExisting,
                            icon: const Icon(Icons.folder_open_outlined, size: 18),
                            label: const Text('Aus dem Fach wählen'),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('draft-image'),
                            onPressed: _busy || _images.length >= 4 ? null : _pickImages,
                            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                            label: const Text('Foto der Vorlage'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LabAnswerField(
                        key: const ValueKey('draft-specs'),
                        initial: e.reportSpecs,
                        minLines: 3,
                        hint: 'Vorgaben: z. B. „max. 5 Seiten, Passiv, Gliederung: Ziel, Theorie, Aufbau, Auswertung …“',
                        onSave: (text) => _update((cur) => cur.copyWith(reportSpecs: text)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LabCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Optionen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        key: const ValueKey('draft-mode'),
                        segments: const [
                          ButtonSegment(value: false, label: Text('Ausformuliert')),
                          ButtonSegment(value: true, label: Text('Nur Gerüst')),
                        ],
                        selected: {_outline},
                        onSelectionChanged: (v) => setState(() => _outline = v.first),
                      ),
                      if (widget.onlySectionId == null)
                        SwitchListTile(
                          key: const ValueKey('draft-structure'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _adoptStructure,
                          onChanged: (v) => setState(() => _adoptStructure = v),
                          title: const Text('Gliederung der Vorlage übernehmen', style: TextStyle(fontSize: 13.5)),
                          subtitle: Text(
                            'Abschnitte, die nur die Vorlage kennt, werden neu angelegt.',
                            style: TextStyle(fontSize: 12, color: c.inkMuted),
                          ),
                        ),
                      SwitchListTile(
                        key: const ValueKey('draft-own'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _useOwnTexts,
                        onChanged: (v) => setState(() => _useOwnTexts = v),
                        title: const Text('Meine bisherigen Texte berücksichtigen', style: TextStyle(fontSize: 13.5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('draft-create'),
                  onPressed: hasKey && !_busy ? _create : null,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(_progress ?? (only == null ? 'Entwurf erstellen' : 'Entwurf für diesen Abschnitt erstellen')),
                ),
                if (!hasKey)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Dafür braucht die App deinen OpenRouter-Key (Einstellungen).',
                        style: TextStyle(fontSize: 12.5, color: c.warn)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  LabCard(
                    tint: c.dangerSoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!, key: const ValueKey('draft-error'), style: TextStyle(color: c.danger, height: 1.35)),
                        if (_raw != null)
                          TextButton(
                            onPressed: () => showRawResponseDialog(context, _raw!),
                            child: const Text('Rohantwort anzeigen'),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_missing != null) ...[
                  const SizedBox(height: 12),
                  LabCard(
                    key: const ValueKey('draft-done'),
                    tint: c.goodSoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Der Entwurf liegt in den Abschnitten des Berichts.',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (_missing!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Was dafür noch fehlt:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
                          for (final m in _missing!)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('•  $m', style: const TextStyle(fontSize: 13, height: 1.35)),
                            ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Zum Bericht')),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
