import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/lab_experiment.dart';
import '../../models/material_item.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/material_file_store.dart';
import '../../services/material_text_extractor.dart';
import '../../services/pdf_ocr_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/existing_material_picker.dart';
import '../widgets/ocr_notice.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'lab_experiment_screen.dart';
import 'lab_widgets.dart';

/// Neuen Laborversuch anlegen: Titel, Termine und die Unterlagen (Versuchs-
/// anleitung, Theorie-Skript) – die KI liest daraus Vorbereitungsfragen,
/// Versuchsteile, Messwerttabellen und Auswertungsfragen heraus.
class LabCreateScreen extends StatefulWidget {
  const LabCreateScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  @override
  State<LabCreateScreen> createState() => _LabCreateScreenState();
}

class _LabCreateScreenState extends State<LabCreateScreen> with SafeSetState<LabCreateScreen> {
  static final _date = DateFormat('dd.MM.yyyy');

  final _title = TextEditingController();
  final List<MaterialItem> _guides = [];
  final List<MaterialItem> _theories = [];
  DateTime? _labDate;
  DateTime? _reportDue;
  bool _busy = false;
  String? _progress;
  String? _error;
  String? _rawResponse;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool _isPicked(MaterialItem m) => _guides.any((g) => g.id == m.id) || _theories.any((t) => t.id == m.id);

  Future<void> _pickExisting(List<MaterialItem> target) async {
    final available = context.read<MaterialRepository>().forModule(widget.moduleId);
    final selected = await showExistingMaterialPicker(
      context,
      available: available,
      alreadyPickedIds: {for (final m in [..._guides, ..._theories]) m.id},
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() => target.addAll(selected.where((m) => !_isPicked(m))));
  }

