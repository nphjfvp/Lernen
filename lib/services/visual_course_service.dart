import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/visual_course.dart';
import '../models/visual_lesson.dart';
import 'ai_service.dart';
import 'pdf_service.dart';
import 'visual_math.dart';

/// Ein gefundenes Thema samt Herkunft und Seitentext (für die Planung).
typedef CourseTopic = ({String title, String summary, String how, bool visual, String source, String material});

/// Lernpfad bauen: Themen aus mehreren PDFs sammeln, von der KI ordnen lassen,
/// je Thema die Lektion mit Rückblick erzeugen.
class VisualCourseService {
  VisualCourseService(this.ai);

  final AiService ai;

  /// Text eines Abschnitts höchstens so lang (wie bei der Themensuche).
  static const windowChars = 30000;
  static const windowPages = 40;

  /// Abschnitte einer PDF ([texts] = Text je Seite).
  static List<List<int>> windowsOf(List<String> texts) {
    final windows = <List<int>>[];
    var current = <int>[];
    var chars = 0;
    for (var p = 1; p <= texts.length; p++) {
      final len = texts[p - 1].length;
      if (current.isNotEmpty && (chars + len > windowChars || current.length >= windowPages)) {
        windows.add(current);
        current = [];
        chars = 0;
      }
      current.add(p);
      chars += len;
    }
    if (current.isNotEmpty) windows.add(current);
    return windows;
  }

  static String pagesLabel(List<int> pages) =>
      pages.isEmpty ? '' : (pages.length == 1 ? 'S. ${pages.first}' : 'S. ${pages.first}–${pages.last}');

  /// Schritt 1: Themen aller [pdfs] (Name, Inhalt) in der Reihenfolge der
  /// Unterlagen. [onProgress]: (erledigt, gesamt).
  Future<List<CourseTopic>> collectTopics(
    List<({String name, Uint8List bytes})> pdfs, {
    String wish = '',
    void Function(int done, int total)? onProgress,
  }) async {
    final jobs = <({String name, List<String> texts, List<int> pages})>[];
    for (final pdf in pdfs) {
      final texts = PdfService().extractPageTexts(pdf.bytes);
      for (final w in windowsOf(texts)) {
        jobs.add((name: pdf.name, texts: texts, pages: w));
      }
    }
    final topics = <CourseTopic>[];
    for (final (k, job) in jobs.indexed) {
      onProgress?.call(k, jobs.length);
      String textOf(Iterable<int> pages) => [
        for (final p in pages)
          if (p - 1 < job.texts.length && job.texts[p - 1].trim().isNotEmpty)
            '--- ${job.name}, Seite $p ---\n${job.texts[p - 1].trim()}',
      ].join('\n\n');
      final material = textOf(job.pages);
      if (material.trim().isEmpty) continue;
      final found = await ai.findVisualTopics(
        topic: wish,
        material: material,
        maxTopics: (job.pages.length / 2).ceil().clamp(4, 15),
      );
      for (final t in found) {
        final pages = [
          for (final p in t.pages)
            if (job.pages.contains(p)) p,
        ]..sort();
        final own = textOf(pages.isEmpty ? job.pages : pages);
        topics.add((
          title: t.title,
          summary: t.summary,
          how: t.how,
          visual: t.visual,
          source: [job.name, pagesLabel(pages)].where((s) => s.isNotEmpty).join(', '),
          material: own.length > CourseUnit.maxMaterialChars ? own.substring(0, CourseUnit.maxMaterialChars) : own,
        ));
      }
    }
    onProgress?.call(jobs.length, jobs.length);
    return topics;
  }

  /// Schritt 2: die KI ordnet die Themen; daraus der Lernpfad.
  Future<VisualCourse> plan(
    List<CourseTopic> topics, {
    required String moduleId,
    String wish = '',
    String detail = 'normal',
    VisualStyle style = VisualStyle.explain,
  }) async {
    final json = await ai.planVisualCourse(
      topics: [
        for (final (i, t) in topics.indexed)
          {
            'n': i + 1,
            'title': t.title,
            if (t.summary.isNotEmpty) 'summary': t.summary,
            if (t.how.isNotEmpty) 'how': t.how,
            'source': t.source,
            if (!t.visual) 'visual': false,
          },
      ],
      wish: wish,
    );
    return courseFromPlan(json, topics, moduleId: moduleId, detail: detail, style: style);
  }

