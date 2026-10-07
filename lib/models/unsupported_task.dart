/// Eine Übungsaufgabe, die die App noch nicht interaktiv prüfen kann (die KI
/// hat beim "Aufgabe übernehmen" gesagt: passt nicht). Gesammelt, damit man
/// sieht, welche Bedienarten am häufigsten fehlen – siehe
/// UnsupportedTasksScreen.
class UnsupportedTask {
  const UnsupportedTask({
    required this.id,
    required this.moduleId,
    required this.text,
    required this.createdAt,
    this.reason = '',
    this.needs = '',
    this.sourceMaterialId,
    this.sourcePage,
    this.cardIds = const [],
  });

  final String id;
  final String moduleId;

  /// Die Aufgabe (wortgetreu, so wie die KI sie gelesen hat).
  final String text;

  /// Warum es (noch) nicht passt.
  final String reason;

  /// Welche Bedienart fehlt, in wenigen Wörtern ("Kurve in Diagramm zeichnen").
  final String needs;
  final String? sourceMaterialId;
  final int? sourcePage;
  final DateTime createdAt;

  /// Karten, die schon aus dieser Aufgabe erstellt wurden („Fragen dazu
  /// erstellen“ – nicht interaktiv, z.B. als Lernaufgabe mit Lösungsweg).
  /// Die Aufgabe bleibt trotzdem auf der Liste, die Bedienart fehlt ja weiter.
  final List<String> cardIds;

  bool get hasCards => cardIds.isNotEmpty;

  /// Gleiche Aufgabe = gleicher Text (Leerzeichen und Groß/klein egal).
  static String sameKey(String text) => text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Gruppe in der Liste: die fehlende Bedienart, sonst "Sonstiges".
  String get group {
    final n = needs.trim();
    if (n.isEmpty) return 'Sonstiges';
    return n[0].toUpperCase() + n.substring(1);
  }

  UnsupportedTask copyWith({
    String? reason,
    String? needs,
    DateTime? createdAt,
    String? sourceMaterialId,
    int? sourcePage,
    List<String>? cardIds,
  }) => UnsupportedTask(
    id: id,
    moduleId: moduleId,
    text: text,
    createdAt: createdAt ?? this.createdAt,
    reason: reason ?? this.reason,
    needs: needs ?? this.needs,
    sourceMaterialId: sourceMaterialId ?? this.sourceMaterialId,
    sourcePage: sourcePage ?? this.sourcePage,
    cardIds: cardIds ?? this.cardIds,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    'text': text,
    'reason': reason,
    'needs': needs,
    'sourceMaterialId': sourceMaterialId,
    'sourcePage': sourcePage,
    'createdAt': createdAt.toIso8601String(),
    if (cardIds.isNotEmpty) 'cardIds': cardIds,
  };

  factory UnsupportedTask.fromMap(Map<String, dynamic> map) => UnsupportedTask(
    id: '${map['id'] ?? ''}',
    moduleId: '${map['moduleId'] ?? ''}',
    text: '${map['text'] ?? ''}',
    reason: '${map['reason'] ?? ''}',
    needs: '${map['needs'] ?? ''}',
    sourceMaterialId: map['sourceMaterialId'] as String?,
    sourcePage: (map['sourcePage'] as num?)?.toInt(),
    createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    cardIds: [
      if (map['cardIds'] is List)
        for (final id in map['cardIds'] as List) '$id',
    ],
  );

  /// Nach fehlender Bedienart gruppiert (Groß/klein egal), die häufigste
  /// zuerst, "Sonstiges" zuletzt.
  static List<({String group, List<UnsupportedTask> tasks})> grouped(List<UnsupportedTask> tasks) {
    final byKey = <String, List<UnsupportedTask>>{};
    for (final t in tasks) {
      byKey.putIfAbsent(t.group.toLowerCase(), () => []).add(t);
    }
    final groups = [for (final list in byKey.values) (group: list.first.group, tasks: list)];
    groups.sort((a, b) {
      if ((a.group == 'Sonstiges') != (b.group == 'Sonstiges')) return a.group == 'Sonstiges' ? 1 : -1;
      final byCount = b.tasks.length.compareTo(a.tasks.length);
      return byCount != 0 ? byCount : a.group.compareTo(b.group);
    });
    return groups;
  }

  /// Die Liste als Text zum Kopieren und Weiterschicken.
  static String exportText(List<UnsupportedTask> tasks, {String? title, String Function(String moduleId)? moduleName}) {
    final buffer = StringBuffer()
      ..writeln(
        'Noch nicht interaktiv – ${tasks.length} ${tasks.length == 1 ? 'Aufgabe' : 'Aufgaben'}'
        '${title == null || title.isEmpty ? '' : ' ($title)'}',
      )
      ..writeln('Gruppiert nach der Bedienart, die der App fehlt.');
    for (final g in grouped(tasks)) {
      buffer
        ..writeln()
        ..writeln('## ${g.group} (${g.tasks.length})');
      for (final t in g.tasks) {
        var text = t.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.length > 400) text = '${text.substring(0, 400)} …';
        buffer.writeln('- $text');
        if (t.reason.trim().isNotEmpty) buffer.writeln('  Grund: ${t.reason.trim()}');
        final where = [
          if (moduleName != null && moduleName(t.moduleId).isNotEmpty) 'Fach: ${moduleName(t.moduleId)}',
          if (t.sourcePage != null) 'Seite ${t.sourcePage}',
        ];
        if (where.isNotEmpty) buffer.writeln('  (${where.join(', ')})');
      }
    }
    return buffer.toString().trimRight();
  }
}
