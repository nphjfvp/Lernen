import 'package:flutter/material.dart';

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
    var candidateStart = DateTime(from.year, from.month, from.day, hour, minute);
    final daysUntilWeekday = (weekday - from.weekday) % 7;
    candidateStart = candidateStart.add(Duration(days: daysUntilWeekday));
    final candidateEnd = hasEndTime
        ? DateTime(candidateStart.year, candidateStart.month, candidateStart.day, endHour!, endMinute!)
        : candidateStart;
    if (candidateEnd.isBefore(from)) candidateStart = candidateStart.add(const Duration(days: 7));
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
        weekday: map['weekday'] as int,
        hour: map['hour'] as int,
        minute: map['minute'] as int,
        endHour: map['endHour'] as int?,
        endMinute: map['endMinute'] as int?,
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

  const Module({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.icon,
    required this.examDate,
    required this.createdAt,
    this.lectureSlots,
  });

  Color get color => Color(colorValue);

  int? get daysUntilExam {
    if (examDate == null) return null;
    final today = DateTime.now();
    final examDay = DateTime(examDate!.year, examDate!.month, examDate!.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return examDay.difference(todayDay).inDays;
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
  }) {
    return Module(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      icon: icon ?? this.icon,
      examDate: clearExamDate ? null : (examDate ?? this.examDate),
      createdAt: createdAt,
      lectureSlots: clearLectureSlots ? null : (lectureSlots ?? this.lectureSlots),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'icon': icon,
        'examDate': examDate?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'lectureSlots': lectureSlots?.map((s) => s.toMap()).toList(),
      };

  factory Module.fromMap(Map<String, dynamic> map) => Module(
        id: map['id'] as String,
        name: map['name'] as String,
        colorValue: map['colorValue'] as int,
        icon: map['icon'] as String,
        examDate: map['examDate'] == null
            ? null
            : DateTime.parse(map['examDate'] as String),
        createdAt: DateTime.parse(map['createdAt'] as String),
        lectureSlots: (map['lectureSlots'] as List?)
            ?.map((e) => LectureSlot.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
