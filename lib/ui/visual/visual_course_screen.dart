import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/material_item.dart';
import '../../models/visual_course.dart';
import '../../models/visual_lesson.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/visual_course_repository.dart';
import '../../repositories/visual_lesson_repository.dart';
import '../../services/ai_service.dart';
import '../../services/background_transport.dart';
import '../../services/material_file_store.dart';
import '../../services/visual_course_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';
import 'visual_lesson_screen.dart';

/// KI für Lernpfade (Text-Modell) – null ohne Key.
AiService? _courseAi(BuildContext context) {
  final settings = context.read<SettingsRepository?>()?.settings;
  if (settings == null || !settings.hasApiKey) return null;
  return VisualCourseCreateScreen.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
      AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
}

String _detailLabel(String d) => switch (d) {
  'kurz' => 'Kurz',
  'ausführlich' => 'Ausführlich',
  _ => 'Normal',
};

/// Lernpfad erstellen: Vorlesungen (PDFs des Fachs oder hochgeladen) wählen,
/// die KI sammelt die Themen, ordnet sie mit Übergängen – Vorschau, dann
/// speichern.
class VisualCourseCreateScreen extends StatefulWidget {
  const VisualCourseCreateScreen({super.key, required this.moduleId});

  final String moduleId;

  /// Test-Hooks: KI und PDF-Auswahl.
  static AiService? Function(String apiKey, String model)? aiFactory;
  static Future<({String name, Uint8List bytes})?> Function()? pickPdfHook;

  @override
  State<VisualCourseCreateScreen> createState() => _VisualCourseCreateScreenState();
}

