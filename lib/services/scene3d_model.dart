import '../models/ai_model_info.dart';

/// Welches Modell räumliche Szenen zeichnet, wenn der Nutzer keines dafür
/// gewählt hat („3D-Modell erzeugen“, 3D-Szenen der zweiten Stufe).
///
/// Günstige Allzweck-Modelle setzen Koordinaten im Raum deutlich schlechter
/// als die aktuellen Flash-Modelle von Google; das steht so in den
/// Vergleichen für 3D/CAD-Erzeugung (Stand November 2026), in denen ein
/// Gemini-Flash-Modell bei kleinem Budget jeweils vorn lag. Die Liste ist
/// eine Rangfolge – genommen wird das erste Modell, das der Katalog des
/// Geräts wirklich kennt. So bricht nichts, wenn es eine Kennung nicht (mehr)
/// gibt.
class Scene3dModel {
  const Scene3dModel._();

  /// Beste zuerst.
  static const candidates = [
    'google/gemini-3.8-flash',
    'google/gemini-3.7-flash',
    'google/gemini-3.6-flash',
    'deepseek/deepseek-v4-pro',
    'deepseek/deepseek-v4-pro-0813',
  ];

  /// Das Modell für 3D ohne eigene Wahl. Es bleibt beim Fragen-Modell
  /// ([questionModelId]), wenn
  /// - der Katalog keinen der Kandidaten kennt (z.B. noch nie geladen),
  /// - das Fragen-Modell kostenlos ist (dann soll 3D nicht plötzlich kosten),
  /// - das Fragen-Modell teurer ist als der Kandidat (dann hat der Nutzer
  ///   bewusst ein stärkeres gewählt).
  static String auto({required String questionModelId, required AiModelInfo? Function(String id) info}) {
    final own = info(questionModelId);
    if (own != null && own.isFree) return questionModelId;
    for (final id in candidates) {
      if (id == questionModelId) return id;
      final candidate = info(id);
      if (candidate == null) continue;
      final ownPrice = own?.completionPricePerMillion, price = candidate.completionPricePerMillion;
      if (ownPrice != null && price != null && ownPrice > price) return questionModelId;
      return id;
    }
    return questionModelId;
  }
}
