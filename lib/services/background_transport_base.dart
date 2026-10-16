/// Die Übertragung selbst ist gescheitert (keine HTTP-Antwort) – dann
/// versucht es AiService auf dem normalen Weg.
class BackgroundTransportException implements Exception {
  BackgroundTransportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Eine KI-Anfrage, die lief, als die App beendet wurde (siehe AiCrashGuard).
typedef PendingAiRequest = ({String label, int bytes, String via, DateTime startedAt});

/// Fehlercode, wenn die App mitten in einer KI-Anfrage oder einer großen
/// Aufgabe (z.B. PDFs für den Lernpfad lesen) beendet wurde.
const aiCrashCode = 'KI-HG-01';

/// Text für die Meldung nach einem Absturz während einer KI-Anfrage.
String aiCrashReport(List<PendingAiRequest> pending) {
  final p = pending.first;
  String two(int v) => v.toString().padLeft(2, '0');
  final at = p.startedAt;
  return [
    'Fehlercode $aiCrashCode – die App wurde mitten in einer Aufgabe beendet.',
    'Aufgabe: ${p.label.isEmpty ? 'unbekannt' : p.label}',
    if (p.bytes > 0) 'Größe der KI-Anfrage: ${(p.bytes / 1024).toStringAsFixed(1)} KB',
    'Weg: ${p.via}',
    'Gestartet: ${two(at.day)}.${two(at.month)}.${at.year} ${two(at.hour)}:${two(at.minute)}',
    if (pending.length > 1) 'Gleichzeitig liefen ${pending.length} Anfragen.',
  ].join('\n');
}
