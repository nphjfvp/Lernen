import '../models/flashcard.dart';
import 'html_question_contract.dart';

/// Gemeinsame Parsing-Hilfen für von der KI generierte Fragen-JSON-Objekte
/// (siehe AiService.generateConceptsAndFlashcards / generateHarderVariant) –
/// wird sowohl beim initialen Erstellen (ReviewScreen) als auch bei der
/// Schwierigkeits-Eskalation (DailyQuizScreen) gebraucht.
class QuestionParsing {
  QuestionParsing._();

  // Die parse*-Funktionen verarbeiten ungeprüfte KI-Ausgabe: ein einzelnes
  // abweichend geformtes Element (Option als reiner String, "isCorrect":
  // "true", fehlendes Feld) darf nicht per TypeError die gesamte
  // Generierung abbrechen – unbrauchbare Elemente werden übersprungen,
  // [normalizeGeneratedFlashcard] entscheidet danach über Rettung/Verwerfen.

  static List<QuizOption>? parseOptions(dynamic raw) {
    if (raw is! List) return null;
    final options = <QuizOption>[];
    for (final o in raw) {
      if (o is Map) {
        final text = o['text'];
        if (text == null) continue;
        final isCorrect = o['isCorrect'];
        options.add(QuizOption(
          text: text.toString(),
          isCorrect: isCorrect == true || isCorrect == 1 || const {'true', '1'}.contains(isCorrect.toString().toLowerCase()),
        ));
      } else if (o != null) {
        options.add(QuizOption(text: o.toString(), isCorrect: false));
      }
    }
    return options;
  }

  static List<String>? parseBlanks(dynamic raw) {
    if (raw is! List) return null;
    return raw.where((b) => b != null).map((b) => b.toString()).toList();
  }

  static List<DragPair>? parseDragPairs(dynamic raw) {
    if (raw is! List) return null;
    return [
      for (final p in raw)
        if (p is Map && p['source'] != null && p['target'] != null)
          DragPair(source: p['source'].toString(), target: p['target'].toString()),
    ];
  }

  /// Kette für die Schwierigkeits-Eskalation "einfach -> mittel -> schwer"
  /// (Single-Choice -> Lückentext -> Freitext) – wird gesetzt, wenn die KI
  /// eine Single-Choice-Frage explizit mit `"escalate": true` markiert hat.
  static const escalationChain = [
    QuestionType.singleChoice,
    QuestionType.fillBlank,
    QuestionType.freeText,
  ];

  static const _aiTypeAliases = {
    'flashcard': QuestionType.flashcard,
    'single_choice': QuestionType.singleChoice,
    'multiple_choice': QuestionType.multipleChoice,
    'free_text': QuestionType.freeText,
    'fill_blank': QuestionType.fillBlank,
    'drag_drop': QuestionType.dragDrop,
    'drag_category': QuestionType.dragCategory,
    'html': QuestionType.html,
    'diagram_label': QuestionType.diagramLabel,
    'mark_image': QuestionType.markImage,
    'table': QuestionType.table,
    'learn': QuestionType.learn,
  };

  /// Wandelt den von der KI gelieferten "type"-String (snake_case, siehe
  /// AiService-Prompts, z.B. "single_choice") in [QuestionType] um.
  ///
  /// WICHTIG: bewusst NICHT dasselbe wie [questionTypeFromString] – jene
  /// Funktion vergleicht gegen die camelCase-Enum-Namen (`singleChoice`) wie
  /// sie intern für die DB-Persistierung (`Flashcard.toMap`/`fromMap`)
  /// verwendet werden. Ein von der KI/Crosscheck geliefertes JSON mit
  /// "single_choice" würde dort NIE matchen und still auf `flashcard`
  /// zurückfallen (der eigentliche Grund, warum früher scheinbar nur noch
  /// einfache Karteikarten ohne Rückseite erzeugt wurden) – deshalb hier
  /// eine eigene, für das KI-JSON-Format zuständige Zuordnung.
  static QuestionType parseType(String? value) => _parseTypeOrNull(value) ?? QuestionType.flashcard;

