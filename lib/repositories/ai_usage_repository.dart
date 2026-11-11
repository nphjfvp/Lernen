import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/ai_model_info.dart';
import '../models/ai_usage.dart';
import '../services/database_service.dart';

/// Was die KI-Anfragen dieses Geräts gekostet haben: die letzten Anfragen
/// einzeln, dazu Summen je Tag und Modell. Bleibt auf dem Gerät (wird nicht
/// synchronisiert) – die Gesamtsumme über alle Geräte zeigt OpenRouter selbst.
class AiUsageRepository extends ChangeNotifier {
  AiUsageRepository({this.modelInfo});

  /// Katalog-Eintrag eines Modells (für den Listenpreis, falls OpenRouter in
  /// der Antwort keine Kosten meldet).
  final AiModelInfo? Function(String model)? modelInfo;

  /// So viele einzelne Anfragen bleiben gespeichert.
  static const keepEntries = 200;

  final List<AiUsage> _recent = [];
  final Map<String, AiUsageTotal> _totals = {};
  bool _loaded = false;
  Future<void>? _loading;
  Future<void> _queue = Future.value();

  /// Jüngste zuerst.
  List<AiUsage> get recent => List.unmodifiable(_recent);
  AiUsage? get last => _recent.isEmpty ? null : _recent.first;
  bool get isEmpty => _totals.isEmpty;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final entries = await DatabaseService.aiUsage.find(db);
    final totals = await DatabaseService.aiUsageTotals.find(db);
    _recent
      ..clear()
      ..addAll([for (final r in entries) AiUsage.fromMap(r.value)].whereType<AiUsage>())
      ..sort((a, b) => b.at.compareTo(a.at));
    _totals.clear();
    for (final r in totals) {
      final total = AiUsageTotal.fromMap(r.value);
      if (total != null) _totals[total.id] = total;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Hängt eine Anfrage an (für `AiService.onUsage`). Fehler beim Speichern
  /// dürfen keine KI-Antwort kosten – sie werden nur gemeldet.
  void record(AiUsage usage) {
    _queue = _queue.then((_) => _record(usage)).catchError((Object e) {
      debugPrint('KI-Kosten nicht gespeichert ($e).');
    });
  }

  /// Wartet, bis alle gemeldeten Anfragen gespeichert sind (für Tests).
  Future<void> get settled => _queue;

  Future<void> _record(AiUsage raw) async {
    if (!_loaded) await load();
    final info = modelInfo?.call(raw.model);
    final usage = raw.withEstimate(info?.promptPricePerMillion, info?.completionPricePerMillion);
    final day = AiUsageTotal.dayOf(usage.at);
    final total = (_totals['$day|${usage.model}'] ?? AiUsageTotal(day: day, model: usage.model)).plus(usage);
    _totals[total.id] = total;
    _recent.insert(0, usage);
    final dropped = _recent.length > keepEntries ? _recent.sublist(keepEntries) : const <AiUsage>[];
    if (dropped.isNotEmpty) _recent.removeRange(keepEntries, _recent.length);
    notifyListeners();

    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      await DatabaseService.aiUsageTotals.record(total.id).put(txn, total.toMap());
      await DatabaseService.aiUsage.record(_key(usage)).put(txn, usage.toMap());
      for (final old in dropped) {
        await DatabaseService.aiUsage.record(_key(old)).delete(txn);
      }
    });
  }

  static String _key(AiUsage usage) => '${usage.at.microsecondsSinceEpoch}-${usage.model}';

  /// Summe aller Tage ab [from] (einschließlich, `JJJJ-MM-TT`); ohne = alles.
  AiUsageTotal sum({String? from, String? model}) {
    var result = AiUsageTotal(day: from ?? '', model: model ?? '');
    for (final total in _totals.values) {
      if (from != null && total.day.compareTo(from) < 0) continue;
      if (model != null && total.model != model) continue;
      result = result.merge(total);
    }
    return result;
  }

  AiUsageTotal today([DateTime? now]) => sum(from: AiUsageTotal.dayOf(now ?? DateTime.now()));

  AiUsageTotal thisMonth([DateTime? now]) => sum(from: _monthStart(now ?? DateTime.now()));

  static String _monthStart(DateTime now) => '${AiUsageTotal.dayOf(now).substring(0, 8)}01';

  /// Summen je Modell ab [from], teuerstes zuerst.
  List<AiUsageTotal> byModel({String? from}) {
    final models = {for (final t in _totals.values) t.model};
    return [for (final m in models) sum(from: from, model: m)].where((t) => t.calls > 0).toList()
      ..sort((a, b) => b.cost != a.cost ? b.cost.compareTo(a.cost) : b.calls.compareTo(a.calls));
  }

  List<AiUsageTotal> byModelThisMonth([DateTime? now]) => byModel(from: _monthStart(now ?? DateTime.now()));

  /// Durchschnitt der letzten Anfragen an [model] mit bekanntem Preis.
  ({double cost, int calls})? averageFor(String model) {
    final known = [
      for (final u in _recent)
        if (u.model == model && u.cost != null) u.cost!,
    ];
    if (known.isEmpty) return null;
    return (cost: known.reduce((a, b) => a + b) / known.length, calls: known.length);
  }

  Future<void> clear() async {
    await _queue;
    _recent.clear();
    _totals.clear();
    notifyListeners();
    final db = await DatabaseService.instance.database;
    await db.transaction((txn) async {
      await DatabaseService.aiUsage.delete(txn);
      await DatabaseService.aiUsageTotals.delete(txn);
    });
  }
}
