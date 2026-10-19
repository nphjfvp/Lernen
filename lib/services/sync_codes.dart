import 'dart:math';

/// Sync-Codes (Abgleich ohne Konto): wer den Code kennt, kommt an die Daten –
/// er ist ein Passwort. Selbst gewählte, kurze Codes lassen sich durchprobieren
/// (AUDIT H10), deshalb erzeugt die App zufällige und die Firestore-Regeln
/// verlangen mindestens [minLength] Zeichen.
class SyncCodes {
  SyncCodes._();

  /// So lang wie ein erzeugter Code ohne Bindestriche; die Firestore-Regeln
  /// (firestore.rules) prüfen dieselbe Länge.
  static const minLength = 16;

  /// Ohne leicht verwechselbare Zeichen (0/o, 1/l/i).
  static const _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

  /// Zufälliger Code, z.B. `k7mq-x2vd-9hfa-tn4e` (16 Zeichen aus 31, rund
  /// 79 Bit – nicht durchprobierbar).
  static String generate({Random? random}) {
    final r = random ?? Random.secure();
    final chars = List.generate(minLength, (_) => _alphabet[r.nextInt(_alphabet.length)]);
    return [for (var i = 0; i < minLength; i += 4) chars.sublist(i, i + 4).join()].join('-');
  }

  /// Lang genug für die Firestore-Regeln.
  static bool isStrong(String code) => code.trim().length >= minLength;
}
