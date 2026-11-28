/// Inhaltsdatei für den Panik-Modus (Format `panik-content`, Version 1).
///
/// Die App enthält selbst keine Lerninhalte: Eine solche Datei kommt per
/// Claude-Postfach oder als JSON-Datei und wird beim Import zu einem eigenen
/// Fach (siehe PanikImport). Das Fach lässt sich wie jedes andere löschen.
///
/// Aufbau: `{format, version, subject, types: [...], items: [...]}`.
/// - Ein **Typ** ist ein Aufgabentyp („Trennung der Variablen“) mit
///   Erkennungsmerkmalen, Rezept, typischen Fehlern und Prüfungsgewicht.
/// - Ein **Eintrag** ist ein Lösungsbeispiel, eine Aufgabe, eine
///   Reserveaufgabe (nur für Probeklausuren), eine „Verfahren erkennen“-Frage
///   oder eine Formelkarte.
///
/// [PanikContent.parse] prüft alles streng und wirft eine [FormatException]
/// mit allen Fehlern – eine fehlerhafte Datei wird nie halb übernommen.
library;

/// Kennung im Feld `format`.
const panikContentFormat = 'panik-content';

/// Höchste Version, die diese App lesen kann.
const panikContentVersion = 1;

/// Art eines Eintrags.
enum PanikItemKind {
  /// Vollständig vorgerechnetes Lösungsbeispiel (Beispiel → Aufgabe).
  example,

  /// Übungsaufgabe: auf Papier rechnen, Schritt für Schritt abgleichen.
  task,

  /// Wird nur in Probeklausuren gestellt (vorher nie gesehen).
  reserve,

  /// „Verfahren erkennen“: nur die Aufgabenstellung, Antwort = Typ.
  recognize,

  /// Formelkarte zum Auswendiglernen.
  formula,
}

/// Ein Aufgabentyp.
class PanikType {
  const PanikType({
    required this.id,
    required this.title,
    required this.area,
    required this.core,
    required this.weight,
    this.weightReason = '',
    this.prerequisites = const [],
    this.recognition = const [],
    this.recipe = const [],
    this.mistakes = const [],
    this.sources = const [],
  });

  final String id;
  final String title;

  /// Themengebiet (z.B. „DGL“) – für gemischte Sätze.
  final String area;

  /// Pflichtkern (true) oder Ausbau (false).
  final bool core;

  /// Geschätztes Prüfungsgewicht: H, M oder N.
  final String weight;
  final String weightReason;
  final List<String> prerequisites;
  final List<String> recognition;
  final List<String> recipe;
  final List<String> mistakes;
  final List<String> sources;
}

/// Ein Schritt eines Rechenwegs: kurzes Prinzip-Etikett + Ergebnis (LaTeX).
class PanikStep {
  const PanikStep(this.label, this.result);
  final String label;
  final String result;
}

/// Ein Eintrag (Beispiel, Aufgabe, Reserve, Erkennen, Formel).
class PanikItem {
  const PanikItem({
    required this.id,
    required this.typeId,
    required this.kind,
    required this.prompt,
    required this.answer,
    this.source = '',
    this.steps = const [],
    this.options = const [],
    this.reason = '',
    this.fade = 0,
    this.verified = false,
    this.verifyNote = '',
  });

  final String id;
  final String typeId;
  final PanikItemKind kind;

  /// Aufgabenstellung (Text mit `$…$`) bzw. Vorderseite der Formelkarte.
  final String prompt;

  /// Endergebnis (reines LaTeX) bzw. Typ-ID (Erkennen) bzw. Rückseite (Formel).
  final String answer;

  /// Quelle, z.B. „S1-25“ (Skript 1, Seite 25) oder „neu“.
  final String source;

  /// Rechenweg (bei Beispiel, Aufgabe, Reserve).
  final List<PanikStep> steps;

  /// Typ-IDs zur Auswahl (bei Erkennen).
  final List<String> options;

  /// Begründung, woran man den Typ erkennt (bei Erkennen).
  final String reason;

  /// Wie viele Schritte in der Fading-Version zuerst verdeckt sind (0 = keine).
  final int fade;

  /// Lösung maschinell nachgerechnet (sonst sichtbar als „ungeprüft“).
  final bool verified;
  final String verifyNote;

  bool get hasSteps => kind == PanikItemKind.example || kind == PanikItemKind.task || kind == PanikItemKind.reserve;
}

class PanikContent {
  const PanikContent({required this.subject, required this.types, required this.items});

  final String subject;
  final List<PanikType> types;
  final List<PanikItem> items;

  /// Ist das eine Panik-Inhaltsdatei? (Erkennt sie ohne Fehlerprüfung.)
  static bool looksLike(Object? json) => json is Map && json['format'] == panikContentFormat;

