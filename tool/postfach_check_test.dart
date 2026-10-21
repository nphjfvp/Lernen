// Prüft eine Postfach-Lieferung mit genau dem Leser der App, bevor sie
// abgeschickt wird (siehe .claude/skills/postfach/SKILL.md):
//
//   POSTFACH_FILE=/pfad/aufgaben.json flutter test tool/postfach_check_test.dart
//
// Mit POSTFACH_PROMPT=/pfad/prompt.txt schreibt er stattdessen die
// Format-Regeln (dieselben wie für externe KIs) in die Datei.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/ai_service.dart';

void main() {
  final promptOut = Platform.environment['POSTFACH_PROMPT'];
  final file = Platform.environment['POSTFACH_FILE'];

  test('Postfach-Lieferung', () {
    if (promptOut != null) {
      File(promptOut).writeAsStringSync(AiService.externalTaskPrompt);
      // ignore: avoid_print
      print('Format-Regeln geschrieben: $promptOut');
      return;
    }
    expect(file, isNotNull, reason: 'POSTFACH_FILE setzen');
    final result = AiService.parseImportedTasks(File(file!).readAsStringSync());
    final lines = <String>[];
    var problems = 0;
    for (final (i, d) in result.drafts.indexed) {
      final String what;
      if (d.kind != null) {
        what = 'interaktiv: ${d.kind!.name}${d.incomplete ? ' – UNVOLLSTÄNDIG' : ''}';
        if (d.incomplete) problems++;
      } else if (d.questionData != null) {
        what = 'Frage: ${d.questionData!['type'] ?? '?'}';
      } else if (d.asQuestion) {
        what = 'Frage (App-KI baut sie erst, ${d.questionType})';
      } else {
        what = 'NICHT INTERAKTIV → Sammelliste (${d.needs.isEmpty ? d.reason : d.needs})';
        problems++;
      }
      final front = d.front.replaceAll('\n', ' ');
      lines.add('${i + 1}. $what – ${front.length > 70 ? '${front.substring(0, 70)}…' : front}');
    }
    // ignore: avoid_print
    print([...lines, '${result.drafts.length} gelesen, ${result.dropped} verworfen, $problems Hinweis(e)'].join('\n'));
    expect(result.drafts, isNotEmpty, reason: 'keine Aufgabe lesbar');
    expect(result.dropped, 0, reason: 'unvollständige Einträge – JSON prüfen');
  });
}
