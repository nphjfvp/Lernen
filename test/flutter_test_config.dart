import 'dart:async';

import 'package:lernen/services/ai_service.dart';

/// Gilt für alle Tests: KI-Anfragen ohne automatische Wiederholung, damit
/// simulierte Fehler (500, offline …) sofort durchkommen statt Sekunden zu
/// warten. Tests der Wiederholung setzen [AiService.retryDelays] selbst.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AiService.retryDelays = const [];
  await testMain();
}
