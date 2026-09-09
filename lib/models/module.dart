import 'package:flutter/material.dart';

/// Ein Fach-Ordner: sammelt Folien, Übungsaufgaben und Konzepte und trägt
/// ein optionales Klausurdatum, das den Exam-Scheduler steuert.
class Module {
  final String id;
  final String name;
  final int colorValue;
  final String icon;
  final DateTime? examDate;
  final DateTime createdAt;

  const Module({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.icon,
    required this.examDate,
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  int? get daysUntilExam {
    if (examDate == null) return null;
    final today = DateTime.now();
    final examDay = DateTime(examDate!.year, examDate!.month, examDate!.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return examDay.difference(todayDay).inDays;
  }

  Module copyWith({
    String? name,
    int? colorValue,
    String? icon,
    DateTime? examDate,
    bool clearExamDate = false,
  }) {
    return Module(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      icon: icon ?? this.icon,
      examDate: clearExamDate ? null : (examDate ?? this.examDate),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'icon': icon,
        'examDate': examDate?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
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
      );
}
