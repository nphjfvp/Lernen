import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/zoomable_image.dart';
import '../../models/crystal_task.dart';
import '../../models/flashcard.dart';
import '../../services/crystal_geometry.dart';
import '../../services/fsrs_service.dart';
import '../../theme/app_colors.dart';
import '../study/study_aids.dart';
import '../widgets/math_text.dart';
import 'crystal_cube.dart';

/// Stand einer Teilaufgabe.
class _PartState {
  List<int>? start;
  final List<(List<int>, List<int>)> arrows = [];
  final List<List<int>> picked = [];
  final List<String?> intercepts = [null, null, null];
  bool interceptMode = false;
  final Set<String> marked = {};
  final controllers = [TextEditingController(), TextEditingController(), TextEditingController()];
  CrystalVerdict? verdict;
  bool solved = false;
  bool revealed = false;
  int wrong = 0;
  int hintsShown = 0;

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

/// Kristallgitter-Aufgabe beantworten ([QuestionType.crystal]): Richtungen
/// und Ebenen im drehbaren Würfel einzeichnen oder ablesen, Familien, Atome
/// in einer Ebene. Die App prüft selbst (CrystalGeometry).
///
/// Bewertung beim "Weiter": ohne Fehlversuch und Tipp = gewusst, sonst
/// Schwer; eine Lösung angesehen oder aufgelöst = Nochmal. Probeklausur:
/// keine Rückmeldung, "Antwort abgeben" wertet alle Teile.
class CrystalTaskView extends StatefulWidget {
  const CrystalTaskView({
    super.key,
    required this.card,
    required this.task,
    required this.isNew,
    required this.onComplete,
    this.examMode = false,
    this.onSkip,
    this.canGiveUp = false,
  });

  final Flashcard card;
  final CrystalTask task;
  final bool isNew;
  final bool examMode;
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;
  final VoidCallback? onSkip;
  final bool canGiveUp;

  @override
  State<CrystalTaskView> createState() => _CrystalTaskViewState();
}

class _CrystalTaskViewState extends State<CrystalTaskView> {
  late final List<_PartState> _parts = [for (final _ in widget.task.parts) _PartState()];
  int _current = 0;
  bool _half = false;
  late bool _live = !widget.examMode;
  bool _gaveUp = false;
  bool _submitted = false;

  CrystalPart get _part => widget.task.parts[_current];
  _PartState get _state => _parts[_current];
  CrystalLattice get _lattice => widget.task.latticeOf(_part);

  bool get _allDone => _gaveUp || _parts.every((p) => p.solved || p.revealed);

  @override
  void dispose() {
    for (final p in _parts) {
      p.dispose();
    }
    super.dispose();
  }

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _finish() {
    if (_gaveUp || _parts.any((p) => p.revealed)) return _submit(isCorrect: false);
    final clean = _parts.every((p) => p.wrong == 0 && p.hintsShown == 0);
    if (clean) return _submit(isCorrect: true);
    _submit(isCorrect: true, selfGrade: Grade.hard);
  }

  // ---------------------------------------------------------------------------
  // Eingaben
  // ---------------------------------------------------------------------------

  CrystalPlane? _userPlane(_PartState s) {
    if (s.interceptMode) {
      if (s.intercepts.any((x) => x == null)) return null;
      return CrystalGeometry.planeFromIntercepts([for (final x in s.intercepts) x!]);
    }
    if (s.picked.length < 3) return null;
    return CrystalGeometry.planeFromPoints(s.picked).plane;
  }

  bool _collinear(_PartState s) => !s.interceptMode && s.picked.length == 3 && CrystalGeometry.planeFromPoints(s.picked).collinear;

  List<int>? _typed(_PartState s) {
    final out = <int>[];
    for (final c in s.controllers) {
      final raw = c.text.trim().replaceAll(RegExp('[−–]'), '-');
      final neg = raw.contains('̄') || raw.contains('̅');
      final n = int.tryParse(raw.replaceAll(RegExp('[̄̅]'), ''));
      if (n == null) return null;
      out.add(neg ? -n.abs() : n);
    }
    return out;
  }

