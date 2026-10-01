import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/lab_experiment.dart';
import '../../models/lab_photo.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../repositories/lab_photo_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/image_crop.dart';
import '../../services/lab_photo_reading.dart';
import '../../theme/app_colors.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'lab_widgets.dart';

/// Fotos zu Laborversuchen: mehrere auf einmal hochladen, die KI ordnet jedes
/// einem Versuch (und Versuchsteil) zu und liest die Messwerte für die leeren
/// Tabellenzellen ab. Nichts wird ohne Blick übernommen: Zuordnung und Werte
/// lassen sich ändern, schon ausgefüllte Zellen werden nur auf Wunsch
/// überschrieben. Mit [experimentId] geht es nur um diesen einen Versuch.
class LabPhotosScreen extends StatefulWidget {
  const LabPhotosScreen({super.key, required this.moduleId, required this.moduleName, this.experimentId});

  final String moduleId;
  final String moduleName;
  final String? experimentId;

  /// So viele Fotos auf einmal.
  static const maxPhotos = 10;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs.
  @visibleForTesting
  static Future<List<({String name, Uint8List bytes})>> Function()? pickImagesHook;

  @override
  State<LabPhotosScreen> createState() => _LabPhotosScreenState();
}

enum _Status { idle, reading, read, failed, applied }

class _Item {
  _Item(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
  _Status status = _Status.idle;
  LabPhotoReading? reading;
  String? error;
  String? raw;
  String? experimentId;
  String? partId;

  /// Abgewählte Zellen ("tabelle-zeile-spalte") und ob die weiteren Werte als
  /// Notiz mit sollen.
  final Set<String> off = {};
  bool notesOn = true;
  String description = '';
  int applied = 0;
}

class _LabPhotosScreenState extends State<LabPhotosScreen> with SafeSetState<LabPhotosScreen> {
  static final _date = DateFormat('dd.MM.');

  final List<_Item> _items = [];
  bool _busy = false;

  List<LabExperiment> get _experiments {
    final all = context.read<LabExperimentRepository>().forModule(widget.moduleId);
    final only = widget.experimentId;
    return only == null
        ? all
        : [
            for (final e in all)
              if (e.id == only) e,
          ];
  }

  AiService? _ai() {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    // Fotos lesen braucht das Bild-Modell.
    return LabPhotosScreen.aiFactory?.call(settings.openRouterApiKey!, settings.visionModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId);
  }

  Future<void> _pick() async {
    final room = LabPhotosScreen.maxPhotos - _items.length;
    if (room <= 0) return;
    final List<({String name, Uint8List bytes})> picked;
    final hook = LabPhotosScreen.pickImagesHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      picked = [for (final f in files.take(room)) (name: f.name, bytes: await f.readAsBytes())];
    }
    final prepared = <_Item>[];
    for (final p in picked.take(room)) {
      prepared.add(_Item(p.name, await prepareImageForAi(p.bytes)));
    }
    if (!mounted) return;
    setState(() => _items.addAll(prepared));
  }

