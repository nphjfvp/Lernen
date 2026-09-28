/// Ausgang eines Updates aus der App heraus (siehe installUpdate).
enum UpdateInstallResult {
  /// Installation läuft (Windows: die App beendet sich; Android: der
  /// System-Dialog "Aktualisieren?" ist offen).
  started,

  /// Android: Lernen darf noch keine Apps installieren – die passende
  /// Einstellung wurde geöffnet, danach nochmal versuchen.
  needsPermission,

  /// Hat nicht geklappt – Download im Browser als Ausweg.
  failed,
}
