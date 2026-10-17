/// Visueller Chat in „Visuell lernen“: frei fragen, ohne PDF – die KI
/// antwortet mit Text und/oder einer Darstellung (Szene, 3D, Graph, Fahrzeug,
/// Umformung). Ein Gespräch je [VisualChat], mehrere je Fach.
library;

import 'visual_lesson.dart';

String _str(Object? raw) => '${raw ?? ''}'.trim();

/// Wie die Antwort aussehen soll.
enum VisualChatMode { visual, text, both }

/// Eine Nachricht des Gesprächs.
class VisualChatMessage {
  const VisualChatMessage({
    required this.user,
    required this.text,
    this.mode = VisualChatMode.both,
    this.visual,
    required this.createdAt,
  });

  final bool user;
  final String text;

  /// Gewünschte Art (bei Fragen) bzw. gelieferte (bei Antworten).
  final VisualChatMode mode;

  /// Darstellung der Antwort im Lektionsformat: variable, domain, functions,
  /// show (scene, scene3d, car, plot …) und transform. null = nur Text.
  final Map<String, dynamic>? visual;
  final DateTime createdAt;

  /// Die Darstellung als Ein-Schritt-Lektion (Funktionen geprüft) – null ohne.
  VisualLesson? get visualLesson {
    final v = visual;
    if (v == null) return null;
    final show = <String, dynamic>{
      if (v['show'] is Map) ...Map<String, dynamic>.from(v['show'] as Map),
      if (v['transform'] is List) 'transform': v['transform'],
    };
    if (show.isEmpty) return null;
    final lesson = VisualLesson.fromMap({
      'title': 'Antwort',
      'variable': v['variable'],
      'domain': v['domain'],
      'functions': v['functions'],
      'steps': [
        {'title': 'Antwort', 'show': show},
      ],
    }, createdAt: createdAt);
    // Auch eine ganz unlesbare Darstellung zurückgeben (mit Grund in broken).
    final s = lesson?.steps.single.show;
    return s == null || (s.isEmpty && s.broken.isEmpty) ? null : lesson;
  }

  Map<String, dynamic> toMap() => {
    'user': user,
    'text': text,
    'mode': mode.name,
    'visual': ?visual,
    'createdAt': createdAt.toIso8601String(),
  };

  static VisualChatMessage? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final text = _str(raw['text']);
    final visual = raw['visual'] is Map ? Map<String, dynamic>.from(raw['visual'] as Map) : null;
    if (text.isEmpty && visual == null) return null;
    return VisualChatMessage(
      user: raw['user'] == true,
      text: text,
      mode: VisualChatMode.values.where((m) => m.name == raw['mode']).firstOrNull ?? VisualChatMode.both,
      visual: visual,
      createdAt: DateTime.tryParse(_str(raw['createdAt'])) ?? DateTime.now(),
    );
  }
}

/// Ein Gespräch.
class VisualChat {
  const VisualChat({
    required this.id,
    required this.moduleId,
    this.title = '',
    this.messages = const [],
    required this.createdAt,
  });

  final String id;
  final String moduleId;

  /// Kurzer Titel (von der KI bei der ersten Antwort).
  final String title;
  final List<VisualChatMessage> messages;
  final DateTime createdAt;

  /// Höchstens so viele Nachrichten bleiben gespeichert.
  static const maxMessages = 80;

  DateTime get updatedAt => messages.isEmpty ? createdAt : messages.last.createdAt;

  String get displayTitle {
    if (title.isNotEmpty) return title;
    final first = messages.where((m) => m.user).firstOrNull?.text ?? '';
    if (first.isEmpty) return 'Neuer Chat';
    return first.length > 50 ? '${first.substring(0, 50)}…' : first;
  }

  VisualChat withMessage(VisualChatMessage m, {String? title}) {
    final all = [...messages, m];
    return VisualChat(
      id: id,
      moduleId: moduleId,
      title: (title ?? '').isNotEmpty && this.title.isEmpty ? title! : this.title,
      messages: all.length > maxMessages ? all.sublist(all.length - maxMessages) : all,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    if (title.isNotEmpty) 'title': title,
    'messages': [for (final m in messages) m.toMap()],
    'createdAt': createdAt.toIso8601String(),
  };

  static VisualChat? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = _str(raw['id']);
    final moduleId = _str(raw['moduleId']);
    if (id.isEmpty || moduleId.isEmpty) return null;
    return VisualChat(
      id: id,
      moduleId: moduleId,
      title: _str(raw['title']),
      messages: [
        if (raw['messages'] is List)
          for (final m in raw['messages'] as List) ?VisualChatMessage.fromMap(m),
      ],
      createdAt: DateTime.tryParse(_str(raw['createdAt'])) ?? DateTime.now(),
    );
  }
}
