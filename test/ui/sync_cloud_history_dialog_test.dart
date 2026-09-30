import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/sync_cloud_history.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/settings/sync_cloud_history_dialog.dart';

class _FakeSync extends SyncService {
  _FakeSync(this.previous, {this.restoreError});

  final List<CloudStateEntry> previous;
  final Object? restoreError;
  CloudStateEntry? restored;

  @override
  bool get isAvailable => true;

  @override
  Future<({CloudSyncMeta? current, List<CloudStateEntry> previous})> cloudHistory(SyncTarget target) async => (
        current: CloudSyncMeta(pushId: 'jetzt', deviceId: 'handy', updatedAt: DateTime(2026, 9, 30, 12), modules: 3, flashcards: 90),
        previous: previous,
      );

  @override
  Future<String> restoreCloudState(SyncTarget target, CloudStateEntry entry, {required String deviceId}) async {
    if (restoreError != null) throw restoreError!;
    restored = entry;
    return 'neue-push-id';
  }
}

Future<String?> _open(WidgetTester tester, _FakeSync sync) async {
  String? result = 'offen';
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(extensions: const [AppColors.light]),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => result = await showDialog<String>(
              context: context,
              builder: (_) => SyncCloudHistoryDialog(service: sync, target: const SyncTarget.account('u'), deviceId: 'handy'),
            ),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Öffnen'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('zeigt den aktuellen und die früheren Stände, Wiederherstellen fragt nach und meldet die neue Kennung', (tester) async {
    bigView(tester);
    final older = CloudStateEntry(pushId: 'p-pc', partCount: 1, deviceId: 'pc', at: DateTime(2026, 9, 29, 21, 30), modules: 4, flashcards: 250);
    final sync = _FakeSync([older]);
    String? result = 'offen';
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showDialog<String>(
                context: context,
                builder: (_) => SyncCloudHistoryDialog(service: sync, target: const SyncTarget.account('u'), deviceId: 'handy'),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Frühere Cloud-Stände'), findsOneWidget);
    expect(find.text('30.09.2026 12:00'), findsOneWidget);
    expect(find.textContaining('3 Fächer, 90 Karten · von diesem Gerät'), findsOneWidget);
    expect(find.text('29.09.2026 21:30'), findsOneWidget);
    expect(find.textContaining('4 Fächer, 250 Karten · von einem anderen Gerät'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cloud-restore-p-pc')));
    await tester.pumpAndSettle();
    expect(find.text('Diesen Cloud-Stand wiederherstellen?'), findsOneWidget);
    expect(find.textContaining('du kannst es also zurücknehmen'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Wiederherstellen'));
    await tester.pumpAndSettle();

    expect(sync.restored?.pushId, 'p-pc');
    expect(result, 'neue-push-id');
  });

  testWidgets('ohne frühere Stände steht ein Hinweis da, ein Fehler beim Wiederherstellen bleibt sichtbar', (tester) async {
    bigView(tester);
    await _open(tester, _FakeSync(const []));
    expect(find.textContaining('Noch keine'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    final failing = _FakeSync(
      [CloudStateEntry(pushId: 'p1', partCount: 1, deviceId: 'pc', at: DateTime(2026, 9, 1), modules: 1, flashcards: 1)],
      restoreError: SyncException('Dieser frühere Stand ist in der Cloud nicht mehr vollständig vorhanden.'),
    );
    await _open(tester, failing);
    await tester.tap(find.byKey(const ValueKey('cloud-restore-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nicht mehr vollständig vorhanden'), findsOneWidget);
    expect(find.text('Frühere Cloud-Stände'), findsOneWidget); // Dialog bleibt offen
  });
}
