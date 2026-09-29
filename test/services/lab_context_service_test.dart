import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/services/lab_context_service.dart';
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

MaterialItem _pdfMaterial(String id, String name, List<String> pages) => MaterialItem(
      id: id,
      moduleId: 'm1',
      fileName: name,
      kind: MaterialKind.slide,
      extractedText: pages.join('\n'),
      createdAt: DateTime(2026, 9, 1),
      fileBytesBase64: base64Encode(_pdf(pages)),
    );

MaterialItem _textMaterial(String id, String name, String text) => MaterialItem(
      id: id,
      moduleId: 'm1',
      fileName: name,
      kind: MaterialKind.slide,
      extractedText: text,
      createdAt: DateTime(2026, 9, 1),
    );

LabExperiment _experiment({List<String> theory = const [], List<String> guide = const []}) => LabExperiment(
      id: 'lab1',
      moduleId: 'm1',
      title: 'Oszilloskop',
      createdAt: DateTime(2026, 9, 1),
      theoryMaterialIds: theory,
      guideMaterialIds: guide,
    );

void main() {
  final theory = _pdfMaterial('lab-theory', 'Theorie.pdf', [
    'Organisatorisches zum Praktikum: Termine, Gruppen, Sicherheit',
    'Der Trigger startet die Aufzeichnung des Oszilloskops bei einem Pegel',
    'Die Abtastrate bestimmt die zeitliche Auflösung des Oszilloskops',
  ]);
  final guide = _pdfMaterial('lab-guide', 'Durchfuehrung.pdf', [
    'Schließen Sie den Tastkopf an Kanal eins an und drücken Sie Autoset',
  ]);
  final service = LabContextService();

  test('Unterlagen: erst Theorie, dann Anleitung; unbekannte Kennungen werden übersprungen', () {
    final sources = LabContextService.sourcesOf(
      _experiment(theory: ['lab-theory', 'gibt-es-nicht'], guide: ['lab-guide']),
      [guide, theory],
    );
    expect(sources.map((m) => m.id), ['lab-theory', 'lab-guide']);
  });

  test('findet die passende PDF-Seite samt Fundstelle zum Öffnen', () async {
    final ctx = await service.contextFor(
      experiment: _experiment(theory: ['lab-theory'], guide: ['lab-guide']),
      materials: [theory, guide],
      question: 'Wozu dient der Trigger des Oszilloskops?',
    );
    expect(ctx.isEmpty, isFalse);
    expect(ctx.references.first.material.id, 'lab-theory');
    expect(ctx.references.first.page, 2);
    expect(ctx.references.first.label, 'Theorie.pdf, Seite 2');
    expect(ctx.text, startsWith('[Theorie.pdf, Seite 2]'));
    expect(ctx.text, contains('startet die Aufzeichnung'));
  });

  test('die eigene Antwort hilft beim Finden (Vokabular der Antwort zählt mit)', () async {
    final ctx = await service.contextFor(
      experiment: _experiment(theory: ['lab-theory']),
      materials: [theory],
      question: 'Erkläre das bitte',
      answer: 'Die Abtastrate legt die zeitliche Auflösung des Oszilloskops fest.',
    );
    expect(ctx.references.first.page, 3);
  });

  test('Materialien ohne PDF-Seiten: Text in Stücken, aber ohne Fundstelle zum Öffnen', () async {
    final docx = _textMaterial(
      'lab-docx',
      'Versuch.docx',
      'Einleitung zum Versuch.\n\nDer Trigger startet die Aufzeichnung des Oszilloskops.\n\nAnhang.',
    );
    final ctx = await service.contextFor(
      experiment: _experiment(theory: ['lab-docx']),
      materials: [docx],
      question: 'Wozu dient der Trigger des Oszilloskops?',
    );
    expect(ctx.references, isEmpty);
    expect(ctx.text, contains('[Versuch.docx]'));
    expect(ctx.text, contains('startet die Aufzeichnung'));
  });

  test('ohne Treffer oder ohne Unterlagen bleibt der Auszug leer', () async {
    expect(
      (await service.contextFor(
        experiment: _experiment(theory: ['lab-theory']),
        materials: [theory],
        question: 'Quantenchromodynamik Gluonen',
      ))
          .isEmpty,
      isTrue,
    );
    expect(
      (await service.contextFor(experiment: _experiment(), materials: [theory], question: 'Trigger Oszilloskop')).isEmpty,
      isTrue,
    );
  });

  test('Text ohne Seiten wird an Absätzen in Stücke geteilt', () {
    final long = List.generate(30, (i) => 'Absatz $i ${'wort ' * 60}').join('\n\n');
    final pages = LabContextService.splitIntoPseudoPages(long);
    expect(pages.length, greaterThan(3));
    expect(pages.every((p) => p.length <= 3000), isTrue);
    expect(pages.join('\n\n').contains('Absatz 29'), isTrue);
    expect(LabContextService.splitIntoPseudoPages('  \n\n  '), isEmpty);
  });

  test('Messwerte und Antworten als Text für die KI', () {
    final part = LabPart(
      id: 'p1',
      title: 'Teil 1',
      tables: [
        LabTable.fromAi({
          'title': 'Messwerte',
          'columns': ['f', 'U'],
          'rows': [
            ['1 kHz', ''],
          ],
        }).withCell(0, 1, '2 V'),
      ],
      questions: const [
        LabQuestion(id: 'q1', number: '1.1', text: 'Periodendauer?', answer: '1 ms'),
        LabQuestion(id: 'q2', number: '1.2', text: 'Amplitude?'),
      ],
    );
    expect(LabContextService.measurementsOf(part), 'Messwerte\nf | U\n1 kHz | 2 V');
    expect(LabContextService.measurementsOf(null), '');
    expect(LabContextService.answersOf(part), '1.1 Periodendauer?\nAntwort: 1 ms');
    final experiment = _experiment().copyWith(parts: [part]);
    expect(LabContextService.allMeasurements(experiment), 'Teil 1\nMesswerte\nf | U\n1 kHz | 2 V');
  });
}
