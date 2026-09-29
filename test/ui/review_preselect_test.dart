import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/models/lecture_unit.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/repositories/lecture_unit_repository.dart';
import 'package:lernen/repositories/material_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/review/review_screen.dart';
import 'package:provider/provider.dart';

class _Materials extends MaterialRepository {
  _Materials(this.items);
  final List<MaterialItem> items;

  @override
  List<MaterialItem> forModule(String moduleId) => [for (final m in items) if (m.moduleId == moduleId) m];

  @override
  Future<void> loadForModule(String moduleId) async {}
}

class _Units extends LectureUnitRepository {
  @override
  List<LectureUnit> forModule(String moduleId) => const [];

  @override
  Future<void> loadForModule(String moduleId) async {}
}

class _Settings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings(openRouterApiKey: 'sk-test');
}

MaterialItem _material(String id, String name, String text) => MaterialItem(
      id: id,
      moduleId: 'm1',
      fileName: name,
      kind: MaterialKind.slide,
      extractedText: text,
      createdAt: DateTime(2026, 9, 1),
    );

void main() {
  testWidgets('Nachbereiten: vorgewählte Materialien (z.B. vom Laborversuch) sind gleich als Folien eingetragen',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MaterialRepository>.value(
          value: _Materials([
            _material('t1', 'Theorie.pdf', 'Vorbereitungsaufgabe 1: Wozu dient der Trigger?'),
            _material('g1', 'Durchfuehrung.pdf', 'Schritt 1: Tastkopf anschließen'),
            _material('x', 'Anderes.pdf', 'Nicht gewählt'),
            _material('leer', 'Leer.pdf', '   '),
          ]),
        ),
        ChangeNotifierProvider<LectureUnitRepository>.value(value: _Units()),
        ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: const ReviewScreen(moduleId: 'm1', initialSlideMaterialIds: ['t1', 'g1', 'leer', 'gibt-es-nicht']),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Theorie.pdf'), findsOneWidget);
    expect(find.text('Durchfuehrung.pdf'), findsOneWidget);
    expect(find.text('Anderes.pdf'), findsNothing);
    // Ohne Text lässt sich nichts erstellen – nicht übernommen.
    expect(find.text('Leer.pdf'), findsNothing);
  });
}
