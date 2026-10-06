import 'dart:math' as math;

import '../models/step_task.dart';
import 'calc_engine.dart';
import 'math_input.dart';

/// Ergebnis der Prüfung eines Felds.
enum FieldVerdictKind {
  correct,
  wrong,

  /// Ein bekannter typischer Fehler (mit eigener Rückmeldung).
  mistake,

  /// Eingabe nicht lesbar oder mit Größen, die hier nicht vorkommen dürfen.
  invalid,
  empty,

  /// Die App kann es nicht selbst nachrechnen (z.B. nirgends definiert).
  uncheckable,
}

class FieldVerdict {
  const FieldVerdict(this.kind, this.message);

  final FieldVerdictKind kind;

  /// Rückmeldung für die Anzeige.
  final String message;

  bool get isCorrect => kind == FieldVerdictKind.correct;

  /// Zählt als Fehlversuch – eine leere oder unlesbare Eingabe nicht.
  bool get isAttempt => kind == FieldVerdictKind.wrong || kind == FieldVerdictKind.mistake;
}

/// Eine Zeile der Probe ("Anfangswert y(4) = 2 ✓").
class ProbeRow {
  const ProbeRow({required this.label, required this.detail, required this.ok});

  final String label;
  final String detail;
  final bool ok;
}

class ProbeReport {
  const ProbeReport({this.rows = const [], required this.passed, this.note = ''});

  final List<ProbeRow> rows;
  final bool passed;

  /// Erklärung, wenn nicht geprüft werden konnte.
  final String note;
}

/// Ergebnis der Nachprüfung einer ganzen Aufgabe (Musterlösung).
class StepTaskCheck {
  const StepTaskCheck({this.problems = const [], this.probe});

  /// Was an der Aufgabe nicht stimmt (deutsch, je ein Satz).
  final List<String> problems;

  /// Probe der erwarteten Endlösung, falls die Aufgabe eine hat.
  final ProbeReport? probe;

  bool get ok => problems.isEmpty && (probe?.passed ?? true);
}

/// Prüft Antworten von Rechenweg-Aufgaben ([StepTask]) ohne KI: Formeln
/// werden an mehreren Stellen eingesetzt und mit der erwarteten Antwort
/// verglichen – jede gleichwertige Umformung zählt. Bei Integrationskonstanten
/// zählt jede Schreibweise derselben Lösungsschar (C − 2x, 2(K − x)). Typische
/// Fehler aus der Aufgabe bekommen ihre eigene Rückmeldung, sonst erkennt die
/// App Vorzeichen-, Faktor- und Konstantenfehler selbst.
class StepChecker {
  StepChecker._();

  /// Feste "krumme" Stützstellen – deterministisch (gleiche Eingabe, gleiches
  /// Urteil) und ohne Sonderwerte wie 0 oder 1.
  static const _candidates = [
    0.73, 1.37, -0.61, 2.21, -1.53, 0.29, 3.11, -2.47, 1.83, 4.37, -3.29, 0.17, 2.69, 5.21, -4.13, 1.07, //
    6.7, -5.9, 8.3, 0.53, -0.37, 9.6, 12.4, -7.7, 15.1, 0.91, 23.3, -11.2, 0.043, 31.7, 47.9, -19.4,
  ];
  static const _fractions = [0.13, 0.37, 0.61, 0.83, 0.07, 0.29, 0.53, 0.71, 0.95, 0.19, 0.44, 0.67, 0.88, 0.02, 0.31];
  static const _constantSamples = [7.3, 12.9, 3.1, 25.4, -2.2, 0.8, 41.5];

  static bool _close(double a, double b, {double tol = 1e-7}) {
    if (!a.isFinite || !b.isFinite) return false;
    return (a - b).abs() <= tol * math.max(1.0, math.max(a.abs(), b.abs()));
  }

  /// Belegungen der Größen [vars] (im Bereich [domain], falls angegeben).
  static Iterable<Map<String, double>> _assignments(List<String> vars, Map<String, (double, double)> domain) sync* {
    if (vars.isEmpty) {
      yield const {};
      return;
    }
    final n = _candidates.length * 2;
    for (var i = 0; i < n; i++) {
      yield {
        for (final (k, v) in vars.indexed)
          v: switch (domain[v]) {
            final d? => d.$1 + _fractions[(i + 5 * k) % _fractions.length] * (d.$2 - d.$1),
            null => _candidates[(i + 7 * k) % _candidates.length],
          },
      };
    }
  }

