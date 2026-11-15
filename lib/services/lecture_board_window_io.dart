import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/lecture/lecture_board.dart';

/// Tafel in einem eigenen Fenster: Die Lern-App startet sich ein zweites Mal
/// im Tafel-Modus (`--lecture-board=<Port>:<Schlüssel>`) und schickt ihr über
/// einen lokalen Kanal (nur dieser Rechner, mit Zufallsschlüssel) jeden neuen
/// Stand; Fragen aus dem Tafel-Fenster kommen zurück. Das Fenster lässt sich
/// frei verschieben – z.B. auf den zweiten Bildschirm.
class LectureBoardWindow {
  LectureBoardWindow._(this._server, this._token);

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Test-Hook statt des zweiten App-Starts.
  @visibleForTesting
  static Future<Process?> Function(String executable, List<String> arguments)? launchHook;

  final HttpServer _server;
  final String _token;
  Process? _process;
  final _sockets = <WebSocket>[];
  LectureBoardState? _last;
  bool _closed = false;

  /// Ist das Tafel-Fenster verbunden?
  final connected = ValueNotifier<bool>(false);

  String get argument => '--lecture-board=${_server.port}:$_token';

  static Future<LectureBoardWindow?> open({
    required void Function(Map<String, dynamic> action) onAction,
    VoidCallback? onClosed,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final token = [for (var i = 0; i < 24; i++) random.nextInt(16).toRadixString(16)].join();
    final window = LectureBoardWindow._(server, token);
    void finish() {
      if (window._closed) return;
      window._closed = true;
      window.connected.value = false;
      unawaited(server.close(force: true));
      onClosed?.call();
    }

    server.listen((request) async {
      if (request.uri.queryParameters['t'] != token || !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      window._sockets.add(socket);
      window.connected.value = true;
      final last = window._last;
      if (last != null) socket.add(jsonEncode({'type': 'state', 'state': last.toMap()}));
      socket.listen(
        (data) {
          try {
            final message = jsonDecode('$data');
            if (message is Map) onAction(Map<String, dynamic>.from(message));
          } catch (_) {
            // Unlesbares ignorieren.
          }
        },
        onDone: () {
          window._sockets.remove(socket);
          if (window._sockets.isEmpty) finish();
        },
        cancelOnError: true,
      );
    });
    final launch = launchHook;
    final process = launch != null
        ? await launch(Platform.resolvedExecutable, [window.argument])
        : await Process.start(Platform.resolvedExecutable, [window.argument]);
    window._process = process;
    unawaited(process?.exitCode.then((_) => finish()));
    return window;
  }

  /// Neuen Stand an das Tafel-Fenster schicken.
  void send(LectureBoardState state) {
    _last = state;
    final text = jsonEncode({'type': 'state', 'state': state.toMap()});
    for (final s in [..._sockets]) {
      s.add(text);
    }
  }

  Future<void> close() async {
    _closed = true;
    connected.value = false;
    for (final s in [..._sockets]) {
      await s.close();
    }
    _sockets.clear();
    await _server.close(force: true);
    _process?.kill();
  }
}

/// Tafel-Modus: statt der ganzen App nur die Tafel, gespeist vom Hauptfenster.
Future<void> runLectureBoardClient(String argument) async {
  final parts = argument.split(':');
  final port = int.tryParse(parts.first) ?? 0;
  final token = parts.length > 1 ? parts[1] : '';
  runApp(LectureBoardApp(port: port, token: token));
}

class LectureBoardApp extends StatefulWidget {
  const LectureBoardApp({super.key, required this.port, required this.token});

  final int port;
  final String token;

  @override
  State<LectureBoardApp> createState() => _LectureBoardAppState();
}

class _LectureBoardAppState extends State<LectureBoardApp> {
  WebSocket? _socket;
  LectureBoardState _state = const LectureBoardState(busy: true, busyText: 'Verbinde mit der Lern-App …');

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      final socket = await WebSocket.connect('ws://127.0.0.1:${widget.port}/?t=${widget.token}');
      _socket = socket;
      socket.listen(
        (data) {
          final message = jsonDecode('$data');
          if (message is Map && message['type'] == 'state' && mounted) {
            setState(() => _state = LectureBoardState.fromMap(message['state']));
          }
        },
        // Hauptfenster weg: Tafel-Fenster schließen.
        onDone: () => exit(0),
        cancelOnError: true,
      );
    } catch (_) {
      exit(0);
    }
  }

  void _ask(String question, {int? formula}) =>
      _socket?.add(jsonEncode({'type': 'ask', 'text': question, 'formula': ?formula}));

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lernen – Tafel',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    home: Scaffold(
      body: SafeArea(
        child: LectureBoardView(state: _state, onAsk: _ask),
      ),
    ),
  );
}
