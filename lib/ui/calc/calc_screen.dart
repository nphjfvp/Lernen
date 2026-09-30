import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/lab_experiment.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/calc_engine.dart';
import '../../services/calc_plan.dart';
import '../../services/image_crop.dart';
import '../../theme/app_colors.dart';
import '../lab/lab_widgets.dart';
import '../widgets/raw_response_dialog.dart';
import '../widgets/safe_set_state.dart';
import 'calc_widgets.dart';

/// Rechnen mit KI: Werte als Text/Tabelle und/oder Fotos einer Aufgabe, Tabelle
/// oder eines Messgeräts hineingeben – die KI liest die Werte und stellt den
/// Rechenplan auf, die App rechnet und zeigt den Rechenweg (Formel, eingesetzte
/// Werte, Ergebnis mit Einheit). Gelesene Werte lassen sich korrigieren, die
/// Rechnung läuft dann sofort neu; mit einem Wunsch ("rechne auch die
/// Leistung") überarbeitet die KI den Plan.
class CalcScreen extends StatefulWidget {
  const CalcScreen({
    super.key,
    required this.moduleName,
    this.experiment,
    this.part,
    this.initialTask = '',
    this.initialValues = '',
    this.onSaveNote,
  });

  final String moduleName;

  /// Versuch und Versuchsteil, aus dem heraus gerechnet wird (Kontext für die KI).
  final LabExperiment? experiment;
  final LabPart? part;
  final String initialTask;
  final String initialValues;

  /// Speichert den Rechenweg (z.B. in den Notizen des Versuchsteils); ohne
  /// Angabe gibt es den Knopf nicht.
  final Future<void> Function(String text)? onSaveNote;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs.
  @visibleForTesting
  static Future<List<({String name, Uint8List bytes})>> Function()? pickImagesHook;

  /// So viele Bilder auf einmal.
  static const maxImages = 6;

  @override
  State<CalcScreen> createState() => _CalcScreenState();
}

class _CalcScreenState extends State<CalcScreen> with SafeSetState<CalcScreen> {
  late final TextEditingController _task = TextEditingController(text: widget.initialTask);
  late final TextEditingController _values = TextEditingController(text: widget.initialValues);
  final _instruction = TextEditingController();
  final List<({String name, Uint8List bytes})> _images = [];

  CalcPlan? _plan;
  List<CalcStepResult> _results = const [];

  /// Erhöht sich mit jedem neuen Plan – die Wertefelder bauen sich dann neu auf.
  int _revision = 0;
  bool _busy = false;
  bool _resendImages = false;
  String? _error;
  String? _raw;

  @override
  void dispose() {
    _task.dispose();
    _values.dispose();
    _instruction.dispose();
    super.dispose();
  }

  AiService? _ai({required bool vision}) {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    final model = vision ? settings.visionModelId : settings.questionModelId;
    return CalcScreen.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
  }

  /// Was die KI über den Versuch wissen soll (die Messwerte stehen im Werte-Feld).
  String _contextText() {
    final e = widget.experiment;
    if (e == null) return '';
    final part = widget.part;
    final b = StringBuffer('Versuch: ${e.title}');
    if (part != null) {
      b.writeln('\nVersuchsteil: ${part.title}');
      for (final g in part.goals) {
        b.writeln('Ziel: $g');
      }
      for (final q in part.questions) {
        b.writeln('Auswertungsaufgabe ${q.number}: ${q.text}');
      }
    }
    return b.toString().trim();
  }

