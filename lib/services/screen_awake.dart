import 'screen_awake/screen_awake_stub.dart'
    if (dart.library.js_interop) 'screen_awake/screen_awake_web.dart'
    as platform;

/// Hält den Bildschirm an, solange eine KI-Anfrage läuft. Nötig im Browser
/// (iPad/iPhone): Safari hält eine Seite an, sobald das Gerät sperrt – eine
/// minutenlange Anfrage bräche dann ab. Android hat dafür den
/// Hintergrund-Transport, auf den übrigen Plattformen tut [hold] nichts.
class ScreenAwake {
  ScreenAwake._();

  static int _holds = 0;

  /// Wie viele Anfragen den Bildschirm gerade wach halten.
  static int get holds => _holds;

  /// Hält den Bildschirm wach, bis die zurückgegebene Funktion aufgerufen
  /// wird (mehrfaches Aufrufen schadet nicht).
  static void Function() hold() {
    if (_holds++ == 0) platform.setAwake(true);
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_holds == 0) platform.setAwake(false);
    };
  }
}
