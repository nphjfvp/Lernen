import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/concept.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/services/source_locator.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List _pdf(List<String> pages) {
  final document = PdfDocument();
  for (final text in pages) {
    document.pages.add().graphics.drawString(
          text,
          PdfStandardFont(PdfFontFamily.helvetica, 11),
          bounds: const Rect.fromLTWH(0, 0, 500, 700),
        );
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

MaterialItem _material(String id, List<String> pages, {String? unitId, String name = 'Folien.pdf'}) => MaterialItem(
      id: id,
      moduleId: 'm1',
      fileName: name,
      kind: MaterialKind.slide,
      extractedText: pages.join('\n'),
      createdAt: DateTime(2026, 9, 1),
      fileBytesBase64: base64Encode(_pdf(pages)),
      unitId: unitId,
    );

Flashcard _card(String front, String back, {String? unitId, String? conceptId, String? sourceId, int? page}) =>
    Flashcard(
      id: 'c-$front',
      moduleId: 'm1',
      front: front,
      back: back,
      createdAt: DateTime(2026, 9, 1),
      due: DateTime(2026, 9, 1),
      unitId: unitId,
      conceptId: conceptId,
      sourceMaterialId: sourceId,
      sourcePage: page,
    );

const _elektro = [
  'Organisatorisches: Termine, Klausur, Sprechstunde',
  'Das Ohmsche Gesetz: Spannung U gleich Widerstand R mal Strom I',
  'Kirchhoffsche Regeln: Knotenregel und Maschenregel',
  'Leistung P gleich Spannung mal Strom, Einheit Watt',
];

void main() {
  test('Stichworte: klein, Stämme, ohne Füllwörter und kurze Wörter', () {
    expect(SourceLocator.keywords('Welche Spannungen liegen am Widerstand an?'), ['spannun', 'liegen', 'widerst']);
    expect(SourceLocator.keywords('Spannung'), SourceLocator.keywords('Spannungen'));
  });

  test('beste Seite: seltene Begriffe aus Frage und Lösung entscheiden', () {
    final query = SourceLocator.queryFor(_card('Wie lautet das Ohmsche Gesetz?', 'U = R · I (Spannung = Widerstand mal Strom)'));
    expect(SourceLocator.bestPage(query, _elektro), 1);
    final kirchhoff = SourceLocator.queryFor(_card('Was besagt die Knotenregel nach Kirchhoff?', 'Summe der Ströme ist null'));
    expect(SourceLocator.bestPage(kirchhoff, _elektro), 2);
    // Nur ein gemeinsamer Begriff reicht nicht.
    final vague = SourceLocator.queryFor(_card('Was ist ein Termin?', 'x'));
    expect(SourceLocator.bestPage(vague, _elektro), isNull);
  });

  test('gespeicherte Seite geht vor, Seitentext kommt mit', () async {
    final folien = _material('mat-a', _elektro);
    final source = await SourceLocator().locate(
      _card('Irgendwas', 'egal', sourceId: 'mat-a', page: 3),
      materials: [folien],
    );
    expect(source!.material.id, 'mat-a');
    expect(source.page, 3);
    expect(source.guessed, isFalse);
    expect(source.pageText, contains('Kirchhoffsche'));
  });

  test('Konzept-Verweis, sonst Textabgleich – zuerst in derselben Einheit', () async {
    final einheit1 = _material('mat-b', _elektro, unitId: 'u1');
    final einheit2 = _material('mat-c', [
      'Ohmsches Gesetz Wiederholung: Spannung Widerstand Strom',
      'Sonstiges',
    ], unitId: 'u2', name: 'Übung.pdf');
    final concept = Concept(
      id: 'k1',
      moduleId: 'm1',
      title: 'Leistung',
      explanation: '',
      sourceMaterialIds: const [],
      createdAt: DateTime(2026, 9, 1),
      linkedMaterialId: 'mat-b',
      linkedPageNumber: 4,
    );
    final viaConcept = await SourceLocator().locate(
      _card('Frage ohne Treffer', 'nichts', conceptId: 'k1'),
      materials: [einheit1, einheit2],
      concepts: [concept],
    );
    expect(viaConcept!.page, 4);

    final guessed = await SourceLocator().locate(
      _card('Wie lautet das Ohmsche Gesetz?', 'Spannung gleich Widerstand mal Strom', unitId: 'u2'),
      materials: [einheit1, einheit2],
    );
    expect(guessed!.material.id, 'mat-c');
    expect(guessed.page, 1);
    expect(guessed.guessed, isTrue);

    final nothing = await SourceLocator().locate(_card('Photosynthese Chlorophyll', 'Licht'), materials: [einheit1]);
    expect(nothing, isNull);
  });
}
