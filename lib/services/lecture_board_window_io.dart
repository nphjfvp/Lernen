import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/worked_solution.dart';
import '../repositories/settings_repository.dart';
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

  /// [settings]: KI-Einstellungen (Key, Modelle) – damit im Tafel-Fenster Fragen
  /// und „feiner“ gehen; bleibt auf diesem Rechner.
  static Future<LectureBoardWindow?> open({
    Map<String, dynamic> settings = const {},
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
      socket.add(jsonEncode({'type': 'settings', 'settings': settings}));
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
  final _settings = _BoardSettings();

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
          if (message is! Map || !mounted) return;
          if (message['type'] == 'settings' && message['settings'] is Map) {
            _settings.apply(AppSettings.fromMap(Map<String, dynamic>.from(message['settings'] as Map)));
          } else if (message['type'] == 'state') {
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

  void _send(Map<String, Object?> message) => _socket?.add(jsonEncode(message));

  void _ask(String question, {int? formula}) => _send({'type': 'ask', 'text': question, 'formula': ?formula});

  void _refined(int concept, int step, int count, WorkedSolution updated) =>
      _send({'type': 'refined', 'concept': concept, 'step': step, 'count': count, 'solution': updated.toMap()});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<SettingsRepository>.value(
    value: _settings,
    child: MaterialApp(
      title: 'Lernen – Tafel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Scaffold(
        body: SafeArea(
          child: LectureBoardView(
            state: _state,
            onAsk: _ask,
            onSelect: (concept) => _send({'type': 'select', 'concept': concept}),
            onRefined: _refined,
          ),
        ),
      ),
    ),
  );
}

/// Die KI-Einstellungen aus dem Hauptfenster (das Tafel-Fenster öffnet keine
/// Datenbank).
class _BoardSettings extends SettingsRepository {
  AppSettings _received = const AppSettings();

  @override
  AppSettings get settings => _received;

  void apply(AppSettings settings) {
    _received = settings;
    notifyListeners();
  }
}
