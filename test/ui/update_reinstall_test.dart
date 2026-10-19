import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/ui/widgets/update_actions.dart';

void main() {
  testWidgets('Schlüsselwechsel: Hinweis mit Sync-Schritten, „APK herunterladen“ lädt herunter', (tester) async {
    var downloads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReinstallDialog(context, onDownload: () async => downloads++),
            child: const Text('los'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-reinstall')), findsOneWidget);
    expect(find.textContaining('synchronisieren'), findsOneWidget);
    expect(find.textContaining('Laborfotos'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-reinstall-download')));
    await tester.pumpAndSettle();
    expect(downloads, 1);
    expect(find.byKey(const ValueKey('update-reinstall')), findsNothing);
  });
}
