import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/paper_review.dart';
import 'package:lernen/theme/app_theme.dart';
import 'package:lernen/ui/tasks/hand_math.dart';

List<HandNode> _parse(String s) => HandMathParser(s).parse().where((n) => !(n is HandText && n.space)).toList();

String _texts(HandNode n) => switch (n) {
  HandText(:final text) => text,
  HandGroup(:final items, :final parens) => '${parens ? '(' : ''}${items.map(_texts).join()}${parens ? ')' : ''}',
  HandFrac(:final num, :final den) => '[${_texts(num)}/${_texts(den)}]',
  HandSup(:final base, :final exp) => '${_texts(base)}^{${_texts(exp)}}',
  HandSub(:final base, :final sub) => '${_texts(base)}_{${_texts(sub)}}',
  HandSqrt(:final body) => '√{${_texts(body)}}',
};

void main() {
  test('Brüche, Hoch-/Tiefstellung, Wurzel, Klammern, Zeichen', () {
    expect(_parse('dy/dx = 2x').map(_texts).join(' '), '[dy/dx] = 2 x');
    expect(_parse('a = (1000 mm - 650 mm)/2').map(_texts).join(' '), 'a = [1000 mm − 650 mm/2]');
    expect(_parse('F / 2').single, isA<HandFrac>(), reason: 'Leerzeichen um / erlaubt');
    expect(_texts(_parse('d_1^3').single), 'd_{1}^{3}');
    expect(_texts(_parse('sigma_{ba,vorh}').single), 'σ_{ba,vorh}');
    expect(_texts(_parse('x²').single), 'x^{2}');
    expect(_texts(_parse('√(12 - 2*x)').single), '√{12 − 2·x}');
    expect(_texts(_parse('sqrt(x)').single), '√{x}');
    expect(_parse('a => b <= c != d').whereType<HandText>().where((t) => t.op).map((t) => t.text), ['⇒', '≤', '≠']);
    expect(_parse('1,25*6000').map(_texts), ['1,25', '·', '6000']);
    // Kaputtes bleibt lesbar statt abzustürzen.
    expect(() => HandMathParser(')(^_/{').parse(), returnsNormally);
    expect(() => HandMathParser('x^').parse(), returnsNormally);
  });

  testWidgets('Rechenblatt: Zeilen live, Haken, leer mit Hinweis, groß ansehen', (tester) async {
    var expanded = false;
    Future<void> show(List<String> lines, {Map<int, PaperLineStatus> statuses = const {}}) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: HandwrittenSheet(lines: lines, statuses: statuses, resultLine: 1, onExpand: () => expanded = true),
          ),
        ),
      ),
    );
    await show(const ['', '']);
    expect(find.textContaining('erscheint dein Rechenweg'), findsOneWidget);
    await show(const ['a = F/2', 'b = 3', ''], statuses: const {0: PaperLineStatus.ok, 1: PaperLineStatus.error});
    expect(find.byKey(const ValueKey('hand-line-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('hand-line-2')), findsNothing, reason: 'leere Zeilen nicht');
    expect(find.byKey(const ValueKey('hand-mark-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('hand-mark-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hand-sheet-expand')));
    expect(expanded, isTrue);
  });
}
