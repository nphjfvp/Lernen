import 'dart:convert';

/// Fehlerantworten von OpenRouter verstehen: welche sich ein erneuter Versuch
/// lohnt und wie man sie dem Nutzer erklärt (statt den rohen Antwort-Body zu
/// zeigen – der bleibt in `AiServiceException.rawResponse` für die Details).
class OpenRouterErrors {
  OpenRouterErrors._();

  /// Vorübergehend: Zeitüberschreitung (408/504), zu viele Anfragen (429 –
  /// bei kostenlosen Modellen häufig), Anbieter nicht erreichbar (502/503).
  /// 500 bewusst nicht: meist ein echter Fehler der Anfrage.
  static const transientCodes = {408, 429, 502, 503, 504};

  /// Fehlercode einer Antwort: der HTTP-Status oder – OpenRouter meldet
  /// Fehler des Anbieters mitten in der Antwort auch mit 200 – der Code im
  /// `error`-Feld des Bodys. null = kein Fehler.
  static int? codeOf(int status, String body) {
    if (status != 200) return status;
    final error = _errorOf(body);
    if (error == null) return null;
    final code = error is Map ? error['code'] : null;
    return code is num ? code.toInt() : int.tryParse('$code') ?? 500;
  }

  static bool isTransient(int status, String body) => transientCodes.contains(codeOf(status, body));

  /// Wartezeit aus dem `Retry-After`-Header (Sekunden), höchstens [max].
  static Duration? retryAfter(Map<String, String> headers, {Duration max = const Duration(seconds: 30)}) {
    final value = headers['retry-after'] ?? headers['Retry-After'];
    final seconds = int.tryParse(value?.trim() ?? '');
    if (seconds == null || seconds < 0) return null;
    final wait = Duration(seconds: seconds);
    return wait > max ? max : wait;
  }

  /// Verständliche Meldung für Fehler [code]; [attempts] > 1 = schon so oft
  /// versucht.
  static String message(int code, String body, {int attempts = 1}) {
    final detail = detailOf(body);
    final tried = attempts > 1 ? ' – auch nach $attempts Versuchen' : '';
    final withDetail = detail.isEmpty ? '' : ': $detail';
    return switch (code) {
      401 => 'OpenRouter lehnt den API-Key ab (401) – bitte in den Einstellungen prüfen.',
      402 => 'Kein Guthaben mehr bei OpenRouter (402) – Guthaben aufladen oder ein kostenloses Modell wählen.',
      403 => 'Der Anbieter des Modells hat die Anfrage abgelehnt (403)$withDetail',
      404 =>
        'Modell oder Funktion bei OpenRouter nicht gefunden (404)$withDetail – ggf. in den Einstellungen '
            'ein anderes Modell wählen.',
      408 || 504 => 'Zeitüberschreitung beim Anbieter des Modells ($code)$tried. Bitte später erneut versuchen.',
      429 =>
        'Zu viele Anfragen (429)$tried – das Modell ist ausgelastet oder ein Limit ist erreicht '
            '(kostenlose Modelle haben Tageslimits). Später erneut versuchen oder ein anderes Modell wählen.',
      502 || 503 =>
        'Der Anbieter des Modells ist gerade nicht erreichbar ($code)$tried. Später erneut versuchen '
            'oder ein anderes Modell wählen.',
      _ => 'OpenRouter-Anfrage fehlgeschlagen ($code)$withDetail',
    };
  }

  /// Die Fehlerbeschreibung aus dem Body (`error.message`), sonst der Body
  /// selbst – beides gekürzt.
  static String detailOf(String body) {
    final error = _errorOf(body);
    final text = switch (error) {
      {'message': final String m} => m,
      final String s => s,
      _ => error == null ? body : '',
    };
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 200 ? '${clean.substring(0, 200)}…' : clean;
  }

  static Object? _errorOf(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? decoded['error'] : null;
    } catch (_) {
      return null; // kein JSON
    }
  }
}