  List<int> _foundFamily(_PartState s) {
    final members = CrystalGeometry.familyMembers(_part.indices);
    final found = <int>[];
    for (final (a, b) in s.arrows) {
      final v = CrystalGeometry.directionOf(a, b);
      final i = members.indexWhere((m) => CrystalGeometry.same(m, v));
      if (i >= 0 && !found.contains(i)) found.add(i);
    }
    return found;
  }

  void _tapDot(CubeDot dot) {
    final s = _state;
    if (s.solved || s.revealed || _gaveUp) return;
    final p = dot.half;
    setState(() {
      switch (_part.kind) {
        case CrystalPartKind.direction:
        case CrystalPartKind.family:
          if (s.start == null) {
            s.start = p;
            return;
          }
          if (CrystalGeometry.same(s.start, p)) {
            s.start = null;
            return;
          }
          final arrow = (s.start!, p);
          s.start = null;
          if (_part.kind == CrystalPartKind.direction) {
            s.arrows
              ..clear()
              ..add(arrow);
            s.verdict = null;
          } else {
            _addFamilyArrow(s, arrow);
          }
        case CrystalPartKind.plane:
          if (s.interceptMode) return;
          final i = s.picked.indexWhere((q) => CrystalGeometry.same(q, p));
          if (i >= 0) {
            s.picked.removeAt(i);
          } else if (s.picked.length >= 3) {
            s.picked
              ..clear()
              ..add(p);
          } else {
            s.picked.add(p);
          }
          s.verdict = null;
        case CrystalPartKind.planeAtoms:
          if (!dot.atom) return;
          final id = dot.id;
          if (!s.marked.remove(id)) s.marked.add(id);
          s.verdict = null;
        case CrystalPartKind.readDirection:
        case CrystalPartKind.readPlane:
          return;
      }
    });
  }

  void _addFamilyArrow(_PartState s, (List<int>, List<int>) arrow) {
    final members = CrystalGeometry.familyMembers(_part.indices);
    final before = _foundFamily(s).length;
    s.arrows.add(arrow);
    if (s.arrows.length > members.length + 4) s.arrows.removeAt(0);
    final v = CrystalGeometry.directionOf(arrow.$1, arrow.$2);
    final hit = members.any((m) => CrystalGeometry.same(m, v));
    final found = _foundFamily(s).length;
    final lab = millerText(v);
    if (!hit) {
      s.wrong++;
      s.verdict = CrystalVerdict(false, '$lab gehört nicht zur Familie ${_part.notation}.');
    } else if (found == before) {
      s.verdict = CrystalVerdict(false, '$lab hast du schon. Es fehlen noch ${members.length - found}.');
    } else if (found == members.length) {
      s.verdict = CrystalVerdict(true, 'Alle ${members.length} gefunden: ${members.map(millerText).join(', ')}.');
      s.solved = true;
    } else {
      s.verdict = CrystalVerdict(true, '$lab gehört dazu – $found von ${members.length}.');
    }
  }

  /// Ergebnis der aktuellen Eingabe (ohne Zähler zu ändern).
  CrystalVerdict _judge(CrystalPart part, _PartState s) {
    final lattice = widget.task.latticeOf(part);
    switch (part.kind) {
      case CrystalPartKind.direction:
        if (s.arrows.isEmpty) return const CrystalVerdict(false, 'Zeichne zuerst einen Pfeil: Startpunkt antippen, dann Zielpunkt.');
        return CrystalGeometry.judgeDirection(part.indices, s.arrows.last.$1, s.arrows.last.$2);
      case CrystalPartKind.readDirection:
        return CrystalGeometry.judgeReadDirection(part.indices, _typed(s));
      case CrystalPartKind.family:
        final n = CrystalGeometry.familyMembers(part.indices).length;
        final found = _foundFamilyFor(part, s).length;
        return found == n
            ? CrystalVerdict(true, 'Alle $n Richtungen gefunden.')
            : CrystalVerdict(false, '$found von $n Richtungen gefunden.');
      case CrystalPartKind.plane:
        return CrystalGeometry.judgePlane(part.indices, _userPlane(s), collinear: _collinear(s));
      case CrystalPartKind.readPlane:
        return CrystalGeometry.judgeReadPlane(part.indices, _typed(s));
      case CrystalPartKind.planeAtoms:
        final marked = [for (final id in s.marked) id.split('-').map(int.parse).toList()];
        return CrystalGeometry.judgeAtoms(part.indices, lattice, marked);
    }
  }

