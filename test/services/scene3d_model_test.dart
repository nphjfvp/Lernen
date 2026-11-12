import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/ai_model_info.dart';
import 'package:lernen/services/scene3d_model.dart';

AiModelInfo _model(String id, {double out = 1, bool free = false}) => AiModelInfo(
  id: id,
  name: id,
  contextLength: 200000,
  promptPricePerMillion: free ? 0 : out / 4,
  completionPricePerMillion: free ? 0 : out,
  supportsVision: true,
  isFree: free,
);

void main() {
  String auto(String question, List<AiModelInfo> catalog) =>
      Scene3dModel.auto(questionModelId: question, info: (id) => catalog.where((m) => m.id == id).firstOrNull);

  test('ohne Katalog oder ohne bekannten Kandidaten bleibt es beim Fragen-Modell', () {
    expect(auto('deepseek/deepseek-chat', const []), 'deepseek/deepseek-chat');
    expect(auto('deepseek/deepseek-chat', [_model('deepseek/deepseek-chat'), _model('x/y')]), 'deepseek/deepseek-chat');
  });

  test('das beste verfügbare 3D-Modell der Rangfolge wird genommen', () {
    final cheap = _model('deepseek/deepseek-chat', out: 0.4);
    expect(
      auto('deepseek/deepseek-chat', [
        cheap,
        _model('deepseek/deepseek-v4-pro', out: 0.9),
        _model('google/gemini-3.8-flash', out: 3.75),
      ]),
      'google/gemini-3.8-flash',
    );
    // Gibt es das neueste nicht (mehr), rückt das nächste nach.
    expect(
      auto('deepseek/deepseek-chat', [cheap, _model('deepseek/deepseek-v4-pro', out: 0.9)]),
      'deepseek/deepseek-v4-pro',
    );
    expect(
      auto('deepseek/deepseek-chat', [cheap, _model('google/gemini-3.7-flash', out: 3.75)]),
      'google/gemini-3.7-flash',
    );
  });

  test('wer ohnehin ein teureres (stärkeres) Fragen-Modell nutzt, behält es auch für 3D', () {
    final catalog = [_model('stark/modell', out: 25), _model('google/gemini-3.8-flash', out: 3.75)];
    expect(auto('stark/modell', catalog), 'stark/modell');
    // Ist das Fragen-Modell selbst ein Kandidat, bleibt es.
    expect(auto('google/gemini-3.8-flash', catalog), 'google/gemini-3.8-flash');
  });

  test('ein kostenloses Fragen-Modell wird nicht heimlich durch ein kostenpflichtiges ersetzt', () {
    final catalog = [_model('frei/modell:free', free: true), _model('google/gemini-3.8-flash', out: 3.75)];
    expect(auto('frei/modell:free', catalog), 'frei/modell:free');
  });
}
