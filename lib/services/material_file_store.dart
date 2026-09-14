import 'dart:convert';
import 'dart:typed_data';

import 'material_file_store_stub.dart'
    if (dart.library.io) 'material_file_store_io.dart'
    if (dart.library.html) 'material_file_store_web.dart' as platform;

/// Persistiert die Original-Bytes einer hochgeladenen PDF-Datei dauerhaft –
/// Grundlage für die visuelle Ansicht + Markier-Funktion in
/// MaterialViewerScreen (ohne das würde nur der beim Upload extrahierte
/// Text vorliegen, aber kein Dokument zum Anzeigen/Markieren). Auf
/// Mobile/Desktop als Datei im Anwendungsverzeichnis, auf Web als Base64
/// direkt in der DB (dort gibt es kein persistentes Dateisystem).
class MaterialFileStore {
  MaterialFileStore._();

  /// Speichert [bytes] und gibt (filePath, fileBytesBase64) zurück – je nach
  /// Plattform ist nur eines der beiden Felder gesetzt.
  static Future<(String?, String?)> store(String materialId, Uint8List bytes) =>
      platform.storePdfBytes(materialId, bytes);

  static Future<Uint8List?> load({String? filePath, String? fileBytesBase64}) async {
    if (fileBytesBase64 != null) return base64Decode(fileBytesBase64);
    if (filePath != null) return platform.loadPdfBytes(filePath);
    return null;
  }

  static Future<void> delete({String? filePath}) => platform.deletePdfFile(filePath);
}
