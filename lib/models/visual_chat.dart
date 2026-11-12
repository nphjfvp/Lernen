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
    this.context = '',
    this.learn = false,
  });

  /// Lern-Chat zu einer Aufgabe („Lernen“ in der Lektion): erst Begriffe und
  /// Konzepte verstehen – die KI verrät die Lösung nicht.
  final bool learn;

  final String id;
  final String moduleId;

  /// Worauf sich das Gespräch bezieht (z.B. eine Aufgabe samt Lösungsweg aus
  /// „Aufgaben visuell lösen“) – geht bei jeder Frage an die KI mit.
  final String context;

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
      context: context,
      learn: learn,
    );
  }

  /// Das Gespräch als Lektion(en) – OHNE die KI noch einmal zu fragen: je
  /// Antwort ein Schritt mit genau dem Text und der Darstellung, die im Chat zu
  /// sehen waren (Titel = die Frage davor). Meist eine Lektion; rechnen
  /// Antworten mit verschiedenen Variablen oder Bereichen, entsteht je Gruppe
  /// eine eigene („… (Teil 2)“), damit jeder Graph so bleibt, wie er war.
  /// Gleich benannte, aber verschiedene Funktionen werden umbenannt.
  List<VisualLesson> toLessons({required String Function() newId, DateTime? now}) {
    final groups = <_LessonGroup>[];
    var question = '';
    var count = 0;
    for (final m in messages) {
      if (m.user) {
        question = m.text;
        continue;
      }
      final v = m.visual ?? const <String, dynamic>{};
      final functions = [
        if (v['functions'] is List)
          for (final f in v['functions'] as List)
            if (f is Map && _str(f['key']).isNotEmpty) Map<String, dynamic>.from(f),
      ];
      final variable = _str(v['variable']);
      final domain = '${v['domain'] ?? ''}';
      var group = groups.lastOrNull;
      final clash =
          group != null &&
          functions.isNotEmpty &&
          group.functions.isNotEmpty &&
          (group.variable != variable || group.domainKey != domain);
      if (group == null || clash) groups.add(group = _LessonGroup());
      if (functions.isNotEmpty && group.functions.isEmpty) {
        group
          ..variable = variable
          ..domain = v['domain']
          ..domainKey = domain;
      }
      // Gleicher Name, anderer Term: umbenennen und die Bezüge mitziehen.
      final renamed = <String, String>{};
      for (final f in functions) {
        var key = _str(f['key']);
        final known = group.functions[key];
        if (known != null && _str(known['expr']) != _str(f['expr'])) {
          var n = 2;
          while (group.functions.containsKey('${key}_$n')) {
            n++;
          }
          renamed[key] = '${key}_$n';
          key = '${key}_$n';
        }
        group.functions[key] = {...f, 'key': key};
      }
      String ref(Object? k) => renamed[_str(k)] ?? _str(k);
      final show = <String, dynamic>{
        if (v['show'] is Map) ...Map<String, dynamic>.from(v['show'] as Map),
        if (v['transform'] is List) 'transform': v['transform'],
      };
      if (renamed.isNotEmpty) {
        for (final k in const ['car', 'tangent', 'area']) {
          if (show[k] != null) show[k] = ref(show[k]);
        }
        final plot = show['plot'];
        if (plot is List) show['plot'] = [for (final p in plot) ref(p)];
        if (plot is String) show['plot'] = ref(plot);
      }
      count++;
      final asked = question.replaceAll(RegExp(r'\s+'), ' ').trim();
      group.steps.add({
        'title': asked.isEmpty ? 'Antwort $count' : (asked.length > 70 ? '${asked.substring(0, 70)}…' : asked),
        if (m.text.isNotEmpty) 'text': m.text,
        if (show.isNotEmpty) 'show': show,
      });
      group.intro ??= question;
      question = '';
    }
    final created = now ?? DateTime.now();
    return [
      for (final (i, g) in groups.indexed)
        ?VisualLesson.fromMap(
          {
            'title': groups.length == 1 ? displayTitle : '$displayTitle (Teil ${i + 1})',
            if ((g.intro ?? '').isNotEmpty) 'intro': g.intro,
            if (g.variable.isNotEmpty) 'variable': g.variable,
            'domain': ?g.domain,
            'functions': g.functions.values.toList(),
            'steps': g.steps,
          },
          id: newId(),
          moduleId: moduleId,
          createdAt: created,
          source: 'Visueller Chat: $displayTitle',
        ),
    ];
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    if (title.isNotEmpty) 'title': title,
    'messages': [for (final m in messages) m.toMap()],
    'createdAt': createdAt.toIso8601String(),
    if (context.isNotEmpty) 'context': context,
    if (learn) 'learn': true,
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
      context: _str(raw['context']),
      learn: raw['learn'] == true,
    );
  }
}

/// Antworten eines Gesprächs, die zusammen EINE Lektion ergeben (gleiche
/// Variable, gleicher Bereich) – siehe [VisualChat.toLessons].
class _LessonGroup {
  String variable = '';
  Object? domain;
  String domainKey = '';
  String? intro;
  final functions = <String, Map<String, dynamic>>{};
  final steps = <Map<String, dynamic>>[];
}
