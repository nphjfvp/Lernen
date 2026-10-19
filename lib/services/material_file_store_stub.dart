import 'dart:typed_data';

import 'package:sembast/sembast.dart';

Future<(String?, String?)> storePdfBytes(String materialId, Uint8List bytes) async => (null, null);

Future<Uint8List?> loadPdfBytes(String filePath) async => null;

Future<void> deletePdfFile(String? filePath) async {}

Future<int> migrateLegacyPdfs(Database db) async => 0;
