import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../models/lecture_walk.dart';
import '../../models/worked_solution.dart';
import '../../theme/app_colors.dart';
import '../visual/worked_solution_screen.dart';
import '../widgets/math_text.dart';

/// Ein Konzept in der Leiste über der Tafel.
class LectureBoardConcept {
  const LectureBoardConcept({required this.title, this.pages = '', this.revealed = 0, this.total = 0});

  final String title;
  final String pages;
  final int revealed;

  /// 0 = Aufgabe wird noch vorbereitet.
  final int total;

  Map<String, dynamic> toMap() => {'title': title, 'pages': pages, 'revealed': revealed, 'total': total};

  static LectureBoardConcept fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    int number(Object? v) => v is num ? v.toInt() : 0;
    return LectureBoardConcept(
      title: '${m['title'] ?? ''}',
      pages: '${m['pages'] ?? ''}',
      revealed: number(m['revealed']),
      total: number(m['total']),
    );
  }
}

/// Was die Tafel bei „Vorlesung mit Aufgabe“ zeigt – serialisierbar, damit
/// sie auch im eigenen Fenster (PC, zweiter Bildschirm) gleich aussieht.
class LectureBoardState {
  const LectureBoardState({
    this.concepts = const [],
    this.current = -1,
    this.solution,
    this.revealed = 0,
    this.focus,
    this.pageLabel = '',
    this.formulas = const [],
    this.freshFormulas = 0,
    this.coach = '',
    this.chat = const [],
    this.busy = false,
    this.busyText = '',
    this.error,
  });

  final List<LectureBoardConcept> concepts;
  final int current;

  /// Die Aufgabe des aktuellen Konzepts als Vorrechnen-Lösung.
  final WorkedSolution? solution;

  /// So viele Schritte sind freigegeben (Seiten schon gelesen).
  final int revealed;

  /// Schritt, auf den die Tafel springt (dort hakte es beim Selbstlösen).
  final int? focus;
  final String pageLabel;
  final List<LectureFormula> formulas;

  /// Die letzten so vielen Formeln sind gerade neu dazugekommen.
  final int freshFormulas;

  /// Was die KI gerade sagt („Okay, lass uns mit unserer Aufgabe weitermachen …“).
  final String coach;

  /// Fragen und Antworten zur Formelsammlung und zur Vorlesung.
  final List<({bool user, String text})> chat;
  final bool busy;
  final String busyText;
  final String? error;

  Map<String, dynamic> toMap() => {
    'concepts': [for (final c in concepts) c.toMap()],
    'current': current,
    'solution': solution?.toMap(),
    'revealed': revealed,
    'focus': focus,
    'pageLabel': pageLabel,
    'formulas': [for (final f in formulas) f.toMap()],
    'freshFormulas': freshFormulas,
    'coach': coach,
    'chat': [
      for (final m in chat) {'user': m.user, 'text': m.text},
    ],
    'busy': busy,
    'busyText': busyText,
    'error': error,
  };

  static LectureBoardState fromMap(Object? raw) {
    if (raw is! Map) return const LectureBoardState();
    int number(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
    final concepts = raw['concepts'];
    final formulas = raw['formulas'];
    final chat = raw['chat'];
    final focus = raw['focus'];
    return LectureBoardState(
      concepts: [for (final c in concepts is List ? concepts : const []) LectureBoardConcept.fromMap(c)],
      current: number(raw['current'], -1),
      solution: WorkedSolution.fromMap(raw['solution']),
      revealed: number(raw['revealed']),
      focus: focus is num ? focus.toInt() : null,
      pageLabel: '${raw['pageLabel'] ?? ''}',
      formulas: [for (final f in formulas is List ? formulas : const []) ?LectureFormula.fromMap(f)],
      freshFormulas: number(raw['freshFormulas']),
      coach: '${raw['coach'] ?? ''}',
      chat: [
        for (final m in chat is List ? chat : const [])
          if (m is Map) (user: m['user'] == true, text: '${m['text'] ?? ''}'),
      ],
      busy: raw['busy'] == true,
      busyText: '${raw['busyText'] ?? ''}',
      error: raw['error'] == null ? null : '${raw['error']}',
    );
  }
}

/// Die Tafel: oben die Konzepte, in der Mitte „Vorrechnen“ (Tafel,
/// Taschenrechner, Regeln, Fragen je Schritt, feiner) – nur so weit, wie die
/// Vorlesung schon gelesen ist –, unten die Formelsammlung.
class LectureBoardView extends StatefulWidget {
  const LectureBoardView({
    super.key,
    required this.state,
    required this.onAsk,
    required this.onSelect,
    this.onRefined,
    this.onDetach,
    this.actions = const [],
  });

