import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/module_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/claude_inbox.dart';
import 'package:lernen/services/sync_codes.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/inbox/claude_inbox_screen.dart';
import 'package:lernen/ui/inbox/claude_inbox_settings.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _FakeInbox implements InboxBackend {
  final items = <String, Map<String, dynamic>>{};
  final deleted = <String>[];
  String? askedCode;

  @override
  Future<List<(String, Map<String, dynamic>)>> list(String code) async {
    askedCode = code;
    return [for (final e in items.entries) (e.key, e.value)];
  }

  @override
  Future<void> delete(String code, String id) async {
    deleted.add(id);
    items.remove(id);
  }
}

class _Settings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(inboxCode: 'abcd-efgh-jkmn-pqrs');
}

class _Modules extends ModuleRepository {
  @override
  List<Module> get modules => [
    Module(id: 'm1', name: 'Mathe', colorValue: 0xFF336699, icon: 'calc', examDate: null, createdAt: DateTime(2026)),
    Module(
      id: 'm2',
      name: 'Werkstoffkunde',
      colorValue: 0xFF336699,
      icon: 'science',
      examDate: null,
      createdAt: DateTime(2026),
    ),
  ];
}

class _RecordingCards extends FlashcardRepository {
  final saved = <Flashcard>[];

  @override
  Future<void> saveAll(List<Flashcard> cards) async => saved.addAll(cards);
}

final _payload = jsonEncode({
  'flashcards': [
    {
      'type': 'single_choice',
      'front': 'Welche Koordinationszahl hat das kfz-Gitter?',
      'options': [
        {'text': '12', 'isCorrect': true},
        {'text': '8', 'isCorrect': false},
      ],
      'back': '12',
    },
    {'type': 'flashcard', 'front': 'Was ist die Packungsdichte?', 'back': 'Volumenanteil der Atome in der Zelle.'},
  ],
});

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_inbox_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });
  tearDown(() => ClaudeInbox.testBackend = null);

  test('Lieferungen lesen: Titel, Fach, Zeit, ohne Aufgaben-Text verworfen, neueste zuerst', () async {
    final fake = _FakeInbox()
      ..items['alt'] = {'title': 'Blatt 1', 'payload': _payload, 'createdAt': '2026-10-01T10:00:00Z'}
      ..items['neu'] = {
        'title': ' Blatt 2 ',
        'subject': 'Werkstoffkunde',
        'payload': _payload,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 20)),
      }
      ..items['leer'] = {'title': 'Kaputt'};
    final list = await ClaudeInbox(backend: fake).fetch('abcd-efgh-jkmn-pqrs');
    expect(list.map((d) => d.id), ['neu', 'alt']);
    expect(list.first.title, 'Blatt 2');
    expect(list.first.subject, 'Werkstoffkunde');
    expect(list.first.taskCount, 2);
    expect(InboxDelivery.fromMap('x', {'payload': 'kein json'})!.taskCount, 0);
    expect(InboxDelivery.fromMap('x', {'payload': _payload})!.title, 'Lieferung');
  });

  testWidgets('Postfach: Lieferung ansehen, Fach nach Vorschlag, im Import speichern – danach gelöscht', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _FakeInbox()
      ..items['d1'] = {
        'title': 'Übungsblatt 3',
        'subject': 'Werkstoffe',
        'note': 'Kristallgitter, zwei Fragen.',
        'payload': _payload,
      };
    ClaudeInbox.testBackend = fake;
    final cards = _RecordingCards();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
          ChangeNotifierProvider<ModuleRepository>.value(value: _Modules()),
          ChangeNotifierProvider<FlashcardRepository>.value(value: cards),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const ClaudeInboxScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fake.askedCode, 'abcd-efgh-jkmn-pqrs');
    expect(find.text('Übungsblatt 3'), findsOneWidget);
    expect(find.textContaining('2 Aufgaben · für Werkstoffe'), findsOneWidget);
    expect(find.text('Kristallgitter, zwei Fragen.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inbox-take-0')));
    await tester.pumpAndSettle();
    expect(find.text('Claude schlägt „Werkstoffe“ vor.'), findsOneWidget);
    expect(find.text('Werkstoffkunde'), findsOneWidget, reason: 'passendes Fach vorausgewählt');
    await tester.tap(find.byKey(const ValueKey('inbox-module-ok')));
    await tester.pumpAndSettle();

    expect(find.text('2 Aufgaben zum Übernehmen'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('task-import-save')));
    await tester.tap(find.byKey(const ValueKey('task-import-save')));
    await tester.pumpAndSettle();

    expect(cards.saved, hasLength(2));
    expect(cards.saved.every((c) => c.moduleId == 'm2'), isTrue);
    expect(fake.deleted, ['d1']);
    expect(find.textContaining('2 Aufgaben gespeichert'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-empty')), findsOneWidget);
  });

  testWidgets('Verwerfen löscht ohne zu übernehmen', (tester) async {
    final fake = _FakeInbox()..items['d1'] = {'title': 'Doppelt', 'payload': _payload};
    ClaudeInbox.testBackend = fake;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
          ChangeNotifierProvider<ModuleRepository>.value(value: _Modules()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const ClaudeInboxScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inbox-discard-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verwerfen').last);
    await tester.pumpAndSettle();
    expect(fake.deleted, ['d1']);
    expect(find.byKey(const ValueKey('inbox-empty')), findsOneWidget);
  });

  test('Postfach-Code: geheim wie der API-Key, nie durch einen leeren Cloud-Wert gelöscht', () {
    const settings = AppSettings(inboxCode: 'abcd-efgh-jkmn-pqrs');
    expect(syncedSettingsOf(settings, includeSecrets: true)['inboxCode'], 'abcd-efgh-jkmn-pqrs');
    expect(syncedSettingsOf(settings, includeSecrets: false)['inboxCode'], isNull);
    expect(mergeAiSettings(const AppSettings(), {'inboxCode': 'neu-neu-neu-neu-neu'}).inboxCode, 'neu-neu-neu-neu-neu');
    expect(mergeAiSettings(settings, {'inboxCode': null}).inboxCode, 'abcd-efgh-jkmn-pqrs');
    expect(syncedAiSettingsForPull({'inboxCode': 'x'}, acceptApiKey: false)['inboxCode'], isNull);
    expect(AppSettings.fromMap(settings.toMap()).inboxCode, 'abcd-efgh-jkmn-pqrs');
    expect(settings.copyWith(inboxCode: '').inboxCode, isNull, reason: 'leer = entfernen');
    expect(settings.copyWith().inboxCode, 'abcd-efgh-jkmn-pqrs');
  });

  testWidgets('Einstellungen: Code erzeugen, anzeigen, Postfach öffnen', (tester) async {
    ClaudeInbox.testBackend = _FakeInbox();
    final settings = SettingsRepository();
    await tester.runAsync(() => settings.update(const AppSettings()));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          ChangeNotifierProvider<ModuleRepository>.value(value: _Modules()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppColors.light]),
          home: const Scaffold(body: ClaudeInboxSettings()),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('inbox-code')), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('inbox-generate')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final code = settings.settings.inboxCode!;
    expect(SyncCodes.isStrong(code), isTrue);
    expect(find.text(code), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('inbox-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-empty')), findsOneWidget);
  });
}
