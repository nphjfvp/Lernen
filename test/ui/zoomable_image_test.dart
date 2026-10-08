import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/widgets/zoomable_image.dart';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 40, 20), ui.Paint()..color = const ui.Color(0xFF0000FF));
  final image = await recorder.endRecording().toImage(40, 20);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  testWidgets('Bild antippen öffnet es groß, Schließen geht zurück', (tester) async {
    final png = (await tester.runAsync(_png))!;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(body: Center(child: ZoomableImage(bytes: png))),
    ));
    // Das Bild wird echt dekodiert – erst danach hat es eine Größe.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('zoomable-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-fullscreen')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-fullscreen-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-fullscreen')), findsNothing);
  });
}
