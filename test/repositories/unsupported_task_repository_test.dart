import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/repositories/unsupported_task_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('lernen_unsupported_repo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  test('sammeln ohne Doppelte, nach Fach filtern, entfernen, leeren', () async {
    final repo = UnsupportedTaskRepository();
    var notified = 0;
    repo.addListener(() => notified++);

    await repo.add(
      moduleId: 'm1',
      text: 'Skizziere das Diagramm.',
      needs: 'Kurve zeichnen',
      now: DateTime(2026, 10, 1),
    );
    await repo.add(moduleId: 'm1', text: 'Begründe.', now: DateTime(2026, 10, 2));
    await repo.add(moduleId: 'm2', text: 'Skizziere das Diagramm.', now: DateTime(2026, 10, 3));
    // Dieselbe Aufgabe noch einmal: nur Begründung/Bedienart werden aktualisiert.
    final again = await repo.add(moduleId: 'm1', text: ' skizziere  das Diagramm. ', reason: 'Neu gelesen', needs: '');
    expect(notified, greaterThanOrEqualTo(4));
    expect(repo.forModule('m1'), hasLength(2));
    expect(again.reason, 'Neu gelesen');
    expect(again.needs, 'Kurve zeichnen');
    // Neueste zuerst.
    expect(repo.all.map((t) => t.text), ['Skizziere das Diagramm.', 'Begründe.', 'Skizziere das Diagramm.']);

    // Ein zweites Repository liest dasselbe aus der Datenbank.
    final other = UnsupportedTaskRepository();
    await other.load();
    expect(other.forModule('m1').map((t) => t.reason), containsAll(['Neu gelesen', '']));

    await repo.removeText('m1', 'SKIZZIERE das Diagramm.');
    expect(repo.forModule('m1').map((t) => t.text), ['Begründe.']);
    expect(repo.forModule('m2'), hasLength(1));

    await repo.delete(repo.forModule('m1').single.id);
    expect(repo.forModule('m1'), isEmpty);

    await repo.add(moduleId: 'm1', text: 'Noch eine');
    await repo.clear(moduleId: 'm2');
    expect(repo.all.map((t) => t.moduleId), ['m1']);
    await repo.clear();
    expect(repo.all, isEmpty);
  });
}
