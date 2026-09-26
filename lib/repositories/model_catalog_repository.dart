import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/ai_model_info.dart';
import '../services/database_service.dart';
import '../services/model_catalog_service.dart';

/// Hält den zuletzt abgerufenen OpenRouter-Modell-Katalog lokal vor (Sembast)
/// und aktualisiert ihn bei Bedarf. So funktioniert die Modellauswahl auch
/// offline (mit dem zuletzt bekannten Stand) und muss nicht bei jedem
/// Settings-Öffnen neu laden.
class ModelCatalogRepository extends ChangeNotifier {
  ModelCatalogRepository({ModelCatalogService? service}) : _service = service ?? ModelCatalogService();

  final ModelCatalogService _service;
  static const _recordKey = 'catalog';

  List<AiModelInfo> _models = kFallbackModels;
  DateTime? _lastUpdated;
  bool _refreshing = false;
  String? _lastError;

  List<AiModelInfo> get models => List.unmodifiable(_models);
  DateTime? get lastUpdated => _lastUpdated;
  bool get isRefreshing => _refreshing;
  String? get lastError => _lastError;

  List<AiModelInfo> get visionModels => _models.where((m) => m.supportsVision).toList();
  List<AiModelInfo> get freeModels => _models.where((m) => m.isFree).toList();

  /// Lädt den zwischengespeicherten Katalog und stößt bei Bedarf (leer oder
  /// älter als 7 Tage) im Hintergrund einen Refresh an. Wird beim App-Start
  /// aufgerufen – schlägt der Refresh fehl (offline etc.), bleibt einfach der
  /// zwischengespeicherte bzw. der eingebaute Fallback-Stand erhalten.
  Future<void> loadCached({bool refreshIfStale = true}) async {
    final db = await DatabaseService.instance.database;
    final record = await DatabaseService.modelCatalog.record(_recordKey).get(db);
    if (record != null) {
      final list = (record['models'] as List?)
              ?.map((m) => AiModelInfo.fromMap(Map<String, dynamic>.from(m as Map)))
              .toList() ??
          [];
      if (list.isNotEmpty) _models = list;
      _lastUpdated = DateTime.tryParse(record['updatedAt']?.toString() ?? '');
      notifyListeners();
    }

    final isStale = _lastUpdated == null || DateTime.now().difference(_lastUpdated!) > const Duration(days: 7);
    if (refreshIfStale && isStale) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    _refreshing = true;
    _lastError = null;
    notifyListeners();
    try {
      final fetched = await _service.fetchModels();
      if (fetched.isEmpty) {
        throw ModelCatalogException('OpenRouter meldete null Modelle.');
      }
      _models = fetched;
      _lastUpdated = DateTime.now();

      final db = await DatabaseService.instance.database;
      await DatabaseService.modelCatalog.record(_recordKey).put(db, {
        'models': fetched.map((m) => m.toMap()).toList(),
        'updatedAt': _lastUpdated!.toIso8601String(),
      });
    } on ModelCatalogException catch (e) {
      _lastError = e.message;
    } catch (e) {
      _lastError = 'Modell-Katalog konnte nicht aktualisiert werden: $e';
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  AiModelInfo? byId(String id) {
    for (final m in _models) {
      if (m.id == id) return m;
    }
    return null;
  }
}
