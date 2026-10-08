import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/flashcard.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/daily/question_answer_view.dart';
import 'package:lernen/ui/tasks/bom_task_view.dart';

Map<String, dynamic> _stored(String type, Map<String, dynamic>? taskData) => {
  'id': 'k1',
  'moduleId': 'm1',
  'front': 'Erstellen Sie die Strukturstückliste.',
  'back': '',
  'createdAt': '2026-10-01T00:00:00.000',
  'due': '2026-10-01T00:00:00.000',
  'type': type,
  'taskData': taskData,
};

const _bom = {
  'kind': 'bom',
  'root': {
    'nr': '10',
    'children': [
      {'nr': '20', 'qty': 2},
    ],
  },
  'parts': [
    {'list': 'structure'},
  ],
};

void main() {
  test('von einer älteren App-Version als Karteikarte gespeichert: wird wieder zur Aufgabe', () {
    // Ältere Versionen kannten "bom" nicht und haben beim Lernen "flashcard" gespeichert.
    expect(Flashcard.fromMap(_stored('flashcard', _bom)).type, QuestionType.bom);
    expect(Flashcard.fromMap(_stored('bom', _bom)).type, QuestionType.bom);
    expect(Flashcard.fromMap(_stored('irgendwas', {..._bom, 'kind': 'sketch'})).type, QuestionType.sketch);
    // Normale Karteikarten bleiben, was sie sind.
    expect(Flashcard.fromMap(_stored('flashcard', null)).type, QuestionType.flashcard);
    expect(Flashcard.fromMap(_stored('freeText', {'kind': 'bom'})).type, QuestionType.freeText);
  });

  testWidgets('Aufgabe einer neueren App-Version: Hinweis statt stiller Karteikarte', (tester) async {
    Future<void> show(Flashcard card) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: QuestionAnswerView(card: card, isNew: false, onComplete: ({selfGrade, isCorrect}) {}),
              ),
            ],
          ),
        ),
      ),
    );

    await show(Flashcard.fromMap(_stored('hologram', {'kind': 'hologram'})));
    expect(find.byKey(const ValueKey('question-needs-update')), findsOneWidget);

    await show(Flashcard.fromMap(_stored('flashcard', _bom)));
    await tester.pump();
    expect(find.byKey(const ValueKey('question-needs-update')), findsNothing);
    expect(find.byType(BomTaskView), findsOneWidget);
  });
}
