import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/app_settings.dart';
import '../services/database_service.dart';

class SettingsRepository extends ChangeNotifier {
  static const _recordKey = 'app_settings';

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  Future<void> load() async {
    final db = await DatabaseService.instance.database;
    final record = await DatabaseService.settings.record(_recordKey).get(db);
    if (record != null) {
      _settings = AppSettings.fromMap(record);
    }
    notifyListeners();
  }

  Future<void> update(AppSettings settings) async {
    final db = await DatabaseService.instance.database;
    await DatabaseService.settings.record(_recordKey).put(db, settings.toMap());
    _settings = settings;
    notifyListeners();
  }
}
