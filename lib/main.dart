import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'repositories/auth_repository.dart';
import 'repositories/concept_repository.dart';
import 'repositories/flashcard_repository.dart';
import 'repositories/material_repository.dart';
import 'repositories/model_catalog_repository.dart';
import 'repositories/module_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/summary_repository.dart';
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

  runApp(const LernenApp());
}

class LernenApp extends StatelessWidget {
  const LernenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthRepository()),
        ChangeNotifierProvider(create: (_) => ModuleRepository()..load()),
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider(create: (_) => SummaryRepository()),
        ChangeNotifierProvider(create: (_) => ConceptRepository()),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider(create: (_) => SettingsRepository()..load()),
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
