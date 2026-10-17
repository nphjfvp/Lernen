/// Visuell lernen: eine Erklärung, die die App selbst animiert. Die KI liefert
/// nur Struktur – Funktionen in Eingabe-Schreibweise (z.B. "0.5*t^2 + 2*t"),
/// Schritte mit Text und Formel und je Schritt, was gezeigt wird (Auto auf
/// einer Straße, Funktionsgraph mit Tangente oder Fläche, Umformung einer
/// Gleichung Schritt für Schritt). Rechnen, Zeichnen und Simulieren
/// übernimmt die App (VisualMath, Simulationen). Am Ende eine Übung als
/// Rechenweg (StepTask), deren falsche Antworten die App ebenfalls simuliert.
library;

import 'step_task.dart';
import 'visual_diagram.dart';
import 'visual_scene3d.dart';

double? _num(Object? raw) {
  final v = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}

String _str(Object? raw) => '${raw ?? ''}'.trim();

/// Eine Funktion der Lektion, z.B. Weg s(t).
class VisualFunction {
  const VisualFunction({required this.key, required this.expr, this.label = '', this.unit = ''});

  /// Kurzer Name, auf den sich Schritte beziehen (z.B. "s", "v").
  final String key;

  /// Term in Eingabe-Schreibweise in der Variablen der Lektion.
  final String expr;

  /// Anzeige, z.B. "Weg s(t)".
  final String label;

  /// Einheit der Werte, z.B. "m".
  final String unit;

  String get title => label.isEmpty ? '$key(…)' : label;

  VisualFunction copyWith({String? key, String? expr, String? label, String? unit}) => VisualFunction(
    key: key ?? this.key,
    expr: expr ?? this.expr,
    label: label ?? this.label,
    unit: unit ?? this.unit,
  );

  Map<String, dynamic> toMap() => {
    'key': key,
    'expr': expr,
    if (label.isNotEmpty) 'label': label,
    if (unit.isNotEmpty) 'unit': unit,
  };

  static VisualFunction? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = _str(raw['key'] ?? raw['name']);
    final expr = _str(raw['expr'] ?? raw['expression'] ?? raw['term'] ?? raw['formula']);
    if (key.isEmpty || expr.isEmpty) return null;
    return VisualFunction(key: key, expr: expr, label: _str(raw['label']), unit: _str(raw['unit'] ?? raw['einheit']));
  }
}

/// Ein Zwischenstand beim Umformen einer Gleichung.
class TransformState {
  const TransformState({required this.latex, this.note = ''});

  /// Die Gleichung in LaTeX (ohne $).
  final String latex;

  /// Was in diesem Schritt gemacht wurde (z.B. "beide Seiten durch dx").
  final String note;

  Map<String, dynamic> toMap() => {'latex': latex, if (note.isNotEmpty) 'note': note};

  static TransformState? fromRaw(Object? raw) {
    if (raw is String) return raw.trim().isEmpty ? null : TransformState(latex: _stripDollar(raw));
    if (raw is! Map) return null;
    final latex = _stripDollar(_str(raw['latex'] ?? raw['formula'] ?? raw['equation']));
    if (latex.isEmpty) return null;
    return TransformState(latex: latex, note: _str(raw['note'] ?? raw['why'] ?? raw['text']));
  }

  static String _stripDollar(String s) {
    var t = s.trim();
    while (t.startsWith(r'$')) {
      t = t.substring(1);
    }
    while (t.endsWith(r'$')) {
      t = t.substring(0, t.length - 1);
    }
    return t.trim();
  }
}

/// Wie das Auto gesteuert wird: über den Weg s(t) oder über die
/// Geschwindigkeit v(t) (dann rechnet die App den Weg durch Aufsummieren).
enum CarSource { position, velocity }

/// Was ein Schritt zeigt.
class VisualShow {
  const VisualShow({
    this.car,
    this.carSource = CarSource.position,
    this.vehicle = '',
    this.plot = const [],
    this.tangent,
    this.area,
    this.transform = const [],
    this.scene,
    this.scene3d,
    this.broken = '',
  });