  List<int> _foundFamilyFor(CrystalPart part, _PartState s) {
    final members = CrystalGeometry.familyMembers(part.indices);
    final found = <int>{};
    for (final (a, b) in s.arrows) {
      final i = members.indexWhere((m) => CrystalGeometry.same(m, CrystalGeometry.directionOf(a, b)));
      if (i >= 0) found.add(i);
    }
    return found.toList();
  }

  void _check() {
    if (widget.examMode) {
      final ok = [for (final (i, p) in widget.task.parts.indexed) _judge(p, _parts[i]).ok].every((b) => b);
      _submit(isCorrect: ok);
      return;
    }
    final s = _state;
    final v = _judge(_part, s);
    setState(() {
      s.verdict = v;
      if (v.ok) {
        s.solved = true;
      } else {
        s.wrong++;
      }
    });
  }

  void _clear() => setState(() {
        final s = _state;
        s.start = null;
        if (_part.kind == CrystalPartKind.family) {
          if (s.arrows.isNotEmpty) s.arrows.removeLast();
        } else {
          s.arrows.clear();
        }
        s.picked.clear();
        for (var i = 0; i < 3; i++) {
          s.intercepts[i] = null;
        }
        s.marked.clear();
        for (final c in s.controllers) {
          c.clear();
        }
        s.verdict = null;
      });

  void _reveal() => setState(() {
        final s = _state;
        s.revealed = true;
        s.start = null;
        s.verdict = CrystalVerdict(false, '${_solutionText(_part)} Zählt als „Nochmal“.');
      });

  void _giveUp() => setState(() {
        _gaveUp = true;
        for (final p in _parts) {
          if (!p.solved) p.revealed = true;
        }
        _state.verdict = CrystalVerdict(false, '${_solutionText(_part)} Aufgelöst – zählt als nicht gewusst.');
      });

  String _solutionText(CrystalPart part) {
    final v = part.indices;
    switch (part.kind) {
      case CrystalPartKind.direction:
        final seg = CrystalGeometry.gridSegment(CrystalGeometry.reduce(v));
        return seg == null
            ? 'Lösung ist grün gestrichelt eingezeichnet.'
            : 'Lösung: von ${CrystalGeometry.pointText(seg.$1)} nach ${CrystalGeometry.pointText(seg.$2)} (grün gestrichelt).';
      case CrystalPartKind.readDirection:
        return 'Lösung: ${part.notation}.';
      case CrystalPartKind.family:
        return 'Lösung: ${CrystalGeometry.familyMembers(v).map(millerText).join(', ')} (grün gestrichelt).';
      case CrystalPartKind.plane:
        final o = CrystalGeometry.standardOrigin(v);
        return 'Lösung: Achsenabschnitte ${CrystalGeometry.standardPlane(v).interceptsFrom(o).join(', ')}'
            '${CrystalGeometry.same(o, const [0, 0, 0]) ? '' : ' vom Ursprung ${CrystalGeometry.pointText(o)} aus'} (grün gestrichelt).';
      case CrystalPartKind.readPlane:
        return 'Lösung: ${part.notation}.';
      case CrystalPartKind.planeAtoms:
        final atoms = CrystalGeometry.atomsIn(v, _lattice);
        return 'Lösung: ${atoms.length} Atome – ${CrystalGeometry.atomsSummary(atoms)} (grün umrandet).';
    }
  }

  // ---------------------------------------------------------------------------
  // Würfelinhalt
  // ---------------------------------------------------------------------------

