import 'package:sembast_web/sembast_web.dart';

/// Web: IndexedDB-gestützter Sembast-Store, kein echtes Dateisystem nötig.
Future<Database> openLernenDatabase() {
  return databaseFactoryWeb.openDatabase('lernen.db');
}