  /// Funktion, die das Auto fährt (null = kein Auto).
  final String? car;
  final CarSource carSource;

  /// Was statt des Autos fährt: rocket, bike, train, runner, ball, plane,
  /// boat – oder ein beliebiges Emoji. Leer = Auto.
  final String vehicle;

  /// Funktionen im Graphen.
  final List<String> plot;

  /// Tangente an dieser Funktion an der aktuellen Stelle (Steigung = Ableitung).
  final String? tangent;

  /// Fläche unter dieser Funktion vom Anfang bis zur aktuellen Stelle (Integral).
  final String? area;

  /// Umformung Schritt für Schritt.
  final List<TransformState> transform;

  /// Freie Szene (Formen mit Schlüsselbildern) – für alles, was kein Auto
  /// und kein Funktionsgraph ist.
  final VisualDiagram? scene;

  /// Räumliche Szene – nur, wo der räumliche Aufbau wesentlich ist.
  final VisualScene3D? scene3d;

  /// Was sich nicht laden ließ (leer = alles gut) – die Oberfläche zeigt es
  /// samt „Neu erzeugen“, statt die Darstellung still wegzulassen.
  final String broken;

  bool get isEmpty =>
      car == null &&
      plot.isEmpty &&
      tangent == null &&
      area == null &&
      transform.isEmpty &&
      scene == null &&
      scene3d == null;

  /// Alle Funktionen, auf die sich die Anzeige bezieht.
  Set<String> get keys => {?car, ...plot, ?tangent, ?area};

  /// Nur Bezüge auf vorhandene Funktionen behalten (fehlende werden in
  /// [broken] vermerkt).
  VisualShow restrictedTo(Set<String> known) {
    final missing = {
      for (final k in [?car, ...plot, ?tangent, ?area])
        if (!known.contains(k)) k,
    };
    final reasons = [
      if (broken.isNotEmpty) broken,
      if (missing.isNotEmpty) 'Funktion ${missing.map((k) => '„$k“').join(', ')} fehlt oder ließ sich nicht lesen',
    ];
    return _restricted(known, reasons.join(' · '));
  }

  VisualShow _restricted(Set<String> known, String broken) => VisualShow(
    car: car != null && known.contains(car) ? car : null,
    carSource: carSource,
    vehicle: vehicle,
    plot: [
      for (final p in plot)
        if (known.contains(p)) p,
    ],
    tangent: tangent != null && known.contains(tangent) ? tangent : null,
    area: area != null && known.contains(area) ? area : null,
    transform: transform,
    scene: scene,
    scene3d: scene3d,
    broken: broken,
  );

  Map<String, dynamic> toMap() => {
    if (car != null) 'car': car,
    if (car != null && carSource == CarSource.velocity) 'carFrom': 'velocity',
    if (vehicle.isNotEmpty) 'vehicle': vehicle,
    if (plot.isNotEmpty) 'plot': plot,
    if (tangent != null) 'tangent': tangent,
    if (area != null) 'area': area,
    if (transform.isNotEmpty) 'transform': [for (final t in transform) t.toMap()],
    if (scene != null) 'scene': scene!.toMap(),
    if (scene3d != null) 'scene3d': scene3d!.toMap(),
    if (broken.isNotEmpty) 'broken': broken,
  };