  /// Bis zu [count] Belegungen, an denen [ref] (mit [fixed]) etwas ergibt.
  static List<Map<String, double>> _validPoints(
    MathExpression ref,
    List<String> vars,
    Map<String, (double, double)> domain, {
    Map<String, double> fixed = const {},
    int count = 8,
  }) {
    final out = <Map<String, double>>[];
    for (final env in _assignments(vars, domain)) {
      if (ref.evaluate({...fixed, ...env}).isFinite) out.add(env);
      if (out.length >= count) break;
    }
    return out;
  }

  /// Gleich als Funktion von [vars]? `null` = nicht prüfbar.
  static bool? _samePlain(MathExpression user, MathExpression ref, List<String> vars, Map<String, (double, double)> domain,
      {Map<String, double> userFixed = const {}, Map<String, double> refFixed = const {}}) {
    final points = _validPoints(ref, vars, domain, fixed: refFixed);
    if (points.isEmpty || (vars.isNotEmpty && points.length < 2)) return null;
    for (final env in points) {
      if (!_close(user.evaluate({...userFixed, ...env}), ref.evaluate({...refFixed, ...env}))) return false;
    }
    return true;
  }

  /// Nullstelle von [g] nahe [start] (Sekanten, sonst Raster + Halbierung).
  static double? _solve(double Function(double) g, double start, double scale) {
    final eps = 1e-11 * math.max(1.0, scale);
    var a = start, b = start + 0.5;
    var ga = g(a), gb = g(b);
    for (var i = 0; i < 60; i++) {
      if (ga.isFinite && ga.abs() <= eps) return a;
      if (gb.isFinite && gb.abs() <= eps) return b;
      if (!ga.isFinite || !gb.isFinite || gb == ga) break;
      final c = b - gb * (b - a) / (gb - ga);
      if (!c.isFinite) break;
      a = b;
      ga = gb;
      b = c;
      gb = g(b);
    }
    double? prevK, prevG;
    for (var k = -200.0; k <= 200.0; k += 0.25) {
      final v = g(k);
      if (!v.isFinite) {
        prevK = prevG = null;
        continue;
      }
      if (v.abs() <= eps) return k;
      if (prevG != null && (prevG < 0) != (v < 0)) {
        var lo = prevK!, hi = k, glo = prevG;
        for (var i = 0; i < 90; i++) {
          final mid = (lo + hi) / 2, gm = g(mid);
          if (!gm.isFinite) break;
          if ((gm < 0) == (glo < 0)) {
            lo = mid;
            glo = gm;
          } else {
            hi = mid;
          }
        }
        return (lo + hi) / 2;
      }
      prevK = k;
      prevG = v;
    }
    return null;
  }

  /// Dieselbe Lösungsschar mit einer frei wählbaren Konstante? [userConst] ist
  /// die Konstante in der Eingabe, [refConst] die der erwarteten Antwort.
  /// `null` = nicht prüfbar.
  static bool? _sameFamily(MathExpression user, String userConst, MathExpression ref, String refConst, List<String> vars,
      Map<String, (double, double)> domain) {
    var tested = 0, failed = 0;
    for (final c in _constantSamples) {
      final points = _validPoints(user, vars, domain, fixed: {userConst: c});
      if (points.length < 3) continue;
      final x0 = points.first;
      final target = user.evaluate({...x0, userConst: c});
      final k = _solve((k) => ref.evaluate({...x0, refConst: k}) - target, c, target.abs());
      if (k == null) {
        failed++;
        continue;
      }
      var compared = 0;
      for (final env in points.skip(1)) {
        final r = ref.evaluate({...env, refConst: k});
        if (!r.isFinite) continue;
        if (!_close(user.evaluate({...env, userConst: c}), r, tol: 1e-6)) return false;
        compared++;
      }
      if (compared >= 2) tested++;
      if (tested >= 3) break;
    }
    if (tested >= 2) return true;
    return failed > 0 && tested == 0 ? false : null;
  }

