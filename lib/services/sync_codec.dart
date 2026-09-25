import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Reine Kodier-Logik für den Cloud-Sync (kein Firestore-Zugriff, damit
/// testbar): Firestore erlaubt höchstens 1 MiB pro Dokument. Früher lag der
/// komplette Datenbestand als EIN Dokument in der Cloud – ein paar
/// Vorlesungsfolien (als Base64-PDF) reichten, und der Sync brach ab.
///
/// Jetzt: der Datenbestand wird als JSON gzip-komprimiert (Text schrumpft
/// dabei typischerweise auf 10–25 %) und in Stücke von höchstens
/// [maxPartBytes] geteilt, die jeweils in ein eigenes Dokument passen. Die
/// PDF-Dateien selbst werden gar nicht übertragen (siehe
/// [stripDeviceLocalMaterialFields]) – sie sind bereits komprimiert, groß
/// und für die Lernlogik nicht nötig (der extrahierte Text reist mit).
class SyncCodec {
  /// Sicherheitsabstand zum 1-MiB-Limit für die übrigen Felder des
  /// Dokuments (pushId, Zeitstempel …).
  static const int maxPartBytes = 900 * 1024;

  /// Felder eines Materials, die nur auf dem Gerät Sinn ergeben bzw. zu groß
  /// für den Sync sind: der lokale Dateipfad der PDF und (im Web) ihre
  /// Base64-Bytes.
  static const deviceLocalMaterialFields = ['filePath', 'fileBytesBase64'];

  static Map<String, dynamic> stripDeviceLocalMaterialFields(Map<String, dynamic> material) {
    return {
      for (final e in material.entries)
        if (!deviceLocalMaterialFields.contains(e.key)) e.key: e.value,
    };
  }

  /// Übernimmt beim Herunterladen die lokal vorhandene PDF (Pfad/Bytes) für
  /// ein Material, das es auf diesem Gerät schon gibt – sonst ginge sie bei
  /// jedem Pull verloren, weil die Cloud sie nicht mitführt.
  static Map<String, dynamic> withLocalMaterialFields(
    Map<String, dynamic> remote,
    Map<String, dynamic>? local,
  ) {
    if (local == null) return remote;
    return {
      ...remote,
      for (final key in deviceLocalMaterialFields)
        if (local[key] != null) key: local[key],
    };
  }

  static List<Uint8List> encode(Map<String, dynamic> payload, {int maxPartBytes = SyncCodec.maxPartBytes}) {
    final raw = utf8.encode(jsonEncode(payload));
    final compressed = GZipEncoder().encode(raw)!;
    final parts = <Uint8List>[];
    for (var start = 0; start < compressed.length; start += maxPartBytes) {
      final end = (start + maxPartBytes).clamp(0, compressed.length);
      parts.add(Uint8List.fromList(compressed.sublist(start, end)));
    }
    return parts.isEmpty ? [Uint8List(0)] : parts;
  }

  static Map<String, dynamic> decode(List<Uint8List> parts) {
    final builder = BytesBuilder(copy: false);
    for (final p in parts) {
      builder.add(p);
    }
    final raw = GZipDecoder().decodeBytes(builder.takeBytes());
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(raw)) as Map);
  }
}
