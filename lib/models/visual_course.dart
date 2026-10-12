/// Lernpfad in „Visuell lernen“: ein ganzes Semester (mehrere Vorlesungen oder
/// eine lange) als geordnete Folge von Themen mit Übergängen. Jedes Thema
/// ([CourseUnit]) wird erst beim Öffnen (oder „Alle vorbereiten“) zu einer
/// Lektion – mit Rückblick auf die Themen, auf denen es aufbaut. Der Seitentext
/// je Thema ist hier mitgespeichert, damit die Lektion auch ohne die PDF
/// (z.B. auf einem anderen Gerät) entstehen kann.
library;

import 'visual_lesson.dart';

String _str(Object? raw) => '${raw ?? ''}'.trim();

/// Ein Thema des Lernpfads.
class CourseUnit {
  const CourseUnit({
    required this.id,
    required this.title,
    this.summary = '',
    this.how = '',
    this.bridge = '',
    this.needs = const [],
    this.source = '',
    this.material = '',
    this.lessonId,
    this.done = false,
  });

  final String id;
  final String title;

  /// Worum es geht (1 Satz).
  final String summary;

  /// Idee zur Darstellung.
  final String how;

  /// Übergang: warum dieses Thema jetzt kommt und was es vom Vorherigen braucht.
  final String bridge;

  /// IDs der Themen, auf denen dieses aufbaut.
  final List<String> needs;

  /// Woher es stammt, z.B. "Vorlesung 3.pdf, S. 4–7".
  final String source;

  /// Text der Seiten (gekürzt) – Grundlage der Lektion.
  final String material;

  /// Die erzeugte Lektion (null = noch nicht erstellt).
  final String? lessonId;
  final bool done;

  /// Höchstlänge des gespeicherten Seitentexts je Thema.
  static const maxMaterialChars = 8000;

  CourseUnit copyWith({String? lessonId, bool? done, bool clearLesson = false}) => CourseUnit(
    id: id,
    title: title,
    summary: summary,
    how: how,
    bridge: bridge,
    needs: needs,
    source: source,
    material: material,
    lessonId: clearLesson ? null : (lessonId ?? this.lessonId),
    done: done ?? this.done,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    if (summary.isNotEmpty) 'summary': summary,
    if (how.isNotEmpty) 'how': how,
    if (bridge.isNotEmpty) 'bridge': bridge,
    if (needs.isNotEmpty) 'needs': needs,
    if (source.isNotEmpty) 'source': source,
    if (material.isNotEmpty) 'material': material,
    'lessonId': ?lessonId,
    if (done) 'done': true,
  };

  static CourseUnit? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = _str(raw['id']);
    final title = _str(raw['title']);
    if (id.isEmpty || title.isEmpty) return null;
    final material = _str(raw['material']);
    return CourseUnit(
      id: id,
      title: title,
      summary: _str(raw['summary']),
      how: _str(raw['how']),
      bridge: _str(raw['bridge']),
      needs: [
        if (raw['needs'] is List)
          for (final n in raw['needs'] as List)
            if (_str(n).isNotEmpty) _str(n),
      ],
      source: _str(raw['source']),
      material: material.length > maxMaterialChars ? material.substring(0, maxMaterialChars) : material,
      lessonId: _str(raw['lessonId']).isEmpty ? null : _str(raw['lessonId']),
      done: raw['done'] == true,
    );
  }
}

/// Der ganze Lernpfad.
class VisualCourse {
  const VisualCourse({
    required this.id,
    required this.moduleId,
    required this.title,
    this.intro = '',
    this.units = const [],
    this.detail = 'normal',
    this.style = VisualStyle.explain,
    required this.createdAt,
  });

  final String id;
  final String moduleId;
  final String title;

  /// Überblick: worum es im Semester geht und wie die Themen zusammenhängen.
  final String intro;
  final List<CourseUnit> units;
  final String detail;
  final VisualStyle style;
  final DateTime createdAt;

  int get doneCount => units.where((u) => u.done).length;

  /// Das nächste nicht erledigte Thema (null = alles geschafft).
  int? get nextIndex {
    final i = units.indexWhere((u) => !u.done);
    return i < 0 ? null : i;
  }

  CourseUnit? unit(String id) => units.where((u) => u.id == id).firstOrNull;

  /// Die Themen, auf denen [index] aufbaut – plus der direkte Vorgänger.
  List<CourseUnit> basisOf(int index) {
    final unit = units[index];
    return [
      for (final (i, u) in units.indexed)
        if (i < index && (unit.needs.contains(u.id) || i == index - 1)) u,
    ];
  }

  VisualCourse withUnit(int index, CourseUnit unit) => copyWith(units: [...units]..[index] = unit);

  VisualCourse copyWith({List<CourseUnit>? units, String? title}) => VisualCourse(
    id: id,
    moduleId: moduleId,
    title: title ?? this.title,
    intro: intro,
    units: units ?? this.units,
    detail: detail,
    style: style,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    'title': title,
    if (intro.isNotEmpty) 'intro': intro,
    'units': [for (final u in units) u.toMap()],
    'detail': detail,
    if (style != VisualStyle.explain) 'style': style.name,
    'createdAt': createdAt.toIso8601String(),
  };

  static VisualCourse? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = _str(raw['id']);
    final moduleId = _str(raw['moduleId']);
    final units = [
      if (raw['units'] is List)
        for (final u in raw['units'] as List) ?CourseUnit.fromMap(u),
    ];
    if (id.isEmpty || moduleId.isEmpty || units.isEmpty) return null;
    return VisualCourse(
      id: id,
      moduleId: moduleId,
      title: _str(raw['title']).isEmpty ? 'Lernpfad' : _str(raw['title']),
      intro: _str(raw['intro']),
      units: units,
      detail: _str(raw['detail']).isEmpty ? 'normal' : _str(raw['detail']),
      style: _str(raw['style']) == VisualStyle.socratic.name ? VisualStyle.socratic : VisualStyle.explain,
      createdAt: DateTime.tryParse(_str(raw['createdAt'])) ?? DateTime.now(),
    );
  }
}
