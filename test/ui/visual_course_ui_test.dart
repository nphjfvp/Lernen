import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/repositories/visual_course_repository.dart';
import 'package:lernen/repositories/visual_lesson_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/visual/visual_course_screen.dart';
import 'package:lernen/ui/visual/visual_learn_screen.dart';
import 'package:lernen/ui/visual/visual_lesson_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../services/visual_diagram_test.dart' show latticeScene;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SettingsWithKey extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

Uint8List _pdf(List<String> pages) {
  final document = PdfDocument();
  for (final text in pages) {
    document.pages.add().graphics.drawString(
      text,
      PdfStandardFont(PdfFontFamily.helvetica, 11),
      bounds: const Rect.fromLTWH(0, 0, 500, 700),
    );
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

Map<String, dynamic> _lesson(String title) => {
  'title': title,
  'recap': 'Bei den Atomen haben wir gesehen, dass sie sich ordnen – das brauchen wir jetzt.',
  'steps': [
    {
      'title': 'Schritt zu $title',
      'text': 'Erklärung zu $title.',
      'show': {'scene': latticeScene()},
    },
  ],
  'short': {'title': 'Kurzfassung', 'text': '• Kernpunkt zu $title\n• Zweiter Punkt', 'formula': r'a = 2r'},
};

void main() {
  late List<String> requests;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_visual_course_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  setUp(() => requests = []);

  tearDown(() {
    VisualCourseCreateScreen.aiFactory = null;
    VisualCourseCreateScreen.pickPdfHook = null;
  });

  Future<void> settle(WidgetTester tester, [int rounds = 10]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  testWidgets('Lernpfad: zwei Vorlesungen → Themen → geordnet, Rückblick, Kurzfassung, abschließen, weiter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    VisualCourseCreateScreen.aiFactory = (key, model) => AiService(
      apiKey: key,
      model: model,
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final user = '${(body['messages'] as List)[1]['content']}';
        requests.add(user);
        final Object reply;
        if (user.startsWith('Höchstens')) {
          reply = user.contains('V1.pdf')
              ? {
                  'topics': [
                    {
                      'title': 'Atome',
                      'summary': 'Aufbau der Atome.',
                      'pages': [1],
                      'how': 'Kugeln',
                      'visual': true,
                    },
                    {
                      'title': 'Organisatorisches',
                      'pages': [2],
                      'visual': false,
                      'reason': 'Termine',
                    },
                  ],
                }
              : {
                  'topics': [
                    {
                      'title': 'Gitter',
                      'summary': 'kfz und krz.',
                      'pages': [1, 2],
                      'how': '3D-Zelle',
                      'visual': true,
                    },
                  ],
                };
        } else if (user.startsWith('Wunsch') || user.startsWith('Themen')) {
          reply = {
            'title': 'Werkstoffkunde I',
            'intro': 'Vom Atom zum Gitter.',
            'units': [
              {'n': 1, 'bridge': 'Grundlage.'},
              {'n': 2, 'bridge': 'Nur Termine.'},
              {
                'n': 3,
                'bridge': 'Atome ordnen sich im Gitter.',
                'needs': [1],
              },
            ],
          };
        } else {
          reply = {
            'lessons': [_lesson(user.contains('Thema: Gitter') ? 'Gitter' : 'Atome')],
          };
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(reply)},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final uploads = [
      (name: 'V1.pdf', bytes: _pdf(['Atome: Kern und Hülle', 'Termine der Übung'])),
      (name: 'V2.pdf', bytes: _pdf(['Gitter: kfz', 'Gitter: krz'])),
    ];
    VisualCourseCreateScreen.pickPdfHook = () async => uploads.removeAt(0);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey()),
          ChangeNotifierProvider<VisualLessonRepository>(create: (_) => VisualLessonRepository()),
          ChangeNotifierProvider<VisualCourseRepository>(create: (_) => VisualCourseRepository()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const VisualLearnScreen(moduleId: 'mk', moduleName: 'Werkstoffkunde'),
        ),
      ),
    );
    await settle(tester);
    await tap(tester, 'visual-course-new');
    expect(find.byType(VisualCourseCreateScreen), findsOneWidget);
    await tap(tester, 'course-upload');
    await tap(tester, 'course-upload');
    expect(find.text('V1.pdf'), findsOneWidget);
    expect(find.text('V2.pdf'), findsOneWidget);
    await tester.tap(find.text('Ausführlich'));
    await tester.pump();

    await tap(tester, 'course-plan');
    await settle(tester, 20);
    expect(requests.where((r) => r.startsWith('Höchstens')), hasLength(2), reason: 'je Vorlesung ein Abschnitt');
    expect(requests[0], contains('--- V1.pdf, Seite 1 ---'));
    final planRequest = requests[2];
    expect(planRequest, contains('"title":"Gitter"'));
    expect(planRequest, contains('"source":"V2.pdf, S. 1–2"'));
    expect(find.text('Werkstoffkunde I'), findsOneWidget);
    expect(find.byKey(const ValueKey('course-preview-2')), findsOneWidget);

    // „Organisatorisches“ weglassen.
    await tap(tester, 'course-unit-remove-1');
    expect(find.text('Lernpfad mit 2 Themen speichern'), findsOneWidget);
    await tap(tester, 'course-save');
    expect(find.byType(VisualCourseScreen), findsOneWidget);
    expect(find.textContaining('0 von 2 Themen erledigt'), findsOneWidget);
    expect(find.textContaining('baut auf Thema 1 auf'), findsOneWidget);

    // Starten: Lektion zu Thema 1 entsteht, mit Rückblick und Kurzfassung.
    await tap(tester, 'course-continue');
    await settle(tester, 20);
    final first = requests.last;
    expect(first, contains('LERNPFAD'));
    expect(first, contains('Thema 1 von 2: Atome'));
    expect(first, contains('Detailgrad: ausführlich'));
    expect(first, contains('--- V1.pdf, Seite 1 ---'));
    expect(find.byType(VisualLessonScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-recap')), findsOneWidget);
    await tester.tap(find.text('Kurzfassung'));
    await tester.pump();
    expect(find.textContaining('Kernpunkt zu Atome'), findsOneWidget);
    expect(find.byKey(const ValueKey('visual-short-finish')), findsOneWidget);
    await tester.tap(find.text('Ausführlich'));
    await tester.pump();
    await tap(tester, 'visual-finish');
    await settle(tester);
    expect(find.byType(VisualLessonScreen), findsNothing);
    expect(find.textContaining('1 von 2 Themen erledigt'), findsOneWidget);
    expect(find.byKey(const ValueKey('course-short-0')), findsOneWidget);

    // Weiter mit Thema 2: Rückblick auf Thema 1 mit dessen Kurzfassung.
    expect(find.textContaining('Weiter mit „Gitter“'), findsOneWidget);
    await tap(tester, 'course-continue');
    await settle(tester, 20);
    final second = requests.last;
    expect(second, contains('Thema 2 von 2: Gitter'));
    expect(second, contains('- Atome: • Kernpunkt zu Atome'));
    expect(second, contains('Übergang laut Plan: Atome ordnen sich im Gitter.'));
    expect(find.text('Lernpfad abschließen'), findsOneWidget);
    await tap(tester, 'visual-finish');
    await settle(tester);
    expect(find.textContaining('2 von 2 Themen erledigt'), findsOneWidget);
    expect(find.textContaining('Alles geschafft'), findsOneWidget);

    // Kurzfassung direkt aus dem Pfad – ohne neue Anfrage.
    final before = requests.length;
    await tap(tester, 'course-short-0');
    expect(find.byKey(const ValueKey('visual-short')), findsOneWidget);
    expect(requests.length, before);
    await tester.pageBack();
    await settle(tester);

    // Zurück in „Visuell lernen“: Pfad gelistet, seine Lektionen nicht doppelt.
    await tester.pageBack();
    await settle(tester);
    expect(find.byKey(const ValueKey('visual-course-0')), findsOneWidget);
    expect(find.textContaining('2 von 2 Themen erledigt'), findsOneWidget);
    expect(find.text('Noch keine – erstelle oben die erste.'), findsOneWidget);

    // Löschen samt Lektionen.
    await tap(tester, 'visual-course-0');
    await tap(tester, 'course-delete');
    await tap(tester, 'course-delete-confirm');
    await settle(tester, 20);
    expect(find.byType(VisualCourseScreen), findsNothing);
    expect(find.byKey(const ValueKey('visual-course-0')), findsNothing);
    final lessons = await tester.runAsync(() => VisualLessonRepository().forModule('mk'));
    expect(lessons, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
