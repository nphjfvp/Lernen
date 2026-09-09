import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'repositories/concept_repository.dart';
import 'repositories/flashcard_repository.dart';
import 'repositories/material_repository.dart';
import 'repositories/module_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/summary_repository.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cloud-Sync ist optional: ohne eigenes Firebase-Projekt (siehe README,
  // `flutterfire configure`) bleibt die App vollständig offline nutzbar.
  try {
    await Firebase.initializeApp();
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
        ChangeNotifierProvider(create: (_) => ModuleRepository()..load()),
        ChangeNotifierProvider(create: (_) => MaterialRepository()),
        ChangeNotifierProvider(create: (_) => SummaryRepository()),
        ChangeNotifierProvider(create: (_) => ConceptRepository()),
        ChangeNotifierProvider(create: (_) => FlashcardRepository()),
        ChangeNotifierProvider(create: (_) => SettingsRepository()..load()),
      ],
      child: MaterialApp(
        title: 'Lernen',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D5AFE)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3D5AFE),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const RootShell(),
      ),
    );
  }
}
