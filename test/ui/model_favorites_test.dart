import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/app_settings.dart';
import 'package:lernen/repositories/model_catalog_repository.dart';
import 'package:lernen/repositories/settings_repository.dart';
import 'package:lernen/services/sync_service.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/widgets/model_override_tile.dart';
import 'package:provider/provider.dart';

/// Einstellungen im Speicher (kein Datenbankzugriff); merkt sich Änderungen.
class _MemorySettings extends SettingsRepository {
  _MemorySettings([this._current = const AppSettings(openRouterApiKey: 'sk-test')]);
  AppSettings _current;

  @override
  AppSettings get settings => _current;

  @override
  Future<void> update(AppSettings settings) async {
    _current = settings;
    notifyListeners();
  }
}

void main() {
  group('AppSettings.favoriteModelIds', () {
    test('standardmäßig keine, Round-Trip behält die Reihenfolge', () {
      expect(const AppSettings().favoriteModelIds, isEmpty);
      final settings = const AppSettings().copyWith(favoriteModelIds: ['b/b', 'a/a']);
      expect(AppSettings.fromMap(settings.toMap()).favoriteModelIds, ['b/b', 'a/a']);
    });

    test('togglen fügt an und entfernt wieder', () {
      var settings = const AppSettings();
      settings = settings.copyWith(favoriteModelIds: settings.favoritesToggled('a/a'));
      settings = settings.copyWith(favoriteModelIds: settings.favoritesToggled('b/b'));
      expect(settings.favoriteModelIds, ['a/a', 'b/b']);
      expect(settings.isFavoriteModel('a/a'), isTrue);
      settings = settings.copyWith(favoriteModelIds: settings.favoritesToggled('a/a'));
      expect(settings.favoriteModelIds, ['b/b']);
      expect(settings.isFavoriteModel('a/a'), isFalse);
    });

    test('ältere oder kaputte Datensätze bleiben lesbar (ohne Doppelte und Leeres)', () {
      expect(AppSettings.fromMap(const {}).favoriteModelIds, isEmpty);
      expect(AppSettings.fromMap({'favoriteModelIds': 'kaputt'}).favoriteModelIds, isEmpty);
      expect(
        AppSettings.fromMap({
          'favoriteModelIds': ['a/a', '', 42, 'a/a', ' b/b '],
        }).favoriteModelIds,
        ['a/a', 'b/b'],
      );
    });

    test('Sync: Favoriten reisen mit; ein älterer Cloud-Stand lässt sie stehen, eine leere Angabe leert sie', () {
      final local = const AppSettings().copyWith(favoriteModelIds: ['a/a']);
      expect(syncedSettingsOf(local, includeSecrets: false)['favoriteModelIds'], ['a/a']);
      expect(mergeAiSettings(local, {'questionModelId': 'x/y'}).favoriteModelIds, ['a/a']);
      expect(mergeAiSettings(local, {'favoriteModelIds': ['c/c', 'a/a']}).favoriteModelIds, ['c/c', 'a/a']);
      expect(mergeAiSettings(local, {'favoriteModelIds': <String>[]}).favoriteModelIds, isEmpty);
    });
  });

  group('Modellwähler mit Favoriten', () {
    Widget host(SettingsRepository? settings, Widget child) => MultiProvider(
          providers: [
            if (settings != null) ChangeNotifierProvider<SettingsRepository>.value(value: settings),
            ChangeNotifierProvider<ModelCatalogRepository>.value(value: ModelCatalogRepository()),
          ],
          child: MaterialApp(theme: ThemeData(extensions: const [AppColors.light]), home: Scaffold(body: child)),
        );

    Widget tile(ValueChanged<String?> onChanged, [String? override]) => ModelOverrideTile(
          defaultId: AppSettings.defaultQuestionModel,
          overrideId: override,
          onChanged: onChanged,
        );

    testWidgets('Stern markiert ein Modell; Favoriten stehen oben unter "Favoriten"', (tester) async {
      final settings = _MemorySettings();
      await tester.pumpWidget(host(settings, tile((_) {})));

      await tester.tap(find.byKey(const ValueKey('model-override')));
      await tester.pumpAndSettle();
      expect(find.text('Favoriten'), findsNothing);
      // Das dritte Modell der Liste als Favorit markieren.
      await tester.tap(find.byKey(const ValueKey('model-fav-anthropic/claude-3.5-haiku')));
      await tester.pumpAndSettle();

      expect(settings.settings.favoriteModelIds, ['anthropic/claude-3.5-haiku']);
      expect(find.text('Favoriten'), findsOneWidget);
      expect(find.text('Alle Modelle'), findsOneWidget);
      // Der Favorit steht jetzt vor dem (ursprünglich ersten) DeepSeek-Modell.
      Finder inList(String text) => find.descendant(of: find.byType(ListView), matching: find.textContaining(text));
      final haiku = tester.getTopLeft(inList('Claude 3.5 Haiku')).dy;
      final deepseek = tester.getTopLeft(inList('DeepSeek')).dy;
      expect(haiku, lessThan(deepseek));

      // Noch einmal tippen: kein Favorit mehr.
      await tester.tap(find.byKey(const ValueKey('model-fav-anthropic/claude-3.5-haiku')));
      await tester.pumpAndSettle();
      expect(settings.settings.favoriteModelIds, isEmpty);
      expect(find.text('Favoriten'), findsNothing);
    });

    testWidgets('Schnellwahl beim Frage erstellen: Favorit antippen wählt es, das Standard-Modell setzt zurück',
        (tester) async {
      final settings = _MemorySettings(const AppSettings(
        openRouterApiKey: 'sk-test',
        favoriteModelIds: ['anthropic/claude-3.5-haiku', AppSettings.defaultQuestionModel, 'gibt/es-nicht'],
      ));
      String? override;
      await tester.pumpWidget(host(
        settings,
        StatefulBuilder(
          builder: (context, setState) => tile((id) => setState(() => override = id), override),
        ),
      ));

      // Nur Favoriten, die es im Katalog gibt.
      expect(find.byKey(const ValueKey('model-fav-chip-anthropic/claude-3.5-haiku')), findsOneWidget);
      expect(find.byKey(const ValueKey('model-fav-chip-gibt/es-nicht')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('model-fav-chip-anthropic/claude-3.5-haiku')));
      await tester.pumpAndSettle();
      expect(override, 'anthropic/claude-3.5-haiku');
      expect(find.text('KI-Modell für diese Aktion'), findsOneWidget);

      // Das Standard-Modell als Favorit: wählen = zurück auf "Standard".
      await tester.tap(find.byKey(const ValueKey('model-fav-chip-${AppSettings.defaultQuestionModel}')));
      await tester.pumpAndSettle();
      expect(override, isNull);
    });

    testWidgets('ohne Favoriten keine Schnellwahl; ohne Einstellungen im Baum keine Sterne', (tester) async {
      await tester.pumpWidget(host(_MemorySettings(), tile((_) {})));
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.pumpWidget(host(null, tile((_) {})));
      await tester.tap(find.byKey(const ValueKey('model-override')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
      expect(find.textContaining('DeepSeek'), findsWidgets);
    });
  });
}
