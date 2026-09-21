import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/chat_message.dart';

void main() {
  group('ChatMessage – toMap/fromMap Round-Trip', () {
    test('erhält alle Felder inkl. sourceFileNames', () {
      final message = ChatMessage(
        id: '1',
        moduleId: 'm1',
        role: ChatRole.assistant,
        content: 'Antwort',
        createdAt: DateTime(2026, 1, 1),
        sourceFileNames: const ['Folie1.pdf', 'Folie2.pdf'],
      );
      final restored = ChatMessage.fromMap(message.toMap());
      expect(restored.role, ChatRole.assistant);
      expect(restored.content, 'Antwort');
      expect(restored.sourceFileNames, ['Folie1.pdf', 'Folie2.pdf']);
    });

    test('sourceFileNames bleibt eine leere Liste (bewusst "kein Material genutzt")', () {
      final message = ChatMessage(
        id: '1',
        moduleId: 'm1',
        role: ChatRole.assistant,
        content: 'Antwort',
        createdAt: DateTime(2026, 1, 1),
        sourceFileNames: const [],
      );
      final restored = ChatMessage.fromMap(message.toMap());
      expect(restored.sourceFileNames, isNotNull);
      expect(restored.sourceFileNames, isEmpty);
    });

    test('sourceFileNames ist null, wenn nicht angegeben (Material-Kontext-Schalter war aus)', () {
      final message = ChatMessage(
        id: '1',
        moduleId: 'm1',
        role: ChatRole.user,
        content: 'Frage',
        createdAt: DateTime(2026, 1, 1),
      );
      final restored = ChatMessage.fromMap(message.toMap());
      expect(restored.sourceFileNames, isNull);
    });

    test('ist abwärtskompatibel zu älteren Datensätzen ohne sourceFileNames-Feld', () {
      final legacyMap = {
        'id': '1',
        'moduleId': 'm1',
        'role': 'assistant',
        'content': 'Antwort',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final restored = ChatMessage.fromMap(legacyMap);
      expect(restored.sourceFileNames, isNull);
    });
  });
}
