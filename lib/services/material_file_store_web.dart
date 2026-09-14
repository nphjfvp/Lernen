import 'dart:convert';
import 'dart:typed_data';

Future<(String?, String?)> storePdfBytes(String materialId, Uint8List bytes) async =>
    (null, base64Encode(bytes));

Future<Uint8List?> loadPdfBytes(String filePath) async => null;

Future<void> deletePdfFile(String? filePath) async {}