  final LectureBoardState state;

  /// Frage zur Vorlesung – [formula] = Index in der Formelsammlung.
  final void Function(String question, {int? formula}) onAsk;

  /// Anderes Konzept an die Tafel.
  final ValueChanged<int> onSelect;

  /// An der Tafel wurde ein Schritt feiner aufgeteilt.
  final void Function(int concept, int step, int count, WorkedSolution updated)? onRefined;

  /// Tafel in eigenem Fenster (nur am PC).
  final VoidCallback? onDetach;

  /// Weitere Knöpfe über der Tafel (z.B. Visuell erklären).
  final List<Widget> actions;

  @override
  State<LectureBoardView> createState() => _LectureBoardViewState();
}

class _LectureBoardViewState extends State<LectureBoardView> {
  late final _limit = ValueNotifier<int>(_effectiveLimit(widget.state));
  final _question = TextEditingController();
  bool _formulasOpen = false;

  static int _effectiveLimit(LectureBoardState s) => s.focus != null ? s.focus! + 1 : s.revealed;

  @override
  void didUpdateWidget(LectureBoardView old) {
    super.didUpdateWidget(old);
    if (_effectiveLimit(widget.state) != _limit.value) {
      // Nach dem Bauen melden – der Vorrechnen-Bildschirm schreibt dann an.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _limit.value = _effectiveLimit(widget.state);
      });
    }
  }

  @override
  void dispose() {
    _limit.dispose();
    _question.dispose();
    super.dispose();
  }

  void _ask() {
    final q = _question.text.trim();
    if (q.isEmpty) return;
    _question.clear();
    widget.onAsk(q);
  }

  Widget _header(AppColors c, LectureBoardState s) {
    final fresh = s.freshFormulas.clamp(0, s.formulas.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.coach.isNotEmpty)
          Container(
            key: const ValueKey('lecture-coach'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.record_voice_over_outlined, size: 20, color: c.accent),
                const SizedBox(width: 8),
                Expanded(child: MathText(s.coach, style: const TextStyle(height: 1.45))),
              ],
            ),
          ),
        if (s.busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text(s.busyText.isEmpty ? 'Einen Moment …' : s.busyText)),
              ],
            ),
          ),
        if (s.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(s.error!, style: TextStyle(color: c.danger)),
          ),
        if (fresh > 0)
          Container(
            key: const ValueKey('lecture-new-formulas'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2A24),
              border: Border.all(color: const Color(0xFF81C784), width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fresh == 1 ? 'Neue Formel – an die Tafel geschrieben' : 'Neue Formeln – an die Tafel geschrieben',
                  style: const TextStyle(color: Color(0xFFA5D6A7), fontWeight: FontWeight.w700),
                ),
                for (final f in s.formulas.sublist(s.formulas.length - fresh)) _FormulaLine(formula: f, onBoard: true),
              ],
            ),
          ),
        if (widget.actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: widget.actions),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.state;
    final solution = s.solution;
    return Column(
      key: const ValueKey('lecture-board'),
      children: [
        Material(
          color: c.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (i, concept) in s.concepts.indexed)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Tooltip(
                              message: concept.pages,
                              child: ChoiceChip(
                                key: ValueKey('lecture-concept-$i'),
                                selected: i == s.current,
                                onSelected: (_) => widget.onSelect(i),
                                label: Text(
                                  concept.total == 0
                                      ? '${i + 1}. ${concept.title} · …'
                                      : '${i + 1}. ${concept.title} · ${concept.revealed}/${concept.total}',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (s.pageLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(s.pageLabel, style: TextStyle(color: c.inkMuted, fontSize: 12)),
                  ),
                if (widget.onDetach != null)
                  IconButton(
                    key: const ValueKey('lecture-detach'),
                    tooltip: 'Tafel in eigenem Fenster (auf den zweiten Bildschirm ziehen)',
                    onPressed: widget.onDetach,
                    icon: const Icon(Icons.open_in_new),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: solution == null
              ? ListView(padding: const EdgeInsets.all(16), children: [_header(c, s)])
              : WorkedSolutionScreen(
                  // Neu aufgebaut nur bei anderem Konzept bzw. Sprung zum Haken.
                  key: ValueKey('worked-${s.current}-${s.focus}'),
                  moduleId: solution.moduleId,
                  solution: solution,
                  embedded: true,
                  revealLimit: _limit,
                  header: _header(c, s),
                  onRefined: (step, count, updated) => widget.onRefined?.call(s.current, step, count, updated),
                ),
        ),
        _formulaPanel(c, s),
      ],
    );
  }

  Widget _formulaPanel(AppColors c, LectureBoardState s) => Material(
    color: c.surface,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: const ValueKey('lecture-formulas'),
          onTap: () => setState(() => _formulasOpen = !_formulasOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.functions, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Formelsammlung (${s.formulas.length})${s.chat.isEmpty ? '' : ' · Fragen'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(_formulasOpen ? Icons.expand_more : Icons.expand_less),
              ],
            ),
          ),
        ),
        if (_formulasOpen)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                if (s.formulas.isEmpty)
                  Text('Neue Formeln kommen hierher, sobald sie drankommen.', style: TextStyle(color: c.inkMuted)),
                for (final (i, f) in s.formulas.indexed)
                  _FormulaLine(
                    formula: f,
                    index: i,
                    onAsk: () => widget.onAsk(
                      'Erkläre mir die Formel „${f.name.isEmpty ? f.latex : f.name}“: wofür brauche ich sie, woher '
                      'kommt sie und wie benutze ich sie in unserer Aufgabe?',
                      formula: i,
                    ),
                  ),
                for (final m in s.chat)
                  Align(
                    alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 560),
                      decoration: BoxDecoration(
                        color: m.user ? c.accentSoft : c.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: MathText(m.text, style: const TextStyle(height: 1.4)),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('lecture-question'),
                        controller: _question,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) => _ask(),
                        decoration: const InputDecoration(
                          hintText: 'Frage zur Seite, zu einer Formel oder zur Aufgabe …',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('lecture-ask'),
                      tooltip: 'Fragen',
                      onPressed: s.busy ? null : _ask,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _FormulaLine extends StatelessWidget {
  const _FormulaLine({required this.formula, this.onAsk, this.index, this.onBoard = false});

  final LectureFormula formula;
  final VoidCallback? onAsk;
  final int? index;

  /// Auf der Tafel (hell auf dunkel).
  final bool onBoard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = onBoard ? Colors.white70 : c.inkMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (formula.name.isNotEmpty)
                  Text(
                    formula.page > 0 ? '${formula.name} · S. ${formula.page}' : formula.name,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Math.tex(
                    formula.latex,
                    textStyle: TextStyle(fontSize: 18, color: onBoard ? Colors.white : null),
                    onErrorFallback: (_) => Text(formula.latex),
                  ),
                ),
                if (formula.note.isNotEmpty)
                  Text(formula.note, style: TextStyle(fontSize: 12, color: muted, height: 1.35)),
              ],
            ),
          ),
          if (onAsk != null)
            IconButton(
              key: ValueKey('lecture-formula-ask-$index'),
              tooltip: 'Frage zu dieser Formel',
              onPressed: onAsk,
              icon: const Icon(Icons.help_outline, size: 20),
            ),
        ],
      ),
    );
  }
}