  static VisualShow fromMap(Object? raw) {
    if (raw is! Map) return const VisualShow();
    String? key(Object? v) => _str(v).isEmpty || _str(v) == 'null' ? null : _str(v);
    final plot = raw['plot'] ?? raw['graph'];
    final transform = raw['transform'] ?? raw['umformung'];
    final from = _str(raw['carFrom'] ?? raw['carSource']).toLowerCase();
    final rawScene = raw['scene'] ?? raw['diagram'] ?? raw['szene'] ?? raw['animation'];
    final rawScene3d = raw['scene3d'] ?? raw['scene3D'] ?? raw['3d'];
    final scene = VisualDiagram.fromMap(rawScene);
    final scene3d = VisualScene3D.fromMap(rawScene3d);
    final transforms = [
      if (transform is List)
        for (final t in transform) ?TransformState.fromRaw(t),
    ];
    final broken = [
      if (_str(raw['broken']).isNotEmpty) _str(raw['broken']),
      if (rawScene != null && scene == null) '2D-Szene ließ sich nicht lesen',
      if (rawScene3d != null && scene3d == null) '3D-Szene ließ sich nicht lesen',
      if (transform is List && transform.isNotEmpty && transforms.isEmpty) 'Umformung ließ sich nicht lesen',
    ];
    return VisualShow(
      car: key(raw['car'] ?? raw['auto']),
      carSource: from.startsWith('v') || from.startsWith('geschw') ? CarSource.velocity : CarSource.position,
      vehicle: _str(raw['vehicle'] ?? raw['fahrzeug']),
      plot: switch (plot) {
        List() => [
          for (final p in plot)
            if (_str(p).isNotEmpty) _str(p),
        ],
        String() when plot.trim().isNotEmpty => [plot.trim()],
        _ => const [],
      },
      tangent: key(raw['tangent'] ?? raw['tangente']),
      area: key(raw['area'] ?? raw['flaeche'] ?? raw['fläche']),
      transform: transforms,
      scene: scene,
      scene3d: scene3d,
      broken: broken.join(' · '),
    );
  }
}

/// Ein Erklärschritt.
class VisualStep {
  const VisualStep({
    required this.title,
    this.text = '',
    this.formula = '',
    this.show = const VisualShow(),
    this.guide = '',
  });

  final String title;

  /// Warum wir das machen und was es (z.B. mit dem Auto) bedeutet.
  final String text;

  /// Benutzte Formel in LaTeX (ohne $).
  final String formula;
  final VisualShow show;

  /// Sokratisch lernen: Leitfrage, mit der man diesen Schritt selbst
  /// herausfindet (verrät die Lösung nicht).
  final String guide;

  VisualStep copyWith({VisualShow? show}) =>
      VisualStep(title: title, text: text, formula: formula, show: show ?? this.show, guide: guide);

  Map<String, dynamic> toMap() => {
    'title': title,
    if (text.isNotEmpty) 'text': text,
    if (formula.isNotEmpty) 'formula': formula,
    if (!show.isEmpty) 'show': show.toMap(),
    if (guide.isNotEmpty) 'guide': guide,
  };

  static VisualStep? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final title = _str(raw['title'] ?? raw['titel']);
    final text = _str(raw['text'] ?? raw['explanation'] ?? raw['erklaerung'] ?? raw['erklärung']);
    if (title.isEmpty && text.isEmpty) return null;
    return VisualStep(
      title: title.isEmpty ? 'Schritt' : title,
      text: text,
      formula: TransformState._stripDollar(_str(raw['formula'] ?? raw['formel'])),
      show: VisualShow.fromMap(
        raw['show'] ??
            raw['visual'] ??
            raw['anzeige'] ??
            // Manche Modelle setzen die Darstellung direkt an den Schritt.
            (const ['scene', 'scene3d', 'car', 'plot', 'transform'].any(raw.containsKey) ? raw : null),
      ),
      guide: _str(raw['guide'] ?? raw['leitfrage'] ?? raw['question']),
    );
  }
}

/// Wie die Lektion durchgegangen wird: Schritte erklärt bekommen oder
/// sokratisch – mit Leitfragen selbst darauf kommen.
enum VisualStyle { explain, socratic }

/// Wie eine falsche Antwort in der Übung simuliert wird.
enum ExerciseSimulation { graph, position, velocity }