  ({List<CubeArrow> arrows, List<CubePolygon> polys, List<CubeArrow> lines, List<CubeDot> dots}) _scene(AppColors c) {
    final part = _part, s = _state, kind = part.kind;
    final arrows = <CubeArrow>[];
    final polys = <CubePolygon>[];
    final lines = <CubeArrow>[];
    final showSolution = s.revealed || _gaveUp;
    final members = kind == CrystalPartKind.family ? CrystalGeometry.familyMembers(part.indices) : const <List<int>>[];

    switch (kind) {
      case CrystalPartKind.direction:
        for (final (a, b) in s.arrows) {
          final color = s.verdict == null ? c.accent : (s.verdict!.ok ? c.good : c.danger);
          arrows.add(CubeArrow(halfToUnit(a), halfToUnit(b), widget.examMode ? c.accent : color));
        }
        if (showSolution) {
          final (a, b) = CrystalGeometry.segment(CrystalGeometry.reduce(part.indices));
          arrows.add(CubeArrow(a, b, c.good, dashed: true));
        }
      case CrystalPartKind.readDirection:
        final (a, b) = CrystalGeometry.segment(part.indices);
        arrows.add(CubeArrow(a, b, c.accent));
      case CrystalPartKind.family:
        for (final (a, b) in s.arrows) {
          final v = CrystalGeometry.directionOf(a, b);
          final hit = members.any((m) => CrystalGeometry.same(m, v));
          arrows.add(CubeArrow(halfToUnit(a), halfToUnit(b), widget.examMode ? c.accent : (hit ? c.good : c.danger)));
        }
        if (showSolution) {
          for (final m in members) {
            final (a, b) = CrystalGeometry.segment(m);
            arrows.add(CubeArrow(a, b, c.good, dashed: true));
          }
        }
      case CrystalPartKind.plane:
        final plane = _userPlane(s);
        if (plane != null) _addPlane(polys, lines, plane, s.verdict == null || widget.examMode ? c.accent : (s.verdict!.ok ? c.good : c.danger), fill: true, c: c);
        if (showSolution) _addPlane(polys, lines, CrystalGeometry.standardPlane(part.indices), c.good, dashed: true, c: c);
      case CrystalPartKind.readPlane:
      case CrystalPartKind.planeAtoms:
        _addPlane(polys, lines, CrystalGeometry.standardPlane(part.indices), c.accent, fill: true, c: c);
    }

    // Punkte und Atome
    final tappable = !(s.solved || s.revealed || _gaveUp) &&
        (kind == CrystalPartKind.direction ||
            kind == CrystalPartKind.family ||
            (kind == CrystalPartKind.plane && !s.interceptMode) ||
            kind == CrystalPartKind.planeAtoms);
    final sites = CrystalGeometry.sites(_lattice);
    bool isSite(List<int> p) => sites.any((q) => CrystalGeometry.same(q, p));
    final points = <List<int>>[
      ...CrystalGeometry.gridPoints(_lattice, half: _half && kind != CrystalPartKind.planeAtoms),
    ];
    // Bei Ebenen-Teilen immer die Atome des Gitters zeigen.
    for (final q in sites) {
      if (!points.any((p) => CrystalGeometry.same(p, q))) points.add(q);
    }
    final plane = kind == CrystalPartKind.plane ? _userPlane(s) : null;
    final want = kind == CrystalPartKind.planeAtoms ? CrystalGeometry.atomsIn(part.indices, _lattice) : const <List<int>>[];
    final dots = <CubeDot>[];
    for (final p in points) {
      final atom = isSite(p) && (kind.isPlane || _lattice != CrystalLattice.sc);
      final isStart = CrystalGeometry.same(s.start, p);
      final isPicked = s.picked.any((q) => CrystalGeometry.same(q, p));
      final id = p.join('-');
      Color? fill;
      Color? ring;
      var ringWidth = 1.2;
      var dashed = false;
      if (atom && plane != null && (_live || s.solved || showSolution) && !widget.examMode && plane.contains(p)) {
        fill = c.goodSoft;
        ring = c.good;
        ringWidth = 1.8;
      }
      if (kind == CrystalPartKind.planeAtoms) {
        final marked = s.marked.contains(id);
        final should = want.any((w) => CrystalGeometry.same(w, p));
        if (marked) {
          fill = c.accentSoft;
          ring = c.accent;
          ringWidth = 2;
        }
        if (!widget.examMode && s.verdict != null && marked && !should) {
          ring = c.danger;
          ringWidth = 3;
        }
        if (showSolution && should && !marked) {
          ring = c.good;
          ringWidth = 2.5;
          dashed = true;
        }
      }
      if (isStart || isPicked) {
        ring = c.accent;
        ringWidth = 3;
      }
      if (!tappable && !atom && kind != CrystalPartKind.readDirection) continue;
      if (kind == CrystalPartKind.readDirection && !atom && !_half) continue;
      dots.add(CubeDot(
        half: p,
        atom: atom,
        fill: fill,
        ring: ring,
        ringWidth: ringWidth,
        dashedRing: dashed,
        selected: isStart || isPicked,
      ));
    }
    return (arrows: arrows, polys: polys, lines: lines, dots: dots);
  }

