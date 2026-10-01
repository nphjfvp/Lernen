import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/lab_experiment.dart';
import '../../models/material_item.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/card_csv_service.dart';
import '../../services/lab_context_service.dart';
import '../../services/lab_export_service.dart';
import '../../theme/app_colors.dart';
import '../calc/calc_screen.dart';
import '../chat/module_chat_screen.dart';
import '../modules/material_opener.dart';
import '../review/review_screen.dart';
import '../widgets/confirm_delete_dialog.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';
import 'lab_draft_screen.dart';
import 'lab_widgets.dart';

/// Ein Laborversuch mit vier Reitern: Vorbereitung (Aufgaben mit eigenen
/// Antworten und KI-Gegenlesen), Durchführung (Schritte, Messwerte,
/// Auswertungsfragen), Bericht (eigene Texte, KI als Gegenleser) und Lernen
/// (Karten aus Skript und eigenen Antworten).
class LabExperimentScreen extends StatefulWidget {
  const LabExperimentScreen({super.key, required this.experimentId, required this.moduleName});

  final String experimentId;
  final String moduleName;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  /// Nur für Tests: statt des Datei-Dialogs (Name, Bytes, MIME-Typ).
  @visibleForTesting
  static Future<void> Function(String fileName, Uint8List bytes, String mimeType)? saveFileHook;

  @override
  State<LabExperimentScreen> createState() => _LabExperimentScreenState();
}

class _LabExperimentScreenState extends State<LabExperimentScreen> with SafeSetState<LabExperimentScreen> {
  static final _date = DateFormat('dd.MM.yyyy');

  late final LabExperimentRepository _repo = context.read<LabExperimentRepository>();
  final _context = LabContextService();

  /// Aufgaben/Abschnitte, die gerade von der KI gelesen werden.
  final Set<String> _busy = {};
  final Map<String, List<LabReference>> _refs = {};

  /// Zählt, wie oft die Notizen eines Teils von außen (Rechenweg) ergänzt wurden –
  /// das Textfeld baut sich dann mit dem neuen Stand neu auf.
  final Map<String, int> _notesRevision = {};

  /// Dasselbe für Berichtsabschnitte, wenn ein Entwurf in den Text übernommen wurde.
  final Map<String, int> _sectionRevision = {};
  String? _batchProgress;

