import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/daily_session_state.dart';
import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/daily_session_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/module_repository.dart';
import '../../services/daily_scheduler_service.dart';
import '../../services/fsrs_service.dart';
import '../../services/home_widget_service.dart';
import '../../theme/app_colors.dart';
import 'card_review_mixin.dart';
import 'question_answer_view.dart';

/// Welche Runde einer Session eine Karte gerade angezeigt wird – steuert in
/// [_DailyQuizScreenState._handleComplete], aus welcher Warteschlange sie
/// entfernt wird (statt das anhand von [_DailyQuizScreenState._index]
/// zurückzuraten, was bei mehreren parallel möglichen Runden mehrdeutig
/// wäre).
enum _QuizStage { main, revisit, bonus }

/// Daily Quiz / Exam-Scheduler: tägliche Lernsession über alle Fächer
/// hinweg. Fällige Wiederholungen + eine je nach Wissensstand und
/// Klausurnähe dosierte Menge neuer Karten.
class DailyQuizScreen extends StatefulWidget {
  const DailyQuizScreen({super.key, this.isActive = true});

  /// Ob der Daily-Quiz-Tab gerade sichtbar ist (siehe RootShell).
  final bool isActive;

  @override
  State<DailyQuizScreen> createState() => _DailyQuizScreenState();
}

