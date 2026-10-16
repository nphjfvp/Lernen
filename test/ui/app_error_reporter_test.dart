import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/background_transport.dart';
import 'package:lernen/ui/widgets/app_error_reporter.dart';
import 'package:lernen/ui/widgets/slow_ai_dialog.dart';
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
    final dir = Directory.systemTemp.createTempSync('lernen_crash_guard_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir.path);
  });

  test('Absturz-Notiz: laufende Aufgabe wird beim nächsten Start gefunden, sauber beendete nicht', () async {
    expect(await AiCrashGuard.takePending(), isEmpty);
    final done = await AiCrashGuard.mark(label: 'Fertig', bytes: 10, via: 'Hintergrund');
    await AiCrashGuard.clear(done);
    await AiCrashGuard.mark(
      label: 'Du planst in einer Lern-App einen LERNPFAD',
      bytes: 34000,
      via: 'Hintergrund (Datei)',
    );
    final pending = await AiCrashGuard.takePending();
    expect(pending, hasLength(1));
    expect(pending.single.label, contains('LERNPFAD'));
    expect(await AiCrashGuard.takePending(), isEmpty, reason: 'nur einmal melden');
    final report = aiCrashReport(pending);
    expect(report, contains(aiCrashCode));
    expect(report, contains('33.2 KB'));
    expect(report, contains('Hintergrund (Datei)'));
  });

  testWidgets('Fehler mit Code anzeigen, Details kopieren; Absturz-Meldung beim Start', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: Text('App')),
      ),
    );

    final error = StateError('Ungültiger Zustand im Lernpfad');
    AppErrorReporter.report(error, StackTrace.current);
    AppErrorReporter.report(error, StackTrace.current);
    await tester.pump();
    final code = AppErrorReporter.codeOf(error);
    expect(code, startsWith('APP-'));
    expect(find.textContaining('Fehler $code: Bad state: Ungültiger Zustand'), findsOneWidget, reason: 'nur einmal');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-error-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-error-copy')));
    await tester.pumpAndSettle();
    expect(copied, contains('Fehlercode $code'));

    AppErrorReporter.showAiCrash([
      (label: 'Lernpfad planen – 3 PDFs lesen', bytes: 0, via: 'App', startedAt: DateTime(2026, 10, 16, 14, 3)),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Die App wurde beim letzten Mal beendet'), findsOneWidget);
    expect(find.textContaining(aiCrashCode), findsOneWidget);
    expect(find.textContaining('Lernpfad planen – 3 PDFs lesen'), findsOneWidget);
    expect(find.textContaining('16.10.2026 14:03'), findsOneWidget);
  });
}
