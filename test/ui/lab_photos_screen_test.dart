import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/models/lab_photo.dart';
import 'package:lernen/repositories/lab_experiment_repository.dart';
import 'package:lernen/repositories/lab_photo_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/lab/lab_photo_strip.dart';
import 'package:lernen/ui/lab/lab_photos_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SettingsWithKey extends SettingsRepository {
  _SettingsWithKey({this.withKey = true});
  final bool withKey;

  @override
  AppSettings get settings => AppSettings(openRouterApiKey: withKey ? 'sk-test' : null);
}

http.Response _chat(String content) => http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'content': content},
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

LabExperiment _experiment(String id, String title) => LabExperiment.fromStructure(
      {
        'title': title,
        'parts': [
          {
            'title': 'Grundeinstellungen',
            'tables': [
              {
                'title': 'Messwerte',
                'columns': ['Frequenz', 'Amplitude'],
                'rows': [
                  ['1 kHz', ''],
                  ['2 kHz', ''],
                ],
              },
            ],
          },
        ],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: id,
    );

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_lab_photos_ui_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  tearDown(() {
    LabPhotosScreen.aiFactory = null;
    LabPhotosScreen.pickImagesHook = null;
  });

  late LabExperimentRepository labs;
  late LabPhotoRepository photos;

  Future<void> pump(WidgetTester tester, Widget home, {List<LabExperiment> experiments = const [], bool withKey = true}) async {
    tester.view.physicalSize = const Size(900, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = await tester.runAsync(() => databaseFactoryMemory.openDatabase('photos_ui_${DateTime.now().microsecondsSinceEpoch}'));
    labs = LabExperimentRepository(openDatabase: () async => db!);
    photos = LabPhotoRepository(openDatabase: () async => db!);
    for (final e in experiments) {
      await tester.runAsync(() => labs.save(e));
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LabExperimentRepository>.value(value: labs),
        ChangeNotifierProvider<LabPhotoRepository>.value(value: photos),
        ChangeNotifierProvider<SettingsRepository>.value(value: _SettingsWithKey(withKey: withKey)),
      ],
      child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: home),
    ));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> addPhoto(WidgetTester tester) async {
    LabPhotosScreen.pickImagesHook = () async => [(name: 'protokoll.png', bytes: _tinyPng)];
    await tester.tap(find.byKey(const ValueKey('lab-photos-pick')));
    // Das Verkleinern des Bildes läuft in der echten Engine.
    for (var i = 0; i < 40 && find.byKey(const ValueKey('lab-photo-0')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('lab-photo-0')), findsOneWidget);
  }

  testWidgets('Foto: KI ordnet zu, Werte werden gezeigt, Übernehmen trägt sie ein und legt das Foto beim Versuch ab',
      (tester) async {
    final osc = _experiment('lab-osc-0001', 'Oszilloskop');
    final other = _experiment('lab-dio-0002', 'Diode');
    late Map<String, dynamic> request;
    LabPhotosScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            request = jsonDecode(r.body) as Map<String, dynamic>;
            return _chat(jsonEncode({
              'description': 'Messprotokoll Oszilloskop',
              'experimentId': osc.id,
              'partId': osc.parts.first.id,
              'confidence': 'hoch',
              'cells': [
                {'table': 1, 'row': 1, 'col': 2, 'value': '2,0 V'},
                {'table': 1, 'row': 2, 'col': 2, 'value': '3,9 V'},
              ],
              'notes': 'Tastkopf 10:1',
              'unclear': ['Zeile 3 unleserlich'],
            }));
          }),
        );
    await pump(tester, const LabPhotosScreen(moduleId: 'm1', moduleName: 'ET'), experiments: [osc, other]);
    await addPhoto(tester);

    await tester.tap(find.byKey(const ValueKey('lab-photos-read')));
    await settle(tester);

    // Die KI sieht beide Versuche und Zeilen ab 1.
    final content = ((request['messages'] as List).last['content']) as List;
    final prompt = (content.first as Map)['text'] as String;
    expect(prompt, contains('VERSUCH lab-osc-0001: Oszilloskop'));
    expect(prompt, contains('VERSUCH lab-dio-0002: Diode'));
    expect(prompt, contains('Zeile 1: 1 kHz | ·'));
    expect(content.last, containsPair('type', 'image_url'));

    expect(find.text('Messprotokoll Oszilloskop'), findsOneWidget);
    expect(find.text('2,0 V'), findsOneWidget);
    expect(find.text('Messwerte · Zeile 1 · Amplitude'), findsOneWidget);
    expect(find.textContaining('Zeile 3 unleserlich'), findsOneWidget);
    expect(find.textContaining('Tastkopf 10:1'), findsOneWidget);

    // Einen Wert abwählen: er wird nicht eingetragen.
    await tester.tap(find.byKey(const ValueKey('lab-photo-cell-0-0-1-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lab-photo-apply-0')));
    await settle(tester);

    expect(find.textContaining('Übernommen: 1 Wert'), findsOneWidget);
    final saved = labs.byId(osc.id)!;
    final table = saved.parts.first.tables.single;
    expect(table.rows[0][1], '2,0 V');
    expect(table.rows[1][1], '');
    expect(saved.parts.first.notes, contains('Tastkopf 10:1'));
    final stored = await tester.runAsync(() => photos.forExperiment(osc.id));
    expect(stored, hasLength(1));
    expect(stored!.single.partId, osc.parts.first.id);
    expect(stored.single.description, 'Messprotokoll Oszilloskop');
    expect(labs.byId(other.id)!.parts.first.tables.single.rows[0][1], '');
  });

  testWidgets('keine sichere Zuordnung: Hinweis, Übernehmen erst nach Wahl des Versuchs', (tester) async {
    final osc = _experiment('lab-osc-0001', 'Oszilloskop');
    final other = _experiment('lab-dio-0002', 'Diode');
    LabPhotosScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async => _chat(jsonEncode({
                'description': 'Unscharfes Foto',
                'experimentId': null,
                'cells': [
                  {'table': 1, 'row': 1, 'col': 2, 'value': '2,0 V'},
                ],
              }))),
        );
    await pump(tester, const LabPhotosScreen(moduleId: 'm1', moduleName: 'ET'), experiments: [osc, other]);
    await addPhoto(tester);
    await tester.tap(find.byKey(const ValueKey('lab-photos-read')));
    await settle(tester);

    expect(find.textContaining('keinem Versuch sicher zuordnen'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lab-photo-apply-0'))).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('lab-photo-exp-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diode').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lab-photo-apply-0'))).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('lab-photo-apply-0')));
    await settle(tester);

    // Anderes Ziel als das der KI: nichts in die Tabelle, nur das Foto liegt beim Versuch.
    expect(labs.byId(other.id)!.parts.first.tables.single.rows[0][1], '');
    expect(await tester.runAsync(() => photos.forExperiment(other.id)), hasLength(1));
  });

  testWidgets('nur ein Versuch (aus dem Versuch geöffnet): die KI sieht nur ihn', (tester) async {
    final osc = _experiment('lab-osc-0001', 'Oszilloskop');
    final other = _experiment('lab-dio-0002', 'Diode');
    late String prompt;
    LabPhotosScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async {
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            prompt = ((((body['messages'] as List).last['content']) as List).first as Map)['text'] as String;
            return _chat(jsonEncode({'description': 'Foto', 'experimentId': null, 'notes': 'U = 5 V'}));
          }),
        );
    await pump(tester, LabPhotosScreen(moduleId: 'm1', moduleName: 'ET', experimentId: osc.id), experiments: [osc, other]);
    await addPhoto(tester);
    await tester.tap(find.byKey(const ValueKey('lab-photos-read')));
    await settle(tester);
    expect(prompt, contains('Oszilloskop'));
    expect(prompt, isNot(contains('Diode')));
    // Der eine Versuch ist vorgewählt.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lab-photo-apply-0'))).onPressed, isNotNull);
  });

  testWidgets('Fehler der KI: Meldung mit erneutem Versuch; ohne Key ist Auslesen aus', (tester) async {
    final osc = _experiment('lab-osc-0001', 'Oszilloskop');
    LabPhotosScreen.aiFactory = (key, model) => AiService(
          apiKey: key,
          model: model,
          client: MockClient((r) async => _chat('kein json')),
        );
    await pump(tester, const LabPhotosScreen(moduleId: 'm1', moduleName: 'ET'), experiments: [osc]);
    await addPhoto(tester);
    await tester.tap(find.byKey(const ValueKey('lab-photos-read')));
    await settle(tester);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Antwort der KI'), findsOneWidget);
  });

  testWidgets('ohne Versuche und ohne Key: der Grund steht da, Auslesen ist aus', (tester) async {
    await pump(tester, const LabPhotosScreen(moduleId: 'm1', moduleName: 'ET'), withKey: false);
    expect(find.textContaining('Lege zuerst einen Laborversuch an'), findsOneWidget);
    expect(find.textContaining('OpenRouter-Key'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('lab-photos-read'))).onPressed, isNull);
  });

  testWidgets('Fotos eines Versuchs: Streifen zeigt sie, groß ansehen und löschen', (tester) async {
    final osc = _experiment('lab-osc-0001', 'Oszilloskop');
    await pump(tester, Scaffold(body: Builder(builder: (context) => LabPhotoStrip(experiment: osc))), experiments: [osc]);
    expect(find.textContaining('Fotos ('), findsNothing);

    await tester.runAsync(() async {
      await photos.add(LabPhoto(
        id: 'p1',
        experimentId: osc.id,
        moduleId: 'm1',
        base64: base64Encode(_tinyPng),
        createdAt: DateTime(2026, 9, 1),
        partId: osc.parts.first.id,
        description: 'Protokoll',
      ));
    });
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Fotos (1)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('lab-photo-thumb-p1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Grundeinstellungen · Protokoll'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lab-photo-delete')));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Fotos ('), findsNothing);
    expect(await tester.runAsync(() => photos.forExperiment(osc.id)), isEmpty);
  });
}
