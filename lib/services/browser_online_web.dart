import 'package:web/web.dart' as web;

/// `navigator.onLine`: false heißt sicher offline (true kann auch ein
/// Netz ohne Internet sein).
bool browserOnline() {
  try {
    return web.window.navigator.onLine;
  } catch (_) {
    return true;
  }
}
