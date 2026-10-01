import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/lab_experiment.dart';
import 'package:lernen/services/ai_service.dart';
import 'package:lernen/services/lab_photo_reading.dart';

LabExperiment _experiment({String id = 'lab-aaaa-1111', String title = 'Oszilloskop'}) => LabExperiment.fromStructure(
      {
        'title': title,
        'parts': [
          {
            'title': 'Grundeinstellungen',
            'tables': [
              {
                'title': 'Messwerte',
                'columns': ['Frequenz', 'Amplitude'],
                'rows': [
                  ['1 kHz', ''],
                  ['2 kHz', '3,1 V'],
                ],
              },
            ],
          },
          {
            'title': 'Tastkopf',
            'steps': ['Tastkopf abgleichen'],
          },
        ],
      },
      moduleId: 'm1',
      now: DateTime(2026, 9, 1),
      id: id,
    );

void main() {
  final e = _experiment();
  final partId = e.parts.first.id;

  Map<String, dynamic> json({Object? experiment, Object? part, List<Map<String, Object?>>? cells, Object? notes}) => {
        'description': 'Messprotokoll',
        'experimentId': experiment ?? e.id,
        'partId': part ?? partId,
        'confidence': 'hoch',
        'cells': cells ?? [{'table': 1, 'row': 1, 'col': 2, 'value': '2,0 V'}],
        'notes': notes ?? '',
      };

  group('Zuordnung', () {
    test('Kennung genau, als eindeutiger Anfang oder über den Titel', () {
      expect(LabPhotoReading.fromJson(json(), [e]).experimentId, e.id);
      expect(LabPhotoReading.fromJson(json(experiment: 'lab-aaaa'), [e]).experimentId, e.id);
      expect(LabPhotoReading.fromJson(json(experiment: 'oszilloskop'), [e]).experimentId, e.id);
    });

    test('Unbekanntes oder mehrdeutiges wird zu null statt zu einer falschen Zuordnung', () {
      expect(LabPhotoReading.fromJson(json(experiment: 'gibt es nicht'), [e]).experimentId, isNull);
      expect(LabPhotoReading.fromJson(json(experiment: 'null'), [e]).experimentId, isNull);
      final twin = _experiment(id: 'lab-aaaa-2222');
      expect(LabPhotoReading.fromJson(json(experiment: 'lab-aaaa'), [e, twin]).experimentId, isNull);
      expect(LabPhotoReading.fromJson(json(experiment: 'Oszilloskop'), [e, twin]).experimentId, isNull);
    });

    test('Teil: Kennung oder Titel; ohne Angabe nur, wenn es nur einen gibt', () {
      expect(LabPhotoReading.fromJson(json(part: 'Grundeinstellungen'), [e]).partId, partId);
      expect(LabPhotoReading.fromJson(json(part: 'unbekannt'), [e]).partId, isNull);
      final single = LabExperiment.fromStructure(
        {
          'title': 'Einer',
          'parts': [
            {
              'title': 'Nur ein Teil',
              'steps': ['Aufbauen'],
            },
          ],
        },
        moduleId: 'm1',
        now: DateTime(2026, 9, 1),
        id: 'solo-0001',
      );
      expect(LabPhotoReading.fromJson(json(experiment: single.id, part: 'x'), [single]).partId, single.parts.single.id);
    });

    test('kaputte Zellen werden übergangen, die Zählung ab 1 wird auf ab 0 umgestellt', () {
      final reading = LabPhotoReading.fromJson(
        json(cells: [
          {'table': 1, 'row': 1, 'col': 2, 'value': ' 2,0 V '},
          {'table': 'x', 'row': 1, 'col': 1, 'value': '5'},
          {'table': 1, 'row': 1, 'col': 1, 'value': ''},
        ]),
        [e],
      );
      expect(reading.cells, [(table: 0, row: 0, col: 1, value: '2,0 V')]);
    });
  });

  group('Ziel', () {
    test('leere Zelle passt, mit Beschriftung; vom Nutzer schon gefüllte Zelle wird als Ersetzen erkannt', () {
      final filled = e.updatePart(partId, (p) => p.copyWith(tables: [p.tables.single.withCell(0, 1, '1,0 V')]));
      final reading = LabPhotoReading.fromJson(
        json(cells: [
          {'table': 1, 'row': 1, 'col': 2, 'value': '2,0 V'},
        ]),
        [filled],
      );
      final target = reading.targetFor(filled, partId);
      expect(target.fills, hasLength(1));
      expect(target.fills.single.label, 'Messwerte · Zeile 1 · Amplitude');
      expect(target.fills.single.existing, '1,0 V');
      expect(target.fills.single.overwrites, isTrue);
      // In die leere Zelle der Ausgangsversuchs: kein Ersetzen.
      final empty = LabPhotoReading.fromJson(json(), [e]).targetFor(e, partId);
      expect(empty.fills.single.overwrites, isFalse);
    });

    test('feste Zellen und Zellen außerhalb gehen als Text in die Notizen', () {
      final reading = LabPhotoReading.fromJson(
        json(
          cells: [
            {'table': 1, 'row': 2, 'col': 2, 'value': '3,3 V'}, // feste Zelle (im Skript schon eingetragen)
            {'table': 2, 'row': 1, 'col': 1, 'value': '9'}, // keine zweite Tabelle
          ],
          notes: 'Tastkopf 10:1',
        ),
        [e],
      );
      final target = reading.targetFor(e, partId);
      expect(target.fills, isEmpty);
      expect(target.notes, contains('Tastkopf 10:1'));
      expect(target.notes, contains('Tabelle 1, Zeile 2, Spalte 2: 3,3 V'));
      expect(target.notes, contains('Tabelle 2, Zeile 1, Spalte 1: 9'));
    });

    test('anderes Ziel als das der KI: die Nummerierung stimmt dann nicht, alles geht in die Notizen', () {
      final reading = LabPhotoReading.fromJson(json(), [e]);
      final other = e.parts.last.id;
      final target = reading.targetFor(e, other);
      expect(target.fills, isEmpty);
      expect(target.notes, contains('2,0 V'));
      expect(reading.targetFor(null, null).fills, isEmpty);
    });
  });

  group('Eintragen', () {
    test('trägt die Werte ein und hängt die Notizen mit Kopfzeile an', () {
      final reading = LabPhotoReading.fromJson(json(notes: 'Tastkopf 10:1'), [e]);
      final target = reading.targetFor(e, partId);
      final next = LabPhotoReading.apply(e, partId, target.fills, notes: target.notes, stamp: 'Foto vom 01.09.');
      final table = next.partById(partId)!.tables.single;
      expect(table.rows[0][1], '2,0 V');
      expect(table.rows[0][0], '1 kHz');
      expect(next.partById(partId)!.notes, 'Foto vom 01.09.:\nTastkopf 10:1');
      // Zweites Foto: wird angehängt, nichts überschrieben.
      final again = LabPhotoReading.apply(next, partId, const [], notes: 'noch ein Wert', stamp: 'Foto');
      expect(again.partById(partId)!.notes, 'Foto vom 01.09.:\nTastkopf 10:1\n\nFoto:\nnoch ein Wert');
    });

    test('ohne Notizen bleiben die Notizen unverändert', () {
      final next = LabPhotoReading.apply(e, partId, const []);
      expect(next.partById(partId)!.notes, e.partById(partId)!.notes);
    });
  });

  test('Übersicht für die KI: Zeilen ab 1, leere Zellen als Punkt, feste mit Wert', () {
    final text = AiService.describeExperimentsForPhoto([e]);
    expect(text, contains('VERSUCH ${e.id}: Oszilloskop'));
    expect(text, contains('TEIL $partId: Grundeinstellungen'));
    expect(text, contains('Spalten: 1=Frequenz | 2=Amplitude'));
    expect(text, contains('Zeile 1: 1 kHz | ·'));
    expect(text, contains('Zeile 2: 2 kHz | 3,1 V'));
  });
}
