import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/repositories/flashcard_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/database_service.dart';
import 'package:lernen/ui/daily/card_review_mixin.dart';
import 'package:provider/provider.dart';
import 'package:sembast/sembast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Flashcard _card(String id, {String front = 'Frage'}) => Flashcard(
      id: id,
      moduleId: 'm1',
      front: front,
      back: 'Antwort',
      createdAt: DateTime(2026, 9, 26),
      due: DateTime(2026, 9, 26),
    );

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with CardReviewMixin<_Host> {
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_flashcard_repo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  test('loadAll lässt Karten ohne bestehendes Fach weg', () async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.modules.record('m1').put(db, {'id': 'm1', 'name': 'Fach'});
    final repo = FlashcardRepository();
    await repo.saveAll([_card('mit-fach')]);
    await DatabaseService.flashcards.record('verwaist').put(db, {
      ..._card('verwaist').toMap(),
      'moduleId': 'geloescht',
    });

    final ids = (await repo.loadAll()).map((c) => c.id).toSet();
    expect(ids, contains('mit-fach'));
    expect(ids, isNot(contains('verwaist')));
  });

  test('update schreibt bestehende Karten zurück', () async {
    final repo = FlashcardRepository();
    await repo.saveAll([_card('a')]);
    expect(await repo.update(_card('a', front: 'Geändert')), isTrue);
    expect((await repo.loadById('a'))!.front, 'Geändert');
  });

  test('update legt eine inzwischen gelöschte Karte nicht wieder an', () async {
    final repo = FlashcardRepository();
    await repo.saveAll([_card('b')]);
    final staleCopy = (await repo.loadById('b'))!;
    await repo.delete('b', 'm1');

    // Z.B. beantwortet in einer noch laufenden Lernrunde.
    expect(await repo.update(staleCopy), isFalse);
    expect(await repo.loadById('b'), isNull);
    expect(repo.forModule('m1').where((c) => c.id == 'b'), isEmpty);
  });

  testWidgets('recordReview wendet Antworten auf den gespeicherten Stand an, nicht auf eine alte Kopie',
      (tester) async {
    final repo = FlashcardRepository();
    await tester.runAsync(() => repo.saveAll([_card('c')]));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<FlashcardRepository>.value(value: repo),
        ChangeNotifierProvider<SettingsRepository>(create: (_) => SettingsRepository()),
      ],
      child: const MaterialApp(home: _Host()),
    ));
    final host = tester.state<_HostState>(find.byType(_Host));
    final staleCopy = (await tester.runAsync(() => repo.loadById('c')))!;

    // Zweimal mit derselben alten Kopie beantwortet (z.B. Probeklausur, dann
    // "falsche üben"): beide Antworten zählen, keine überschreibt die andere.
    await tester.runAsync(() => host.recordReview(staleCopy, isCorrect: false));
    await tester.runAsync(() => host.recordReview(staleCopy, isCorrect: true));

    final stored = (await tester.runAsync(() => repo.loadById('c')))!;
    expect(stored.reps, 2);
    expect(stored.lapses, 0); // Erste Antwort auf eine neue Karte ist kein Lapse.

    // Gelöschte Karte wird durch eine späte Antwort nicht wieder angelegt –
    // und als gelöscht gemeldet (keine Wiederholungsrunde im Daily Quiz).
    await tester.runAsync(() => repo.delete('c', 'm1'));
    final late = await tester.runAsync(() => host.recordReview(staleCopy, isCorrect: false));
    expect(late!.cardDeleted, isTrue);
    expect(await tester.runAsync(() => repo.loadById('c')), isNull);
  });
}
