import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/html_question_contract.dart';

void main() {
  group('wrapHtmlQuestionPage', () {
    test('bettet das Body-Fragment unverändert ein', () {
      final page = wrapHtmlQuestionPage('<div id="quiz">Frage</div>');
      expect(page, contains('<div id="quiz">Frage</div>'));
    });

    test('enthält eine restriktive Content-Security-Policy ohne Netzwerkzugriff', () {
      final page = wrapHtmlQuestionPage('<div></div>');
      expect(page, contains("default-src 'none'"));
      expect(page, contains("script-src 'unsafe-inline'"));
      expect(page, contains("style-src 'unsafe-inline'"));
    });

    test('liefert ein vollständiges Dokument mit dem Fragment im <body>', () {
      final page = wrapHtmlQuestionPage('<p>x</p>');
      expect(page, contains('<!DOCTYPE html>'));
      expect(page.indexOf('<body>'), lessThan(page.indexOf('<p>x</p>')));
      expect(page.indexOf('<p>x</p>'), lessThan(page.indexOf('</body>')));
    });

    test('htmlAnswerChannelName entspricht dem in den Prompts dokumentierten Kanalnamen', () {
      expect(htmlAnswerChannelName, 'FlutterAnswer');
    });
  });
}
