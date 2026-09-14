import 'package:home_widget/home_widget.dart';

import '../models/flashcard.dart';
import '../models/module.dart';
import 'calendar_service.dart';
import 'daily_scheduler_service.dart';

const _kWeekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Berechnet die drei Textzeilen des Android-Startbildschirm-Widgets
/// (nächste Vorlesung, Lernerinnerung anhand fälliger Karten, Klausur-
/// Countdown) und schreibt sie über das `home_widget`-Package in die
/// geteilten Widget-Daten, von wo `CalendarWidgetProvider.kt` sie ausliest.
///
/// Die Text-Berechnung selbst ist bewusst als separate, pure Methoden
/// gehalten (testbar ohne Platform-Channel); nur [refresh] spricht die
/// native Seite an – auf iOS/Web ohne Wirkung, da bislang nur ein
/// Android-Widget existiert.
class HomeWidgetService {
  static const androidProviderName = 'CalendarWidgetProvider';
  static const keyLecture = 'widget_lecture';
  static const keyReminder = 'widget_reminder';
  static const keyCountdown = 'widget_countdown';

  final CalendarService _calendarService;
  final DailySchedulerService _schedulerService;

  HomeWidgetService({CalendarService? calendarService, DailySchedulerService? schedulerService})
      : _calendarService = calendarService ?? CalendarService(),
        _schedulerService = schedulerService ?? DailySchedulerService();

  String buildLectureLine(List<Module> modules, {DateTime? from}) {
    final next = _calendarService.nextLecture(modules, from: from);
    if (next == null) return 'Keine Vorlesung geplant';
    final d = next.dateTime;
    final weekday = _kWeekdayLabels[d.weekday - 1];
    final start = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final end = next.endDateTime;
    final time = end == null
        ? start
        : '$start–${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    return '📅 $weekday $time · ${next.module.name}';
  }

  String buildReminderLine(
    List<Module> modules,
    List<Flashcard> allCards, {
    Map<String, bool> unitCoveredById = const {},
    DateTime? now,
  }) {
    final plan = _schedulerService.buildPlan(
      modules: modules,
      allCards: allCards,
      unitCoveredById: unitCoveredById,
      now: now,
    );
    final count = plan.total;
    if (count == 0) return '🎉 Heute nichts fällig';
    return '🔔 $count Karte${count == 1 ? '' : 'n'} fällig heute';
  }

  String buildCountdownLine(List<Module> modules, {DateTime? from}) {
    final next = _calendarService.nextExam(modules, from: from);
    if (next == null) return 'Keine Klausur geplant';
    final start = from ?? DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final examDay = DateTime(next.dateTime.year, next.dateTime.month, next.dateTime.day);
    final days = examDay.difference(startDay).inDays;
    if (days <= 0) return '⏳ ${next.module.name}: Klausur heute!';
    return '⏳ ${next.module.name} in $days Tag${days == 1 ? '' : 'en'}';
  }

  /// Berechnet die drei Zeilen neu und schreibt sie ins Android-Widget.
  /// Bewusst fehlertolerant (wie die Hintergrund-Beförderung in
  /// DailyQuizScreen): auf Plattformen ohne den `home_widget`-Platform-
  /// Channel (iOS/Web/Tests) oder ohne installiertes Widget soll das nie die
  /// eigentliche App-Funktion stören.
  Future<void> refresh({
    required List<Module> modules,
    required List<Flashcard> allCards,
    Map<String, bool> unitCoveredById = const {},
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(keyLecture, buildLectureLine(modules));
      await HomeWidget.saveWidgetData<String>(
          keyReminder, buildReminderLine(modules, allCards, unitCoveredById: unitCoveredById));
      await HomeWidget.saveWidgetData<String>(keyCountdown, buildCountdownLine(modules));
      await HomeWidget.updateWidget(androidName: androidProviderName);
    } catch (_) {
      // Stille Behandlung, siehe Doc-Kommentar oben.
    }
  }
}
