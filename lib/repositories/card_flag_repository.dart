import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../models/card_flag.dart';
import '../services/database_service.dart';

/// Markierte Fragen (siehe [CardFlag]) – einmal geladen und im Speicher
/// gehalten, damit der Markier-Knopf im Quiz sofort weiß, ob die Karte
/// markiert ist.
class CardFlagRepository extends ChangeNotifier {
  /// [openDatabase]: nur für Tests (z.B. eine Datenbank im Speicher).
  CardFlagRepository({Future<DatabaseClient> Function()? openDatabase})
    : _open = openDatabase ?? (() => DatabaseService.instance.database);

  final Future<DatabaseClient> Function() _open;
  Map<String, CardFlag>? _flags;
  Future<void>? _loading;

  bool get isLoaded => _flags != null;

  /// Lädt (einmal) alle Markierungen; [reload] nach einem Abgleich.
  Future<void> load({bool reload = false}) {
    if (_flags != null && !reload) return Future.value();
    return _loading ??= () async {
      try {
        final db = await _open();
        final records = await DatabaseService.cardFlags.find(db);
        final flags = <String, CardFlag>{};
        for (final r in records) {
          final f = CardFlag.fromMap(r.value);
          if (f != null) flags[f.cardId] = f;
        }
        _flags = flags;
        notifyListeners();
      } finally {
        _loading = null;
      }
    }();
  }

  CardFlag? flagOf(String cardId) => _flags?[cardId];

  /// Neueste zuerst; [moduleId] null = alle Fächer.
  List<CardFlag> list({String? moduleId}) {
    final out = [
      for (final f in (_flags ?? const <String, CardFlag>{}).values)
        if (moduleId == null || f.moduleId == moduleId) f,
    ];
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> set(CardFlag flag) async {
    await load();
    final db = await _open();
    await DatabaseService.cardFlags.record(flag.cardId).put(db, flag.toMap());
    _flags![flag.cardId] = flag;
    notifyListeners();
  }

  Future<void> remove(String cardId) async {
    await load();
    final db = await _open();
    await DatabaseService.cardFlags.record(cardId).delete(db);
    _flags!.remove(cardId);
    notifyListeners();
  }
}
