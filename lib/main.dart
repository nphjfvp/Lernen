import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'repositories/auth_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/concept_repository.dart';
import 'repositories/flashcard_repository.dart';
import 'repositories/material_repository.dart';
import 'repositories/model_catalog_repository.dart';
import 'repositories/module_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/summary_repository.dart';
import 'services/reminder_service.dart';
import 'theme/app_theme.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cloud-Sync ist optional: schlägt die Initialisierung fehl, bleibt die
  // App vollständig offline nutzbar. Timeout ist bewusst gesetzt: im Web
  // lädt Firebase sein JS-SDK per dynamischem Import von Googles CDN nach –
  // blockiert das (Firewall, Adblocker, kein Netz), würde die App sonst nie
  // über den Startbildschirm hinauskommen, weil runApp() erst danach läuft.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('Firebase nicht konfiguriert – Cloud-Sync deaktiviert ($e).');
  }

  // Settings werden vor runApp() geladen (schneller lokaler DB-Read), damit
  // die Lernerinnerung direkt beim Start neu geplant werden kann – u.a.
  // wichtig nach einem Geräte-Neustart auf Plattformen ohne Boot-Receiver.
  final settingsRepository = SettingsRepository();
  await settingsRepository.load();
  unawaited(ReminderService().reschedule(settingsRepository.settings));

  runApp(LernenApp(settingsRepository: settingsRepository));
}

class LernenApp extends StatelessWidget {
  const LernenApp({super.key, required this.settingsRepository});

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthRepository()),
        ChangeNotifierProvider(create: (_) => ModuleRepository()..load()),
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider(create: (_) => ChatRepository()),
        ChangeNotifierProvider(create: (_) => SummaryRepository()),
        ChangeNotifierProvider(create: (_) => ConceptRepository()),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider.value(value: settingsRepository),
        ChangeNotifierProvider(create: (_) => ModelCatalogRepository()..loadCached()),
      ],
      child: MaterialApp(
        title: 'Lernen',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const RootShell(),
      ),
    );
  }
}