  /// Hängt [e] von [name] ab?
  static bool _dependsOn(MathExpression e, String name, List<String> vars, Map<String, (double, double)> domain) {
    for (final env in _assignments(vars, domain).take(12)) {
      final a = e.evaluate({...env, name: 3.7}), b = e.evaluate({...env, name: 11.3});
      if (a.isFinite && b.isFinite && !_close(a, b)) return true;
    }
    return false;
  }

  static bool _looksLikeConstant(String name) => RegExp(r"^[A-Za-z](_?[A-Za-z0-9]+)?$").hasMatch(name);

  static String _names(Iterable<String> names) =>
      names.map((n) => n.replaceAll("'", '′')).join(', ');

  /// LaTeX der gelesenen Eingabe für die Vorschau, `null` bei leerer oder
  /// unlesbarer Eingabe.
  static String? preview(StepField field, String input) {
    if (input.trim().isEmpty) return null;
    return MathExpression.tryParse(input, names: field.declaredNames)?.toLatex();
  }

  /// Prüft eine Eingabe für [field].
  static FieldVerdict check(StepField field, String input) {
    if (input.trim().isEmpty) return const FieldVerdict(FieldVerdictKind.empty, 'Gib zuerst etwas ein.');
    return field.kind == StepFieldKind.number ? _checkNumber(field, input) : _checkFormula(field, input);
  }

  /// Prüft die gewählte Option eines Auswahl-Schritts.
  static FieldVerdict checkOption(TaskStep step, int index) {
    if (index < 0 || index >= step.options.length) {
      return const FieldVerdict(FieldVerdictKind.empty, 'Wähle zuerst eine Antwort.');
    }
    final o = step.options[index];
    if (o.correct) return FieldVerdict(FieldVerdictKind.correct, o.feedback.isEmpty ? 'Richtig.' : o.feedback);
    return FieldVerdict(
      o.feedback.isEmpty ? FieldVerdictKind.wrong : FieldVerdictKind.mistake,
      o.feedback.isEmpty ? 'Das passt hier nicht – überleg noch einmal.' : o.feedback,
    );
  }

  // -------------------------------------------------------------------------
  // Zahlen
  // -------------------------------------------------------------------------

  static FieldVerdict _checkNumber(StepField field, String input) {
    final MathExpression user;
    try {
      user = MathExpression.parse(input);
    } on MathInputException catch (e) {
      return FieldVerdict(FieldVerdictKind.invalid, e.message);
    }
    if (user.freeSymbols.isNotEmpty) {
      return FieldVerdict(FieldVerdictKind.invalid,
          'Hier ist eine Zahl gefragt – ${_names(user.freeSymbols)} kann ich nicht einsetzen.');
    }
    final u = user.evaluate();
    if (!u.isFinite) return const FieldVerdict(FieldVerdictKind.invalid, 'Das ergibt keine Zahl.');
    final expected = MathExpression.tryParse(field.answer)?.evaluate() ?? double.nan;
    if (!expected.isFinite) {
      return const FieldVerdict(FieldVerdictKind.uncheckable, 'Diese Antwort kann ich nicht selbst nachrechnen.');
    }
    final tol = field.tolerance ?? 1e-9;
    if (_close(u, expected, tol: tol)) return const FieldVerdict(FieldVerdictKind.correct, 'Richtig.');
    // Richtig gerundet? (0,68 für 0,6802 – mindestens zwei gültige Ziffern)
    final literal = RegExp(r'^\s*[+-]?(\d+)(?:[.,](\d+))?\s*$').firstMatch(MathExpression.normalize(input));
    if (literal != null) {
      final decimals = literal[2]?.length ?? 0;
      final digits = '${literal[1]}${literal[2] ?? ''}'.replaceFirst(RegExp(r'^0+'), '');
      if ((u - expected).abs() <= 0.5 * math.pow(10, -decimals) + 1e-12) {
        if (digits.length >= 2) return const FieldVerdict(FieldVerdictKind.correct, 'Richtig (gerundet).');
        return const FieldVerdict(FieldVerdictKind.wrong, 'Zu grob gerundet – gib mindestens zwei gültige Ziffern an.');
      }
    }
    for (final m in field.mistakes) {
      final v = MathExpression.tryParse(m.answer)?.evaluate();
      if (v != null && _close(u, v, tol: tol)) return FieldVerdict(FieldVerdictKind.mistake, m.feedback);
    }
    if (expected != 0 && _close(u, -expected, tol: tol)) {
      return const FieldVerdict(FieldVerdictKind.wrong, 'Fast – das Vorzeichen stimmt nicht.');
    }
    return const FieldVerdict(FieldVerdictKind.wrong, 'Das stimmt noch nicht.');
  }

