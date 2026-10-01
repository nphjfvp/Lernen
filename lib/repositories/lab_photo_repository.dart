import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/lab_photo.dart';
import '../services/database_service.dart';

/// Fotos der Laborversuche. Bewusst eigener Speicher, nicht im Versuch: Bilder
/// sind groß und sollen weder den Versuch noch den Cloud-Abgleich aufblähen.
/// Sie bleiben auf diesem Gerät; [version] steigt bei jeder Änderung, damit
/// Ansichten neu laden.
class LabPhotoRepository extends ChangeNotifier {
  /// [openDatabase]: nur für Tests.
  LabPhotoRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;
  int _version = 0;
  int get version => _version;

  Future<List<LabPhoto>> forExperiment(String experimentId) async {
    final db = await _open();
    final records = await DatabaseService.labPhotos.find(
      db,
      finder: Finder(filter: Filter.equals('experimentId', experimentId)),
    );
    final photos = [for (final r in records) LabPhoto.fromMap(r.value)];
    photos.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return photos;
  }

  Future<int> countForExperiment(String experimentId) async {
    final db = await _open();
    return DatabaseService.labPhotos.count(db, filter: Filter.equals('experimentId', experimentId));
  }

  Future<void> add(LabPhoto photo) async {
    final db = await _open();
    await DatabaseService.labPhotos.record(photo.id).put(db, photo.toMap());
    _version++;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final db = await _open();
    await DatabaseService.labPhotos.record(id).delete(db);
    _version++;
    notifyListeners();
  }

  Future<void> deleteForExperiment(String experimentId) async {
    final db = await _open();
    await DatabaseService.labPhotos.delete(db, finder: Finder(filter: Filter.equals('experimentId', experimentId)));
    _version++;
    notifyListeners();
  }
}
