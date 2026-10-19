import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Screen Wake Lock API (Safari ab iOS 16.4, Chrome, Edge). Der Browser gibt
/// die Sperre selbst frei, sobald die Seite unsichtbar wird – kommt sie
/// zurück, solange noch eine Anfrage läuft, wird sie neu angefordert.
bool _wanted = false;
web.WakeLockSentinel? _sentinel;
bool _listening = false;

void setAwake(bool awake) {
  _wanted = awake;
  if (awake) {
    if (!_listening) {
      _listening = true;
      web.document.addEventListener(
        'visibilitychange',
        ((web.Event _) {
          if (_wanted && web.document.visibilityState == 'visible') _request();
        }).toJS,
      );
    }
    _request();
  } else {
    final s = _sentinel;
    _sentinel = null;
    if (s != null) {
      try {
        s.release();
      } catch (_) {}
    }
  }
}

Future<void> _request() async {
  if (_sentinel != null && !_sentinel!.released) return;
  try {
    final s = await web.window.navigator.wakeLock.request('screen').toDart;
    if (_wanted) {
      _sentinel = s;
    } else {
      s.release();
    }
  } catch (_) {
    // Nicht unterstützt oder abgelehnt (z.B. Energiesparmodus) – egal.
  }
}