  /// Neue Dateien: Text auslesen und – wie beim normalen Hochladen – als
  /// Material des Fachs ablegen.
  Future<void> _upload(List<MaterialItem> target) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: MaterialTextExtractor.supportedExtensions,
    );
    if (picked.isEmpty || !mounted) return;
    final repo = context.read<MaterialRepository>();
    final ocr = PdfOcrService.fromSettings(context.read<SettingsRepository>().settings);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Dateien werden gelesen …';
    });
    final errors = <String>[];
    for (final file in picked) {
      try {
        final Uint8List bytes = await file.readAsBytes();
        final text = await MaterialTextExtractor()
            .extractTextWithOcr(file.name, bytes, ocr: ocr, onProgress: ocrStartNotice(messenger, file.name));
        if (text.isEmpty) {
          errors.add('${file.name}: kein Text gefunden.');
          continue;
        }
        final id = const Uuid().v4();
        String? filePath;
        String? fileBytesBase64;
        if (file.name.toLowerCase().endsWith('.pdf')) {
          (filePath, fileBytesBase64) = await MaterialFileStore.store(id, bytes);
        }
        final material = MaterialItem(
          id: id,
          moduleId: widget.moduleId,
          fileName: file.name,
          kind: MaterialKind.slide,
          extractedText: text,
          createdAt: DateTime.now(),
          filePath: filePath,
          fileBytesBase64: fileBytesBase64,
        );
        await repo.save(material);
        if (!mounted) return;
        setState(() => target.add(material));
      } catch (e) {
        errors.add('${file.name}: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      if (errors.isNotEmpty) _error = errors.join('\n');
    });
  }

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 730)),
      );

  int get _sourceLength => [..._guides, ..._theories].fold(0, (sum, m) => sum + m.extractedText.length);

  bool get _tooLong => [_guides, _theories].any(
      (list) => list.fold<int>(0, (sum, m) => sum + m.extractedText.length) > AiService.labSourceCap);

  Future<void> _create({required bool withAi}) async {
    final settings = context.read<SettingsRepository>().settings;
    final repo = context.read<LabExperimentRepository>();
    final navigator = Navigator.of(context);
    final title = _title.text.trim();
    if (!withAi && title.isEmpty) {
      setState(() => _error = 'Gib dem Versuch einen Namen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _rawResponse = null;
      _progress = withAi ? 'Die KI liest die Unterlagen …' : null;
    });
    try {
      Map<String, dynamic> structure = const {};
      if (withAi) {
        final ai = LabCreateScreen.aiFactory?.call(settings.openRouterApiKey ?? '', settings.questionModelId) ??
            AiService(apiKey: settings.openRouterApiKey ?? '', model: settings.questionModelId);
        structure = await ai.structureLabExperiment(sources: [
          for (final m in _guides) (label: 'Versuchsanleitung: ${m.fileName}', text: m.extractedText),
          for (final m in _theories) (label: 'Theorie-Skript: ${m.fileName}', text: m.extractedText),
        ]);
      }
      final experiment = LabExperiment.fromStructure(
        {...structure, if (title.isNotEmpty) 'title': title},
        moduleId: widget.moduleId,
        now: DateTime.now(),
        fallbackTitle: 'Laborversuch',
        guideMaterialIds: [for (final m in _guides) m.id],
        theoryMaterialIds: [for (final m in _theories) m.id],
        labDate: _labDate,
        reportDue: _reportDue,
      );
      if (withAi && experiment.prep.isEmpty && experiment.parts.isEmpty) {
        throw AiServiceException(
            'Die KI hat in den Unterlagen weder Vorbereitungsfragen noch Versuchsteile gefunden. '
            'Prüfe, ob die richtigen Dateien gewählt sind – oder lege den Versuch leer an.');
      }
      await repo.save(experiment);
      if (!mounted) return;
      navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => LabExperimentScreen(experimentId: experiment.id, moduleName: widget.moduleName),
      ));
    } on AiServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = e.message;
        _rawResponse = e.rawResponse;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = 'Der Versuch konnte nicht angelegt werden: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    final canRead = hasKey && (_guides.isNotEmpty || _theories.isNotEmpty) && !_busy;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Laborversuch anlegen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Lade die Versuchsanleitung und – falls vorhanden – das Theorie-Skript hoch. Die KI liest '
            'Vorbereitungsfragen, Versuchsteile, Messwerttabellen und Auswertungsfragen heraus; '
            'danach kannst du alles von Hand ändern.',
            style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('lab-title'),
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Name des Versuchs (optional)',
              hintText: 'z.B. Digitalspeicheroszilloskop',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  label: 'Labortermin',
                  date: _labDate,
                  format: _date,
                  onPick: () async {
                    final d = await _pickDate(_labDate);
                    if (d != null && mounted) setState(() => _labDate = d);
                  },
                  onClear: () => setState(() => _labDate = null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateButton(
                  label: 'Bericht abgeben bis',
                  date: _reportDue,
                  format: _date,
                  onPick: () async {
                    final d = await _pickDate(_reportDue ?? _labDate);
                    if (d != null && mounted) setState(() => _reportDue = d);
                  },
                  onClear: () => setState(() => _reportDue = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _MaterialPicker(
            title: 'Versuchsanleitung / Durchführung',
            hint: 'Was du im Labor tust: Aufbau, Schritte, Messwerttabellen.',
            picked: _guides,
            busy: _busy,
            onExisting: () => _pickExisting(_guides),
            onUpload: () => _upload(_guides),
            onRemove: (m) => setState(() => _guides.remove(m)),
          ),
          const SizedBox(height: 16),
          _MaterialPicker(
            title: 'Theorie-Skript zum Versuch',
            hint: 'Hintergrund und Vorbereitungsaufgaben.',
            picked: _theories,
            busy: _busy,
            onExisting: () => _pickExisting(_theories),
            onUpload: () => _upload(_theories),
            onRemove: (m) => setState(() => _theories.remove(m)),
          ),
          if (_tooLong) ...[
            const SizedBox(height: 10),
            Text(
              'Die Unterlagen sind sehr lang (${(_sourceLength / 1000).round()} k Zeichen) – die KI liest '
              'davon pro Gruppe nur die ersten ${AiService.labSourceCap ~/ 1000} k Zeichen. '
              'Fehlt danach etwas, kannst du es von Hand ergänzen.',
              style: TextStyle(fontSize: 12.5, color: c.warn, height: 1.4),
            ),
          ],
          const SizedBox(height: 22),
          if (!hasKey)
            Text(
              'Zum Einlesen braucht die App deinen OpenRouter-Key (Einstellungen). Ohne Key kannst du den '
              'Versuch leer anlegen und alles selbst eintragen.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: c.danger, fontSize: 13, height: 1.4)),
            if (_rawResponse != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => showRawResponseDialog(context, _rawResponse!),
                  child: const Text('KI-Antwort ansehen'),
                ),
              ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('lab-read'),
            onPressed: canRead ? () => _create(withAi: true) : null,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(_busy ? (_progress ?? 'Einen Moment …') : 'Versuch einlesen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('lab-empty'),
            onPressed: _busy ? null : () => _create(withAi: false),
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Leer anlegen (ohne KI)'),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.date,
    required this.format,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final DateFormat format;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: date == null
              ? const Icon(Icons.event_outlined, size: 18)
              : IconButton(
                  tooltip: 'Datum entfernen',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                ),
        ),
        child: Text(date == null ? 'offen' : format.format(date!),
            style: TextStyle(color: date == null ? c.inkMuted : c.ink)),
      ),
    );
  }
}

class _MaterialPicker extends StatelessWidget {
  const _MaterialPicker({
    required this.title,
    required this.hint,
    required this.picked,
    required this.busy,
    required this.onExisting,
    required this.onUpload,
    required this.onRemove,
  });

  final String title;
  final String hint;
  final List<MaterialItem> picked;
  final bool busy;
  final VoidCallback onExisting;
  final VoidCallback onUpload;
  final ValueChanged<MaterialItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(hint, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          const SizedBox(height: 8),
          for (final m in picked)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 18, color: c.inkMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(m.fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: 'Entfernen',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: busy ? null : () => onRemove(m),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onUpload,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Hochladen'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onExisting,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Aus dem Fach'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
