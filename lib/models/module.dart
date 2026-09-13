import 'package:flutter/material.dart';

/// Ein wöchentlich wiederkehrender Vorlesungstermin (Wochentag + Uhrzeit).
class LectureSlot {
  final int weekday; // 1 = Montag ... 7 = Sonntag (DateTime.monday..sunday)
  final int hour;
  final int minute;

  const LectureSlot({required this.weekday, required this.hour, required this.minute});

  /// Nächstes Vorkommen dieses Termins ab [from] (inklusive, falls die Uhrzeit
  /// an diesem Tag noch nicht vorbei ist).
  DateTime nextOccurrenceFrom(DateTime from) {
    var candidate = DateTime(from.year, from.month, from.day, hour, minute);
    final daysUntilWeekday = (weekday - from.weekday) % 7;
    candidate = candidate.add(Duration(days: daysUntilWeekday));
    if (candidate.isBefore(from)) candidate = candidate.add(const Duration(days: 7));
    return candidate;
  }

  Map<String, dynamic> toMap() => {'weekday': weekday, 'hour': hour, 'minute': minute};

  factory LectureSlot.fromMap(Map<String, dynamic> map) => LectureSlot(
        weekday: map['weekday'] as int,
        hour: map['hour'] as int,
        minute: map['minute'] as int,
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
