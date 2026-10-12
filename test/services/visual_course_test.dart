import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/visual_course.dart';
import 'package:lernen/models/visual_lesson.dart';
import 'package:lernen/services/sync_merge.dart';
import 'package:lernen/services/visual_course_service.dart';

CourseTopic _topic(String title, {String source = 'V1.pdf, S. 1', String material = 'Text'}) =>
    (title: title, summary: 'Über $title.', how: 'Szene zu $title', visual: true, source: source, material: material);

void main() {
  final topics = [
    _topic('Atomaufbau'),
    _topic('Gitterstrukturen', source: 'V1.pdf, S. 4–6', material: 'z' * 6000),
    _topic('Packungsdichte', source: 'V2.pdf, S. 1–2', material: 'x' * 6000),
    _topic('Literatur'),
    _topic('Gitterfehler', source: 'V2.pdf, S. 3–5', material: 'y' * 6000),
  ];

  test('Plan der KI → Lernpfad: Reihenfolge, Zusammenlegen, nur frühere Voraussetzungen, Text gekürzt', () {
    final course = VisualCourseService.courseFromPlan(
      {
        'title': 'Werkstoffkunde I',
        'intro': 'Vom Atom zum Gefüge.',
        'units': [
          {'n': 1, 'title': 'Atome und Bindung', 'bridge': 'Grundlage für alles.'},
          {
            'n': 2,
            'merge': [3, 99, 2],
            'bridge': 'Atome ordnen sich im Gitter.',
            'needs': [1, 5],
          },
          {'n': 2, 'title': 'doppelt'},
          {'n': 77},
          {
            'n': 5,
            'needs': [2, 3],
          },
        ],
      },
      topics,
      moduleId: 'm',
      now: DateTime(2026),
    );
    expect(course.title, 'Werkstoffkunde I');
    expect(course.units.map((u) => u.title), ['Atome und Bindung', 'Gitterstrukturen', 'Gitterfehler']);
    final lattice = course.units[1];
    expect(lattice.needs, ['u1'], reason: 'Thema 5 kommt später – keine Voraussetzung');
    expect(lattice.source, 'V1.pdf, S. 4–6 · V2.pdf, S. 1–2');
    expect(lattice.summary, contains('Packungsdichte'));
    expect(lattice.material.length, CourseUnit.maxMaterialChars);
    expect(course.units[2].needs, ['u2'], reason: 'Thema 3 steckt in u2');
    expect(course.units.any((u) => u.title == 'Literatur'), isFalse);

    final back = VisualCourse.fromMap(course.toMap())!;
    expect(back.toMap(), course.toMap());
    expect(back.nextIndex, 0);
    expect(() => VisualCourseService.courseFromPlan({'units': []}, topics, moduleId: 'm'), throwsA(anything));
  });

  test('Rückblick-Kontext: Vorgänger und Voraussetzungen mit deren Kurzfassung', () {
    final course = VisualCourse(
      id: 'c',
      moduleId: 'm',
      title: 'WK',
      createdAt: DateTime(2026),
      units: const [
        CourseUnit(id: 'u1', title: 'Atome', summary: 'Aufbau der Atome', lessonId: 'l1', done: true),
        CourseUnit(id: 'u2', title: 'Gitter', summary: 'kfz, krz'),
        CourseUnit(id: 'u3', title: 'Gitterfehler', bridge: 'Echte Gitter sind nicht perfekt.', needs: ['u1']),
        CourseUnit(id: 'u4', title: 'Verformung'),
      ],
    );
    final lesson = VisualLesson.fromMap({
      'title': 'Atome',
      'steps': [
        {'title': 'a'},
      ],
      'short': {'title': 'Kurzfassung', 'text': '• Kern + Hülle\n• Bindungen'},
      'recap': 'Rückblick',
    }, id: 'l1')!;
    expect(lesson.shortVersion!.text, contains('Kern + Hülle'));
    expect(VisualLesson.fromMap(lesson.toMap())!.recap, 'Rückblick');

    final ctx = VisualCourseService.contextFor(course, 2, {'l1': lesson});
    expect(ctx, contains('Thema 3 von 4: Gitterfehler'));
    expect(ctx, contains('Übergang laut Plan: Echte Gitter sind nicht perfekt.'));
    expect(ctx, contains('- Atome: • Kern + Hülle • Bindungen'), reason: 'Kurzfassung der vorhandenen Lektion');
    expect(ctx, contains('- Gitter: kfz, krz'), reason: 'direkter Vorgänger');
    expect(ctx, contains('Danach kommt: Verformung'));
    expect(VisualCourseService.contextFor(course, 0, const {}), contains('Erstes Thema'));
    expect(course.nextIndex, 1);
    expect(course.basisOf(3).map((u) => u.id), ['u3']);
  });

  test('Abschnitte je PDF und Seitenangaben', () {
    expect(VisualCourseService.windowsOf(['a' * 20000, 'b' * 20000, 'c']).map((w) => w.length), [1, 2]);
    expect(VisualCourseService.pagesLabel([3]), 'S. 3');
    expect(VisualCourseService.pagesLabel([3, 4, 7]), 'S. 3–7');
  });

  test('Abgleich: erledigt auf dem einen, Lektion auf dem anderen Gerät – beides bleibt', () {
    Map<String, dynamic> course(List<Map<String, dynamic>> units) => {
      'id': 'c',
      'moduleId': 'm',
      'title': 'WK',
      'units': units,
      'createdAt': '2026-01-01T00:00:00.000',
    };
    final base = {
      'modules': [
        {'id': 'm', 'name': 'WK'},
      ],
    };
    final local = {
      ...base,
      'visualCourses': [
        course([
          {'id': 'u1', 'title': 'A', 'done': true},
          {'id': 'u2', 'title': 'B'},
        ]),
      ],
    };
    final remote = {
      ...base,
      'visualCourses': [
        course([
          {'id': 'u1', 'title': 'A', 'lessonId': 'l1'},
          {'id': 'u2', 'title': 'B', 'done': true, 'lessonId': 'l2'},
        ]),
      ],
    };
    final merged = mergeSyncPayloads(local: local, remote: remote, base: const {});
    final units = ((merged.payload['visualCourses'] as List).single as Map)['units'] as List;
    expect(units[0], containsPair('done', true));
    expect(units[0], containsPair('lessonId', 'l1'));
    expect(units[1], containsPair('done', true));
    expect(units[1], containsPair('lessonId', 'l2'));
  });
}