class _DailyQuizScreenState extends State<DailyQuizScreen>
    with WidgetsBindingObserver, CardReviewMixin<DailyQuizScreen> {
  DailyPlan? _plan;
  int _index = 0;
  int _reviewedCount = 0;

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

  /// Freiwillige Zusatzrunde über das Tagesbudget hinaus (siehe
  /// [_continueVoluntarily]/DailySchedulerService.buildExtraBatch) – FIFO
  /// wie [_wrongQueue], aber erst befüllt, NACHDEM Haupt- und
  /// Wiederholungsrunde durch sind, und nur auf Nutzerwunsch (Button auf
  /// _AllDoneView/_SessionDoneView). Bewusst eine EIGENE Queue statt den
  /// bestehenden [_plan] zu vergrößern: [_index] indiziert positional in
  /// `plan.allCards` (das Fächer-Interleaving neu mischt, sobald sich die
  /// zugrundeliegenden Listen ändern) – ein nachträgliches Anhängen dort
  /// hätte bereits gezeigte Karten verschieben und erneut anzeigen können.
  final List<Flashcard> _bonusQueue = [];
  bool _bonusLoading = false;

  /// Kalendertag, für den [_plan] zuletzt berechnet wurde – Grundlage für
  /// [didChangeAppLifecycleState]: RootShell hält diesen Screen dauerhaft im
  /// Speicher (IndexedStack, kein Dispose beim Tab-Wechsel), ein normales
  /// App-Backgrounding beendet den Dart-Isolate NICHT. Ohne diese Prüfung
  /// bliebe der Plan über Mitternacht hinweg stehen: wer die App abends
  /// öffnet, tagsüber im Hintergrund lässt und nachts wieder aufruft, sähe
  /// weiterhin den (jetzt veralteten) Plan von heute Morgen statt neu
  /// fälliger Karten für den neuen Tag.
  DateTime? _lastLoadedDay;

  /// Gespeicherter Tagesfortschritt (siehe DailySessionState) – übersteht
  /// App-Neustart und "Aktualisieren".
  DailySessionState _session = DailySessionState.empty(DateTime.now());

  /// Antworten seit dem letzten [_loadPlan] – solange 0, darf ein Tab-Wechsel
  /// den Plan neu berechnen, ohne eine laufende Karte zu unterbrechen.
  int _answeredSinceLoad = 0;

  bool get _sessionFinished {
    final plan = _plan;
    return plan != null && _index >= plan.total && _wrongQueue.isEmpty && _bonusQueue.isEmpty;
  }

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
  void didUpdateWidget(covariant DailyQuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ohne Neuladen beim Tab-Wechsel zeigte dieser Screen nur den Stand vom
    // App-Start – seither (Nachbereiten, "Frage erstellen", Zwischen-Check)
    // angelegte Karten tauchten nicht auf, "nichts fällig" blieb stehen.
    // Mitten in einer Runde wird nicht neu geplant (die aktuelle Karte
    // bliebe sonst nicht stehen); vorher oder nach Abschluss schon – der
    // Tagesfortschritt selbst liegt in [_session] und geht dabei nicht verloren.
    if (widget.isActive && !oldWidget.isActive && (_answeredSinceLoad == 0 || _sessionFinished)) {
      _loadPlan();
    }
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
    final now = DateTime.now();
    final session = await DailySessionRepository().load(now);
    final cardsById = {for (final c in allCards) c.id: c};
    final introducedToday = session.introducedByModule({for (final c in allCards) c.id: c.moduleId});
    final plan = DailySchedulerService().buildPlan(
      modules: modules,
      allCards: allCards,
      unitCoveredById: unitCoveredById,
      introducedTodayByModule: introducedToday,
    );
    unawaited(HomeWidgetService().refresh(
      modules: modules,
      allCards: allCards,
      unitCoveredById: unitCoveredById,
      introducedTodayByModule: introducedToday,
    ));
    if (!mounted) return;
    final plannedIds = {for (final c in plan.allCards) c.id};
    setState(() {
      _plan = plan;
      _session = session;
      _index = 0;
      _answeredSinceLoad = 0;
      _reviewedCount = session.reviewedCount;
      _wrongQueue
        ..clear()
        ..addAll([
          for (final id in session.wrongIds)
            if (cardsById[id] != null && !plannedIds.contains(id)) cardsById[id]!,
        ]);
      _wrongAttempts
        ..clear()
        ..addAll(session.wrongAttempts);
      _bonusQueue.clear();
      _lastLoadedDay = DailySessionState.dayOf(now);
    });
  }

  void _persistSession({required Flashcard answered}) {
    final wasNew = answered.reps == 0;
    _session = _session.copyWith(
      reviewedCount: _reviewedCount,
      introducedIds: wasNew ? {..._session.introducedIds, answered.id} : null,
      wrongIds: _wrongQueue.map((c) => c.id).toList(),
      wrongAttempts: Map.of(_wrongAttempts),
    );
    unawaited(DailySessionRepository().save(_session));
  }

  /// Zusätzliche, rein freiwillige Charge über das Tagesbudget hinaus (siehe
  /// [_bonusQueue]) – für den "Trotzdem weiterlernen"-Button, wenn der
  /// reguläre Tagesplan (inkl. Wiederholungsrunde) bereits abgeschlossen ist.
  Future<void> _continueVoluntarily() async {
    setState(() => _bonusLoading = true);
    final modules = context.read<ModuleRepository>().modules;
    final flashcardRepo = context.read<FlashcardRepository>();
    final lectureUnitRepo = context.read<LectureUnitRepository>();
    final allCards = await flashcardRepo.loadAll();
    final unitCoveredById = await lectureUnitRepo.loadAllCoveredById();
    if (!mounted) return;
    final excludeIds = <String>{
      ...?_plan?.allCards.map((c) => c.id),
      ..._wrongQueue.map((c) => c.id),
      ..._bonusQueue.map((c) => c.id),
    };
    final extra = DailySchedulerService().buildExtraBatch(
      modules: modules,
      allCards: allCards,
      unitCoveredById: unitCoveredById,
      excludeIds: excludeIds,
    );
    if (!mounted) return;
    setState(() {
      _bonusLoading = false;
      _bonusQueue.addAll(extra.allCards);
    });
    if (extra.total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktuell keine weiteren Karten verfügbar.'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _handleComplete(Flashcard card, {required _QuizStage stage, Grade? selfGrade, bool? isCorrect}) async {
    final outcome = await recordReview(card, selfGrade: selfGrade, isCorrect: isCorrect);
    final updated = outcome.card;
    final wasWrong = outcome.wasWrong;

    if (!mounted) return;
    setState(() {
      switch (stage) {
        case _QuizStage.main:
          _index += 1;
          if (wasWrong) _wrongQueue.add(updated);
        case _QuizStage.revisit:
          // Wiederholungsrunde: die gerade abgeschlossene Karte stand vorn in
          // der Queue (siehe build()).
          _wrongQueue.removeAt(0);
          final attempts = (_wrongAttempts[card.id] ?? 0) + 1;
          _wrongAttempts[card.id] = attempts;
          if (wasWrong && attempts < _maxWrongRequeueAttempts) {
            _wrongQueue.add(updated);
          }
        case _QuizStage.bonus:
          // Freiwillige Zusatzrunde: falsch beantwortete Karten bekommen
          // trotzdem eine Wiederholungschance über dieselbe _wrongQueue wie
          // die Hauptrunde.
          _bonusQueue.removeAt(0);
          if (wasWrong) _wrongQueue.add(updated);
      }
      _reviewedCount += 1;
      _answeredSinceLoad += 1;
    });
    _persistSession(answered: card);
    unawaited(_refreshHomeWidget());
  }

  Future<void> _refreshHomeWidget() async {
    if (!mounted) return;
    final modules = context.read<ModuleRepository>().modules;
    final lectureUnitRepo = context.read<LectureUnitRepository>();
    final allCards = await context.read<FlashcardRepository>().loadAll();
    final unitCoveredById = await lectureUnitRepo.loadAllCoveredById();
    // Mit derselben Einheiten-Freigabe wie der Tagesplan selbst, sonst zählte
    // das Widget auch Karten noch nicht behandelter Einheiten als fällig.
    await HomeWidgetService().refresh(
      modules: modules,
      allCards: allCards,
      unitCoveredById: unitCoveredById,
      introducedTodayByModule: _session.introducedByModule({for (final c in allCards) c.id: c.moduleId}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final c = context.colors;
    Widget body;
    if (plan == null) {
      body = const Center(child: CircularProgressIndicator());
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
        onComplete: ({selfGrade, isCorrect}) =>
            _handleComplete(card, stage: _QuizStage.main, selfGrade: selfGrade, isCorrect: isCorrect),
      );
    } else if (_wrongQueue.isNotEmpty) {
      // Wiederholungsrunde: Hauptrunde ist durch, aber es gibt noch falsch
      // beantwortete Karten von vorhin (siehe _handleComplete).
      final card = _wrongQueue.first;
      body = _SessionView(
        // Versuchszähler im Key: kommt dieselbe Karte direkt erneut dran
        // (einzige Karte in der Queue), braucht sie einen frischen
        // Antwort-State statt der schon geprüften Eingabe von eben.
        key: ValueKey('revisit-${card.id}-${_wrongAttempts[card.id] ?? 0}'),
        card: card,
        moduleName: context.read<ModuleRepository>().byId(card.moduleId)?.name ?? '',
        progress: 1,
        total: plan.total,
        position: plan.total,
        isNew: false,
        isRevisit: true,
        revisitRemaining: _wrongQueue.length,
        onComplete: ({selfGrade, isCorrect}) =>
            _handleComplete(card, stage: _QuizStage.revisit, selfGrade: selfGrade, isCorrect: isCorrect),
      );
    } else if (_bonusQueue.isNotEmpty) {
      // Freiwillige Zusatzrunde (siehe _continueVoluntarily): Haupt- und
      // Wiederholungsrunde sind durch, der Nutzer wollte trotzdem
      // weiterlernen.
      final card = _bonusQueue.first;
      body = _SessionView(
        key: ValueKey('bonus-${card.id}'),
        card: card,
        moduleName: context.read<ModuleRepository>().byId(card.moduleId)?.name ?? '',
        progress: 1,
        total: plan.total,
        position: plan.total,
        isNew: card.reps == 0,
        isBonus: true,
        revisitRemaining: _bonusQueue.length,
        onComplete: ({selfGrade, isCorrect}) =>
            _handleComplete(card, stage: _QuizStage.bonus, selfGrade: selfGrade, isCorrect: isCorrect),
      );
    } else if (plan.total == 0 && _reviewedCount == 0) {
      body = _AllDoneView(onContinue: _continueVoluntarily, loading: _bonusLoading);
    } else {
      body = _SessionDoneView(
        count: _reviewedCount,
        onRestart: _loadPlan,
        onContinue: _continueVoluntarily,
        loading: _bonusLoading,
      );
    }
    return Material(color: c.bg, child: SafeArea(child: body));
  }
}

class _AllDoneView extends StatelessWidget {
  const _AllDoneView({required this.onContinue, required this.loading});
  final VoidCallback onContinue;
  final bool loading;

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
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: loading ? null : onContinue,
              icon: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_circle_outline),
              label: const Text('Trotzdem freiwillig weiterlernen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionDoneView extends StatelessWidget {
  const _SessionDoneView({
    required this.count,
    required this.onRestart,
    required this.onContinue,
    required this.loading,
  });
  final int count;
  final VoidCallback onRestart;
  final VoidCallback onContinue;
  final bool loading;

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
            Text('Für heute geschafft! $count Karten wiederholt.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: loading ? null : onContinue,
                  icon: loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_circle_outline),
                  label: const Text('Freiwillig weiterlernen'),
                ),
                FilledButton(onPressed: onRestart, child: const Text('Aktualisieren')),
              ],
            ),
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
    this.isBonus = false,
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

  /// true, wenn dies die freiwillige Zusatzrunde nach Sessionende ist (siehe
  /// [_DailyQuizScreenState._bonusQueue]/_continueVoluntarily) – nutzt
  /// [revisitRemaining] für die Restanzeige, mit eigenem Label statt
  /// "Wiederholung".
  final bool isBonus;
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
                    isRevisit
                        ? '🔄 Wiederholung · noch $revisitRemaining'
                        : isBonus
                            ? '🙋 Freiwillig · noch $revisitRemaining'
                            : '$position / $total',
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