  LabExperiment? get _e => _repo.byId(widget.experimentId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final e = _e;
      if (e != null) context.read<MaterialRepository>().loadForModule(e.moduleId);
    });
  }

  /// Ändert immer den zuletzt gespeicherten Stand (nicht eine veraltete
  /// Kopie im Widget) – mehrere schnelle Eingaben überschreiben sich nicht.
  Future<void> _update(LabExperiment Function(LabExperiment) change) async {
    final current = _e;
    if (current == null) return;
    await _repo.save(change(current));
  }

  AiService? _ai() {
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) return null;
    // Gegenlesen ist Hilfe beim Lernen – Modell "Erklärungen & Hilfe".
    return LabExperimentScreen.aiFactory?.call(settings.openRouterApiKey!, settings.effectiveHelpModelId) ??
        AiService(apiKey: settings.openRouterApiKey!, model: settings.effectiveHelpModelId);
  }

  List<MaterialItem> _materials(LabExperiment e) => context.read<MaterialRepository>().forModule(e.moduleId);

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // -- Gegenlesen -------------------------------------------------------------

  LabPart? _partOfQuestion(LabExperiment e, String questionId) {
    for (final p in e.parts) {
      if (p.questions.any((q) => q.id == questionId)) return p;
    }
    return null;
  }

  Future<bool> _reviewQuestion(String id) async {
    final e = _e;
    final q = e?.questionById(id);
    if (e == null || q == null || !q.answered) return false;
    final ai = _ai();
    if (ai == null) {
      _snack('Zum Gegenlesen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return false;
    }
    setState(() => _busy.add(id));
    try {
      final ctx = await _context.contextFor(
        experiment: e,
        materials: _materials(e),
        question: q.text,
        answer: q.answer,
      );
      final feedback = await ai.reviewLabAnswer(
        experimentTitle: e.title,
        number: q.number,
        question: q.text,
        answer: q.answer,
        context: ctx.text,
        measurements: LabContextService.measurementsOf(_partOfQuestion(e, id)),
      );
      _refs[id] = ctx.references;
      await _update((cur) => cur.updateQuestion(id, (old) => old.copyWith(feedback: feedback)));
      return true;
    } on AiServiceException catch (err) {
      if (mounted) _snack(err.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _reviewOpenPrep() async {
    final e = _e;
    if (e == null) return;
    final open = [
      for (final q in e.prep)
        if (q.answered && (q.feedback == null || q.feedback!.isStaleFor(q.answer))) q.id,
    ];
    if (open.isEmpty) {
      _snack('Alles Beantwortete ist schon gegengelesen.');
      return;
    }
    for (var i = 0; i < open.length; i++) {
      if (!mounted) return;
      setState(() => _batchProgress = 'Gegenlesen ${i + 1} von ${open.length} …');
      final ok = await _reviewQuestion(open[i]);
      if (!ok) break;
    }
    if (mounted) setState(() => _batchProgress = null);
  }

  Future<void> _reviewSection(String id) async {
    final e = _e;
    LabReportSection? section;
    for (final s in e?.report ?? const <LabReportSection>[]) {
      if (s.id == id) section = s;
    }
    if (e == null || section == null || section.text.trim().isEmpty) return;
    final ai = _ai();
    if (ai == null) {
      _snack('Zum Gegenlesen braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final part = e.partById(section.partId);
    setState(() => _busy.add(id));
    try {
      final ctx = await _context.contextFor(
        experiment: e,
        materials: _materials(e),
        question: '${section.title} ${section.hint}',
        answer: section.text,
      );
      final feedback = await ai.reviewReportSection(
        experimentTitle: e.title,
        sectionTitle: section.title,
        hint: section.hint,
        text: section.text,
        measurements: part == null ? LabContextService.allMeasurements(e) : LabContextService.measurementsOf(part),
        answers: LabContextService.answersOf(part),
        context: ctx.text,
      );
      _refs[id] = ctx.references;
      await _update((cur) => cur.updateSection(id, (old) => old.copyWith(feedback: feedback)));
    } on AiServiceException catch (err) {
      if (mounted) _snack(err.message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// Passende Stellen im Skript zeigen – ohne KI, nur Stichwortabgleich.
  Future<void> _lookup(String query, {String answer = ''}) async {
    final e = _e;
    if (e == null) return;
    final sources = LabContextService.sourcesOf(e, _materials(e));
    if (sources.isEmpty) {
      _snack('Für diesen Versuch sind keine Unterlagen hinterlegt.');
      return;
    }
    final ctx = await _context.contextFor(experiment: e, materials: _materials(e), question: query, answer: answer);
    if (!mounted) return;
    if (ctx.isEmpty) {
      _snack('Keine passende Stelle gefunden – schau im Inhaltsverzeichnis des Skripts.');
      await _openMaterialChoice(sources);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx2) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Im Skript nachschlagen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final r in ctx.references)
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(r.label),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(ctx2).pop();
                    _openReference(r);
                  },
                ),
              if (ctx.references.isEmpty) SelectableText(ctx.text, style: const TextStyle(fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMaterialChoice(List<MaterialItem> sources) async {
    if (sources.length == 1) return openMaterialAt(context, sources.first);
    final chosen = await showModalBottomSheet<MaterialItem>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in sources)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(m.fileName),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) await openMaterialAt(context, chosen);
  }

  Future<void> _openReference(LabReference r) => openMaterialAt(context, r.material, page: r.page);

  // -- Bearbeiten ---------------------------------------------------------------

  Future<String?> _askText(String title, {String initial = '', String label = 'Text', bool multiline = true}) async {
    final controller = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: multiline ? 6 : 1,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Speichern')),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    return ok == true && text.isNotEmpty ? text : null;
  }

  Future<void> _editQuestion(LabQuestion q) async {
    final text = await _askText('Aufgabe bearbeiten', initial: q.text, label: 'Aufgabentext');
    if (text == null) return;
    await _update((e) => e.updateQuestion(q.id, (old) => LabQuestion(
          id: old.id,
          number: old.number,
          text: text,
          answer: old.answer,
          feedback: old.feedback,
        )));
  }

  Future<void> _deleteQuestion(LabQuestion q) async {
    final ok = await confirmDelete(
      context,
      title: 'Aufgabe löschen?',
      message: 'Die Aufgabe samt deiner Antwort wird entfernt.',
    );
    if (!ok) return;
    await _update((e) => e.copyWith(
          prep: [for (final x in e.prep) if (x.id != q.id) x],
          parts: [
            for (final p in e.parts) p.copyWith(questions: [for (final x in p.questions) if (x.id != q.id) x]),
          ],
        ));
  }

  Future<void> _addPrepQuestion() async {
    final text = await _askText('Aufgabe hinzufügen', label: 'Aufgabentext');
    if (text == null) return;
    await _update((e) => e.copyWith(prep: [
          ...e.prep,
          LabQuestion(id: const Uuid().v4(), number: '${e.prep.length + 1}', text: text),
        ]));
  }

  Future<void> _addEvaluationQuestion(LabPart part) async {
    final text = await _askText('Auswertungsfrage hinzufügen', label: 'Frage');
    if (text == null) return;
    await _update((e) => e.updatePart(part.id, (p) => p.copyWith(questions: [
          ...p.questions,
          LabQuestion(
            id: const Uuid().v4(),
            number: '${e.parts.indexWhere((x) => x.id == part.id) + 1}.${p.questions.length + 1}',
            text: text,
          ),
        ])));
  }

  Future<void> _addStep(LabPart part) async {
    final text = await _askText('Schritt hinzufügen', label: 'Arbeitsschritt');
    if (text == null) return;
    await _update((e) => e.updatePart(part.id, (p) => p.copyWith(steps: [...p.steps, LabStep(text: text)])));
  }

  Future<void> _addPart() async {
    final title = await _askText('Versuchsteil hinzufügen', label: 'Name', multiline: false);
    if (title == null) return;
    final part = LabPart(id: const Uuid().v4(), title: title);
    await _update((e) {
      final section = LabReportSection(id: const Uuid().v4(), title: title, partId: part.id);
      final report = [...e.report];
      // Vor dem abschließenden Fazit einsortieren.
      report.insert(report.length >= 2 ? report.length - 1 : report.length, section);
      return e.copyWith(parts: [...e.parts, part], report: report);
    });
  }

  Future<void> _deletePart(LabPart part) async {
    final ok = await confirmDelete(
      context,
      title: 'Versuchsteil löschen?',
      message: 'Schritte, Messwerte, Notizen und Antworten dieses Teils gehen verloren. '
          'Der zugehörige Berichtsabschnitt bleibt bestehen.',
    );
    if (!ok) return;
    await _update((e) => e.copyWith(parts: [for (final p in e.parts) if (p.id != part.id) p]));
  }

  Future<void> _addSection() async {
    final title = await _askText('Abschnitt hinzufügen', label: 'Überschrift', multiline: false);
    if (title == null) return;
    await _update((e) {
      final report = [...e.report];
      report.insert(report.length >= 2 ? report.length - 1 : report.length,
          LabReportSection(id: const Uuid().v4(), title: title));
      return e.copyWith(report: report);
    });
  }

  Future<void> _deleteSection(LabReportSection s) async {
    final ok = await confirmDelete(
      context,
      title: 'Abschnitt löschen?',
      message: '„${s.title}“ samt deinem Text wird entfernt.',
    );
    if (!ok) return;
    await _update((e) => e.copyWith(report: [for (final x in e.report) if (x.id != s.id) x]));
  }

  Future<void> _editDetails() async {
    final e = _e;
    if (e == null) return;
    final title = TextEditingController(text: e.title);
    var labDate = e.labDate;
    var reportDue = e.reportDue;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          Future<void> pick(bool forLab) async {
            final d = await showDatePicker(
              context: ctx,
              initialDate: (forLab ? labDate : reportDue) ?? labDate ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 730)),
            );
            if (d != null) setInner(() => forLab ? labDate = d : reportDue = d);
          }

          Widget row(String label, DateTime? value, bool forLab) => Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => pick(forLab),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('$label: ${value == null ? 'offen' : _date.format(value)}'),
                      ),
                    ),
                  ),
                  if (value != null)
                    IconButton(
                      tooltip: 'Datum entfernen',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setInner(() => forLab ? labDate = null : reportDue = null),
                    ),
                ],
              );

          return AlertDialog(
            title: const Text('Versuch bearbeiten'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: title, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 8),
                  row('Labortermin', labDate, true),
                  row('Bericht bis', reportDue, false),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Speichern')),
            ],
          );
        },
      ),
    );
    final newTitle = title.text.trim();
    title.dispose();
    if (ok != true) return;
    await _update((cur) => cur.copyWith(
          title: newTitle.isEmpty ? cur.title : newTitle,
          labDate: labDate,
          clearLabDate: labDate == null,
          reportDue: reportDue,
          clearReportDue: reportDue == null,
        ));
  }

  Future<void> _delete() async {
    final e = _e;
    if (e == null) return;
    final ok = await confirmDelete(
      context,
      title: 'Versuch löschen?',
      message: '„${e.title}“ mit allen Antworten, Messwerten und Berichtstexten wird gelöscht. '
          'Die hochgeladenen Unterlagen bleiben im Fach.',
    );
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    await _repo.delete(e.id);
    navigator.pop();
  }

  // -- Export -------------------------------------------------------------------

  Future<void> _export({required bool report}) async {
    final e = _e;
    if (e == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('export-pdf'),
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Als PDF speichern'),
              subtitle: const Text('zum Ausdrucken oder Abgeben'),
              onTap: () => Navigator.of(ctx).pop('pdf'),
            ),
            ListTile(
              key: const ValueKey('export-txt'),
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Als Text speichern'),
              onTap: () => Navigator.of(ctx).pop('txt'),
            ),
            ListTile(
              key: const ValueKey('export-copy'),
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Text kopieren'),
              subtitle: const Text('zum Einfügen in Word oder eine Mail'),
              onTap: () => Navigator.of(ctx).pop('copy'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final text = report
        ? LabExportService.reportText(e, moduleName: widget.moduleName)
        : LabExportService.preparationText(e, moduleName: widget.moduleName);
    final kind = report ? 'Bericht' : 'Vorbereitung';
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _snack('Text kopiert.');
      return;
    }
    final bytes = choice == 'pdf'
        ? (report
            ? LabExportService.reportPdf(e, moduleName: widget.moduleName)
            : LabExportService.preparationPdf(e, moduleName: widget.moduleName))
        : Uint8List.fromList(utf8.encode(text));
    final name = LabExportService.fileName(e.title, kind, choice);
    final mime = choice == 'pdf' ? 'application/pdf' : 'text/plain';
    try {
      final hook = LabExperimentScreen.saveFileHook;
      if (hook != null) {
        await hook(name, bytes, mime);
        return;
      }
      final saved = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime);
      if (saved != null && mounted) _snack('$kind gespeichert.');
    } catch (err) {
      if (mounted) _snack('Export fehlgeschlagen: $err');
    }
  }

  // -- Lernen -------------------------------------------------------------------

  /// Deine bereits als "passt" gegengelesenen Antworten als Karteikarten (Frage
  /// vorn, deine Antwort hinten) – schon vorhandene Karten werden übersprungen.
  Future<void> _answersToCards() async {
    final e = _e;
    if (e == null) return;
    final repo = context.read<FlashcardRepository>();
    final existing = {for (final f in repo.forModule(e.moduleId)) f.front.trim()};
    final rows = <({String front, String back})>[
      for (final q in [...e.prep, ...e.evaluationQuestions])
        if (q.answered && q.feedback?.verdict == 'gut' && !existing.contains(q.text.trim()))
          (front: q.text.trim(), back: q.answer.trim()),
    ];
    if (rows.isEmpty) {
      _snack('Keine neuen Antworten mit „Passt“ – lass Antworten erst gegenlesen.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${rows.length} Karten anlegen?'),
        content: const Text('Jede Aufgabe wird zur Karte, deine eigene Antwort ist die Rückseite. '
            'Die Karten kommen wie andere neue Karten nach und nach im Daily Quiz dran.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Anlegen')),
        ],
      ),
    );
    if (ok != true) return;
    await repo.saveAll(CardCsvService.toFlashcards(rows, e.moduleId));
    if (mounted) _snack('${rows.length} Karten angelegt.');
  }

  // -- Aufbau -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = context.watch<LabExperimentRepository>().byId(widget.experimentId);
    // Neu laden, sobald die Unterlagen des Fachs da sind (Reiter Lernen).
    context.watch<MaterialRepository>();
    if (e == null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(),
        body: const Center(child: Text('Versuch nicht gefunden.')),
      );
    }
    final now = DateTime.now();
    final initialTab = switch (e.phase(now)) {
      LabPhase.preparation => 0,
      LabPhase.labDay => 1,
      _ => 2,
    };
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(widget.moduleName, style: TextStyle(fontSize: 12, color: c.inkMuted, fontWeight: FontWeight.w400)),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Weitere Aktionen',
              onSelected: (v) => switch (v) {
                'details' => _editDetails(),
                'done' => _update((cur) => cur.copyWith(finished: !cur.finished)),
                _ => _delete(),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'details', child: Text('Name und Termine ändern')),
                PopupMenuItem(value: 'done', child: Text(e.finished ? 'Wieder öffnen' : 'Bericht als abgegeben markieren')),
                const PopupMenuItem(value: 'delete', child: Text('Versuch löschen')),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Vorbereitung'), Tab(text: 'Durchführung'), Tab(text: 'Bericht'), Tab(text: 'Lernen')],
          ),
        ),
        body: TabBarView(
          children: [
            _prepTab(e, now),
            _labTab(e, now),
            _reportTab(e, now),
            _learnTab(e),
          ],
        ),
      ),
    );
  }

  Widget _nextStepCard(LabExperiment e, DateTime now) {
    final c = context.colors;
    final days = e.daysUntilLab(now);
    final due = e.daysUntilReport(now);
    final (IconData icon, String text, bool warn) = switch (e.phase(now)) {
      LabPhase.done => (Icons.check_circle_outline, 'Bericht abgegeben. Im Reiter „Lernen“ kannst du den Stoff für die Klausur festigen.', false),
      LabPhase.preparation => e.prepTotal == 0
          ? (Icons.edit_note_outlined, 'Noch keine Vorbereitungsaufgaben – füge welche hinzu oder lege den Versuch mit den Unterlagen neu an.', false)
          : e.prepComplete
              ? (Icons.check_circle_outline, 'Vorbereitung beantwortet${days == null ? '' : ' – Versuch ${labDayText(days)}'}. Lass die Antworten gegenlesen und exportiere sie.', false)
              : (
                  Icons.pending_actions_outlined,
                  '${e.prepTotal - e.prepAnswered} von ${e.prepTotal} Vorbereitungsaufgaben offen${days == null ? '' : ' – Versuch ${labDayText(days)}'}.',
                  e.preparationOverdue(now, withinDays: 3),
                ),
      LabPhase.labDay => (Icons.science_outlined, 'Heute ist der Versuch: Schritte abhaken, Messwerte eintragen, Auffälligkeiten notieren.', false),
      LabPhase.report => (
          Icons.description_outlined,
          'Versuch durchgeführt – Bericht: ${e.reportWritten} von ${e.reportTotal} Abschnitten geschrieben'
              '${due == null ? '' : ', Abgabe ${labDayText(due)}'}.',
          due != null && due <= 2 && e.reportWritten < e.reportTotal,
        ),
    };
    return LabCard(
      tint: warn ? c.warnSoft : c.accentSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: warn ? c.warn : c.accentOnSoft),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink))),
        ],
      ),
    );
  }

  // -- Reiter: Vorbereitung -------------------------------------------------------

  Widget _prepTab(LabExperiment e, DateTime now) {
    final c = context.colors;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        _nextStepCard(e, now),
        if (e.labDate != null || e.reportDue != null) ...[
          const SizedBox(height: 8),
          Text(
            [
              if (e.labDate != null) 'Versuch am ${_date.format(e.labDate!)}',
              if (e.reportDue != null) 'Bericht bis ${_date.format(e.reportDue!)}',
            ].join(' · '),
            style: TextStyle(fontSize: 12.5, color: c.inkMuted),
          ),
        ],
        const SizedBox(height: 12),
        LabCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabProgressLine(
                done: e.prepAnswered,
                total: e.prepTotal,
                label: '${e.prepAnswered} von ${e.prepTotal} Aufgaben beantwortet',
              ),
              const SizedBox(height: 8),
              Text(
                'Schreib die Antworten in eigenen Worten. Die KI liest sie gegen und sagt dir, was fehlt – '
                'eine Musterlösung bekommst du bewusst nicht.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('review-all'),
                    onPressed: hasKey && _batchProgress == null && e.prepAnswered > 0 ? _reviewOpenPrep : null,
                    icon: _batchProgress == null
                        ? const Icon(Icons.rate_review_outlined, size: 18)
                        : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    label: Text(_batchProgress ?? 'Alle offenen gegenlesen'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('export-prep'),
                    onPressed: e.prepTotal == 0 ? null : () => _export(report: false),
                    icon: const Icon(Icons.ios_share_outlined, size: 18),
                    label: const Text('Exportieren / Drucken'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final q in e.prep) ...[
          _questionCard(q, e),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _addPrepQuestion,
          icon: const Icon(Icons.add),
          label: const Text('Aufgabe hinzufügen'),
        ),
      ],
    );
  }

  Widget _questionCard(
    LabQuestion q,
    LabExperiment e, {
    String hint = 'Deine Antwort in eigenen Worten …',
    LabPart? calcPart,
  }) {
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    return LabQuestionCard(
      question: q,
      canReview: hasKey,
      reviewing: _busy.contains(q.id),
      hint: hint,
      references: _refs[q.id] ?? const [],
      onOpenReference: _openReference,
      onAnswer: (text) => _update((cur) => cur.updateQuestion(q.id, (old) => old.copyWith(answer: text))),
      onReview: () => _reviewQuestion(q.id),
      onLookup: () => _lookup(q.text, answer: q.answer),
      onEdit: () => _editQuestion(q),
      onDelete: () => _deleteQuestion(q),
      onCalc: calcPart == null ? null : () => _openCalc(e, calcPart, question: q),
    );
  }

  // -- Rechnen ----------------------------------------------------------------------

  /// "Rechnen mit KI" für einen Versuchsteil (bzw. eine seiner Aufgaben): die
  /// Messwerte des Teils stehen schon im Werte-Feld, der Rechenweg lässt sich in
  /// die Notizen des Teils übernehmen.
  Future<void> _openCalc(LabExperiment e, LabPart part, {LabQuestion? question}) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CalcScreen(
        moduleName: widget.moduleName,
        experiment: e,
        part: part,
        initialTask: question == null ? '' : '${question.number} ${question.text}'.trim(),
        initialValues: LabContextService.measurementsOf(part),
        onSaveNote: (text) => _appendToNotes(part.id, text),
      ),
    ));
  }

  Future<void> _appendToNotes(String partId, String text) async {
    LabAnswerField.flushPending();
    await _update((cur) => cur.updatePart(partId, (p) {
          final old = p.notes.trim();
          return p.copyWith(notes: old.isEmpty ? text : '$old\n\n$text');
        }));
    if (mounted) setState(() => _notesRevision[partId] = (_notesRevision[partId] ?? 0) + 1);
  }

  // -- Reiter: Durchführung ---------------------------------------------------------

  Widget _labTab(LabExperiment e, DateTime now) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        _nextStepCard(e, now),
        const SizedBox(height: 12),
        LabCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabProgressLine(
                done: e.stepsDone,
                total: e.stepsTotal,
                label: 'Schritte: ${e.stepsDone} von ${e.stepsTotal} erledigt',
              ),
              const SizedBox(height: 10),
              LabProgressLine(
                done: e.cellsFilled,
                total: e.cellsTotal,
                label: 'Messwerte: ${e.cellsFilled} von ${e.cellsTotal} Feldern eingetragen',
              ),
              if (e.hints.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Hinweise aus der Anleitung',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
                for (final h in e.hints)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('•  $h', style: const TextStyle(fontSize: 13, height: 1.35)),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (e.parts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Noch keine Versuchsteile.', style: TextStyle(color: c.inkMuted)),
          ),
        for (var i = 0; i < e.parts.length; i++) ...[
          _partCard(e, e.parts[i], i),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _addPart,
          icon: const Icon(Icons.add),
          label: const Text('Versuchsteil hinzufügen'),
        ),
      ],
    );
  }

  Widget _partCard(LabExperiment e, LabPart part, int index) {
    final c = context.colors;
    return LabCard(
      key: ValueKey('lab-part-${part.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${index + 1}  ${part.title}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              PopupMenuButton<String>(
                tooltip: 'Versuchsteil',
                icon: Icon(Icons.more_vert, size: 18, color: c.inkMuted),
                onSelected: (v) => switch (v) {
                  'step' => _addStep(part),
                  'question' => _addEvaluationQuestion(part),
                  _ => _deletePart(part),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'step', child: Text('Schritt hinzufügen')),
                  PopupMenuItem(value: 'question', child: Text('Auswertungsfrage hinzufügen')),
                  PopupMenuItem(value: 'delete', child: Text('Versuchsteil löschen')),
                ],
              ),
            ],
          ),
          for (final g in part.goals)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(g, style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.35)),
            ),
          if (part.steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var s = 0; s < part.steps.length; s++)
              CheckboxListTile(
                key: ValueKey('step-${part.id}-$s'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: part.steps[s].done,
                title: Text(part.steps[s].text,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      decoration: part.steps[s].done ? TextDecoration.lineThrough : null,
                      color: part.steps[s].done ? c.inkMuted : c.ink,
                    )),
                onChanged: (v) => _update((cur) => cur.updatePart(part.id, (p) => p.copyWith(steps: [
                      for (var k = 0; k < p.steps.length; k++)
                        k == s ? p.steps[k].copyWith(done: v ?? false) : p.steps[k],
                    ]))),
              ),
          ],
          for (var t = 0; t < part.tables.length; t++) ...[
            const SizedBox(height: 12),
            LabTableView(
              tableKey: '${part.id}-$t',
              table: part.tables[t],
              onCell: (row, col, value) => _update((cur) => cur.updatePart(part.id, (p) => p.copyWith(tables: [
                    for (var k = 0; k < p.tables.length; k++)
                      k == t ? p.tables[k].withCell(row, col, value) : p.tables[k],
                  ]))),
            ),
          ],
          const SizedBox(height: 12),
          LabAnswerField(
            key: ValueKey(_notesRevision[part.id] == null ? 'notes-${part.id}' : 'notes-${part.id}-${_notesRevision[part.id]}'),
            initial: part.notes,
            minLines: 2,
            hint: 'Notizen: Einstellungen, Auffälligkeiten, Abweichungen …',
            onSave: (text) => _update((cur) => cur.updatePart(part.id, (p) => p.copyWith(notes: text))),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: ValueKey('calc-${part.id}'),
              onPressed: () => _openCalc(e, part),
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text('Rechnen mit KI (Werte oder Bilder)'),
            ),
          ),
          if (part.questions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Auswertung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted)),
            const SizedBox(height: 8),
            for (final q in part.questions) ...[
              _questionCard(q, e, hint: 'Deine Beobachtung / Antwort …', calcPart: part),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  // -- Reiter: Bericht ------------------------------------------------------------------

  Widget _reportTab(LabExperiment e, DateTime now) {
    final c = context.colors;
    final due = e.daysUntilReport(now);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        _nextStepCard(e, now),
        const SizedBox(height: 12),
        LabCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabProgressLine(
                done: e.reportWritten,
                total: e.reportTotal,
                label: '${e.reportWritten} von ${e.reportTotal} Abschnitten geschrieben'
                    '${e.reportDue == null ? '' : ' · Abgabe ${_date.format(e.reportDue!)}${due == null ? '' : ' (${labDayText(due)})'}'}',
              ),
              const SizedBox(height: 8),
              Text(
                'Du schreibst den Bericht selbst – die KI liest jeden Abschnitt gegen und prüft ihn an deinen '
                'Messwerten und dem Skript. Auf Wunsch gibt es zusätzlich einen groben Entwurf als Inspiration; '
                'er steht getrennt von deinem Text und wird nur übernommen, wenn du es willst.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('export-report'),
                    onPressed: e.reportWritten == 0 ? null : () => _export(report: true),
                    icon: const Icon(Icons.ios_share_outlined, size: 18),
                    label: const Text('Bericht exportieren'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('draft-open'),
                    onPressed: () => _openDraft(),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Entwurf zur Inspiration'),
                  ),
                  FilterChip(
                    key: const ValueKey('report-finished'),
                    label: const Text('Abgegeben'),
                    selected: e.finished,
                    onSelected: (v) => _update((cur) => cur.copyWith(finished: v)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final s in e.report) ...[
          _sectionCard(e, s),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _addSection,
          icon: const Icon(Icons.add),
          label: const Text('Abschnitt hinzufügen'),
        ),
      ],
    );
  }

  Widget _sectionCard(LabExperiment e, LabReportSection s) {
    final c = context.colors;
    final hasKey = context.watch<SettingsRepository>().settings.hasApiKey;
    final part = e.partById(s.partId);
    final measurements = LabContextService.measurementsOf(part);
    final reviewing = _busy.contains(s.id);
    return LabCard(
      key: ValueKey('lab-section-${s.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
              if (s.written) Icon(Icons.check_circle, size: 18, color: c.good),
              IconButton(
                tooltip: 'Abschnitt löschen',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, size: 18, color: c.inkMuted),
                onPressed: () => _deleteSection(s),
              ),
            ],
          ),
          if (s.hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: MathText(s.hint, style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4)),
            ),
          if (measurements.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                dense: true,
                title: const Text('Messwerte dieses Teils', style: TextStyle(fontSize: 13)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(measurements,
                        style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace', height: 1.4)),
                  ),
                ],
              ),
            ),
          LabAnswerField(
            key: ValueKey(_sectionRevision[s.id] == null ? 'section-field-${s.id}' : 'section-field-${s.id}-${_sectionRevision[s.id]}'),
            initial: s.text,
            minLines: 6,
            maxLines: 24,
            hint: 'Dein Text …',
            onSave: (text) => _update((cur) => cur.updateSection(s.id, (old) => old.copyWith(text: text))),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                onPressed: hasKey && !reviewing && s.text.trim().isNotEmpty ? () => _reviewSection(s.id) : null,
                icon: reviewing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.rate_review_outlined, size: 18),
                label: Text(s.feedback == null ? 'Gegenlesen lassen' : 'Erneut gegenlesen'),
              ),
              TextButton.icon(
                onPressed: () => _lookup('${s.title} ${s.hint}', answer: s.text),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Im Skript nachschlagen'),
              ),
              if (s.draft.trim().isEmpty)
                TextButton.icon(
                  key: ValueKey('draft-section-${s.id}'),
                  onPressed: () => _openDraft(sectionId: s.id),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Entwurf zur Inspiration'),
                ),
            ],
          ),
          if (s.draft.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _draftPanel(s),
          ],
          if (s.feedback != null) ...[
            const SizedBox(height: 8),
            LabFeedbackView(
              feedback: s.feedback!,
              currentText: s.text,
              references: _refs[s.id] ?? const [],
              onOpenReference: _openReference,
            ),
          ],
        ],
      ),
    );
  }

  // -- Entwurf ------------------------------------------------------------------------

  Future<void> _openDraft({String? sectionId}) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LabDraftScreen(experimentId: widget.experimentId, moduleName: widget.moduleName, onlySectionId: sectionId),
    ));
  }

  /// Der Entwurf des Abschnitts als eigenes Feld unter dem eigenen Text: markier-
  /// und kopierbar, mit "In meinen Text übernehmen" und "Verwerfen".
  Widget _draftPanel(LabReportSection s) {
    final c = context.colors;
    return Container(
      key: ValueKey('draft-panel-${s.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.accentSoft.withValues(alpha: 0.45),
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 16, color: c.accentOnSoft),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Entwurf – KI, nur zur Inspiration',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
              ),
              IconButton(
                key: ValueKey('draft-discard-${s.id}'),
                tooltip: 'Entwurf verwerfen',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 18, color: c.inkMuted),
                onPressed: () => _update((cur) => cur.updateSection(s.id, (old) => old.copyWith(clearDraft: true))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectionArea(child: MathText(s.draft.trim(), style: const TextStyle(fontSize: 14, height: 1.45))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                key: ValueKey('draft-adopt-${s.id}'),
                onPressed: () => _adoptDraft(s),
                icon: const Icon(Icons.playlist_add_outlined, size: 18),
                label: const Text('In meinen Text übernehmen'),
              ),
              TextButton.icon(
                key: ValueKey('draft-copy-${s.id}'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: s.draft.trim()));
                  if (mounted) _snack('Entwurf kopiert.');
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Kopieren'),
              ),
              TextButton.icon(
                onPressed: () => _openDraft(sectionId: s.id),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Neu erzeugen'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Hängt den Entwurf an den eigenen Text (oder setzt ihn, wenn der leer ist)
  /// und räumt den Entwurf weg – der Text gehört jetzt dir und wird von Hand
  /// weiterbearbeitet.
  Future<void> _adoptDraft(LabReportSection s) async {
    // Erst gerade Getipptes speichern – sonst schriebe das alte Feld beim
    // Abbauen seinen Stand über den übernommenen Text.
    LabAnswerField.flushPending();
    await _update((cur) => cur.updateSection(s.id, (old) {
          final own = old.text.trim();
          final draft = old.draft.trim();
          return old.copyWith(text: own.isEmpty ? draft : '$own\n\n$draft', clearDraft: true, clearFeedback: true);
        }));
    if (mounted) setState(() => _sectionRevision[s.id] = (_sectionRevision[s.id] ?? 0) + 1);
  }

  // -- Reiter: Lernen -------------------------------------------------------------------

  Widget _learnTab(LabExperiment e) {
    final c = context.colors;
    final sources = LabContextService.sourcesOf(e, _materials(e));
    final goodAnswers = [
      for (final q in [...e.prep, ...e.evaluationQuestions])
        if (q.answered && q.feedback?.verdict == 'gut') q,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Text(
          'Was du im Labor gemacht hast, kommt in der Klausur wieder dran. Mach daraus Lernkarten – '
          'sie laufen dann wie alle anderen im Daily Quiz.',
          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 14),
        _LearnAction(
          key: const ValueKey('learn-cards-from-script'),
          icon: Icons.auto_awesome_outlined,
          title: 'Karten aus dem Skript erstellen',
          subtitle: sources.isEmpty
              ? 'Keine Unterlagen zum Versuch hinterlegt.'
              : 'Die KI macht aus Theorie-Skript und Anleitung Konzepte und Fragen – du siehst sie vorher.',
          onTap: sources.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReviewScreen(
                      moduleId: e.moduleId,
                      initialSlideMaterialIds: [for (final m in sources) m.id],
                    ),
                  )),
        ),
        const SizedBox(height: 10),
        _LearnAction(
          key: const ValueKey('learn-cards-from-answers'),
          icon: Icons.style_outlined,
          title: 'Meine Antworten als Karten',
          subtitle: goodAnswers.isEmpty
              ? 'Sobald eine deiner Antworten beim Gegenlesen „Passt“ bekommt, kannst du sie hier übernehmen.'
              : '${goodAnswers.length} gegengelesene Antworten: Aufgabe vorn, deine Antwort hinten.',
          onTap: goodAnswers.isEmpty ? null : _answersToCards,
        ),
        const SizedBox(height: 10),
        _LearnAction(
          icon: Icons.forum_outlined,
          title: 'Fragen zum Skript stellen',
          subtitle: 'Nachfragen zu allem, was im Fach hochgeladen ist.',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ModuleChatScreen(moduleId: e.moduleId, moduleName: widget.moduleName),
          )),
        ),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('UNTERLAGEN', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
          const SizedBox(height: 6),
          for (final m in sources)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(m.fileName),
              subtitle: Text(e.theoryMaterialIds.contains(m.id) ? 'Theorie-Skript' : 'Versuchsanleitung'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => openMaterialAt(context, m),
            ),
        ],
      ],
    );
  }
}

class _LearnAction extends StatelessWidget {
  const _LearnAction({super.key, required this.icon, required this.title, required this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(11)),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: c.inkMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35)),
                    ],
                  ),
                ),
                if (enabled) Icon(Icons.chevron_right_rounded, size: 18, color: c.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
