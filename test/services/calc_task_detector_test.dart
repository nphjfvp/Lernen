import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/services/calc_task_detector.dart';

Flashcard _card(
  String front, {
  String back = '',
  QuestionType type = QuestionType.freeText,
  String? correct,
  List<QuizOption>? options,
  List<String>? blanks,
  bool? calc,
}) =>
    Flashcard(
      id: 'c',
      moduleId: 'm',
      front: front,
      back: back,
      createdAt: DateTime(2026, 1, 1),
      due: DateTime(2026, 1, 1),
      type: type,
      correctText: correct,
      options: options,
      blanks: blanks,
      needsCalculator: calc,
    );

void main() {
  group('Rechenaufgaben erkennen', () {
    test('echte Rechenaufgaben', () {
      expect(CalcTaskDetector.looksLikeCalc(_card('Berechne den Strom bei U = 12,3 V und R = 4,7 kΩ.', correct: '2,62 mA')), isTrue);
      expect(CalcTaskDetector.looksLikeCalc(_card('Wie groß ist die Leistung bei 230 V und 2,5 A?', correct: '575 W')), isTrue);
      expect(
        CalcTaskDetector.looksLikeCalc(_card(r'Ein Kondensator mit $C = 2,2 \cdot 10^{-6}$ F wird über 1 kΩ geladen. Zeitkonstante?',
            correct: '2,2 ms')),
        isTrue,
      );
      // Lösung als Zahl mit Einheit + zwei Größen reicht auch ohne "berechne".
      expect(CalcTaskDetector.looksLikeCalc(_card('Ein Draht: l = 25 m, A = 1,5 mm². Widerstand?', correct: '0,29 Ω')), isTrue);
    });

    test('Single Choice mit Zahlen und Lückentext mit Zahlen', () {
      expect(
        CalcTaskDetector.looksLikeCalc(_card('Berechne die Frequenz bei T = 2,5 ms.',
            type: QuestionType.singleChoice,
            options: const [QuizOption(text: '400 Hz', isCorrect: true), QuizOption(text: '40 Hz', isCorrect: false)])),
        isTrue,
      );
      expect(
        CalcTaskDetector.looksLikeCalc(_card('Bei 12 V und 3 Ω fließen ___ A.', type: QuestionType.fillBlank, blanks: const ['4'])),
        isTrue,
      );
    });

    test('keine Rechenaufgaben: Wissen, Kopfrechnen, Nummerierung', () {
      expect(CalcTaskDetector.looksLikeCalc(_card('Was besagt das Ohmsche Gesetz?', correct: 'U = R · I')), isFalse);
      expect(CalcTaskDetector.looksLikeCalc(_card('Was ist 2 + 3?', correct: '5')), isFalse);
      expect(CalcTaskDetector.looksLikeCalc(_card('Aufgabe 3: Nenne die 2 Kirchhoffschen Regeln.', correct: 'Knoten- und Maschenregel')), isFalse);
      expect(CalcTaskDetector.looksLikeCalc(_card('In welchem Jahr formulierte Ohm sein Gesetz?', correct: '1827')), isFalse);
      expect(CalcTaskDetector.looksLikeCalc(_card('Berechne nichts, erkläre den Begriff Spannung.', correct: 'Potentialdifferenz')), isFalse);
    });

    test('die Angabe an der Karte geht der Erkennung vor', () {
      expect(CalcTaskDetector.isCalcTask(_card('Was ist ein Widerstand?', calc: true)), isTrue);
      expect(CalcTaskDetector.isCalcTask(_card('Berechne I bei 12 V und 4 Ω.', correct: '3 A', calc: false)), isFalse);
      expect(CalcTaskDetector.isCalcTask(_card('Berechne I bei 12 V und 4 Ω.', correct: '3 A')), isTrue);
    });

    test('Größen zählen und Zahlen-Lösungen erkennen', () {
      expect(CalcTaskDetector.quantityCount('U = 12 V, I = 0,5 A, 3 Widerstände'), 2);
      expect(CalcTaskDetector.quantityCount('1,5·10^-3 m und 4.7e3'), 2);
      expect(CalcTaskDetector.isNumericAnswer('≈ 27,3 Ω'), isTrue);
      expect(CalcTaskDetector.isNumericAnswer('-3,5 m/s'), isTrue);
      expect(CalcTaskDetector.isNumericAnswer(r'$2,2 \cdot 10^{-3}$ s'), isFalse); // LaTeX-Befehl: keine reine Zahl
      expect(CalcTaskDetector.isNumericAnswer('Die Spannung steigt'), isFalse);
    });
  });
}