  /// Plan der KI → Lernpfad. Unbekannte Nummern fallen weg, doppelte zählen
  /// einmal; "needs" nur auf frühere Themen.
  static VisualCourse courseFromPlan(
    Map<String, dynamic> json,
    List<CourseTopic> topics, {
    required String moduleId,
    String detail = 'normal',
    VisualStyle style = VisualStyle.explain,
    DateTime? now,
  }) {
    int? n(Object? raw) {
      final v = raw is num ? raw.toInt() : int.tryParse('$raw');
      return v != null && v >= 1 && v <= topics.length ? v : null;
    }

    final used = <int>{};
    final units = <CourseUnit>[];
    for (final raw in (json['units'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final main = n(raw['n']);
      if (main == null || used.contains(main)) continue;
      final merged = [
        main,
        if (raw['merge'] is List)
          for (final m in raw['merge'] as List)
            if (n(m) case final v? when v != main && !used.contains(v)) v,
      ];
      used.addAll(merged);
      final parts = [for (final m in merged) topics[m - 1]];
      final known = {for (final u in units) u.id};
      final material = parts.map((t) => t.material).where((m) => m.isNotEmpty).join('\n\n');
      units.add(
        CourseUnit(
          id: 'u$main',
          title: '${raw['title'] ?? ''}'.trim().isEmpty ? parts.first.title : '${raw['title']}'.trim(),
          summary: parts.map((t) => t.summary).where((s) => s.isNotEmpty).join(' '),
          how: parts.first.how,
          bridge: '${raw['bridge'] ?? ''}'.trim(),
          needs: [
            if (raw['needs'] is List)
              for (final x in raw['needs'] as List)
                if (n(x) case final v? when known.contains('u$v')) 'u$v',
          ],
          source: parts.map((t) => t.source).toSet().join(' · '),
          material: material.length > CourseUnit.maxMaterialChars
              ? material.substring(0, CourseUnit.maxMaterialChars)
              : material,
        ),
      );
    }
    if (units.isEmpty) throw AiServiceException('Der Lernpfad ist leer – bitte erneut versuchen.');
    return VisualCourse(
      id: const Uuid().v4(),
      moduleId: moduleId,
      title: '${json['title'] ?? ''}'.trim().isEmpty ? 'Lernpfad' : '${json['title']}'.trim(),
      intro: '${json['intro'] ?? ''}'.trim(),
      units: units,
      detail: detail,
      style: style,
      createdAt: now ?? DateTime.now(),
    );
  }

  /// Was die KI für die Lektion des Themas [index] über den Pfad wissen muss:
  /// Stellung, Übergang und die früheren Themen, auf denen es aufbaut (mit
  /// deren Kurzfassung, sofern die Lektion schon existiert).
  static String contextFor(VisualCourse course, int index, Map<String, VisualLesson> lessons) {
    final unit = course.units[index];
    final out = StringBuffer()
      ..writeln('Lernpfad „${course.title}“ – Thema ${index + 1} von ${course.units.length}: ${unit.title}');
    if (unit.bridge.isNotEmpty) out.writeln('Übergang laut Plan: ${unit.bridge}');
    final basis = course.basisOf(index);
    if (basis.isEmpty) {
      out.writeln('Erstes Thema – Rückblick: was man aus der Schule/dem Vorwissen braucht.');
    } else {
      out.writeln('Frühere Themen, auf denen es aufbaut:');
      for (final b in basis) {
        final lesson = b.lessonId == null ? null : lessons[b.lessonId];
        final short = lesson?.shortVersion;
        final gist = short != null && short.text.isNotEmpty
            ? short.text.replaceAll('\n', ' ')
            : (b.summary.isEmpty ? '' : b.summary);
        out.writeln('- ${b.title}${gist.isEmpty ? '' : ': $gist'}');
      }
    }
    if (index + 1 < course.units.length) out.writeln('Danach kommt: ${course.units[index + 1].title}');
    return out.toString();
  }

  /// Schritt 3: die Lektion zu Thema [index] (Rückblick, Kurzfassung).
  Future<VisualLesson> lessonFor(VisualCourse course, int index, Map<String, VisualLesson> lessons) async {
    final unit = course.units[index];
    final raws = await ai.generateVisualLessons(
      topic: [
        'Thema: ${unit.title}',
        if (unit.summary.isNotEmpty) 'Worum es geht: ${unit.summary}',
        if (unit.how.isNotEmpty) 'Idee zur Darstellung: ${unit.how}',
      ].join('\n'),
      material: unit.material,
      detail: course.detail,
      socratic: course.style == VisualStyle.socratic,
      courseContext: contextFor(course, index, lessons),
    );
    final lesson = [
      for (final raw in raws)
        ?VisualLesson.fromMap(
          raw,
          id: const Uuid().v4(),
          moduleId: course.moduleId,
          createdAt: DateTime.now(),
          source: unit.source,
          detail: course.detail,
          style: course.style,
          courseId: course.id,
        ),
    ].map(VisualMath.sanitize).where((l) => l.isUsable).firstOrNull;
    if (lesson == null) {
      throw AiServiceException('Die KI-Antwort ließ sich nicht als Lektion lesen – bitte erneut versuchen.');
    }
    return lesson;
  }
}
