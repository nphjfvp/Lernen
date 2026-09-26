import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repositories/module_repository.dart';
import '../../services/calendar_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/exam_countdown_badge.dart';

const _kWeekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _kMonthLabels = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
];

/// Monatskalender: zeigt wöchentliche Vorlesungstermine (aus
/// [Module.lectureSlots]) und Klausurtermine ([Module.examDate]) an, plus
/// einen kleinen Countdown zur nächsten Klausur. Reine Anzeige/Navigation –
/// die eigentliche Terminlogik steckt in [CalendarService] (getestet).
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _service = CalendarService();
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1));
  }

  DateTime _gridStart() {
    final offset = _visibleMonth.weekday - 1; // Montag=1 -> Offset 0
    return DateTime(_visibleMonth.year, _visibleMonth.month, _visibleMonth.day - offset);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final modules = context.watch<ModuleRepository>().modules;

    final gridStart = _gridStart();
    final gridEnd = DateTime(gridStart.year, gridStart.month, gridStart.day + 42);
    final events = _service.eventsInRange(modules: modules, start: gridStart, end: gridEnd);

    final eventsByDay = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      final day = DateTime(event.dateTime.year, event.dateTime.month, event.dateTime.day);
      eventsByDay.putIfAbsent(day, () => []).add(event);
    }

    final nextExam = _service.nextExam(modules);
    final selectedEvents = eventsByDay[_selectedDay] ?? const <CalendarEvent>[];

    return Material(
      color: c.bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Kalender',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (nextExam != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        nextExam.module.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                      ),
                      const SizedBox(height: 4),
                      ExamCountdownBadge(daysUntilExam: nextExam.module.daysUntilExam),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_kMonthLabels[_visibleMonth.month - 1]} ${_visibleMonth.year}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            _MonthGrid(
              visibleMonth: _visibleMonth,
              gridStart: gridStart,
              selectedDay: _selectedDay,
              eventsByDay: eventsByDay,
              onSelect: (day) => setState(() => _selectedDay = day),
            ),
            const SizedBox(height: 24),
            Text(_agendaTitle(_selectedDay), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (selectedEvents.isEmpty)
              Text('Keine Termine an diesem Tag.', style: TextStyle(color: c.inkMuted))
            else
              ...selectedEvents.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EventTile(event: event),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _agendaTitle(DateTime day) {
  final today = DateTime.now();
  if (day.year == today.year && day.month == today.month && day.day == today.day) return 'Heute';
  return '${day.day}.${day.month}.${day.year}';
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.gridStart,
    required this.selectedDay,
    required this.eventsByDay,
    required this.onSelect,
  });

  final DateTime visibleMonth;
  final DateTime gridStart;
  final DateTime selectedDay;
  final Map<DateTime, List<CalendarEvent>> eventsByDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      children: [
        Row(
          children: _kWeekdayLabels
              .map((label) => Expanded(
                    child: Center(
                      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.inkMuted)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        for (var week = 0; week < 6; week++)
          Row(
            children: List.generate(7, (i) {
              // Kalendertage statt 24-h-Schritte: über die Zeitumstellung
              // hinweg läge der Tag sonst auf 23 bzw. 1 Uhr – er fände seine
              // Termine nicht und hieße im Oktober doppelt.
              final day = DateTime(gridStart.year, gridStart.month, gridStart.day + week * 7 + i);
              final inMonth = day.month == visibleMonth.month;
              final isToday = day == today;
              final isSelected = day == selectedDay;
              final dayEvents = eventsByDay[day] ?? const <CalendarEvent>[];
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(day),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? c.accentSoft : null,
                      border: isToday && !isSelected ? Border.all(color: c.accent) : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: !inMonth ? c.inkMuted.withValues(alpha: 0.4) : (isSelected ? c.accentOnSoft : c.ink),
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: 5,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: dayEvents.take(3).map((event) {
                              return Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: event.type == CalendarEventType.exam ? c.danger : c.accent,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isExam = event.type == CalendarEventType.exam;
    final start = '${event.dateTime.hour.toString().padLeft(2, '0')}:'
        '${event.dateTime.minute.toString().padLeft(2, '0')}';
    final endDateTime = event.endDateTime;
    final time = endDateTime == null
        ? start
        : '$start–${endDateTime.hour.toString().padLeft(2, '0')}:'
            '${endDateTime.minute.toString().padLeft(2, '0')}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isExam ? c.dangerSoft : c.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isExam ? Icons.school_rounded : Icons.event_repeat_rounded,
                size: 17,
                color: isExam ? c.danger : c.accentOnSoft,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.module.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                    isExam ? 'Klausur · $time Uhr' : 'Vorlesung · $time Uhr',
                    style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
