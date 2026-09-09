import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Windows/iOS/Android/macOS/Linux: echte Datei im App-Support-Verzeichnis.
Future<Database> openLernenDatabase() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final path = p.join(dir.path, 'lernen.db');
  return databaseFactoryIo.openDatabase(path);
}
