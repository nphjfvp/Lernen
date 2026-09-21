import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/module_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/daily_scheduler_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/home_widget_service.dart';
import '../../services/question_parsing.dart';
import '../../theme/app_colors.dart';
import 'question_answer_view.dart';

/// Daily Quiz / Exam-Scheduler: tägliche Lernsession über alle Fächer
/// hinweg. Fällige Wiederholungen + eine je nach Wissensstand und
/// Klausurnähe dosierte Menge neuer Karten.
class DailyQuizScreen extends StatefulWidget {
  const DailyQuizScreen({super.key});

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen> with WidgetsBindingObserver {
  DailyPlan? _plan;
  int _index = 0;
  int _reviewedCount = 0;
  final _fsrs = FsrsService();

  /// Wiederholungsrunde für falsch beantwortete Karten der Hauptrunde
  /// (siehe Klassenkommentar unten): FIFO – das erste Element ist die
  /// gerade angezeigte Karte, siehe [build]. Läuft an, sobald die Hauptrunde
  /// ([_index] >= `plan.total`) durch ist, statt erst am nächsten
  /// natürlichen FSRS-Fälligkeitsdatum wieder aufzutauchen (sonst könnte
  /// eine Session trotz vieler falscher Antworten nach 1-2 Minuten enden).
  final List<Flashcard> _wrongQueue = [];

  /// Wie oft eine Karte in der Wiederholungsrunde schon erneut drankam –
  /// verhindert eine Endlosschleife bei einer Karte, die immer wieder falsch
  /// beantwortet wird.
  final Map<String, int> _wrongAttempts = {};
  static const int _maxWrongRequeueAttempts = 3;

  /// Kalendertag, für den [_plan] zuletzt berechnet wurde – Grundlage für
  /// [didChangeAppLifecycleState]: RootShell hält diesen Screen dauerhaft im
  /// Speicher (IndexedStack, kein Dispose beim Tab-Wechsel), ein normales
  /// App-Backgrounding beendet den Dart-Isolate NICHT. Ohne diese Prüfung
  /// bliebe der Plan über Mitternacht hinweg stehen: wer die App abends
  /// öffnet, tagsüber im Hintergrund lässt und nachts wieder aufruft, sähe
  /// weiterhin den (jetzt veralteten) Plan von heute Morgen statt neu
  /// fälliger Karten für den neuen Tag.
  DateTime? _lastLoadedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlan());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastDay = _lastLoadedDay;
    if (lastDay == null) return;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    if (todayDay.isAfter(lastDay)) _loadPlan();
  }

  Future<void> _loadPlan() async {
    final modules = context.read<ModuleRepository>().modules;
    final flashcardRepo = context.read<FlashcardRepository>();
    final lectureUnitRepo = context.read<LectureUnitRepository>();
    final allCards = await flashcardRepo.loadAll();
    final unitCoveredById = await lectureUnitRepo.loadAllCoveredById();
    final plan = DailySchedulerService()
        .buildPlan(modules: modules, allCards: allCards, unitCoveredById: unitCoveredById);
    unawaited(HomeWidgetService()
        .refresh(modules: modules, allCards: allCards, unitCoveredById: unitCoveredById));
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _plan = plan;
      _index = 0;
      _reviewedCount = 0;
      _wrongQueue.clear();
      _wrongAttempts.clear();
      _lastLoadedDay = DateTime(now.year, now.month, now.day);
    });
  }

  Future<void> _handleComplete(Flashcard card, {Grade? selfGrade, bool? isCorrect}) async {
    final grade = selfGrade ?? _fsrs.gradeFromResult(isCorrect!);
    var updated = _fsrs.review(card, grade);

    if (isCorrect != null && updated.variantChain != null) {
      final boxResult = updated.copyWithBoxUpdate(isCorrect: isCorrect);
      updated = boxResult.card;
      await context.read<FlashcardRepository>().update(updated);
      final nextType = boxResult.nextType;
      if (nextType != null) {
        unawaited(_promoteInBackground(updated, nextType));
        _showLevelChangeSnackBar('⬆️ Stufe geschafft – nächstes Mal: ${nextType.label}');
      } else if (updated.type != card.type) {
        // copyWithBoxUpdate stuft bei wiederholten Fehlversuchen intern
        // zurück (siehe Flashcard.copyWithDemotedVariant) – erkennbar daran,
        // dass sich der Typ geändert hat, obwohl keine Beförderung vorlag.
        _showLevelChangeSnackBar('⬇️ Zurück zu: ${updated.type.label}');
      }
    } else {
      await context.read<FlashcardRepository>().update(updated);
    }

    // Sowohl explizit falsch beantwortete interaktive Fragen (isCorrect ==
    // false) als auch selbst als "Nochmal" eingestufte einfache Karteikarten
    // (selfGrade == Grade.again) gelten als "falsch" für die
    // Wiederholungsrunde – beides bedeutet, der Nutzer wusste die Antwort
    // gerade nicht.
    final wasWrong = isCorrect == false || selfGrade == Grade.again;
    final inMainStage = _index < (_plan?.total ?? 0);

    if (!mounted) return;
    setState(() {
      if (inMainStage) {
        _index += 1;
        if (wasWrong) _wrongQueue.add(updated);
      } else {
        // Wiederholungsrunde: die gerade abgeschlossene Karte stand vorn in
        // der Queue (siehe build()).
        _wrongQueue.removeAt(0);
        final attempts = (_wrongAttempts[card.id] ?? 0) + 1;
        _wrongAttempts[card.id] = attempts;
        if (wasWrong && attempts < _maxWrongRequeueAttempts) {
          _wrongQueue.add(updated);
        }
      }
      _reviewedCount += 1;
    });
    unawaited(_refreshHomeWidget());
  }

  Future<void> _refreshHomeWidget() async {
    if (!mounted) return;
    final modules = context.read<ModuleRepository>().modules;
    final allCards = await context.read<FlashcardRepository>().loadAll();
    await HomeWidgetService().refresh(modules: modules, allCards: allCards);
  }

  /// Kurzes, nicht-blockierendes Feedback bei Auf-/Abstufung innerhalb der
  /// Schwierigkeits-Eskalationskette (siehe [Flashcard.copyWithBoxUpdate]) –
  /// vorher lief das komplett unsichtbar im Hintergrund, wodurch das
  /// eigentlich schon vorhandene Feature ("erst weiter, wenn verstanden")
  /// dem Nutzer nie auffiel.
  void _showLevelChangeSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Erzeugt lazy die nächste (schwerere) Eskalationsstufe per KI und
  /// speichert sie – läuft bewusst im Hintergrund weiter, auch nachdem die
  /// Session zur nächsten Frage übergegangen ist: schlägt es fehl oder ist
  /// kein API-Key hinterlegt, bleibt die Frage einfach auf ihrer aktuellen
  /// Stufe (nächster richtiger Versuch probiert die Beförderung erneut).
  Future<void> _promoteInBackground(Flashcard card, QuestionType nextType) async {
    try {
      final settings = context.read<SettingsRepository>().settings;
      if (!settings.hasApiKey) return;
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final result = await ai.generateHarderVariant(
        questionText: card.front,
        currentAnswer: card.answerSummary,
        targetType: nextType,
      );
      final promoted = card.copyWithPromotedVariant(
        newType: nextType,
        front: (result['front'] ?? card.front).toString(),
        back: (result['back'] ?? '').toString(),
        options: QuestionParsing.parseOptions(result['options']),
        correctText: result['correctText'] as String?,
        blanks: QuestionParsing.parseBlanks(result['blanks']),
        dragPairs: QuestionParsing.parseDragPairs(result['dragPairs']),
      );
      if (!mounted) return;
      await context.read<FlashcardRepository>().update(promoted);
    } catch (_) {
      // Stille Behandlung, siehe Doc-Kommentar oben.
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final c = context.colors;
    Widget body;
    if (plan == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (plan.total == 0 && _wrongQueue.isEmpty) {
      body = const _AllDoneView();
    } else if (_index < plan.total) {
      final card = plan.allCards[_index];
      body = _SessionView(
        key: ValueKey(card.id),
        card: card,
        moduleName: context.read<ModuleRepository>().byId(card.moduleId)?.name ?? '',
        progress: (_index + 1) / plan.total,
        total: plan.total,
        position: _index + 1,
        isNew: plan.newCards.contains(card),
        onComplete: ({selfGrade, isCorrect}) => _handleComplete(card, selfGrade: selfGrade, isCorrect: isCorrect),
      );
    } else if (_wrongQueue.isNotEmpty) {
      // Wiederholungsrunde: Hauptrunde ist durch, aber es gibt noch falsch
      // beantwortete Karten von vorhin (siehe _handleComplete).
      final card = _wrongQueue.first;
      body = _SessionView(
        key: ValueKey('revisit-${card.id}'),
        card: card,
        moduleName: context.read<ModuleRepository>().byId(card.moduleId)?.name ?? '',
        progress: 1,
        total: plan.total,
        position: plan.total,
        isNew: false,
        isRevisit: true,
        revisitRemaining: _wrongQueue.length,
        onComplete: ({selfGrade, isCorrect}) => _handleComplete(card, selfGrade: selfGrade, isCorrect: isCorrect),
      );
    } else {
      body = _SessionDoneView(count: _reviewedCount, onRestart: _loadPlan);
    }
    return Material(color: c.bg, child: SafeArea(child: body));
  }
}

class _AllDoneView extends StatelessWidget {
  const _AllDoneView();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration_outlined, size: 56, color: c.good),
            const SizedBox(height: 16),
            Text(
              'Für heute nichts fällig!\nLege in einem Fach neue Karteikarten '
              'an (Nachbereiten-Modus) oder komm morgen wieder.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDoneView extends StatelessWidget {
  const _SessionDoneView({required this.count, required this.onRestart});
  final int count;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: c.good),
            const SizedBox(height: 16),
            Text('Session abgeschlossen! $count Karten wiederholt.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRestart, child: const Text('Aktualisieren')),
          ],
        ),
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  const _SessionView({
    super.key,
    required this.card,
    required this.moduleName,
    required this.progress,
    required this.total,
    required this.position,
    required this.isNew,
    required this.onComplete,
    this.isRevisit = false,
    this.revisitRemaining = 0,
  });

  final Flashcard card;
  final String moduleName;
  final double progress;
  final int total;
  final int position;
  final bool isNew;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;

  /// true, wenn die Hauptrunde bereits durch ist und dies eine
  /// Wiederholungsrunde für zuvor falsch beantwortete Karten ist (siehe
  /// [_DailyQuizScreenState._wrongQueue]) – zeigt statt "Position / Total"
  /// die Anzahl verbleibender Wiederholungen.
  final bool isRevisit;
  final int revisitRemaining;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isRevisit ? '🔄 Wiederholung · noch $revisitRemaining' : '$position / $total',
                    style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                  ),
                  if (moduleName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        moduleName,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.accentOnSoft),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: QuestionAnswerView(
            key: ValueKey(card.id),
            card: card,
            isNew: isNew,
            onComplete: onComplete,
          ),
        ),
      ],
    );
  }
}