/// Eine ganze Lektion.
class VisualLesson {
  const VisualLesson({
    required this.id,
    required this.moduleId,
    required this.title,
    this.intro = '',
    this.variable = 't',
    this.domainMin = 0,
    this.domainMax = 10,
    this.functions = const [],
    this.steps = const [],
    this.result,
    this.exerciseFront = '',
    this.exercise,
    this.simulation = ExerciseSimulation.graph,
    this.source = '',
    this.detail = 'normal',
    this.style = VisualStyle.explain,
    this.cardId,
    this.courseId,
    this.recap = '',
    this.shortVersion,
    required this.createdAt,
  });

  final String id;
  final String moduleId;
  final String title;

  /// Worum es geht (Beispiel, Ausgangslage).
  final String intro;

  /// Variable der Funktionen und Bereich, über den simuliert wird.
  final String variable;
  final double domainMin;
  final double domainMax;

  final List<VisualFunction> functions;
  final List<VisualStep> steps;

  /// Ergebnis am Ende (mit Simulation).
  final VisualStep? result;

  /// Übung danach: Aufgabe und Rechenweg (wie bei Rechenweg-Aufgaben).
  final String exerciseFront;
  final StepTask? exercise;

  /// Wie eine falsche Antwort der Übung gezeigt wird: im Graphen, als Weg oder
  /// als Geschwindigkeit eines zweiten Autos.
  final ExerciseSimulation simulation;

  /// Woher die Lektion stammt (z.B. "Folien.pdf, S. 3–5" oder "eigenes Beispiel").
  final String source;

  /// "kurz", "normal" oder "ausführlich".
  final String detail;

  /// Gewählter Lernweg (in der Lektion umschaltbar).
  final VisualStyle style;

  /// Aus dieser Frage erstellt („Visuell erklären“) – dann öffnet die Frage
  /// beim nächsten Mal direkt diese Lektion.
  final String? cardId;

  /// Teil eines Lernpfads (dann dort statt in der Lektionsliste).
  final String? courseId;

  /// Rückblick zu Beginn: was aus früheren Themen gebraucht wird und warum.
  final String recap;

  /// Kurzfassung zum schnellen Wiedereinsteigen (Kernpunkte, Formel, eine
  /// Darstellung).
  final VisualStep? shortVersion;
  final DateTime createdAt;

  VisualFunction? function(String key) {
    for (final f in functions) {
      if (f.key == key) return f;
    }
    return null;
  }

  bool get hasCar => [...steps, ?result].any((s) => s.show.car != null);

  /// Das Fahrzeug der Lektion (erstes gesetztes; leer = Auto).
  String get vehicle =>
      [...steps, ?result].map((s) => s.show.vehicle).firstWhere((v) => v.isNotEmpty, orElse: () => '');

  bool get isUsable => title.trim().isNotEmpty && steps.isNotEmpty && domainMax > domainMin;

  VisualLesson copyWith({String? title, String? moduleId, String? id, VisualStyle? style}) => VisualLesson(
    id: id ?? this.id,
    moduleId: moduleId ?? this.moduleId,
    title: title ?? this.title,
    intro: intro,
    variable: variable,
    domainMin: domainMin,
    domainMax: domainMax,
    functions: functions,
    steps: steps,
    result: result,
    exerciseFront: exerciseFront,
    exercise: exercise,
    simulation: simulation,
    source: source,
    detail: detail,
    style: style ?? this.style,
    cardId: cardId,
    courseId: courseId,
    recap: recap,
    shortVersion: shortVersion,
    createdAt: createdAt,
  );

  /// Dieselbe Lektion mit genau diesen Funktionen ([extra] ergänzt bzw.
  /// ersetzt gleichnamige); Bezüge auf fehlende Funktionen fallen weg.
  VisualLesson withFunctions(List<VisualFunction> functions, {List<VisualFunction> extra = const []}) {
    final all = [
      for (final f in functions)
        if (!extra.any((e) => e.key == f.key)) f,
      ...extra,
    ];
    return VisualLesson.fromMap(
          {
            ...toMap(),
            'functions': [for (final f in all) f.toMap()],
          },
          id: id,
          moduleId: moduleId,
          createdAt: createdAt,
        ) ??
        this;
  }