  Future<void> _readAll() async {
    final ai = _ai();
    if (ai == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zum Auslesen braucht die App deinen OpenRouter-Key (Einstellungen).')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      for (final item in _items.where((i) => i.status == _Status.idle || i.status == _Status.failed).toList()) {
        if (!mounted) return;
        await _read(ai, item);
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _read(AiService ai, _Item item) async {
    setState(() {
      item.status = _Status.reading;
      item.error = null;
      item.raw = null;
    });
    try {
      final experiments = _experiments;
      final reading = await ai.readLabPhoto(image: item.bytes, experiments: experiments);
      setState(() {
        item.reading = reading;
        item.description = reading.description;
        item.experimentId = reading.experimentId ?? (experiments.length == 1 ? experiments.first.id : null);
        item.partId = item.experimentId == reading.experimentId ? reading.partId : null;
        item.off.clear();
        item.status = _Status.read;
      });
    } on AiServiceException catch (e) {
      setState(() {
        item.status = _Status.failed;
        item.error = e.message;
        item.raw = e.rawResponse;
      });
    } catch (e) {
      setState(() {
        item.status = _Status.failed;
        item.error = 'Auslesen fehlgeschlagen: $e';
      });
    }
  }

  Future<void> _readOne(_Item item) async {
    final ai = _ai();
    if (ai == null) return;
    setState(() => _busy = true);
    try {
      await _read(ai, item);
    } finally {
      setState(() => _busy = false);
    }
  }

  ({List<LabCellFill> fills, String notes}) _target(_Item item) {
    final e = context.read<LabExperimentRepository>().byId(item.experimentId ?? '');
    return item.reading!.targetFor(e, item.partId);
  }

  String _key(LabCellFill f) => '${f.table}-${f.row}-${f.col}';

  /// Trägt die gewählten Werte ein und legt das Foto beim Versuch ab.
  Future<void> _apply(_Item item) async {
    final repo = context.read<LabExperimentRepository>();
    final photos = context.read<LabPhotoRepository?>();
    final e = repo.byId(item.experimentId ?? '');
    if (e == null) return;
    LabAnswerField.flushPending();
    final target = _target(item);
    final chosen = [
      for (final f in target.fills)
        if (!item.off.contains(_key(f))) f,
    ];
    final partId = item.partId;
    var next = e;
    var count = 0;
    if (partId != null && e.partById(partId) != null) {
      final notes = item.notesOn ? target.notes : '';
      next = LabPhotoReading.apply(e, partId, chosen, notes: notes, stamp: 'Foto vom ${_date.format(DateTime.now())}');
      count = chosen.length;
    }
    if (next != e) await repo.save(next);
    await photos?.add(
      LabPhoto(
        id: const Uuid().v4(),
        experimentId: e.id,
        moduleId: e.moduleId,
        base64: base64Encode(item.bytes),
        createdAt: DateTime.now(),
        partId: partId,
        description: item.description,
      ),
    );
    if (!mounted) return;
    setState(() {
      item.status = _Status.applied;
      item.applied = count;
    });
  }

  Future<void> _applyAll() async {
    for (final item in _items.where((i) => i.status == _Status.read && i.experimentId != null).toList()) {
      await _apply(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    context.watch<LabExperimentRepository>();
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    final experiments = _experiments;
    final ready = _items.where((i) => i.status == _Status.read && i.experimentId != null).length;
    final toRead = _items.where((i) => i.status == _Status.idle || i.status == _Status.failed).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos zuordnen & auslesen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(
            widget.experimentId == null
                ? 'Lade Fotos von Messprotokollen, Geräteanzeigen oder Notizen hoch. Die KI ordnet jedes '
                      'Foto einem Versuch zu und liest die Werte in die leeren Messwertfelder ab – du siehst '
                      'alles vorher und kannst es ändern.'
                : 'Lade Fotos von Messprotokollen, Geräteanzeigen oder Notizen zu diesem Versuch hoch. Die KI '
                      'liest die Werte in die leeren Messwertfelder ab – du siehst alles vorher und kannst es ändern.',
            style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
          ),
          if (experiments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Lege zuerst einen Laborversuch an – die Fotos werden Versuchen zugeordnet.',
                style: TextStyle(color: c.warn),
              ),
            ),
          if (!hasKey)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Zum Auslesen braucht die App deinen OpenRouter-Key (Einstellungen).',
                style: TextStyle(color: c.warn),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('lab-photos-pick'),
                onPressed: _busy || _items.length >= LabPhotosScreen.maxPhotos ? null : _pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('Fotos wählen (${_items.length}/${LabPhotosScreen.maxPhotos})'),
              ),
              FilledButton.icon(
                key: const ValueKey('lab-photos-read'),
                onPressed: _busy || toRead == 0 || experiments.isEmpty ? null : _readAll,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(_busy ? 'Liest …' : 'Auslesen'),
              ),
              if (ready > 1)
                FilledButton.tonalIcon(
                  key: const ValueKey('lab-photos-apply-all'),
                  onPressed: _busy ? null : _applyAll,
                  icon: const Icon(Icons.done_all),
                  label: Text('Alle $ready übernehmen'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in _items) ...[_card(item, experiments), const SizedBox(height: 12)],
        ],
      ),
    );
  }

