import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/task_label_locator.dart';

void main() {
  const page = [
    'Übungsblatt 2 – Werkstoffkunde',
    'Aufgabe 1 Diffusion',
    'Berechnen Sie den Diffusionskoeffizienten.',
    'a) bei 1000 K',
    'b) bei 1200 K',
    'Aufgabe 2 Kristallgitter',
    'a) Zeichnen Sie die Richtung [1 1 1] ein.',
    'b) Zeichnen Sie die Ebene (1 1 0) ein.',
  ];

  test('Bezeichnungen lesen', () {
    expect(TaskLabelLocator.parseLabel('Aufgabe 1a'), (number: '1', letter: 'a'));
    expect(TaskLabelLocator.parseLabel('2 b)'), (number: '2', letter: 'b'));
    expect(TaskLabelLocator.parseLabel('3'), (number: '3', letter: null));
    expect(TaskLabelLocator.parseLabel('Erkläre die Diffusion'), isNull);
  });

  test('Teilaufgabe unter ihrer Überschrift', () {
    expect(TaskLabelLocator.find(page, 'Aufgabe 1a'), [3]);
    expect(TaskLabelLocator.find(page, '1b'), [4]);
    expect(TaskLabelLocator.find(page, 'Aufgabe 2b'), [7]);
    expect(TaskLabelLocator.find(page, 'Aufgabe 2'), [5]);
  });

  test('direkt beschriftet und wörtlicher Text', () {
    expect(TaskLabelLocator.find(['3a) Bestimmen Sie', 'x'], '3a'), [0]);
    expect(TaskLabelLocator.find(page, 'Zeichnen Sie die Ebene'), [7]);
    expect(TaskLabelLocator.find(page, 'Aufgabe 7c'), isNull);
    expect(TaskLabelLocator.find(page, ''), isNull);
  });
}
