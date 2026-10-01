import 'package:flutter/material.dart';
import '../services/calendar_days.dart';

/// Ein wöchentlich wiederkehrender Vorlesungstermin (Wochentag + Uhrzeit).
/// Endzeit ist optional/nullable – ältere, vor der Endzeit-Unterstützung
/// gespeicherte Termine haben keine und zeigen dann nur die Startzeit.
class LectureSlot {
  final int weekday; // 1 = Montag ... 7 = Sonntag (DateTime.monday..sunday)
  final int hour;
  final int minute;
  final int? endHour;
  final int? endMinute;

  const LectureSlot({
    required this.weekday,
    required this.hour,
    required this.minute,
    this.endHour,
    this.endMinute,
  });

  bool get hasEndTime => endHour != null && endMinute != null;

  /// "10:00" oder, mit hinterlegter Endzeit, "10:00–11:30".
  String get timeLabel {
    final start = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    if (!hasEndTime) return start;
    final end = '${endHour!.toString().padLeft(2, '0')}:${endMinute!.toString().padLeft(2, '0')}';
    return '$start–$end';
  }

  /// Nächstes Vorkommen dieses Termins ab [from] (inklusive, falls der
  /// Termin an diesem Tag noch nicht vorbei ist – mit Endzeit zählt dafür
  /// das Ende, ohne die Startzeit, damit eine gerade laufende Vorlesung
  /// nicht schon als "nächste Woche" angezeigt wird).
  DateTime nextOccurrenceFrom(DateTime from) {
    // Kalendertage statt Duration-Addition: über die Zeitumstellung hinweg
    // bliebe sonst die Uhrzeit nicht stehen.
    final daysUntilWeekday = (weekday - from.weekday) % 7;
    var candidateStart = DateTime(from.year, from.month, from.day + daysUntilWeekday, hour, minute);
    final candidateEnd = hasEndTime
        ? DateTime(candidateStart.year, candidateStart.month, candidateStart.day, endHour!, endMinute!)
        : candidateStart;
    if (candidateEnd.isBefore(from)) {
      candidateStart = DateTime(candidateStart.year, candidateStart.month, candidateStart.day + 7, hour, minute);
    }
    return candidateStart;
  }

  Map<String, dynamic> toMap() => {
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'endHour': endHour,
        'endMinute': endMinute,
      };

  factory LectureSlot.fromMap(Map<String, dynamic> map) => LectureSlot(
        weekday: (map['weekday'] as num?)?.toInt() ?? DateTime.monday,
        hour: (map['hour'] as num?)?.toInt() ?? 8,
        minute: (map['minute'] as num?)?.toInt() ?? 0,
        endHour: (map['endHour'] as num?)?.toInt(),
        endMinute: (map['endMinute'] as num?)?.toInt(),
      );
}

/// Ein Fach-Ordner: sammelt Folien, Übungsaufgaben und Konzepte, trägt ein
/// optionales Klausurdatum (steuert den Exam-Scheduler) sowie optionale
/// wöchentliche Vorlesungstermine (steuern die Kalender-Ansicht).
class Module {
  final String id;
  final String name;
  final int colorValue;
  final String icon;
  final DateTime? examDate;
  final DateTime createdAt;
  final List<LectureSlot>? lectureSlots;

  /// Wie stark dieses Fach insgesamt gewichtet ist (Standard 1.0): wirkt
  /// multiplikativ mit dem Gewicht jeder einzelnen Karte (siehe
  /// Flashcard.weight) auf deren Wiederholungsintervall – ein höher
  /// gewichtetes Fach kommt dadurch bei ALLEN seinen Fragen öfter dran – und
  /// skaliert zusätzlich, wie viele neue Karten es pro Tag ins Daily Quiz
  /// bringt (siehe DailySchedulerService.buildPlan).
  final double weight;

  /// Laborfach: nur dann zeigt das Fach Laborversuche, "Rechnen mit KI" und
  /// den Versuchs-Kalender. Ältere Fächer ohne Angabe zählen als normales
  /// Fach (hat eines schon Versuche, bleiben die sichtbar – siehe
  /// LabExperimentsSection).
  final bool isLab;

  /// Ob das Fach den Labor-Abschnitt zeigt: als Laborfach markiert, oder es
  /// hat (z.B. aus früherer Zeit) schon Versuche – die bleiben sichtbar.
  bool showsLab({required bool hasExperiments}) => isLab || hasExperiments;

  const Module({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.icon,
    required this.examDate,
    required this.createdAt,
    this.lectureSlots,
    this.weight = 1.0,
    this.isLab = false,
  });

  /// Erlaubter Bereich für [weight] (siehe dort), wie bei Flashcard.
  static const double minWeight = 0.25;
  static const double maxWeight = 4.0;

  Color get color => Color(colorValue);

  int? get daysUntilExam {
    if (examDate == null) return null;
    return calendarDaysBetween(DateTime.now(), examDate!);
  }

  /// Nächster Vorlesungstermin ab [from] (Standard: jetzt), oder `null` wenn
  /// keine Vorlesungstermine hinterlegt sind.
  DateTime? nextLectureFrom([DateTime? from]) {
    final slots = lectureSlots;
    if (slots == null || slots.isEmpty) return null;
    final start = from ?? DateTime.now();
    DateTime? best;
    for (final slot in slots) {
      final candidate = slot.nextOccurrenceFrom(start);
      if (best == null || candidate.isBefore(best)) best = candidate;
    }
    return best;
  }

  Module copyWith({
    String? name,
    int? colorValue,
    String? icon,
    DateTime? examDate,
    bool clearExamDate = false,
    List<LectureSlot>? lectureSlots,
    bool clearLectureSlots = false,
    double? weight,
    bool? isLab,
  }) {
    return Module(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      icon: icon ?? this.icon,
      examDate: clearExamDate ? null : (examDate ?? this.examDate),
      createdAt: createdAt,
      lectureSlots: clearLectureSlots ? null : (lectureSlots ?? this.lectureSlots),
      weight: weight == null ? this.weight : _sanitizeWeight(weight),
      isLab: isLab ?? this.isLab,
    );
  }

  static double _sanitizeWeight(double? value) {
    if (value == null || value.isNaN) return 1.0;
    return value.clamp(minWeight, maxWeight).toDouble();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'icon': icon,
        'examDate': examDate?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'lectureSlots': lectureSlots?.map((s) => s.toMap()).toList(),
        'weight': weight,
        'isLab': isLab,
      };

  factory Module.fromMap(Map<String, dynamic> map) => Module(
        id: map['id'] as String,
        name: map['name']?.toString() ?? '',
        colorValue: (map['colorValue'] as num?)?.toInt() ?? 0xFF6B74C4,
        icon: map['icon']?.toString() ?? '📘',
        examDate: DateTime.tryParse(map['examDate']?.toString() ?? ''),
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime(2000),
        lectureSlots: (map['lectureSlots'] as List?)
            ?.map((e) => LectureSlot.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        // Ältere Datensätze ohne Gewicht zählen einfach (1.0).
        weight: _sanitizeWeight((map['weight'] as num?)?.toDouble()),
        isLab: map['isLab'] == true,
      );
}
