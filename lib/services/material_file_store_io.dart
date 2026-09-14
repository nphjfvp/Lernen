import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<(String?, String?)> storePdfBytes(String materialId, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final materialsDir = Directory('${dir.path}/materials');
  if (!await materialsDir.exists()) {
    await materialsDir.create(recursive: true);
  }
  final file = File('${materialsDir.path}/$materialId.pdf');
  await file.writeAsBytes(bytes);
  return (file.path, null);
}

Future<Uint8List?> loadPdfBytes(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

Future<void> deletePdfFile(String? filePath) async {
  if (filePath == null) return;
  final file = File(filePath);
  if (await file.exists()) await file.delete();
}
