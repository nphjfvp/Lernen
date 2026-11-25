// Meldet der Browser eine Verbindung? Außerhalb des Browsers immer true.
// (Siehe main.dart: offline wartet der Web-Start nicht auf Firebase.)
export 'browser_online_stub.dart' if (dart.library.js_interop) 'browser_online_web.dart';