  // -------------------------------------------------------------------------
  // Formeln
  // -------------------------------------------------------------------------

  static FieldVerdict _checkFormula(StepField field, String input) {
    final names = field.declaredNames;
    final MathExpression ref;
    try {
      ref = MathExpression.parse(field.answer, names: names);
    } on MathInputException {
      return const FieldVerdict(FieldVerdictKind.uncheckable, 'Diese Antwort kann ich nicht selbst nachrechnen.');
    }
    final MathExpression user;
    try {
      user = MathExpression.parse(input, names: names);
    } on MathInputException catch (e) {
      return FieldVerdict(FieldVerdictKind.invalid, e.message);
    }
    final constants = field.constants;
    final vars = field.variables.isNotEmpty
        ? field.variables
        : (ref.freeSymbols.difference(constants.toSet()).toList()..sort());
    final allowed = {...vars, ...constants};
    var unknown = user.freeSymbols.difference(allowed);

    // Eine Konstante darf anders heißen (K statt C).
    String? userConst;
    if (constants.length == 1) {
      if (user.freeSymbols.contains(constants.first)) {
        userConst = constants.first;
      } else {
        final candidates = unknown.where(_looksLikeConstant).toList();
        if (candidates.length == 1) {
          userConst = candidates.first;
          unknown = unknown.difference({userConst});
        }
      }
    }
    if (unknown.isNotEmpty) {
      final hint = vars.isEmpty ? '' : ' Erlaubt ${vars.length == 1 ? 'ist' : 'sind'}: ${_names(vars)}.';
      return FieldVerdict(FieldVerdictKind.invalid,
          '${_names(unknown)} ${unknown.length == 1 ? 'kommt' : 'kommen'} hier nicht vor.$hint');
    }

    bool? same(MathExpression a, MathExpression b) {
      if (constants.length == 1) {
        final refConst = constants.first;
        final aConst = identical(a, user) ? userConst : (a.freeSymbols.contains(refConst) ? refConst : null);
        if (aConst == null) return false;
        return _sameFamily(a, aConst, b, refConst, vars, field.domain);
      }
      // Mehrere Konstanten: wie Größen behandeln (gleiche Schreibweise nötig).
      return _samePlain(a, b, [...vars, ...constants], field.domain);
    }

    // Konstante vergessen?
    if (constants.length == 1 && userConst == null && _dependsOn(ref, constants.first, vars, field.domain)) {
      for (final m in field.mistakes) {
        final mistake = MathExpression.tryParse(m.answer, names: names);
        if (mistake != null &&
            !mistake.freeSymbols.contains(constants.first) &&
            _samePlain(user, mistake, vars, field.domain) == true) {
          return FieldVerdict(FieldVerdictKind.mistake, m.feedback);
        }
      }
      return FieldVerdict(FieldVerdictKind.wrong,
          'Die Konstante ${constants.first} fehlt – beim Integrieren kommt eine dazu.');
    }

    final verdict = same(user, ref);
    if (verdict == true) return const FieldVerdict(FieldVerdictKind.correct, 'Richtig.');
    if (verdict == null) {
      return const FieldVerdict(FieldVerdictKind.uncheckable,
          'Das kann ich nicht sicher nachrechnen – vergleiche selbst mit der Lösung.');
    }
    for (final m in field.mistakes) {
      final mistake = MathExpression.tryParse(m.answer, names: names);
      if (mistake == null) continue;
      if (same(user, mistake) == true || _samePlain(user, mistake, [...vars, ...constants], field.domain) == true) {
        return FieldVerdict(FieldVerdictKind.mistake, m.feedback);
      }
    }
    if (constants.isEmpty) {
      final diagnosis = _diagnose(user, ref, vars, field.domain);
      if (diagnosis != null) return FieldVerdict(FieldVerdictKind.wrong, diagnosis);
    }
    return const FieldVerdict(FieldVerdictKind.wrong, 'Das stimmt noch nicht.');
  }