  Widget _card(_Item item, List<LabExperiment> experiments) {
    final c = context.colors;
    final index = _items.indexOf(item);
    return LabCard(
      key: ValueKey('lab-photo-$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(item.bytes, width: 84, height: 84, fit: BoxFit.cover, gaplessPlayback: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusText(item),
                      style: TextStyle(fontSize: 12.5, color: item.status == _Status.failed ? c.danger : c.inkMuted),
                    ),
                  ],
                ),
              ),
              if (item.status != _Status.applied)
                IconButton(
                  tooltip: 'Foto entfernen',
                  icon: const Icon(Icons.close),
                  onPressed: _busy ? null : () => setState(() => _items.remove(item)),
                ),
            ],
          ),
          if (item.status == _Status.failed) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: _busy ? null : () => _readOne(item), child: const Text('Erneut versuchen')),
                if (item.raw != null)
                  TextButton(
                    onPressed: () => showRawResponseDialog(context, item.raw!),
                    child: const Text('Antwort der KI'),
                  ),
              ],
            ),
          ],
          if (item.status == _Status.read) ..._result(item, experiments),
        ],
      ),
    );
  }

  String _statusText(_Item item) => switch (item.status) {
    _Status.idle => 'Noch nicht ausgelesen',
    _Status.reading => 'Wird gelesen …',
    _Status.read => item.description.isEmpty ? 'Ausgelesen' : item.description,
    _Status.failed => item.error ?? 'Auslesen fehlgeschlagen',
    _Status.applied =>
      item.applied > 0
          ? 'Übernommen: ${item.applied} ${item.applied == 1 ? 'Wert' : 'Werte'} eingetragen, Foto beim Versuch abgelegt'
          : 'Foto beim Versuch abgelegt',
  };

  List<Widget> _result(_Item item, List<LabExperiment> experiments) {
    final c = context.colors;
    final reading = item.reading!;
    final experiment = experiments.where((e) => e.id == item.experimentId).firstOrNull;
    final target = _target(item);
    final aiSame = experiment != null && experiment.id == reading.experimentId && item.partId == reading.partId;
    return [
      const SizedBox(height: 10),
      if (reading.confidence == 'niedrig' || reading.experimentId == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            reading.experimentId == null
                ? 'Die KI konnte das Foto keinem Versuch sicher zuordnen – bitte wählen.'
                : 'Die Zuordnung ist unsicher – bitte prüfen.',
            style: TextStyle(fontSize: 12.5, color: c.warn),
          ),
        ),
      Row(
        children: [
          SizedBox(
            width: 62,
            child: Text('Versuch', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          ),
          Expanded(
            child: DropdownButton<String?>(
              key: ValueKey('lab-photo-exp-${_items.indexOf(item)}'),
              isExpanded: true,
              value: experiment?.id,
              hint: const Text('Versuch wählen'),
              items: [
                for (final e in experiments)
                  DropdownMenuItem(
                    value: e.id,
                    child: Text(e.title, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() {
                item.experimentId = v;
                item.partId = v == reading.experimentId ? reading.partId : null;
                item.off.clear();
              }),
            ),
          ),
        ],
      ),
      if (experiment != null && experiment.parts.isNotEmpty)
        Row(
          children: [
            SizedBox(
              width: 62,
              child: Text('Teil', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ),
            Expanded(
              child: DropdownButton<String?>(
                key: ValueKey('lab-photo-part-${_items.indexOf(item)}'),
                isExpanded: true,
                value: experiment.partById(item.partId)?.id,
                hint: const Text('Versuchsteil wählen'),
                items: [
                  for (final p in experiment.parts)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() {
                  item.partId = v;
                  item.off.clear();
                }),
              ),
            ),
          ],
        ),
      if (experiment != null &&
          experiment.partById(item.partId) == null &&
          experiment.parts.isNotEmpty &&
          (reading.cells.isNotEmpty || reading.notes.isNotEmpty))
        Text(
          'Wähle den Versuchsteil, damit die Werte eingetragen werden können.',
          style: TextStyle(fontSize: 12.5, color: c.warn),
        ),
      if (experiment != null && !aiSame && reading.cells.isNotEmpty && experiment.partById(item.partId) != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Du hast die Zuordnung geändert: die gelesenen Werte kommen deshalb als Notiz in den Teil, nicht in die Tabellen.',
            style: TextStyle(fontSize: 12.5, color: c.inkMuted),
          ),
        ),
      if (target.fills.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          'Werte für die Tabellen',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.inkMuted),
        ),
        for (final f in target.fills)
          CheckboxListTile(
            key: ValueKey('lab-photo-cell-${_items.indexOf(item)}-${_key(f)}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: !item.off.contains(_key(f)),
            onChanged: (v) => setState(() => v == true ? item.off.remove(_key(f)) : item.off.add(_key(f))),
            title: Text(f.value, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              f.overwrites ? '${f.label} · ersetzt „${f.existing.trim()}“' : f.label,
              style: TextStyle(fontSize: 12, color: f.overwrites ? c.warn : c.inkMuted),
            ),
          ),
      ],
      if (target.notes.isNotEmpty && experiment?.partById(item.partId) != null)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: item.notesOn,
          onChanged: (v) => setState(() => item.notesOn = v ?? true),
          title: const Text('Weitere Werte als Notiz im Versuchsteil'),
          subtitle: Text(
            target.notes,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.inkMuted),
          ),
        ),
      if (reading.unclear.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Nicht lesbar: ${reading.unclear.join('; ')}', style: TextStyle(fontSize: 12.5, color: c.warn)),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            key: ValueKey('lab-photo-apply-${_items.indexOf(item)}'),
            onPressed: experiment == null || _busy ? null : () => _apply(item),
            child: Text(
              target.fills.isEmpty && !(target.notes.isNotEmpty && item.notesOn)
                  ? 'Foto beim Versuch ablegen'
                  : 'Übernehmen',
            ),
          ),
          TextButton(onPressed: _busy ? null : () => _readOne(item), child: const Text('Neu lesen')),
        ],
      ),
    ];
  }
}