  Future<void> _pickImages() async {
    final room = CalcScreen.maxImages - _images.length;
    if (room <= 0) return;
    final List<({String name, Uint8List bytes})> picked;
    final hook = CalcScreen.pickImagesHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      picked = [
        for (final f in files.take(room)) (name: f.name, bytes: await f.readAsBytes()),
      ];
    }
    final prepared = <({String name, Uint8List bytes})>[];
    for (final p in picked.take(room)) {
      // Fotos vom Handy sind mehrere MB groß – für das Ablesen reichen 1600 px.
      prepared.add((name: p.name, bytes: await downscaleImage(p.bytes, maxSide: 1600) ?? p.bytes));
    }
    if (!mounted) return;
    setState(() => _images.addAll(prepared));
  }

  Future<void> _run({CalcPlan? previous, String instruction = ''}) async {
    final sendImages = _images.isNotEmpty && (previous == null || _resendImages);
    final ai = _ai(vision: sendImages);
    if (ai == null) {
      setState(() => _error = 'Zum Rechnen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _raw = null;
    });
    try {
      final plan = await ai.planCalculation(
        task: _task.text,
        values: _values.text,
        images: sendImages ? [for (final i in _images) i.bytes] : const [],
        context: _contextText(),
        previous: previous,
        instruction: instruction,
      );
      setState(() {
        _plan = plan;
        _results = plan.evaluate();
        _revision++;
        if (previous != null) _instruction.clear();
      });
    } on AiServiceException catch (e) {
      setState(() {
        _error = e.message;
        _raw = e.rawResponse;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  void _onGiven(String symbol, CalcVec values) {
    final plan = _plan?.withGiven(symbol, values);
    if (plan == null) return;
    setState(() {
      _plan = plan;
      _results = plan.evaluate();
    });
  }

  String _text() => _plan!.asText(_results);

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text()));
    if (mounted) _snack('Rechenweg kopiert.');
  }

  Future<void> _saveNote() async {
    await widget.onSaveNote!(_text());
    if (mounted) _snack('Rechenweg in den Notizen gespeichert.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rechnen mit KI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(widget.moduleName, style: TextStyle(fontSize: 12, color: c.inkMuted)),
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
                _inputCard(hasKey),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _errorCard(),
                ],
                if (plan != null) ..._resultViews(plan),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputCard(bool hasKey) {
    final c = context.colors;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('calc-task'),
            controller: _task,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Was soll berechnet werden?',
              hintText: 'z. B. Berechne den Widerstand und die Leistung für jede Messung.',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('calc-values'),
            controller: _values,
            minLines: 3,
            maxLines: 12,
            style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Werte (Text oder Tabelle)',
              hintText: 'z. B. U = 12,3 V, I = 450 mA – oder eine Tabelle einfügen',
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
                key: const ValueKey('calc-add-image'),
                onPressed: _busy || _images.length >= CalcScreen.maxImages ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(_images.isEmpty ? 'Bild hinzufügen' : 'Weiteres Bild'),
              ),
              for (final (i, image) in _images.indexed)
                InputChip(
                  key: ValueKey('calc-image-$i'),
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
          const SizedBox(height: 8),
          Text(
            'Die KI liest die Werte (auch aus Fotos von Aufgabe, Tabelle oder Messgerät) und stellt die Formeln auf – '
            'gerechnet wird in der App, damit die Zahlen stimmen. Gelesene Werte bitte kurz prüfen; du kannst sie '
            'unten korrigieren, die Rechnung läuft dann neu.',
            style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('calc-run'),
            onPressed: hasKey && !_busy ? () => _run() : null,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.calculate_outlined, size: 18),
            label: Text(_busy ? 'Rechnet …' : 'Berechnen'),
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

  Widget _errorCard() {
    final c = context.colors;
    return LabCard(
      tint: c.dangerSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_error!, key: const ValueKey('calc-error'), style: TextStyle(color: c.danger, height: 1.35)),
          if (_raw != null)
            TextButton(onPressed: () => showRawResponseDialog(context, _raw!), child: const Text('Rohantwort anzeigen')),
        ],
      ),
    );
  }

  List<Widget> _resultViews(CalcPlan plan) {
    final c = context.colors;
    final byId = {for (final r in _results) r.step.symbol: r};
    final finals = [
      for (final s in plan.finalSymbols)
        if (byId[s] case final r? when r.ok) r,
    ];
    final finalSet = plan.finalSymbols.toSet();
    return [
      const SizedBox(height: 12),
      if (plan.title.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(plan.title.trim(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      if (finals.isNotEmpty)
        LabCard(
          key: const ValueKey('calc-final'),
          tint: c.accentSoft.withValues(alpha: 0.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ergebnis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
              for (final r in finals)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText(
                    '${r.step.symbol} = ${r.valueText}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
      if (plan.given.isNotEmpty) ...[
        const SizedBox(height: 12),
        LabCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gegeben – bitte prüfen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
              const SizedBox(height: 8),
              for (final g in plan.given)
                CalcGivenRow(
                  key: ValueKey('calc-given-row-${g.symbol}-$_revision'),
                  given: g,
                  onChanged: (values) => _onGiven(g.symbol, values),
                ),
              Text(
                'Werte in der Grundeinheit (z. B. Ω, V, s). Reihen mit Semikolon trennen.',
                style: TextStyle(fontSize: 12, color: c.inkMuted),
              ),
            ],
          ),
        ),
      ],
      if (_results.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Rechenweg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
        const SizedBox(height: 6),
        for (final (i, r) in _results.indexed) ...[
          CalcStepCard(index: i + 1, result: r, isFinal: finalSet.contains(r.step.symbol)),
          const SizedBox(height: 10),
        ],
      ],
      LabCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Zur Einordnung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
            if (plan.assumptions.isEmpty && plan.notes.isEmpty && plan.missing.isEmpty && plan.problems.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 4), child: Text('Keine besonderen Hinweise.')),
            CalcBulletList(title: 'Es fehlt noch', items: plan.missing, color: c.warn),
            CalcBulletList(title: 'Annahmen', items: plan.assumptions),
            CalcBulletList(title: 'Hinweise', items: plan.notes),
            CalcBulletList(title: 'Beim Einlesen aufgefallen', items: plan.problems, color: c.warn),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('calc-copy'),
            onPressed: _copy,
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Rechenweg kopieren'),
          ),
          if (widget.onSaveNote != null)
            OutlinedButton.icon(
              key: const ValueKey('calc-save-note'),
              onPressed: _saveNote,
              icon: const Icon(Icons.note_add_outlined, size: 18),
              label: const Text('In Notizen speichern'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      LabCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Anpassen lassen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('calc-instruction'),
              controller: _instruction,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'z. B. „Rechne zusätzlich die Leistung“ oder „Nimm für R_2 den Wert 220 Ω“',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_images.isNotEmpty)
              SwitchListTile(
                key: const ValueKey('calc-resend'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _resendImages,
                onChanged: (v) => setState(() => _resendImages = v),
                title: const Text('Bilder erneut mitschicken', style: TextStyle(fontSize: 13)),
                subtitle: Text('Nötig, wenn die KI etwas im Bild anders lesen soll.',
                    style: TextStyle(fontSize: 12, color: c.inkMuted)),
              ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('calc-refine'),
              onPressed: _busy ? null : () => _run(previous: plan, instruction: _instruction.text),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Plan überarbeiten'),
            ),
          ],
        ),
      ),
    ];
  }
}
