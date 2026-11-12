import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../models/module.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lab_experiment_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/module_repository.dart';
import '../../services/continue_learning.dart';
import '../../services/database_service.dart';
import '../../services/mastery_service.dart';
import '../../services/module_export_service.dart';
import '../../services/task_folder_service.dart';
import '../../theme/app_colors.dart';
import '../modules/module_detail_screen.dart';
import '../modules/module_form_screen.dart';
import '../practice/practice_screen.dart';
import '../practice/study_sequence_screen.dart';
import '../stats/weakness_screen.dart';
import '../widgets/continue_learning_card.dart';
import '../lab/lab_widgets.dart';
import '../widgets/exam_countdown_badge.dart';
import '../widgets/mastery_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.isActive = true, this.onOpenDailyQuiz});

  /// Schnellzugriff „Daily Quiz“ (wechselt den Tab, siehe RootShell).
  final VoidCallback? onOpenDailyQuiz;

  /// Sichtbarer Tab (siehe RootShell) – beim Zurückwechseln wird die Ampel
  /// je Fach neu geladen, seither Gelerntes soll sofort sichtbar sein.
  final bool isActive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Ampel je Fach (siehe MasteryService.breakdown), null bis geladen.
  Map<String, Map<MasteryLevel, int>>? _ampelByModule;

  /// Anzahl Aufgaben im Aufgaben-Ordner je Fach (siehe TaskFolderService).
  Map<String, int> _taskCountByModule = const {};
  FlashcardRepository? _flashcards;

  /// Womit es weitergeht (Karte „Weiter lernen“) – null, solange nichts da ist.
  ContinueTarget? _continue;

  /// Karten haben sich geändert, während die Startseite verdeckt war – beim
  /// nächsten Sichtbarwerden neu laden statt nach jeder einzelnen Antwort.
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _flashcards = context.read<FlashcardRepository?>()?..addListener(_onCardsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAmpel());
  }

  void _onCardsChanged() {
    if (widget.isActive) {
      _loadAmpel();
    } else {
      _stale = true;
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && _stale) _loadAmpel();
  }

  @override
  void dispose() {
    _flashcards?.removeListener(_onCardsChanged);
    super.dispose();
  }

  Future<void> _loadAmpel() async {
    final repo = _flashcards;
    if (repo == null) return;
    _stale = false;
    final byModule = <String, List<Flashcard>>{};
    for (final card in await repo.loadAll()) {
      byModule.putIfAbsent(card.moduleId, () => []).add(card);
    }
    if (!mounted) return;
    final mastery = MasteryService();
    setState(() {
      _ampelByModule = {
        for (final entry in byModule.entries) entry.key: mastery.breakdown(entry.value),
      };
      _taskCountByModule = {
        for (final entry in byModule.entries) entry.key: TaskFolderService.tasksOf(entry.value).length,
      };
    });
    final target = await loadContinueTarget(
      modules: context.read<ModuleRepository>().modules,
      cardsByModule: byModule,
      units: context.read<LectureUnitRepository?>(),
      materials: context.read<MaterialRepository?>(),
    );
    if (mounted) setState(() => _continue = target);
  }

  /// „Weitermachen“: die angefangene Reihe bzw. Üben im Fach öffnen – danach
  /// neu bestimmen, womit es weitergeht.
  Future<void> _continueLearning(ContinueTarget target) async {
    final source = target.source;
    if (source != null) {
      await openStudySequence(context, target.moduleId, source);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PracticeScreen(moduleId: target.moduleId, moduleName: target.moduleName),
        ),
      );
    }
    if (mounted) await _loadAmpel();
  }

  /// Importiert ein zuvor über ModuleDetailScreen exportiertes Fach (siehe
  /// ModuleExportService) aus einer JSON-Datei – vergibt dabei frische IDs
  /// für alles, also unabhängig davon ob es sich um ein neues Gerät oder eine
  /// zweite Kopie auf demselben Gerät handelt. Fragt, ob der Lernstand
  /// mitkommen soll (eigenes Backup) oder nicht (weitergegebenes Fach), und
  /// schreibt alles in EINER Transaktion.
  Future<void> _importModule(BuildContext context) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (file == null || !context.mounted) return;
    final moduleRepo = context.read<ModuleRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final Uint8List bytes = await file.readAsBytes();
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map) {
        throw const FormatException('Keine gültige Fach-Export-Datei.');
      }
      var imported = ModuleExportService.parse(Map<String, dynamic>.from(json));
      if (!context.mounted) return;
      final keepProgress = imported.flashcards.any((f) => f.reps > 0)
          ? await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Lernstand übernehmen?'),
                content: const Text('Die Datei enthält auch den Lernstand (Ampel, Fälligkeiten). '
                    'Für ein eigenes Backup übernehmen – für ein weitergegebenes Fach lieber neu beginnen.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Neu beginnen')),
                  FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Übernehmen')),
                ],
              ),
            )
          : true;
      if (keepProgress == null) return;
      if (!keepProgress) imported = imported.withoutLearningState();

      final db = await DatabaseService.instance.database;
      await db.transaction((txn) => ModuleExportService.saveImported(txn, imported));
      await moduleRepo.load();
      if (!context.mounted) return;
      await context.read<LabExperimentRepository?>()?.loadAll();
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ModuleDetailScreen(moduleId: imported.module.id)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = context.watch<ModuleRepository>().modules;
    final labs = context.watch<LabExperimentRepository?>();
    final c = context.colors;

    return Material(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Meine Fächer',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          modules.isEmpty ? 'Noch keine Fächer' : '${modules.length} Fächer',
                          style: TextStyle(fontSize: 13, color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fach importieren',
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: () => _importModule(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: modules.isEmpty
                  ? _EmptyState(onCreate: () => _createModule(context))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 160),
                      children: [
                        // „Weiter lernen“: dort weitermachen, wo man aufgehört hat.
                        if (_continue case final target? when modules.any((m) => m.id == target.moduleId)) ...[
                          ContinueLearningCard(
                            key: const ValueKey('home-continue'),
                            target: target,
                            onContinue: () => _continueLearning(target),
                            onOther: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ModuleDetailScreen(moduleId: target.moduleId)),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _QuickAction(
                                key: const ValueKey('home-daily'),
                                icon: Icons.style_outlined,
                                label: 'Daily Quiz',
                                onTap: widget.onOpenDailyQuiz,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickAction(
                                key: const ValueKey('home-weakness'),
                                icon: Icons.track_changes_outlined,
                                label: 'Schwachstellen',
                                onTap: () => Navigator.of(
                                  context,
                                ).push(MaterialPageRoute<void>(builder: (_) => const WeaknessScreen())),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'ALLE FÄCHER',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: c.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final (i, module) in modules.indexed) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _ModuleTile(
                            module: module,
                            ampel: _ampelByModule == null ? null : (_ampelByModule![module.id] ?? const {}),
                            taskFolderWarning: TaskFolderService.isWarning(
                              taskCount: _taskCountByModule[module.id] ?? 0,
                              examDate: module.examDate,
                            ),
                            labHint: labHomeHint(labs?.forModule(module.id) ?? const [], DateTime.now()),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _createModule(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ModuleFormScreen()),
    );
  }
}

/// Schnellzugriff unter „Weiter lernen“.
class _QuickAction extends StatelessWidget {
  const _QuickAction({super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 22, color: c.accentOnSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 56, color: c.inkMuted),
            const SizedBox(height: 16),
            Text(
              'Noch keine Fächer angelegt.\nLege ein Fach an, um Folien und '
              'Übungsaufgaben zu sammeln und ein Klausurdatum zu setzen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Erstes Fach anlegen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module, required this.ampel, this.taskFolderWarning = false, this.labHint});
  final Module module;

  /// Anstehende Laborvorbereitung oder offener Bericht (siehe labHomeHint).
  final String? labHint;

  /// Klausur nah und Aufgaben im Aufgaben-Ordner: roter Hinweis.
  final bool taskFolderWarning;

  /// Ampel des Fachs, null solange noch nicht geladen.
  final Map<MasteryLevel, int>? ampel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final softTint = Color.alphaBlend(module.color.withValues(alpha: 0.16), c.surface);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ModuleDetailScreen(moduleId: module.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: softTint, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(module.icon, style: const TextStyle(fontSize: 19)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    ExamCountdownBadge(daysUntilExam: module.daysUntilExam),
                    if (taskFolderWarning) ...[
                      const SizedBox(height: 7),
                      Container(
                        key: ValueKey('task-warning-${module.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.flag_rounded, size: 13, color: c.danger),
                            const SizedBox(width: 4),
                            Text(
                              'Aufgaben-Ordner durcharbeiten',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.danger),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (labHint != null) ...[
                      const SizedBox(height: 7),
                      Container(
                        key: ValueKey('lab-hint-${module.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.science_outlined, size: 13, color: c.warn),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                labHint!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.warn),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (ampel != null) ...[
                      const SizedBox(height: 10),
                      MasteryBar(key: ValueKey('ampel-${module.id}'), breakdown: ampel!),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
