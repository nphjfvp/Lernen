import 'package:flutter/foundation.dart';

import '../ui/lecture/lecture_board.dart';

/// Im Web gibt es kein eigenes Tafel-Fenster.
class LectureBoardWindow {
  LectureBoardWindow._();

  static bool get supported => false;

  final connected = ValueNotifier<bool>(false);

  static Future<LectureBoardWindow?> open({
    required void Function(Map<String, dynamic> action) onAction,
    VoidCallback? onClosed,
  }) async => null;

  void send(LectureBoardState state) {}

  Future<void> close() async {}
}

/// Nur am PC: die Lern-App als Tafel-Fenster.
Future<void> runLectureBoardClient(String argument) async {}