  /// Weitere Schreibweisen, die Modelle trotz Vorgabe liefern (camelCase,
  /// Leerzeichen/Bindestriche, Abkürzungen, deutsch) – vorher fiel jede
  /// davon still auf "flashcard" zurück, und aus einer Auswahlfrage wurde
  /// eine offene Karte.
  static const _typeSynonyms = {
    'sc': 'single_choice',
    'single': 'single_choice',
    'singlechoice': 'single_choice',
    'single_answer': 'single_choice',
    'choice': 'single_choice',
    'einfachauswahl': 'single_choice',
    'mc': 'multiple_choice',
    'multi': 'multiple_choice',
    'multiplechoice': 'multiple_choice',
    'multi_choice': 'multiple_choice',
    'multiple_answer': 'multiple_choice',
    'mehrfachauswahl': 'multiple_choice',
    'freitext': 'free_text',
    'freetext': 'free_text',
    'short_answer': 'free_text',
    'open': 'free_text',
    'luckentext': 'fill_blank',
    'lückentext': 'fill_blank',
    'lueckentext': 'fill_blank',
    'cloze': 'fill_blank',
    'fillblank': 'fill_blank',
    'fill_in_the_blank': 'fill_blank',
    'fill_in_blank': 'fill_blank',
    'fill_the_blank': 'fill_blank',
    'gap_fill': 'fill_blank',
    'zuordnen': 'drag_drop',
    'zuordnung': 'drag_drop',
    'matching': 'drag_drop',
    'match': 'drag_drop',
    'dragdrop': 'drag_drop',
    'drag_and_drop': 'drag_drop',
    'kategorien': 'drag_category',
    'kategorie': 'drag_category',
    'categorize': 'drag_category',
    'categorization': 'drag_category',
    'dragcategory': 'drag_category',
    'karteikarte': 'flashcard',
    'card': 'flashcard',
    'open_question': 'flashcard',
    'interaktiv': 'html',
    'interactive': 'html',
    'bild_beschriften': 'diagram_label',
    'diagramlabel': 'diagram_label',
    'labeling': 'diagram_label',
    'bild_markieren': 'mark_image',
    'markimage': 'mark_image',
    'hotspot': 'mark_image',
    'tabelle': 'table',
    'table_fill': 'table',
    'fill_table': 'table',
    'tabelle_ausfuellen': 'table',
    'tabelle_ausfüllen': 'table',
    'lernen': 'learn',
    'lernaufgabe': 'learn',
    'aufgabe': 'learn',
    'task': 'learn',
    'exercise': 'learn',
    'worked_example': 'learn',
    'explain': 'learn',
    'explanation': 'learn',
    'verstehen': 'learn',
  };