  void _addPlane(List<CubePolygon> polys, List<CubeArrow> lines, CrystalPlane plane, Color color,
      {bool fill = false, bool dashed = false, required AppColors c}) {
    final pts = CrystalGeometry.section(plane);
    if (pts.length >= 3) {
      polys.add(CubePolygon(pts, stroke: color, fill: fill ? color.withValues(alpha: 0.2) : null, dashed: dashed));
    } else if (pts.length == 2) {
      lines.add(CubeArrow(pts[0], pts[1], c.danger));
    }
  }

  // ---------------------------------------------------------------------------
  // Texte unter dem Würfel
  // ---------------------------------------------------------------------------

  (String, String?) _readout() {
    final part = _part, s = _state;
    switch (part.kind) {
      case CrystalPartKind.direction:
        if (s.start != null) return ('Start ${CrystalGeometry.pointText(s.start!)} – jetzt den Zielpunkt antippen.', null);
        if (s.arrows.isEmpty) return ('Tippe den Startpunkt an, dann den Zielpunkt. Zum Drehen ziehen.', null);
        final (a, b) = s.arrows.last;
        final diff = CrystalGeometry.sub(b, a);
        final halves = diff.any((k) => k.isOdd);
        return (
          'Von ${CrystalGeometry.pointText(a)} nach ${CrystalGeometry.pointText(b)}',
          'Ziel − Start = ${CrystalGeometry.vectorText(diff)}${halves ? '  · 2' : ''}  →  ${millerText(CrystalGeometry.reduce(diff))}',
        );
      case CrystalPartKind.family:
        final n = CrystalGeometry.familyMembers(part.indices).length;
        final found = _foundFamily(s).length;
        if (s.start != null) return ('Start ${CrystalGeometry.pointText(s.start!)} – jetzt den Zielpunkt antippen.', null);
        final last = s.arrows.isEmpty ? null : s.arrows.last;
        return (
          s.arrows.isEmpty ? 'Für jede Richtung einen eigenen Pfeil: Start antippen, dann Ziel.' : 'Gefunden: $found von $n.',
          last == null ? null : 'Letzter Pfeil  →  ${millerText(CrystalGeometry.directionOf(last.$1, last.$2))}',
        );
      case CrystalPartKind.plane:
        final plane = _userPlane(s);
        final text = s.interceptMode
            ? (s.intercepts.any((x) => x == null) ? 'Wähle für jede Achse, wo die Ebene sie schneidet (∞ = parallel).' : 'Ebene aus den Achsenabschnitten')
            : (s.picked.isEmpty
                ? 'Tippe drei Punkte an, die in der Ebene liegen.'
                : s.picked.length < 3
                    ? 'Gewählt: ${s.picked.map(CrystalGeometry.pointText).join(', ')} – noch ${3 - s.picked.length}.'
                    : 'Ebene durch ${s.picked.map(CrystalGeometry.pointText).join(', ')}');
        if (_collinear(s)) return (text, 'Die drei Punkte liegen auf einer Geraden.');
        if (plane == null) return (text, null);
        final o = _readingOrigin(plane, part.indices);
        final h = o == null ? null : plane.millerFrom(o);
        if (h == null) return (text, 'Ebene ${plane.equation} – geht durch den Ursprung.');
        final atoms = [for (final q in CrystalGeometry.sites(_lattice)) if (plane.contains(q)) q];
        return (
          text,
          'Achsenabschnitte ${plane.interceptsFrom(o!).join(', ')}'
              '${CrystalGeometry.same(o, const [0, 0, 0]) ? '' : ' (Ursprung ${CrystalGeometry.pointText(o)})'}'
              '  →  ${millerText(h, open: '(', close: ')')}'
              '${atoms.isEmpty ? '' : '\nDarin: ${atoms.length} Atome – ${CrystalGeometry.atomsSummary(atoms)}'}',
        );
      case CrystalPartKind.readDirection:
      case CrystalPartKind.readPlane:
        final typed = _typed(s);
        final brackets = part.kind == CrystalPartKind.readPlane ? ('(', ')') : ('[', ']');
        return (
          part.kind == CrystalPartKind.readPlane
              ? 'Lies die Achsenabschnitte ab und bilde die Kehrwerte.'
              : 'Lies Start und Ziel des blauen Pfeils ab.',
          typed == null ? null : 'Deine Eingabe: ${millerText(typed, open: brackets.$1, close: brackets.$2)}',
        );
      case CrystalPartKind.planeAtoms:
        return (s.marked.isEmpty ? 'Tippe die Atome an, die in der blauen Ebene liegen.' : '${s.marked.length} Atome markiert.', null);
    }
  }

