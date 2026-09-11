import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/material_item.dart';
import 'package:lernen/services/chat_context_builder.dart';

MaterialItem _material({
  required String id,
  required bool covered,
  required int textLength,
  required DateTime createdAt,
}) {
  return MaterialItem(
    id: id,
    moduleId: 'm1',
    fileName: '$id.pdf',
    kind: MaterialKind.slide,
    extractedText: 'x' * textLength,
    createdAt: createdAt,
    covered: covered,
  );
}

void main() {
  group('ChatContextBuilder.charBudgetForContextTokens', () {
    test('nutzt einen konservativen Fallback ohne bekannte Kontextlänge', () {
      expect(ChatContextBuilder.charBudgetForContextTokens(null), greaterThan(0));
    });

    test('größeres Kontextfenster ergibt größeres Budget', () {
      final small = ChatContextBuilder.charBudgetForContextTokens(8000);
      final large = ChatContextBuilder.charBudgetForContextTokens(1000000);
      expect(large, greaterThan(small));
    });
  });

  group('ChatContextBuilder.build', () {
    test('leere Materialliste ergibt einen Platzhaltertext', () {
      final result = ChatContextBuilder.build([], charBudget: 10000);
      expect(result, contains('keine Materialien'));
    });

    test('alles passt ins Budget: chronologische Reihenfolge, Status markiert', () {
      final t0 = DateTime(2026, 1, 1);
      final materials = [
        _material(id: 'lecture2', covered: true, textLength: 100, createdAt: t0.add(const Duration(days: 7))),
        _material(id: 'lecture1', covered: true, textLength: 100, createdAt: t0),
      ];
      final result = ChatContextBuilder.build(materials, charBudget: 100000);

      expect(result.contains('lecture1'), isTrue);
      expect(result.contains('lecture2'), isTrue);
      expect(result.indexOf('lecture1.pdf'), lessThan(result.indexOf('lecture2.pdf')));
      expect(result.contains('[Behandelt]'), isTrue);
    });

    test('markiert nicht behandelte Materialien entsprechend', () {
      final materials = [
        _material(id: 'future', covered: false, textLength: 50, createdAt: DateTime(2026, 2, 1)),
      ];
      final result = ChatContextBuilder.build(materials, charBudget: 100000);
      expect(result.contains('[Noch nicht behandelt]'), isTrue);
    });

    test('bevorzugt behandelte Materialien, wenn das Budget knapp ist', () {
      final t0 = DateTime(2026, 1, 1);
      final materials = [
        // Unbehandelt, aber chronologisch zuerst - sollte trotzdem NACH
        // dem behandelten Material priorisiert werden (nur Anriss/nichts).
        _material(id: 'early_uncovered', covered: false, textLength: 5000, createdAt: t0),
        _material(id: 'later_covered', covered: true, textLength: 5000, createdAt: t0.add(const Duration(days: 1))),
      ];
      // Budget reicht nur für EIN vollständiges Material.
      final result = ChatContextBuilder.build(materials, charBudget: 5100);

      expect(result.contains('later_covered.pdf'), isTrue);
      // Das vollständige (nicht gekürzte) Material ist das behandelte.
      final coveredBlockIndex = result.indexOf('later_covered.pdf');
      final coveredBlockLine = result.substring(result.lastIndexOf('---', coveredBlockIndex), coveredBlockIndex + 50);
      expect(coveredBlockLine.contains('nur Anriss'), isFalse);
    });

    test('sehr kleines Budget erwähnt Materialien gar nicht mehr statt leerem Anriss', () {
      final materials = [
        _material(id: 'a', covered: true, textLength: 100000, createdAt: DateTime(2026, 1, 1)),
        _material(id: 'b', covered: false, textLength: 100000, createdAt: DateTime(2026, 1, 2)),
      ];
      // Winziges Budget: reicht nicht mal für einen Anriss von 'b'.
      final result = ChatContextBuilder.build(materials, charBudget: 200);
      expect(result.contains('b.pdf'), isFalse);
    });
  });
}
