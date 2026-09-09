import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Öffnet die einzige Sembast-Datenbankdatei der App und stellt die
/// benannten Stores bereit. Ein Singleton, damit nie zwei Instanzen
/// dieselbe Datei öffnen (das ist bei Sembast nicht sicher).
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
    final Directory dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'lernen.db');
    final db = await databaseFactoryIo.openDatabase(path);
    _db = db;
    return db;
  }

  static final modules = stringMapStoreFactory.store('modules');
  static final materials = stringMapStoreFactory.store('materials');
  static final summaries = stringMapStoreFactory.store('summaries');
  static final concepts = stringMapStoreFactory.store('concepts');
  static final flashcards = stringMapStoreFactory.store('flashcards');
  static final settings = stringMapStoreFactory.store('settings');
}
