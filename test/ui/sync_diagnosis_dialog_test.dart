import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/sync_diagnostics.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/settings/sync_diagnosis_dialog.dart';

Widget _app(Future<List<DiagLine>> future) => MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(body: SyncDiagnosisDialog(future: future)),
    );

void main() {
  testWidgets('zeigt erst einen Ladehinweis, dann jede Zeile mit Symbol und Erklärung', (tester) async {
    final completer = Completer<List<DiagLine>>();
    await tester.pumpWidget(_app(completer.future));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Prüfe Verbindung'), findsOneWidget);

    completer.complete(const [
      DiagLine(DiagLevel.ok, 'Firebase ist verbunden', 'Projekt lernenwing'),
      DiagLine(DiagLevel.warn, 'Ein anderes Gerät hat neuer hochgeladen', 'Hier „Herunterladen“ drücken.'),
      DiagLine(DiagLevel.error, 'Schreiben in die Cloud ist nicht möglich', 'Regeln nicht veröffentlicht'),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Firebase ist verbunden'), findsOneWidget);
    expect(find.text('Projekt lernenwing'), findsOneWidget);
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('!'), findsOneWidget);
    expect(find.text('✗'), findsOneWidget);
    expect(find.text('Kopieren'), findsOneWidget);
  });

  testWidgets('ein Absturz der Prüfung wird als Fehlerzeile gezeigt', (tester) async {
    final completer = Completer<List<DiagLine>>();
    await tester.pumpWidget(_app(completer.future));
    completer.completeError('kaputt');
    await tester.pumpAndSettle();
    expect(find.text('Die Prüfung ist abgebrochen'), findsOneWidget);
    expect(find.text('kaputt'), findsOneWidget);
  });
}