  static QuestionType? _parseTypeOrNull(String? value) {
    if (value == null) return null;
    final direct = _aiTypeAliases[value];
    if (direct != null) return direct;
    final key = value
        .trim()
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-/]+'), '_');
    return _aiTypeAliases[key] ?? _aiTypeAliases[_typeSynonyms[key] ?? _typeSynonyms[key.replaceAll('_', '')] ?? ''];
  }

  /// Gegenstück zu [parseType]: der snake_case-Name eines Typs im KI-JSON
  /// (z.B. für Prompts, die einen bestimmten Typ verlangen).
  static String aiTypeName(QuestionType type) =>
      _aiTypeAliases.entries.firstWhere((e) => e.value == type).key;

  /// Prüft einen von der KI generierten Karteikarten-Eintrag auf
  /// Vollständigkeit für seinen deklarierten Typ und repariert ihn bei
  /// Bedarf: fehlen die für den Typ nötigen Felder, aber es lässt sich
  /// anderswo im Eintrag noch eine brauchbare Antwort finden (z.B. weil das
  /// Modell "correctText" statt "options" geliefert hat), wird der Eintrag
  /// als einfache Karteikarte (type: flashcard) gerettet statt verworfen.
  /// Nur wenn sich GAR keine Antwort finden lässt, wird `null` zurückgegeben
  /// (vom Aufrufer zu verwerfen) – so landen keine stummen
  /// "nur Vorderseite ohne Antwort"-Karten in der App.
  static Map<String, dynamic>? normalizeGeneratedFlashcard(Map<String, dynamic> original) {
    final raw = canonicalize(original);
    final front = (raw['front'] ?? '').toString().trim();
    if (front.isEmpty) return null;

    final type = parseType(raw['type']?.toString());
    if (_isComplete(raw, type)) return _sanitized(_withStringFields(raw), type);

    // Lückentext ohne "___"-Markierung mit genau einer Lösung ist eine
    // Freitextfrage – als Lückentext wüsste man nicht, wo die Lücke ist.
    if (type == QuestionType.fillBlank) {
      final blanks = _nonEmptyBlanks(raw);
      if (blanks.length == 1 && blankMarkerCount(front) == 0) {
        return {
          ..._withStringFields(raw)..remove('blanks'),
          'type': 'free_text',
          'correctText': blanks.single,
        };
      }
    }

    // Zuordnen mit nur EINEM Ziel (ein Paar bzw. alles in dieselbe
    // Kategorie) wäre geschenkt – als Freitext fragen, wohin die Begriffe
    // gehören, dann muss man es wirklich wissen.
    if (type == QuestionType.dragDrop || type == QuestionType.dragCategory) {
      final pairs = _usablePairs(raw);
      final targets = {for (final p in pairs) p.target.trim()};
      if (pairs.isNotEmpty && targets.length == 1) {
        return {
          ..._withStringFields(raw)..remove('dragPairs'),
          'type': 'free_text',
          'front': '$front\n${[for (final p in pairs) '„${p.source.trim()}“'].join(', ')}',
          'correctText': targets.single,
        };
      }
    }

    final fallbackAnswer = _bestAvailableAnswer(raw);
    if (fallbackAnswer == null) return null;
    return {
      'type': 'flashcard',
      'front': front,
      'back': fallbackAnswer,
      if (raw['conceptTitle'] != null) 'conceptTitle': raw['conceptTitle'].toString(),
      if (raw['level'] != null) 'level': raw['level'],
      if (raw['group'] != null) 'group': raw['group'],
      // Die KI wollte hier einen präziseren Typ (single_choice/free_text/
      // html/…), aber die Antwort war unvollständig – markiert, damit der
      // Import das nicht stumm verschluckt, sondern anzeigt/nachfragt statt
      // einfach eine schlichte Karteikarte zu speichern (siehe
      // PdfQuestionImportScreen/ReviewScreen).
      if (type != QuestionType.flashcard) 'typeDowngraded': true,
      if (type != QuestionType.flashcard) 'requestedType': type.name,
    };
  }

  static Object? _first(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final value = raw[key];
      if (value != null && !(value is String && value.trim().isEmpty)) return value;
    }
    return null;
  }

  /// Optionen schon im erwarteten Format ({text, isCorrect}, mindestens eine
  /// richtig) – dann bleibt der Eintrag unverändert.
  static bool _wellFormedOptions(Object? options) =>
      options is List &&
      options.isNotEmpty &&
      options.every((o) => o is Map && o.containsKey('text') && o.containsKey('isCorrect')) &&
      options.any((o) => (o as Map)['isCorrect'] == true);

  static bool _truthy(Object? v) =>
      v == true || v == 1 || const {'true', '1', 'yes', 'ja', 'richtig', 'correct'}.contains('$v'.trim().toLowerCase());

  /// Bringt abweichend geformte KI-Einträge in das erwartete Format, bevor
  /// sie geprüft werden: Typ in anderer Schreibweise oder gar nicht
  /// angegeben (dann aus der Struktur abgeleitet), Frage/Antwort unter
  /// anderen Namen, Optionen als reine Texte mit separat genannter Lösung
  /// (Text, Buchstabe oder Index), "correct" statt "isCorrect", Paare als
  /// left/right oder als Objekt, Lücken als Text. Vorhandene, schon richtig
  /// benannte Felder bleiben unverändert.
  static Map<String, dynamic> canonicalize(Map<String, dynamic> raw) {
    final entry = {...raw};
    void fill(String key, Object? value) {
      if (value != null && (entry[key] == null || (entry[key] is String && (entry[key] as String).trim().isEmpty))) {
        entry[key] = value;
      }
    }

    fill('front', _first(raw, const ['question', 'frage', 'prompt', 'aufgabe', 'task']));

    final declared = _parseTypeOrNull(raw['type']?.toString());
    final isChoice = declared == QuestionType.singleChoice || declared == QuestionType.multipleChoice;

    // Optionen: andere Feldnamen, Texte statt Objekte, Lösung separat.
    // "answers" gilt nur bei einer (vermuteten) Auswahlfrage als Optionen –
    // bei einem Lückentext sind es die Lösungen.
    final rawOptions = _first(raw, [
      'options',
      'choices',
      'optionen',
      if (isChoice || declared == null) ...['answers', 'antworten'],
    ]);
    if (rawOptions is List && rawOptions.isNotEmpty && !_wellFormedOptions(raw['options'])) {
      final options = <Map<String, dynamic>>[];
      for (final o in rawOptions) {
        if (o is Map) {
          final text = _first(Map<String, dynamic>.from(o), const ['text', 'option', 'label', 'answer', 'content', 'value']);
          if (text == null) continue;
          final flag = _first(Map<String, dynamic>.from(o),
              const ['isCorrect', 'correct', 'is_correct', 'isRight', 'right', 'richtig', 'isTrue']);
          options.add({'text': text.toString(), 'isCorrect': _truthy(flag)});
        } else if (o != null && o is! List) {
          options.add({'text': o.toString(), 'isCorrect': false});
        }
      }
      if (options.isNotEmpty && !options.any((o) => o['isCorrect'] == true)) {
        _markCorrectOptions(options, raw);
      }
      if (options.isNotEmpty && (raw['options'] != null || isChoice || options.length >= 2)) {
        entry['options'] = options;
      }
    }

    // Lücken als Text oder als Listen von Varianten.
    final rawBlanks = _first(raw, [
      'blanks',
      'gaps',
      'luecken',
      'lücken',
      if (declared == QuestionType.fillBlank) ...['answers', 'solutions', 'antworten'],
    ]);
    if (raw['blanks'] is List && (raw['blanks'] as List).every((b) => b is String)) {
      // schon im erwarteten Format
    } else if (rawBlanks is String) {
      entry['blanks'] = rawBlanks.split('|').map((b) => b.trim()).where((b) => b.isNotEmpty).toList();
    } else if (rawBlanks is List) {
      entry['blanks'] = [
        for (final b in rawBlanks)
          if (b is List) b.map((v) => v.toString()).join('; ') else if (b != null) b.toString(),
      ];
    }

    // Paare: left/right, term/definition … oder ein Objekt {Begriff: Ziel}.
    final rawPairs = _first(raw, const ['dragPairs', 'pairs', 'matches', 'matching', 'zuordnungen']);
    final pairsWellFormed = raw['dragPairs'] is List &&
        (raw['dragPairs'] as List).every((p) => p is Map && p.containsKey('source') && p.containsKey('target'));
    if (pairsWellFormed) {
      // schon im erwarteten Format
    } else if (rawPairs is Map) {
      entry['dragPairs'] = [
        for (final e in rawPairs.entries) {'source': e.key.toString(), 'target': e.value.toString()},
      ];
    } else if (rawPairs is List) {
      entry['dragPairs'] = [
        for (final p in rawPairs)
          if (p is List && p.length >= 2)
            {'source': p[0].toString(), 'target': p[1].toString()}
          else if (p is Map)
            () {
              final m = Map<String, dynamic>.from(p);
              final source = _first(m, const ['source', 'left', 'term', 'begriff', 'item', 'from', 'a']);
              final target =
                  _first(m, const ['target', 'right', 'definition', 'match', 'ziel', 'category', 'kategorie', 'to', 'b']);
              return {'source': source?.toString(), 'target': target?.toString()};
            }(),
      ].where((p) => p['source'] != null && p['target'] != null).toList();
    }

    fill('htmlContent', _first(raw, const ['html']));

    // Typ: tolerant lesen, sonst aus der Struktur ableiten.
    final type = declared ?? _inferType(entry, raw);
    entry['type'] = aiTypeName(type);

    // Lösung/Rückseite unter anderen Namen.
    final answer = _first(raw, const ['answer', 'antwort', 'solution', 'loesung', 'lösung', 'correctAnswer', 'musterloesung']);
    if (answer != null && answer is! List && answer is! Map) {
      if (type == QuestionType.freeText) fill('correctText', answer.toString());
      if (type == QuestionType.flashcard || type == QuestionType.html) fill('back', answer.toString());
    }
    // Lernaufgabe: die Erklärung/der Lösungsweg steht in "back".
    if (type == QuestionType.learn) {
      final explanation = _first(raw, const [
        'explanation',
        'erklaerung',
        'erklärung',
        'loesungsweg',
        'lösungsweg',
        'solutionSteps',
        'walkthrough',
        'musterloesung',
        'musterlösung',
        'solution',
        'loesung',
        'lösung',
        'answer',
        'antwort',
      ]);
      if (explanation != null && explanation is! Map) {
        fill('back', explanation is List ? explanation.map((e) => '$e').join('\n') : explanation.toString());
      }
    }
    return entry;
  }

  /// Optionen ohne Kennzeichnung: die separat genannte Lösung zuordnen –
  /// als Text, Buchstabe ("B", "b)") oder Index (0-basiert).
  static void _markCorrectOptions(List<Map<String, dynamic>> options, Map<String, dynamic> raw) {
    final hint = _first(raw, const [
      'correctIndex',
      'correct_index',
      'answerIndex',
      'correctIndices',
      'correctOption',
      'correctOptions',
      'correctAnswer',
      'correctAnswers',
      'correct',
      'answer',
      'solution',
      'loesung',
      'lösung',
    ]);
    if (hint == null) return;
    String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'^[\(\[]?[a-z][\)\].:]\s+'), '').trim();
    void mark(Object value) {
      if (value is num) {
        final i = value.toInt();
        if (i >= 0 && i < options.length) options[i]['isCorrect'] = true;
        return;
      }
      final text = value.toString().trim();
      final letter = RegExp(r'^[\(\[]?([A-Za-z])[\)\].:]?$').firstMatch(text);
      if (letter != null && options.length <= 26) {
        final i = letter.group(1)!.toUpperCase().codeUnitAt(0) - 65;
        if (i >= 0 && i < options.length) {
          options[i]['isCorrect'] = true;
          return;
        }
      }
      for (final o in options) {
        if (norm(o['text'] as String) == norm(text) || (o['text'] as String).trim().toLowerCase() == text.toLowerCase()) {
          o['isCorrect'] = true;
        }
      }
    }

    if (hint is List) {
      for (final h in hint) {
        if (h != null) mark(h);
      }
    } else {
      mark(hint);
    }
  }

  /// Die Zeilen einer Tabellen-Frage, egal unter welchem Namen die KI sie
  /// liefert.
  static List<List<QuestionTableCell>>? tableRowsIn(Map<String, dynamic> raw) =>
      parseTableRows(raw['tableRows']) ?? parseTableRows(raw['table']) ?? parseTableRows(raw['tabelle']);

  static bool _hasFillableCell(List<List<QuestionTableCell>>? rows) =>
      rows != null && rows.any((r) => r.any((c) => !c.given && c.text.trim().isNotEmpty));

  /// Typ aus dem, was der Eintrag enthält, wenn "type" fehlt oder unbekannt ist.
  static QuestionType _inferType(Map<String, dynamic> entry, Map<String, dynamic> raw) {
    if ((entry['htmlContent'] ?? '').toString().contains(htmlAnswerChannelName)) return QuestionType.html;
    if (_hasFillableCell(tableRowsIn(raw))) return QuestionType.table;
    final targets = imageTargetsIn(raw);
    if (targets != null && targets.isNotEmpty) {
      return targets.any((t) => t.label.isNotEmpty) ? QuestionType.diagramLabel : QuestionType.markImage;
    }
    final options = parseOptions(entry['options']);
    if (options != null && options.length >= 2) {
      return options.where((o) => o.isCorrect).length > 1 ? QuestionType.multipleChoice : QuestionType.singleChoice;
    }
    if ((parseBlanks(entry['blanks']) ?? const []).isNotEmpty) return QuestionType.fillBlank;
    if ((parseDragPairs(entry['dragPairs']) ?? const []).isNotEmpty) return QuestionType.dragDrop;
    if ((raw['correctText'] ?? '').toString().trim().isNotEmpty) return QuestionType.freeText;
    return QuestionType.flashcard;
  }

  /// Schwierigkeitsstufe aus der KI-Antwort ("level": "leicht"/"mittel"/
  /// "schwer", auch englisch oder 1–3) als Flashcard.stageLevel (0–2), sonst
  /// null (dann gilt die Stufe des Fragetyps).
  static int? parseStageLevel(Object? raw) {
    if (raw is num) {
      final i = raw.toInt();
      return i >= 1 && i <= 3 ? i - 1 : null;
    }
    return switch (raw?.toString().trim().toLowerCase()) {
      'leicht' || 'einfach' || 'easy' || '1' => 0,
      'mittel' || 'medium' || '2' => 1,
      'schwer' || 'hard' || 'difficult' || '3' => 2,
      _ => null,
    };
  }

  /// Gruppenschlüssel aus der KI-Antwort ("group") – Leicht/Mittel/Schwer
  /// desselben Sachverhalts (siehe Flashcard.stageGroup), leer = null.
  static String? parseStageGroup(Object? raw) {
    // Mehrfache Leerzeichen zusammenfassen: gleich benannte Gruppen aus
    // verschiedenen KI-Portionen sollen zusammenfinden.
    final value = raw?.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Aufrufer lesen diese Felder per `as String?` – eine Zahl oder ein Bool
  /// von der KI (z.B. `"correctText": 42`) würde dort sonst crashen.
  static Map<String, dynamic> _withStringFields(Map<String, dynamic> raw) => {
        ...raw,
        for (final key in const ['type', 'front', 'back', 'correctText', 'htmlContent', 'conceptTitle'])
          if (raw[key] != null && raw[key] is! String) key: raw[key].toString(),
      };

  /// Anzahl der Lücken-Markierungen ("___", auch länger) in einem Text.
  static int blankMarkerCount(String text) => RegExp(r'_{3,}').allMatches(text).length;

  static List<String> _nonEmptyBlanks(Map<String, dynamic> raw) =>
      (parseBlanks(raw['blanks']) ?? const []).where((b) => b.trim().isNotEmpty).toList();

  static List<QuizOption> _nonEmptyOptions(Map<String, dynamic> raw) =>
      (parseOptions(raw['options']) ?? const []).where((o) => o.text.trim().isNotEmpty).toList();

  static List<DragPair> _usablePairs(Map<String, dynamic> raw) => [
        for (final p in parseDragPairs(raw['dragPairs']) ?? const <DragPair>[])
          if (p.source.trim().isNotEmpty && p.target.trim().isNotEmpty) p,
      ];

  /// Räumt einen vollständigen Eintrag auf, damit er in der App lösbar ist:
  /// leere Optionen/Lücken/Paare fallen weg, und eine Zuordnen-Frage mit
  /// mehrfach genanntem Ziel wird zur Kategorien-Frage (sonst ließen sich
  /// die gleichnamigen Ziele nicht unterscheiden). Ein sauberer Eintrag
  /// bleibt unverändert.
  static Map<String, dynamic> _sanitized(Map<String, dynamic> entry, QuestionType type) {
    switch (type) {
      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        final options = _nonEmptyOptions(entry);
        if (options.length != (entry['options'] as List).length) {
          return {...entry, 'options': options.map((o) => o.toMap()).toList()};
        }
        return entry;
      case QuestionType.fillBlank:
        final blanks = _nonEmptyBlanks(entry);
        if (blanks.length != (entry['blanks'] as List).length) return {...entry, 'blanks': blanks};
        return entry;
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        final pairs = _usablePairs(entry);
        final targets = pairs.map((p) => p.target.trim()).toList();
        final duplicateTargets = type == QuestionType.dragDrop && targets.toSet().length < targets.length;
        if (pairs.length == (entry['dragPairs'] as List).length && !duplicateTargets) return entry;
        return {
          ...entry,
          'dragPairs': pairs.map((p) => p.toMap()).toList(),
          if (duplicateTargets) 'type': 'drag_category',
        };
      case QuestionType.diagramLabel:
      case QuestionType.markImage:
        // Einheitlich unter "imageTargets" ablegen (die KI bzw. Dateien der
        // Vorgänger-App nennen die Ziele "targets", "diagram_labels" oder
        // "mark_regions").
        final targets = imageTargetsIn(entry) ?? const <ImageTarget>[];
        final covers = imageCoversIn(entry);
        return {
          ...entry,
          'imageTargets': [
            for (final t in targets)
              if (type == QuestionType.markImage || t.label.isNotEmpty) t.toMap(),
          ],
          if (covers.isNotEmpty) 'imageCovers': [for (final c in covers) c.toMap()],
        };
      case QuestionType.table:
        // Einheitlich unter "tableRows" im gespeicherten Zellformat ablegen.
        return {
          ...entry,
          'tableRows': [
            for (final row in tableRowsIn(entry) ?? const <List<QuestionTableCell>>[]) [for (final c in row) c.toMap()],
          ],
        };
      case QuestionType.flashcard:
      case QuestionType.learn:
      case QuestionType.freeText:
      case QuestionType.html:
        return entry;
    }
  }

  /// Die Bild-Ziele eines KI-/Import-Eintrags, egal unter welchem Namen.
  static List<ImageTarget>? imageTargetsIn(Map<String, dynamic> raw) =>
      parseImageTargets(raw['imageTargets']) ??
      parseImageTargets(raw['targets']) ??
      parseImageTargets(raw['diagram_labels']) ??
      parseImageTargets(raw['mark_regions']);

  /// Von der KI vorgeschlagene Abdeckungen (Kästen um Text im Bild, der die
  /// Lösung verraten würde) – als `[links, oben, rechts, unten]` oder als
  /// Rechteck-Map; ohne Fläche verworfen.
  static List<ImageTarget> imageCoversIn(Map<String, dynamic> raw) {
    final list = raw['imageCovers'] ?? raw['covers'];
    if (list is! List) return const [];
    return [
      for (final c in list)
        if (c is List)
          ImageTarget.fromMap({'box': c})
        else if (c is Map)
          ImageTarget.fromMap(Map<String, dynamic>.from(c)),
    ].where((c) => c.w > 0 && c.h > 0).toList();
  }

  static bool _isComplete(Map<String, dynamic> raw, QuestionType type) {
    switch (type) {
      case QuestionType.flashcard:
      case QuestionType.learn:
        // Karteikarte: Antwort; Lernaufgabe: Erklärung/Lösungsweg.
        return (raw['back'] ?? '').toString().trim().isNotEmpty;
      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        // Mindestens zwei Optionen, sonst gibt es nichts auszuwählen.
        final options = _nonEmptyOptions(raw);
        return options.length >= 2 && options.any((o) => o.isCorrect);
      case QuestionType.fillBlank:
        // Jede markierte Lücke braucht genau eine Lösung – sonst gäbe es
        // Eingabefelder ohne Lücke oder Lücken ohne Eingabefeld.
        final blanks = _nonEmptyBlanks(raw);
        return blanks.isNotEmpty && blankMarkerCount((raw['front'] ?? '').toString()) == blanks.length;
      case QuestionType.freeText:
        return (raw['correctText'] ?? '').toString().split(';').any((c) => c.trim().isNotEmpty);
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        // Mindestens zwei Paare mit verschiedenen Zielen – mit nur einem
        // Ziel kann man nichts falsch zuordnen.
        final pairs = _usablePairs(raw);
        return pairs.length >= 2 && {for (final p in pairs) p.target.trim().toLowerCase()}.length >= 2;
      case QuestionType.diagramLabel:
        return (imageTargetsIn(raw) ?? const []).any((t) => t.label.isNotEmpty);
      case QuestionType.markImage:
        return (imageTargetsIn(raw) ?? const []).isNotEmpty;
      case QuestionType.table:
        return _hasFillableCell(tableRowsIn(raw));
      case QuestionType.html:
        final html = (raw['htmlContent'] ?? '').toString();
        // Grobe Vertragsprüfung: die Seite muss den JS-Rückkanal tatsächlich
        // ansprechen, sonst bekäme die App nie ein Ergebnis zurück – ohne
        // brauchbaren Fallback-Inhalt (siehe _bestAvailableAnswer) wird ein
        // solcher Eintrag dann komplett verworfen statt als kaputte
        // interaktive Seite gespeichert zu werden.
        return html.trim().isNotEmpty && html.contains(htmlAnswerChannelName);
    }
  }

  /// Ordnet eine von der KI mitgelieferte "conceptTitle" (siehe
  /// AiService.generateConceptsAndFlashcards) der ID des passenden, gerade
  /// neu gespeicherten Konzepts zu – Grundlage für [Flashcard.conceptId].
  /// [conceptIdByTitle] erwartet bereits normalisierte Schlüssel (siehe
  /// Aufrufer in ReviewScreen). Case-/Whitespace-tolerant, da die KI den
  /// Titel nicht immer exakt wiederholt. Liefert `null`, wenn kein Titel
  /// angegeben wurde oder keiner passt – die Karte bleibt dann wie bisher
  /// ohne Konzept-Verknüpfung, statt einen Fehler zu werfen.
  static String? matchConceptId(String? conceptTitle, Map<String, String> conceptIdByTitle) {
    final normalized = conceptTitle?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return conceptIdByTitle[normalized];
  }

  static String? _bestAvailableAnswer(Map<String, dynamic> raw) {
    final back = (raw['back'] ?? '').toString().trim();
    if (back.isNotEmpty) return back;

    final alternatives =
        (raw['correctText'] ?? '').toString().split(';').map((c) => c.trim()).where((c) => c.isNotEmpty);
    if (alternatives.isNotEmpty) return alternatives.join('; ');

    final blanks = parseBlanks(raw['blanks'])?.where((b) => b.trim().isNotEmpty).toList();
    if (blanks != null && blanks.isNotEmpty) return blanks.join(', ');

    final options = parseOptions(raw['options']);
    if (options != null) {
      final correct = options.where((o) => o.isCorrect).map((o) => o.text).where((t) => t.trim().isNotEmpty);
      if (correct.isNotEmpty) return correct.join(', ');
    }

    final pairs = parseDragPairs(raw['dragPairs']);
    if (pairs != null && pairs.isNotEmpty) {
      return pairs.map((p) => '${p.source} → ${p.target}').join(', ');
    }

    final labels = (imageTargetsIn(raw) ?? const []).map((t) => t.label).where((l) => l.isNotEmpty);
    if (labels.isNotEmpty) return labels.join(', ');
    return null;
  }
}
