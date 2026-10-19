import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/services/html_question_bridge.dart';
import 'package:lernen/services/html_question_contract.dart';

void main() {
  test('Brücke steht als erstes Skript im head – vor dem Code der KI', () {
    final page = wrapHtmlQuestionPage('<script>FlutterAnswer.postMessage("{}")</script>');
    final bridged = withHtmlQuestionBridge(page, 'abc');
    final bridge = bridged.indexOf('window.FlutterAnswer=');
    expect(bridge, greaterThan(bridged.indexOf('<head>')));
    expect(bridge, lessThan(bridged.indexOf('FlutterAnswer.postMessage("{}")')));
    expect(bridged, contains('lernenHtmlAnswer:"abc"'));
    expect(bridged, contains("default-src 'none'"), reason: 'CSP bleibt');
    expect(withHtmlQuestionBridge('<p>ohne head</p>', 'x'), startsWith('<script>'));
  });

  test('Nur Nachrichten der eigenen Seite zählen', () {
    expect(
      htmlQuestionBridgeMessage({'lernenHtmlAnswer': 'abc', 'message': '{"correct":true}'}, 'abc'),
      '{"correct":true}',
    );
    expect(htmlQuestionBridgeMessage({'lernenHtmlAnswer': 'fremd', 'message': 'x'}, 'abc'), isNull);
    expect(htmlQuestionBridgeMessage({'lernenHtmlAnswer': 'abc', 'message': 3}, 'abc'), isNull);
    expect(htmlQuestionBridgeMessage('{"correct":true}', 'abc'), isNull);
    expect(htmlQuestionBridgeMessage(null, 'abc'), isNull);
  });

  test('Token kann das Skript nicht aufbrechen', () {
    final s = htmlQuestionBridgeScript('a"</script><b>');
    expect(s, isNot(contains('</script><b>')));
    expect(RegExp('</script>').allMatches(s), hasLength(1));
  });
}