  /// Ursprung zum Ablesen: der übliche für die gesuchte Ebene, sonst (0, 0, 0)
  /// bzw. die erste Ecke, durch die die Ebene nicht geht.
  List<int>? _readingOrigin(CrystalPlane plane, List<int> target) {
    final std = CrystalGeometry.standardOrigin(target);
    if (plane.millerFrom(std) != null) return std;
    for (final o in CrystalGeometry.corners) {
      if (plane.millerFrom(o) != null) return o;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Anzeige
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.card;
    final part = _part, s = _state;
    final scene = _scene(c);
    final (readout, calc) = _readout();
    final hints = CrystalGeometry.hints(part, _lattice);
    final finishedPart = s.solved || s.revealed || _gaveUp;
    final nextIndex = [
      for (var i = 0; i < _parts.length; i++)
        if (i != _current && !_parts[i].solved && !_parts[i].revealed) i,
    ].firstOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final taskCard = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                  child: Text('${QuestionType.crystal.label} · ${_lattice.short}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
                ),
              ),
              const Spacer(),
              if (!widget.examMode) SourceLinkButton(card: card),
            ],
          ),
          const SizedBox(height: 10),
          if (card.imageBase64 != null) _image(card.imageBase64!),
          MathText(card.front, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.45)),
        ],
      ),
    );

    final partChips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (i, p) in widget.task.parts.indexed)
          ChoiceChip(
            key: ValueKey('crystal-part-$i'),
            selected: i == _current,
            showCheckmark: false,
            avatar: _parts[i].solved && !widget.examMode
                ? Icon(Icons.check_circle, size: 16, color: c.good)
                : (_parts[i].revealed ? Icon(Icons.visibility_outlined, size: 16, color: c.warn) : null),
            label: Text('${String.fromCharCode(97 + i)}  ${p.notation}'),
            onSelected: (_) => setState(() => _current = i),
          ),
      ],
    );

    final prompt = Container(
      key: const ValueKey('crystal-prompt'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '${part.promptText} ', style: const TextStyle(fontSize: 14.5, height: 1.4)),
        if (!part.kind.isRead)
          TextSpan(text: part.notation, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        if (part.kind.isPlane && _lattice != CrystalLattice.sc)
          TextSpan(text: '  (${_lattice.label})', style: TextStyle(fontSize: 13, color: c.inkMuted)),
      ])),
    );

    final interceptAllowed = part.kind == CrystalPartKind.plane && part.indices.every((k) => k >= 0);
    final cube = CrystalCube(
      key: ValueKey('crystal-cube-$_current'),
      height: wide ? 420 : 330,
      arrows: scene.arrows,
      polygons: scene.polys,
      lines: scene.lines,
      dots: scene.dots,
      onTapDot: _tapDot,
      half: part.kind == CrystalPartKind.planeAtoms ? null : _half,
      onToggleHalf: () => setState(() => _half = !_half),
      note: 'Ziehen zum Drehen',
    );

    final controls = <Widget>[
      if (interceptAllowed && !finishedPart) ...[
        SegmentedButton<bool>(
          key: const ValueKey('crystal-mode'),
          segments: const [
            ButtonSegment(value: false, label: Text('Punkte antippen')),
            ButtonSegment(value: true, label: Text('Achsenabschnitte')),
          ],
          selected: {s.interceptMode},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            s.interceptMode = v.first;
            s.verdict = null;
          }),
        ),
        const SizedBox(height: 10),
      ],
      if (part.kind == CrystalPartKind.plane && s.interceptMode && !finishedPart) ...[
        _interceptRows(c, s),
        const SizedBox(height: 10),
      ],
      if (part.kind.isRead && !finishedPart) ...[
        _typedRow(c, s),
        const SizedBox(height: 10),
      ],
      Container(
        key: const ValueKey('crystal-readout'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(readout, style: const TextStyle(fontSize: 13.5, height: 1.4)),
            if (calc != null && _live)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(calc, key: const ValueKey('crystal-calc'), style: const TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600)),
              ),
            if (part.kind == CrystalPartKind.family && !widget.examMode) ...[
              const SizedBox(height: 8),
              _familyChips(c, s),
            ],
          ],
        ),
      ),
      if (s.verdict != null && !widget.examMode) ...[
        const SizedBox(height: 10),
        _verdictBox(c, s.verdict!),
      ],
      if (!widget.examMode)
        for (var h = 0; h < s.hintsShown && h < hints.length; h++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              key: ValueKey('crystal-hint-$h'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: c.warn),
                  const SizedBox(width: 8),
                  Expanded(child: Text(hints[h], style: const TextStyle(fontSize: 13.5, height: 1.4))),
                ],
              ),
            ),
          ),
      const SizedBox(height: 12),
      ..._buttons(c, hints.length, finishedPart, nextIndex),
      if (!widget.examMode) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('crystal-live'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _live,
          onChanged: (v) => setState(() => _live = v),
          title: Text('Indizes beim Zeichnen live anzeigen', style: TextStyle(fontSize: 13, color: c.inkMuted)),
        ),
      ],
    ];

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        taskCard,
        const SizedBox(height: 12),
        if (widget.task.parts.length > 1) ...[partChips, const SizedBox(height: 10)],
        prompt,
        if (wide) ...[const SizedBox(height: 12), ...controls],
      ],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (widget.isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
              child: Text('NEU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn)),
            ),
          ),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 380, child: left),
              const SizedBox(width: 20),
              Expanded(child: cube),
            ],
          )
        else ...[
          left,
          const SizedBox(height: 12),
          cube,
          const SizedBox(height: 12),
          ...controls,
        ],
      ],
    );
  }

  Widget _image(String base64) {
    try {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ZoomableImage(bytes: base64Decode(base64)),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _interceptRows(AppColors c, _PartState s) {
    const options = [('1', '1'), ('½', 'half'), ('∞', 'inf')];
    return Column(
      children: [
        for (final (i, axis) in const ['x', 'y', 'z'].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 26, child: Text(axis, style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic))),
                for (final (label, key) in options) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: OutlinedButton(
                        key: ValueKey('crystal-icpt-$axis-$key'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: s.intercepts[i] == label ? c.accentSoft : null,
                          side: BorderSide(color: s.intercepts[i] == label ? c.accent : c.border, width: 1.4),
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => setState(() {
                          s.intercepts[i] = label;
                          s.verdict = null;
                        }),
                        child: Text(label, style: TextStyle(fontSize: 18, color: s.intercepts[i] == label ? c.accentOnSoft : c.ink)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _typedRow(AppColors c, _PartState s) {
    final plane = _part.kind == CrystalPartKind.readPlane;
    final names = plane ? const ['h', 'k', 'l'] : const ['u', 'v', 'w'];
    return Row(
      children: [
        Text(plane ? '(' : '[', style: const TextStyle(fontSize: 26)),
        for (var i = 0; i < 3; i++) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: TextField(
              key: ValueKey('crystal-uvw-$i'),
              controller: s.controllers[i],
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                isDense: true,
                hintText: names[i],
                filled: true,
                fillColor: c.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() => s.verdict = null),
              onSubmitted: (_) => _check(),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Text(plane ? ')' : ']', style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Minus für negativ (−1 wird zu 1̄)', style: TextStyle(fontSize: 12, color: c.inkMuted)),
        ),
      ],
    );
  }

  Widget _familyChips(AppColors c, _PartState s) {
    final members = CrystalGeometry.familyMembers(_part.indices);
    final found = _foundFamily(s);
    final show = s.revealed || _gaveUp;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (i, m) in members.indexed)
          Container(
            key: ValueKey('crystal-family-$i'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: found.contains(i) || show ? c.goodSoft : null,
              border: Border.all(color: found.contains(i) || show ? c.good : c.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(found.contains(i) || show ? millerText(m) : '?',
                style: TextStyle(fontSize: 14, color: found.contains(i) || show ? c.good : c.inkMuted)),
          ),
      ],
    );
  }

  Widget _verdictBox(AppColors c, CrystalVerdict v) => Container(
        key: const ValueKey('crystal-verdict'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: v.ok ? c.goodSoft : c.dangerSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(v.ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: v.ok ? c.good : c.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(v.text, style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w500, color: v.ok ? c.good : c.danger)),
            ),
          ],
        ),
      );

  List<Widget> _buttons(AppColors c, int hintCount, bool finishedPart, int? nextIndex) {
    final s = _state;
    if (widget.examMode) {
      return [
        if (_parts.length > 1)
          OutlinedButton(
            key: const ValueKey('crystal-next-part'),
            onPressed: () => setState(() => _current = (_current + 1) % _parts.length),
            child: const Text('Nächste Teilaufgabe'),
          ),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('crystal-submit'), onPressed: _check, child: const Text('Antwort abgeben')),
      ];
    }
    if (_allDone) {
      final anyRevealed = _gaveUp || _parts.any((p) => p.revealed);
      final clean = !anyRevealed && _parts.every((p) => p.wrong == 0 && p.hintsShown == 0);
      return [
        Container(
          key: const ValueKey('crystal-finished'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: clean ? c.goodSoft : (anyRevealed ? c.warnSoft : c.accentSoft),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _gaveUp
                ? 'Aufgelöst – zählt als nicht gewusst'
                : anyRevealed
                    ? 'Mit angesehener Lösung – zählt als „Nochmal“'
                    : (clean ? 'Alles gelöst – ohne Hilfe' : 'Alles gelöst – mit Hilfe, zählt als „Schwer“'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(key: const ValueKey('crystal-next'), onPressed: _finish, child: const Text('Weiter')),
      ];
    }
    if (finishedPart) {
      return [
        FilledButton(
          key: const ValueKey('crystal-next-part'),
          onPressed: nextIndex == null ? null : () => setState(() => _current = nextIndex),
          child: Text(nextIndex == null ? 'Weiter' : 'Weiter zu ${String.fromCharCode(97 + nextIndex)}  ${widget.task.parts[nextIndex].notation}'),
        ),
      ];
    }
    final canCheck = _part.kind != CrystalPartKind.family;
    return [
      Row(
        children: [
          OutlinedButton.icon(
            key: const ValueKey('crystal-hint-button'),
            onPressed: s.hintsShown >= hintCount ? null : () => setState(() => s.hintsShown++),
            icon: const Icon(Icons.lightbulb_outline, size: 18),
            label: const Text('Tipp'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey('crystal-clear'),
            onPressed: _clear,
            child: Text(_part.kind == CrystalPartKind.family ? 'Letzten löschen' : 'Löschen'),
          ),
          const SizedBox(width: 8),
          if (canCheck)
            Expanded(
              child: FilledButton(key: const ValueKey('crystal-check'), onPressed: _check, child: const Text('Prüfen')),
            ),
        ],
      ),
      Wrap(
        alignment: WrapAlignment.center,
        children: [
          TextButton(key: const ValueKey('crystal-reveal'), onPressed: _reveal, child: const Text('Lösung zeigen')),
          if (widget.onSkip != null)
            TextButton(
              key: const ValueKey('question-skip'),
              onPressed: () {
                if (_submitted) return;
                _submitted = true;
                widget.onSkip!();
              },
              child: const Text('Überspringen'),
            ),
          if (widget.canGiveUp)
            TextButton(key: const ValueKey('question-give-up'), onPressed: _giveUp, child: const Text('Auflösen')),
        ],
      ),
    ];
  }
}
