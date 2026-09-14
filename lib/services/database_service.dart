import 'package:sembast/sembast.dart';

import 'db_factory/db_factory_web.dart'
    if (dart.library.io) 'db_factory/db_factory_io.dart';

/// Öffnet die einzige Sembast-Datenbank der App (echte Datei auf
/// Windows/iOS/Android, IndexedDB im Web – siehe db_factory/) und stellt
/// die benannten Stores bereit. Ein Singleton, damit nie zwei Instanzen
/// dieselbe Datenbank öffnen (das ist bei Sembast nicht sicher).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final db = await openLernenDatabase();
    _db = db;
    return db;
  }

  static final modules = stringMapStoreFactory.store('modules');
  static final materials = stringMapStoreFactory.store('materials');
  static final summaries = stringMapStoreFactory.store('summaries');
  static final concepts = stringMapStoreFactory.store('concepts');
  static final lectureUnits = stringMapStoreFactory.store('lecture_units');
  static final flashcards = stringMapStoreFactory.store('flashcards');
  static final settings = stringMapStoreFactory.store('settings');
  static final modelCatalog = stringMapStoreFactory.store('model_catalog');
  static final chatMessages = stringMapStoreFactory.store('chat_messages');
}