  /// Die Lektion mit der Überarbeitung der KI („Darstellung ändern“, siehe
  /// AiService.reviseVisualLesson). [stepIndex] null = ganze Lektion (was die
  /// KI weglässt, bleibt), sonst nur dieser Schritt (-1 Ergebnis, -2
  /// Kurzfassung) plus neue/geänderte Funktionen. null, wenn unbrauchbar.
  VisualLesson? revisedWith(Map<String, dynamic> json, {int? stepIndex}) {
    final map = toMap();
    if (stepIndex == null) {
      final raw = json['lesson'] is Map ? Map<String, dynamic>.from(json['lesson'] as Map) : json;
      const keys = [
        'title',
        'intro',
        'variable',
        'domain',
        'functions',
        'steps',
        'result',
        'short',
        'recap',
        'exercise',
        'exerciseFront',
        'simulate',
      ];
      for (final k in keys) {
        if (raw[k] != null) map[k] = raw[k];
      }
      // Neue Übung im Erstell-Format: Aufgabe und Simulation stehen darin.
      if (raw['exercise'] is Map) {
        if (raw['exerciseFront'] == null) map.remove('exerciseFront');
        if (raw['simulate'] == null) map.remove('simulate');
      }
    } else {
      final step = json['step'];
      if (step is! Map) return null;
      if (stepIndex >= 0) {
        final steps = [...(map['steps'] as List)];
        if (stepIndex >= steps.length) return null;
        steps[stepIndex] = step;
        map['steps'] = steps;
      } else {
        map[stepIndex == -1 ? 'result' : 'short'] = step;
      }
      final extra = json['functions'];
      if (extra is List) {
        final functions = [...(map['functions'] as List)];
        for (final f in extra) {
          if (f is! Map) continue;
          final i = functions.indexWhere((g) => g is Map && g['key'] == f['key']);
          if (i >= 0) {
            functions[i] = f;
          } else {
            functions.add(f);
          }
        }
        map['functions'] = functions;
      }
    }
    return VisualLesson.fromMap(
      map,
      id: id,
      moduleId: moduleId,
      createdAt: createdAt,
      source: source,
      detail: detail,
      style: style,
      cardId: cardId,
      courseId: courseId,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'moduleId': moduleId,
    'title': title,
    if (intro.isNotEmpty) 'intro': intro,
    'variable': variable,
    'domain': [domainMin, domainMax],
    'functions': [for (final f in functions) f.toMap()],
    'steps': [for (final s in steps) s.toMap()],
    if (result != null) 'result': result!.toMap(),
    if (exerciseFront.isNotEmpty) 'exerciseFront': exerciseFront,
    if (exercise != null) 'exercise': exercise!.toMap(),
    if (simulation != ExerciseSimulation.graph) 'simulate': simulation.name,
    if (source.isNotEmpty) 'source': source,
    'detail': detail,
    if (style != VisualStyle.explain) 'style': style.name,
    'cardId': ?cardId,
    'courseId': ?courseId,
    if (recap.isNotEmpty) 'recap': recap,
    if (shortVersion != null) 'short': shortVersion!.toMap(),
    'createdAt': createdAt.toIso8601String(),
  };

  /// Liest eine gespeicherte Lektion oder einen Eintrag der KI. Bezüge auf
  /// unbekannte Funktionen fallen weg; ohne Titel oder Schritte → null.
  static VisualLesson? fromMap(
    Object? raw, {
    String? id,
    String? moduleId,
    DateTime? createdAt,
    String? source,
    String? detail,
    VisualStyle? style,
    String? cardId,
    String? courseId,
  }) {
    if (raw is! Map) return null;
    final functions = <VisualFunction>[];
    final rawFunctions = raw['functions'] ?? raw['funktionen'];
    if (rawFunctions is List) {
      for (final f in rawFunctions) {
        final fn = VisualFunction.fromMap(f);
        if (fn != null && !functions.any((g) => g.key == fn.key)) functions.add(fn);
      }
    } else if (rawFunctions is Map) {
      // Auch {"s": "0.5*t^2", "v": "t"}.
      for (final e in rawFunctions.entries) {
        final fn = e.value is Map
            ? VisualFunction.fromMap({'key': e.key, ...Map<String, dynamic>.from(e.value as Map)})
            : VisualFunction.fromMap({'key': e.key, 'expr': e.value});
        if (fn != null) functions.add(fn);
      }
    }
    final known = {for (final f in functions) f.key};
    VisualStep? clean(VisualStep? s) => s?.copyWith(show: s.show.restrictedTo(known));
    final rawSteps = raw['steps'] ?? raw['schritte'];
    final steps = [
      if (rawSteps is List)
        for (final s in rawSteps) ?clean(VisualStep.fromMap(s)),
    ];
    final title = _str(raw['title'] ?? raw['titel']);
    if (title.isEmpty || steps.isEmpty) return null;
    final domain = raw['domain'] ?? raw['bereich'];
    var lo = domain is List && domain.isNotEmpty ? _num(domain[0]) : _num(raw['domainMin']);
    var hi = domain is List && domain.length > 1 ? _num(domain[1]) : _num(raw['domainMax']);
    lo ??= 0;
    hi ??= lo + 10;
    if (hi <= lo) hi = lo + 10;
    final rawExercise = raw['exercise'] ?? raw['uebung'] ?? raw['übung'];
    StepTask? exercise;
    var exerciseFront = _str(raw['exerciseFront']);
    if (rawExercise is Map) {
      final data = rawExercise['taskData'] is Map ? rawExercise['taskData'] : rawExercise;
      exercise = StepTask.fromMap(data);
      if (exercise != null && !exercise.isUsable) exercise = null;
      if (exerciseFront.isEmpty) {
        exerciseFront = _str(rawExercise['front'] ?? rawExercise['task'] ?? rawExercise['aufgabe']);
      }
    }
    final sim = _str(raw['simulate'] ?? (rawExercise is Map ? rawExercise['simulate'] : null)).toLowerCase();
    final created = createdAt ?? DateTime.tryParse(_str(raw['createdAt'])) ?? DateTime.now();
    return VisualLesson(
      id: id ?? _str(raw['id']),
      moduleId: moduleId ?? _str(raw['moduleId']),
      title: title,
      intro: _str(raw['intro'] ?? raw['einleitung']),
      variable: _str(raw['variable']).isEmpty ? 't' : _str(raw['variable']),
      domainMin: lo,
      domainMax: hi,
      functions: functions,
      steps: steps,
      result: clean(VisualStep.fromMap(raw['result'] ?? raw['ergebnis'])),
      exerciseFront: exerciseFront,
      exercise: exercise,
      simulation: switch (sim) {
        'position' || 'weg' => ExerciseSimulation.position,
        'velocity' || 'geschwindigkeit' => ExerciseSimulation.velocity,
        _ => ExerciseSimulation.graph,
      },
      source: source ?? _str(raw['source']),
      detail: detail ?? (_str(raw['detail']).isEmpty ? 'normal' : _str(raw['detail'])),
      style: style ?? (_str(raw['style']) == VisualStyle.socratic.name ? VisualStyle.socratic : VisualStyle.explain),
      cardId: cardId ?? (_str(raw['cardId']).isEmpty ? null : _str(raw['cardId'])),
      courseId: courseId ?? (_str(raw['courseId']).isEmpty ? null : _str(raw['courseId'])),
      recap: _str(raw['recap'] ?? raw['rueckblick'] ?? raw['rückblick']),
      shortVersion: clean(VisualStep.fromMap(raw['short'] ?? raw['kurzfassung'])),
      createdAt: created,
    );
  }
}