  /// Vorzeichen, Faktor oder Konstante daneben?
  static String? _diagnose(MathExpression user, MathExpression ref, List<String> vars, Map<String, (double, double)> domain) {
    final points = _validPoints(ref, vars, domain);
    if (points.length < 3) return null;
    final u = [for (final p in points) user.evaluate(p)];
    final r = [for (final p in points) ref.evaluate(p)];
    if (u.any((v) => !v.isFinite)) return null;
    bool all(bool Function(int i) test) => [for (var i = 0; i < u.length; i++) test(i)].every((b) => b);
    if (all((i) => _close(u[i], -r[i])) && r.any((v) => v.abs() > 1e-9)) return 'Fast – das Vorzeichen stimmt nicht.';
    if (vars.isEmpty) return null;
    if (r.every((v) => v.abs() > 1e-9)) {
      final q = u[0] / r[0];
      if (q.isFinite && !_close(q, 1) && !_close(q, -1) && all((i) => _close(u[i] / r[i], q, tol: 1e-6))) {
        return 'Bis auf einen Faktor richtig – prüf den Vorfaktor.';
      }
    }
    final d = u[0] - r[0];
    if (d.abs() > 1e-9 && all((i) => _close(u[i] - r[i], d, tol: 1e-6))) {
      return 'Bis auf eine Konstante richtig – prüf den Summanden ohne ${_names(vars)}.';
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Probe des Endergebnisses
  // -------------------------------------------------------------------------

  static String _fmt(double v) => CalcEngine.format(v);

  /// Setzt [answer] (das Endergebnis, z.B. `x - sqrt(12 - 2x)`) in die DGL
  /// bzw. Stammfunktions-Bedingung der Aufgabe ein. `null` ohne Probe.
  static ProbeReport? probe(StepTask task, String answer) {
    final p = task.probe;
    if (p == null) return null;
    return runProbe(p, answer, constants: task.finalField?.constants ?? const []);
  }

  static ProbeReport runProbe(StepProbe p, String answer, {List<String> constants = const []}) {
    final x = p.variable, y = p.function;
    final MathExpression sol;
    try {
      sol = MathExpression.parse(answer, names: {x, ...constants});
    } on MathInputException catch (e) {
      return ProbeReport(passed: false, note: 'Ergebnis nicht lesbar: ${e.message}');
    }
    final MathExpression rhs;
    try {
      rhs = MathExpression.parse(p.equation, names: {x, y, "$y'", "$y''"});
    } on MathInputException {
      return const ProbeReport(passed: false, note: 'Die Probe der Aufgabe ist nicht lesbar.');
    }
    // Übrige Größen (eine Konstante C) bekommen einen festen Wert – die DGL
    // muss für jeden gelten.
    final extra = {for (final s in sol.freeSymbols.difference({x})) s: 1.7};
    double f(double t) => sol.evaluate({...extra, x: t});
    double d1(double t) {
      final h = 1e-5 * math.max(1.0, t.abs());
      return (f(t + h) - f(t - h)) / (2 * h);
    }

    double d2(double t) {
      final h = 1e-3 * math.max(1.0, t.abs());
      return (f(t + h) - 2 * f(t) + f(t - h)) / (h * h);
    }

    final rows = <ProbeRow>[];
    final yName = y.replaceAll("'", '′');
    for (final c in p.conditions) {
      final value = c.derivative == 0 ? f(c.x) : d1(c.x);
      final ok = _close(value, c.value, tol: c.derivative == 0 ? 1e-7 : 1e-4);
      final name = c.derivative == 0 ? '$yName(${_fmt(c.x)})' : '$yName′(${_fmt(c.x)})';
      rows.add(ProbeRow(
        label: 'Anfangswert $name = ${_fmt(c.value)}',
        detail: value.isFinite ? '$name = ${_fmt(value)}' : '$name ist nicht definiert',
        ok: ok,
      ));
    }
    final domain = p.domain;
    var checked = 0;
    for (final env in _assignments([x], domain == null ? const {} : {x: domain})) {
      if (checked >= 3) break;
      final t = env[x]!;
      final value = f(t);
      final slope = d1(t);
      if (!value.isFinite || !slope.isFinite) continue;
      final double lhs, expected;
      if (p.kind == StepProbeKind.antiderivative) {
        lhs = slope;
        expected = rhs.evaluate({x: t});
      } else if (p.order == 2) {
        lhs = d2(t);
        expected = rhs.evaluate({x: t, y: value, "$y'": slope});
      } else {
        lhs = slope;
        expected = rhs.evaluate({x: t, y: value});
      }
      if (!lhs.isFinite || !expected.isFinite) continue;
      checked++;
      final ok = _close(lhs, expected, tol: p.order == 2 ? 1e-3 : 1e-4) || (lhs - expected).abs() < 1e-6;
      final left = p.kind == StepProbeKind.antiderivative
          ? '$yName′'
          : (p.order == 2 ? '$yName″' : '$yName′');
      final right = p.kind == StepProbeKind.antiderivative ? 'Integrand' : 'rechte Seite';
      rows.add(ProbeRow(
        label: p.kind == StepProbeKind.antiderivative
            ? 'Ableitung an der Stelle $x = ${_fmt(t)}'
            : 'DGL an der Stelle $x = ${_fmt(t)}',
        detail: '$left = ${_fmt(lhs)}  ${ok ? '=' : '≠'}  $right = ${_fmt(expected)}',
        ok: ok,
      ));
    }
    if (checked < 2) {
      return ProbeReport(
        rows: rows,
        passed: false,
        note: 'Die Probe ließ sich nicht an genug Stellen einsetzen.',
      );
    }
    return ProbeReport(rows: rows, passed: rows.every((r) => r.ok));
  }

  // -------------------------------------------------------------------------
  // Nachprüfung der Aufgabe (Musterlösung der KI)
  // -------------------------------------------------------------------------

  /// Rechnet die Musterlösung nach: lesbare erwartete Antworten, typische
  /// Fehler, die nicht in Wahrheit richtig sind, eine richtige Option je
  /// Auswahl und – falls vorhanden – die Probe des Endergebnisses.
  static StepTaskCheck verify(StepTask task) {
    final problems = <String>[];
    for (final (i, step) in task.steps.indexed) {
      final n = i + 1;
      if (step.isChoice) {
        if (!step.options.any((o) => o.correct)) problems.add('Schritt $n: keine Antwort ist als richtig markiert.');
        continue;
      }
      for (final field in step.fields) {
        final names = field.declaredNames;
        final ref = MathExpression.tryParse(field.answer, names: names);
        if (ref == null) {
          problems.add('Schritt $n: die erwartete Antwort „${field.answer}“ ist nicht lesbar.');
          continue;
        }
        if (field.kind == StepFieldKind.number) {
          if (ref.freeSymbols.isNotEmpty || !ref.evaluate().isFinite) {
            problems.add('Schritt $n: „${field.answer}“ ist keine Zahl.');
          }
        } else {
          final vars = field.variables.isNotEmpty
              ? field.variables
              : (ref.freeSymbols.difference(field.constants.toSet()).toList()..sort());
          final fixed = {for (final c in field.constants) c: 3.7};
          if (vars.isNotEmpty && _validPoints(ref, vars, field.domain, fixed: fixed).length < 2) {
            problems.add('Schritt $n: „${field.answer}“ lässt sich nirgends einsetzen.');
          }
        }
        for (final m in field.mistakes) {
          final verdict = check(field, m.answer);
          if (verdict.isCorrect) {
            problems.add('Schritt $n: der „typische Fehler“ „${m.answer}“ ist in Wahrheit richtig.');
          }
        }
      }
    }
    final last = task.finalField;
    final probe = last == null ? null : StepChecker.probe(task, last.answer);
    if (task.steps.isEmpty) problems.add('Die Aufgabe hat keine Schritte.');
    return StepTaskCheck(problems: problems, probe: probe);
  }
}
