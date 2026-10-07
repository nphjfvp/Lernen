import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'repositories/auth_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/concept_repository.dart';
import 'repositories/flashcard_repository.dart';
import 'repositories/lab_experiment_repository.dart';
import 'repositories/lab_photo_repository.dart';
import 'repositories/lecture_unit_repository.dart';
import 'repositories/material_repository.dart';
import 'repositories/model_catalog_repository.dart';
import 'repositories/module_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/summary_repository.dart';
import 'repositories/unsupported_task_repository.dart';
import 'services/auto_sync_service.dart';
import 'services/database_service.dart';
import 'services/sync_backup_service.dart';
import 'services/reminder_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cloud-Sync ist optional: schlägt die Initialisierung fehl, bleibt die
  // App vollständig offline nutzbar. Timeout ist bewusst gesetzt: im Web
  // lädt Firebase sein JS-SDK per dynamischem Import von Googles CDN nach –
  // blockiert das (Firewall, Adblocker, kein Netz), würde die App sonst nie
  // über den Startbildschirm hinauskommen, weil runApp() erst danach läuft.
  //
  // Auf Android/Windows/iOS gibt es dieses CDN-Problem nicht und keinen Grund
  // für eine Frist: läuft die Initialisierung dort einmal länger als 5 Sekunden
  // (kalter Start, Virenscanner), wäre Firebase beim Start "nicht verbunden" –
  // der Auto-Sync startet dann für die ganze Sitzung nicht.
  try {
    final init = Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await (kIsWeb ? init.timeout(const Duration(seconds: 5)) : init);
  } catch (e) {
    debugPrint('Firebase nicht konfiguriert – Cloud-Sync deaktiviert ($e).');
  }

  // Settings werden vor runApp() geladen (schneller lokaler DB-Read), damit
  // die Lernerinnerung direkt beim Start neu geplant werden kann – u.a.
  // wichtig nach einem Geräte-Neustart auf Plattformen ohne Boot-Receiver.
  final settingsRepository = SettingsRepository();
  await settingsRepository.load();
  unawaited(ReminderService().reschedule(settingsRepository.settings));

  // Ebenso VOR runApp() geladen statt per `create: (_) => ModuleRepository()
  // ..load()` im Provider-Baum: RootShell hält alle Haupt-Tabs in einem
  // IndexedStack, das ALLE Screens sofort baut (nicht erst beim Wechseln
  // dorthin) – DailyQuizScreen/StatsScreen lesen `ModuleRepository.modules`
  // dabei nur EINMALIG beim ersten Build (kein `context.watch`, kein erneutes
  // Nachladen), nicht reaktiv. Wäre `load()` beim ersten Build noch nicht
  // fertig, würden sie dauerhaft mit einer leeren Modulliste weiterlaufen –
  // das Daily Quiz hätte dann z.B. für den Rest der Session KEIN Budget für
  // neue Karten (nur fällige Wiederholungen hängen nicht an `modules`),
  // je nachdem wie schnell der lokale DB-Read gegen den ersten Frame lief.
  final moduleRepository = ModuleRepository();
  await moduleRepository.load();

  // Tägliche Sicherung des Lernstands auf diesem Gerät (siehe SyncBackupService):
  // verzögert und im Hintergrund, damit der Start nicht wartet. Fehler dabei
  // sind unwichtig – die Sicherung vor einem Download ist die entscheidende.
  unawaited(Future<void>.delayed(const Duration(seconds: 45), () async {
    try {
      await SyncBackupService.ensureDaily(await DatabaseService.instance.database);
    } catch (e) {
      debugPrint('Tägliche Sicherung fehlgeschlagen ($e).');
    }
  }));

  runApp(LernenApp(settingsRepository: settingsRepository, moduleRepository: moduleRepository));
}

class LernenApp extends StatelessWidget {
  const LernenApp({super.key, required this.settingsRepository, required this.moduleRepository});

  final SettingsRepository settingsRepository;
  final ModuleRepository moduleRepository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthRepository()),
        ChangeNotifierProvider.value(value: moduleRepository),
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider(create: (_) => ChatRepository()),
        ChangeNotifierProvider(create: (_) => UnsupportedTaskRepository()),
        ChangeNotifierProvider(create: (_) => SummaryRepository()),
        ChangeNotifierProvider(create: (_) => ConceptRepository()),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider(create: (_) => LectureUnitRepository()),
        ChangeNotifierProvider(create: (_) => LabExperimentRepository()..loadAll()),
        ChangeNotifierProvider(create: (_) => LabPhotoRepository()),
        ChangeNotifierProvider.value(value: settingsRepository),
        ChangeNotifierProvider(create: (_) => ModelCatalogRepository()..loadCached()),
        ChangeNotifierProvider(
          lazy: false,
          create: (ctx) => AutoSyncService(
            settings: settingsRepository,
            auth: ctx.read<AuthRepository>(),
            // Ein Abgleich mit der Cloud hat Daten dieses Geräts verändert: Fächer
            // und Laborversuche neu laden (die übrigen Ansichten laden beim
            // Öffnen bzw. beim Tab-Wechsel neu).
            onDataChanged: () async {
              final labs = ctx.read<LabExperimentRepository>();
              await moduleRepository.load();
              await labs.loadAll();
            },
          )..start(),
        ),
      ],
      // Builder statt MaterialApp direkt: liest die gewählte Farbpalette und
      // Hell/Dunkel-Vorgabe (siehe SettingsScreen "Erscheinungsbild") reaktiv
      // aus den Einstellungen – ein Wechsel dort baut Theme/ThemeMode sofort
      // neu, ohne App-Neustart.
      child: Builder(
        builder: (context) {
          final appSettings = context.watch<SettingsRepository>().settings;
          final skin = themeSkinFromName(appSettings.themeSkin);
          return MaterialApp(
            title: 'Lernen',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.forSkin(skin, Brightness.light),
            darkTheme: AppTheme.forSkin(skin, Brightness.dark),
            themeMode: themeModePreferenceFromName(appSettings.themeModePreference).themeMode,
            home: const RootShell(),
          );
        },
      ),
    );
  }
}
