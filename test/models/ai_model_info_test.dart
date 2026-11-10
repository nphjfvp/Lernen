import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/ai_model_info.dart';

AiModelInfo _model({int? context, int? maxOut}) => AiModelInfo.fromOpenRouterJson({
  'id': 'x/y',
  'name': 'Y',
  'context_length': context,
  'pricing': {'prompt': '0.000001', 'completion': '0.000002'},
  'top_provider': {'max_completion_tokens': maxOut},
});

void main() {
  test('Ausgabe-Limit aus dem Katalog, gespeichert und gelesen', () {
    final m = _model(context: 64000, maxOut: 8192);
    expect(m.maxOutputTokens, 8192);
    expect(m.requestMaxTokens, 8192);
    expect(AiModelInfo.fromMap(m.toMap()).maxOutputTokens, 8192);
    // Älterer gespeicherter Stand ohne das Feld.
    expect(AiModelInfo.fromMap(m.toMap()..remove('maxOutputTokens')).requestMaxTokens, isNull);
  });

  test('max_tokens je Anfrage: gedeckelt, höchstens das halbe Kontextfenster, sonst nichts', () {
    expect(_model(context: 1000000, maxOut: 128000).requestMaxTokens, AiModelInfo.requestCap);
    expect(_model(context: 16000, maxOut: 16000).requestMaxTokens, 8000);
    expect(_model(context: 64000).requestMaxTokens, isNull, reason: 'kein Limit gemeldet');
    expect(_model(context: 64000, maxOut: 512).requestMaxTokens, isNull, reason: 'unplausibel klein');
    expect(_model(maxOut: 4096).requestMaxTokens, 4096, reason: 'ohne Kontextangabe');
  });
}