  /// Liest und prüft die Datei. Wirft [FormatException] mit allen Fehlern.
  static PanikContent parse(Object? json) {
    if (!looksLike(json)) throw const FormatException('Keine Panik-Inhaltsdatei (format fehlt).');
    final map = json as Map;
    final errors = <String>[];
    final version = map['version'];
    if (version is! int || version < 1 || version > panikContentVersion) {
      throw FormatException('Version $version wird nicht unterstützt – bitte die App aktualisieren.');
    }
    final subject = _str(map['subject']);
    if (subject.isEmpty) errors.add('subject fehlt');

    final types = <PanikType>[];
    for (final (i, raw) in _list(map['types']).indexed) {
      if (raw is! Map) {
        errors.add('Typ $i ist kein Objekt');
        continue;
      }
      final id = _str(raw['id']);
      final tier = _str(raw['tier']);
      final weight = _str(raw['weight']);
      if (id.isEmpty || _str(raw['title']).isEmpty) errors.add('Typ $i: id oder title fehlt');
      if (tier != 'P' && tier != 'A') errors.add('Typ $id: tier muss P oder A sein');
      if (!const {'H', 'M', 'N'}.contains(weight)) errors.add('Typ $id: weight muss H, M oder N sein');
      types.add(PanikType(
        id: id,
        title: _str(raw['title']),
        area: _str(raw['area']),
        core: tier == 'P',
        weight: weight,
        weightReason: _str(raw['weightReason']),
        prerequisites: _strs(raw['prerequisites']),
        recognition: _strs(raw['recognition']),
        recipe: _strs(raw['recipe']),
        mistakes: _strs(raw['mistakes']),
        sources: _strs(raw['sources']),
      ));
    }
    final typeIds = {for (final t in types) t.id};
    if (typeIds.length != types.length) errors.add('doppelte Typ-IDs');
    for (final t in types) {
      for (final p in t.prerequisites) {
        if (!typeIds.contains(p)) errors.add('Typ ${t.id}: unbekannte Voraussetzung $p');
      }
    }

    final items = <PanikItem>[];
    final seen = <String>{};
    for (final (i, raw) in _list(map['items']).indexed) {
      if (raw is! Map) {
        errors.add('Eintrag $i ist kein Objekt');
        continue;
      }
      final id = _str(raw['id']);
      final kind = PanikItemKind.values.where((k) => k.name == raw['kind']).firstOrNull;
      final typeId = _str(raw['typeId']);
      if (id.isEmpty || !seen.add(id)) errors.add('Eintrag $i: ID leer oder doppelt ($id)');
      if (kind == null) {
        errors.add('Eintrag $id: unbekannte Art ${raw['kind']}');
        continue;
      }
      if (!typeIds.contains(typeId)) errors.add('Eintrag $id: unbekannter Typ $typeId');
      final task = raw['task'];
      final steps = [
        for (final s in _list(task is Map ? task['steps'] : null))
          if (s is Map) PanikStep(_str(s['title']), _str(s['result'])),
      ];
      final item = PanikItem(
        id: id,
        typeId: typeId,
        kind: kind,
        prompt: _str(raw['prompt']),
        answer: _str(raw['answer']),
        source: _str(raw['source']),
        steps: steps,
        options: _strs(raw['options']),
        reason: _str(raw['reason']),
        fade: (raw['fade'] as num?)?.toInt() ?? 0,
        verified: raw['verified'] == true,
        verifyNote: _str(raw['verifyNote']),
      );
      if (item.prompt.isEmpty || item.answer.isEmpty) errors.add('Eintrag $id: prompt oder answer fehlt');
      if (item.hasSteps && (steps.isEmpty || steps.any((s) => s.label.isEmpty || s.result.isEmpty))) {
        errors.add('Eintrag $id: Rechenweg fehlt oder hat leere Schritte');
      }
      if (kind == PanikItemKind.recognize) {
        if (!item.options.contains(item.answer)) errors.add('Eintrag $id: Antwort steht nicht in den Optionen');
        if (item.options.any((o) => !typeIds.contains(o))) errors.add('Eintrag $id: Option mit unbekanntem Typ');
      }
      // Verdeckt werden darf höchstens alles bis auf den ersten Schritt.
      if (item.fade != 0 && (!item.hasSteps || item.fade < 0 || item.fade >= steps.length)) {
        errors.add('Eintrag $id: fade passt nicht zur Schrittzahl');
      }
      items.add(item);
    }
    if (types.isEmpty) errors.add('keine Typen');
    if (items.isEmpty) errors.add('keine Einträge');
    if (errors.isNotEmpty) {
      final shown = errors.take(10).join('\n');
      throw FormatException('Panik-Inhaltsdatei fehlerhaft (${errors.length} Fehler):\n$shown');
    }
    return PanikContent(subject: subject, types: types, items: items);
  }
}

String _str(Object? v) => v == null ? '' : '$v'.trim();
List<Object?> _list(Object? v) => v is List ? v : const [];
List<String> _strs(Object? v) => [for (final e in _list(v)) if (_str(e).isNotEmpty) _str(e)];
