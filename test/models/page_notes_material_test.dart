import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/models/module.dart';
import 'package:lernen/models/page_note.dart';
import 'package:lernen/services/highlight_context.dart';
import 'package:lernen/services/module_export_service.dart';

MaterialItem _material({List<PageNote> notes = const []}) => MaterialItem(
      id: 'mat1',
      moduleId: 'm1',
      fileName: 'Skript.pdf',
      kind: MaterialKind.slide,
      extractedText: 'Text',
      createdAt: DateTime(2026, 9, 1),
      fileBytesBase64: 'QUJD',
      pageNotes: notes,
    );

final _notes = [
  PageNote(id: 'n1', page: 4, question: 'Was macht der Trigger?', text: 'Er startet die Aufzeichnung.', createdAt: DateTime(2026, 9, 2)),
];

void main() {
  test('Seitennotizen werden mit dem Material gespeichert und gelesen', () {
    final back = MaterialItem.fromMap(_material(notes: _notes).toMap());
    expect(back.pageNotes.single.page, 4);
    expect(back.pageNotes.single.text, 'Er startet die Aufzeichnung.');
    // Ältere Datensätze ohne das Feld.
    final old = _material().toMap()..remove('pageNotes');
    expect(MaterialItem.fromMap(old).pageNotes, isEmpty);
    // copyWith behält sie, wenn man sie nicht ändert.
    expect(_material(notes: _notes).copyWith(notes: 'x').pageNotes, hasLength(1));
  });

  test('die KI bekommt die Seitennotizen als Kontext', () {
    final context = HighlightContext.build(_material(notes: _notes));
    expect(context, contains('Notiz zu Seite 4: Er startet die Aufzeichnung.'));
    expect(HighlightContext.build(_material()), isEmpty);
  });

  test('Fach-Export und -Import nehmen die Seitennotizen mit', () {
    final module = Module(id: 'm1', name: 'ET', colorValue: 0xFF112233, icon: '⚡', examDate: null, createdAt: DateTime(2026, 1, 1));
    final payload = ModuleExportService.buildPayload(
      module: module,
      lectureUnits: const [],
      materialsWithBytes: [_material(notes: _notes)],
      concepts: const [],
      flashcards: const [],
    );
    final imported = ModuleExportService.parse(payload);
    expect(imported.materials.single.pageNotes.single.text, 'Er startet die Aufzeichnung.');
  });
}
