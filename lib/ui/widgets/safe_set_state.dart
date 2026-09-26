import 'package:flutter/widgets.dart';

/// Ignoriert `setState` nach dem Schließen des Screens. KI-Aufrufe dauern
/// teils Minuten – verlässt der Nutzer den Screen in der Zeit, würde jedes
/// spätere `setState` (Erfolg ODER Fehlerzweig) sonst einen Fehler werfen.
/// Deckt alle Stellen nach einem `await` ab, statt jede einzeln mit
/// `if (!mounted) return;` absichern zu müssen.
mixin SafeSetState<T extends StatefulWidget> on State<T> {
  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }
}