class _VisualCourseCreateScreenState extends State<VisualCourseCreateScreen> {
  final _wish = TextEditingController();
  final Set<String> _chosen = {};
  final List<({String name, Uint8List bytes})> _uploads = [];
  String _detail = 'normal';
  VisualStyle _style = VisualStyle.explain;
  bool _busy = false;
  String _progress = '';
  String? _error;
  VisualCourse? _plan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<MaterialRepository?>()?.loadForModule(widget.moduleId);
      if (mounted) setState(() => _chosen.addAll(_pdfs.map((m) => m.id)));
    });
  }

  @override
  void dispose() {
    _wish.dispose();
    super.dispose();
  }

  List<MaterialItem> get _pdfs => [
    for (final m in context.read<MaterialRepository?>()?.forModule(widget.moduleId) ?? const <MaterialItem>[])
      if (m.hasViewablePdf && m.fileName.toLowerCase().endsWith('.pdf')) m,
  ];

  Future<void> _upload() async {
    ({String name, Uint8List bytes})? picked;
    final hook = VisualCourseCreateScreen.pickPdfHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      if (files.isEmpty) return;
      picked = (name: files.first.name, bytes: await files.first.readAsBytes());
    }
    if (picked != null && mounted) setState(() => _uploads.add(picked!));
  }

  Future<void> _planCourse() async {
    final ai = _courseAi(context);
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final chosen = [
      for (final m in _pdfs)
        if (_chosen.contains(m.id)) m,
    ];
    if (chosen.isEmpty && _uploads.isEmpty) {
      setState(() => _error = 'Wähle mindestens eine Vorlesung aus oder lade eine PDF hoch.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _plan = null;
      _progress = 'Vorlesungen werden gelesen …';
    });
    // Absturz-Notiz: Liest Android große PDFs nicht (Speicher), meldet der
    // nächste Start, wobei es passiert ist.
    final reading = await AiCrashGuard.mark(
      label: 'Lernpfad planen – ${chosen.length + _uploads.length} PDFs lesen',
      bytes: 0,
      via: 'App',
    );
    try {
      final pdfs = <({String name, Uint8List bytes})>[];
      for (final m in chosen) {
        final bytes = await MaterialFileStore.load(filePath: m.filePath, fileBytesBase64: m.fileBytesBase64);
        if (bytes != null) pdfs.add((name: m.fileName, bytes: bytes));
      }
      pdfs.addAll(_uploads);
      if (pdfs.isEmpty) throw AiServiceException('Die PDFs sind auf diesem Gerät nicht verfügbar.');
      final service = VisualCourseService(ai);
      final topics = await service.collectTopics(
        pdfs,
        wish: _wish.text.trim(),
        onProgress: (done, total) {
          if (mounted && done < total) {
            setState(() => _progress = 'Themen werden gesucht (Teil ${done + 1} von $total) …');
          }
        },
      );
      await AiCrashGuard.clear(reading);
      if (topics.isEmpty) throw AiServiceException('In den PDFs wurde kein lesbarer Text gefunden.');
      if (!mounted) return;
      setState(() => _progress = 'Die KI ordnet ${topics.length} Themen zu einem Lernpfad …');
      final plan = await service.plan(
        topics,
        moduleId: widget.moduleId,
        wish: _wish.text.trim(),
        detail: _detail,
        style: _style,
      );
      if (mounted) setState(() => _plan = plan);
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Das hat nicht geklappt: $e');
    } finally {
      await AiCrashGuard.clear(reading);
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  void _removeUnit(int i) {
    final plan = _plan!;
    final removed = plan.units[i].id;
    setState(() {
      _plan = plan.copyWith(
        units: [
          for (final (k, u) in plan.units.indexed)
            if (k != i)
              CourseUnit(
                id: u.id,
                title: u.title,
                summary: u.summary,
                how: u.how,
                bridge: u.bridge,
                needs: [
                  for (final n in u.needs)
                    if (n != removed) n,
                ],
                source: u.source,
                material: u.material,
              ),
        ],
      );
    });
  }

  Future<void> _save() async {
    final plan = _plan;
    if (plan == null || plan.units.isEmpty) return;
    final navigator = Navigator.of(context);
    await context.read<VisualCourseRepository>().save(plan);
    if (!mounted) return;
    // Wer den Bildschirm geöffnet hat, öffnet den Pfad (und lädt danach neu).
    navigator.pop(plan);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pdfs = _pdfs;
    final plan = _plan;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Lernpfad erstellen')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Aus mehreren Vorlesungen (oder einer langen) wird ein Lernpfad fürs ganze Semester: Themen in '
                'sinnvoller Reihenfolge, jede Lektion knüpft an das an, was du vorher gelernt hast – ausführlich '
                'und als Kurzfassung zum Wiedereinsteigen.',
                style: TextStyle(color: c.inkMuted, height: 1.4),
              ),
              const SizedBox(height: 14),
              Text('Vorlesungen', style: Theme.of(context).textTheme.titleMedium),
              if (pdfs.isEmpty && _uploads.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Noch keine PDFs im Fach – lade unten welche hoch.', style: TextStyle(color: c.inkMuted)),
                ),
              for (final (i, m) in pdfs.indexed)
                CheckboxListTile(
                  key: ValueKey('course-pdf-$i'),
                  contentPadding: EdgeInsets.zero,
                  value: _chosen.contains(m.id),
                  onChanged: _busy ? null : (v) => setState(() => v == true ? _chosen.add(m.id) : _chosen.remove(m.id)),
                  title: Text(m.fileName),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              for (final (i, u) in _uploads.indexed)
                ListTile(
                  key: ValueKey('course-upload-$i'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(u.name),
                  trailing: IconButton(
                    tooltip: 'Entfernen',
                    onPressed: _busy ? null : () => setState(() => _uploads.removeAt(i)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('course-upload'),
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('PDF hochladen'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('course-wish'),
                controller: _wish,
                enabled: !_busy,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Schwerpunkt (optional)',
                  hintText: 'z.B. „für die Klausur: Schwerpunkt Gefüge und Wärmebehandlung“',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                key: const ValueKey('course-detail'),
                segments: const [
                  ButtonSegment(value: 'kurz', label: Text('Kurz')),
                  ButtonSegment(value: 'normal', label: Text('Normal')),
                  ButtonSegment(value: 'ausführlich', label: Text('Ausführlich')),
                ],
                selected: {_detail},
                showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (s) => setState(() => _detail = s.first),
              ),
              const SizedBox(height: 8),
              SegmentedButton<VisualStyle>(
                key: const ValueKey('course-style'),
                segments: const [
                  ButtonSegment(value: VisualStyle.explain, label: Text('Erklären')),
                  ButtonSegment(value: VisualStyle.socratic, label: Text('Sokratisch')),
                ],
                selected: {_style},
                showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (s) => setState(() => _style = s.first),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('course-plan'),
                onPressed: _busy ? null : _planCourse,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.route),
                label: Text(_busy ? _progress : 'Lernpfad planen', maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const ValueKey('course-error'),
                  style: TextStyle(color: c.danger),
                ),
              ],
              if (plan != null) ...[
                const SizedBox(height: 22),
                Text(
                  plan.title,
                  key: const ValueKey('course-plan-title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (plan.intro.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  MathText(plan.intro, style: TextStyle(color: c.inkMuted, height: 1.4)),
                ],
                const SizedBox(height: 10),
                for (final (i, u) in plan.units.indexed)
                  Card(
                    key: ValueKey('course-preview-$i'),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                      title: Text(u.title),
                      subtitle: Text(
                        [
                          if (u.source.isNotEmpty) u.source,
                          if (u.needs.isNotEmpty)
                            'baut auf: ${[for (final n in u.needs) plan.units.indexWhere((x) => x.id == n) + 1].join(', ')}',
                          if (u.bridge.isNotEmpty) u.bridge,
                        ].join('\n'),
                      ),
                      isThreeLine: u.bridge.isNotEmpty,
                      trailing: IconButton(
                        key: ValueKey('course-unit-remove-$i'),
                        tooltip: 'Thema weglassen',
                        onPressed: () => _removeUnit(i),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('course-save'),
                  onPressed: plan.units.isEmpty ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text('Lernpfad mit ${plan.units.length} Themen speichern'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Die Lektionen entstehen erst, wenn du ein Thema öffnest – oder mit „Alle vorbereiten“.',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Lernpfad: Fortschritt, „Weiter mit …“, je Thema ausführlich oder
/// Kurzfassung; Lektionen entstehen beim ersten Öffnen (mit Rückblick).
class VisualCourseScreen extends StatefulWidget {
  const VisualCourseScreen({super.key, required this.course});

  final VisualCourse course;

  @override
  State<VisualCourseScreen> createState() => _VisualCourseScreenState();
}

class _VisualCourseScreenState extends State<VisualCourseScreen> {
  late VisualCourse _course = widget.course;
  Map<String, VisualLesson> _lessons = {};
  int? _busyIndex;
  bool _preparing = false;
  bool _stop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final courses = context.read<VisualCourseRepository?>();
    final lessons = await context.read<VisualLessonRepository>().forModule(_course.moduleId);
    final stored = await courses?.byId(_course.id);
    if (!mounted) return;
    setState(() {
      _lessons = {for (final l in lessons) l.id: l};
      if (stored != null) _course = stored;
    });
  }

  Future<void> _saveCourse(VisualCourse course) async {
    setState(() => _course = course);
    await context.read<VisualCourseRepository>().save(course);
  }

  /// Lektion zu Thema [i] – vorhanden oder jetzt erzeugt.
  Future<VisualLesson?> _ensureLesson(int i) async {
    final unit = _course.units[i];
    final existing = unit.lessonId == null ? null : _lessons[unit.lessonId];
    if (existing != null) return existing;
    final ai = _courseAi(context);
    if (ai == null) {
      setState(() => _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).');
      return null;
    }
    final repo = context.read<VisualLessonRepository>();
    setState(() {
      _busyIndex = i;
      _error = null;
    });
    try {
      final lesson = await VisualCourseService(ai).lessonFor(_course, i, _lessons);
      await repo.save(lesson);
      if (!mounted) return lesson;
      _lessons = {..._lessons, lesson.id: lesson};
      await _saveCourse(_course.withUnit(i, _course.units[i].copyWith(lessonId: lesson.id)));
      return lesson;
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = '„${unit.title}“: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _error = '„${unit.title}“: $e');
    } finally {
      if (mounted) setState(() => _busyIndex = null);
    }
    return null;
  }

  Future<void> _open(int i, {bool short = false}) async {
    final lesson = await _ensureLesson(i);
    if (lesson == null || !mounted) return;
    final next = i + 1 < _course.units.length ? _course.units[i + 1].title : null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VisualLessonScreen(
          lesson: lesson,
          startShort: short,
          finishLabel: next == null ? 'Lernpfad abschließen' : 'Abschließen – weiter mit „$next“',
          onFinished: () => _setDone(i, true),
        ),
      ),
    );
  }

  Future<void> _setDone(int i, bool done) => _saveCourse(_course.withUnit(i, _course.units[i].copyWith(done: done)));

  Future<void> _prepareAll() async {
    setState(() {
      _preparing = true;
      _stop = false;
    });
    for (var i = 0; i < _course.units.length && !_stop && mounted; i++) {
      if (_course.units[i].lessonId != null && _lessons.containsKey(_course.units[i].lessonId)) continue;
      final lesson = await _ensureLesson(i);
      if (lesson == null) break;
    }
    if (mounted) setState(() => _preparing = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lernpfad löschen?'),
        content: Text('„${_course.title}“ mit allen erstellten Lektionen.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            key: const ValueKey('course-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await context.read<VisualCourseRepository>().delete(_course.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final course = _course;
    final next = course.nextIndex;
    final prepared = course.units.where((u) => u.lessonId != null && _lessons.containsKey(u.lessonId)).length;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('course-delete'),
            tooltip: 'Lernpfad löschen',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              if (course.intro.isNotEmpty) ...[
                MathText(course.intro, style: TextStyle(color: c.inkMuted, height: 1.45)),
                const SizedBox(height: 12),
              ],
              Text(
                '${course.doneCount} von ${course.units.length} Themen erledigt · $prepared vorbereitet · '
                '${_detailLabel(course.detail)}${course.style == VisualStyle.socratic ? ' · sokratisch' : ''}',
                key: const ValueKey('course-progress'),
                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: course.units.isEmpty ? 0 : course.doneCount / course.units.length,
                  minHeight: 6,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation(c.good),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('course-continue'),
                onPressed: _busyIndex != null ? null : () => _open(next ?? 0, short: next == null),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  next == null
                      ? 'Alles geschafft – Kurzfassungen wiederholen'
                      : '${next == 0 && course.doneCount == 0 ? 'Starten' : 'Weiter'} mit „${course.units[next].title}“',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: _preparing
                    ? TextButton.icon(
                        key: const ValueKey('course-stop'),
                        onPressed: () => setState(() => _stop = true),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(_stop ? 'Wird nach dem aktuellen Thema gestoppt …' : 'Vorbereiten stoppen'),
                      )
                    : TextButton.icon(
                        key: const ValueKey('course-prepare-all'),
                        onPressed: prepared == course.units.length || _busyIndex != null ? null : _prepareAll,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: Text('Alle vorbereiten (${course.units.length - prepared} offen)'),
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  key: const ValueKey('course-error'),
                  style: TextStyle(color: c.danger),
                ),
              ],
              const SizedBox(height: 10),
              for (final (i, u) in course.units.indexed) _unit(c, i, u, i == next),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unit(AppColors c, int i, CourseUnit u, bool isNext) {
    final lesson = u.lessonId == null ? null : _lessons[u.lessonId];
    final busy = _busyIndex == i;
    final needs = [
      for (final n in u.needs)
        if (_course.units.indexWhere((x) => x.id == n) case final k when k >= 0) k + 1,
    ];
    return Card(
      key: ValueKey('course-unit-$i'),
      margin: const EdgeInsets.only(bottom: 8),
      shape: isNext
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: c.accent, width: 1.5),
            )
          : null,
      child: InkWell(
        key: ValueKey('course-open-$i'),
        borderRadius: BorderRadius.circular(12),
        onTap: _busyIndex != null ? null : () => _open(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: ValueKey('course-done-$i'),
                customBorder: const CircleBorder(),
                onTap: () => _setDone(i, !u.done),
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: u.done ? c.good : c.surfaceAlt,
                  child: u.done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text('${i + 1}', style: TextStyle(fontSize: 12, color: c.ink)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (u.source.isNotEmpty) Text(u.source, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                    if (needs.isNotEmpty)
                      Text(
                        'baut auf ${needs.map((n) => 'Thema $n').join(', ')} auf',
                        style: TextStyle(fontSize: 12, color: c.accent),
                      ),
                    if (u.bridge.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(u.bridge, style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35)),
                      ),
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text('Lektion wird erstellt …', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (lesson?.shortVersion != null)
                TextButton(
                  key: ValueKey('course-short-$i'),
                  onPressed: _busyIndex != null ? null : () => _open(i, short: true),
                  child: const Text('Kurz'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
