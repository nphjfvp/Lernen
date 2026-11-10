import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../models/lecture_unit.dart';
import '../../models/material_item.dart';
import '../../models/study_sequence.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/study_sequence_repository.dart';
import '../../services/fsrs_service.dart';
import '../../services/stage_gate_service.dart';
import '../../services/study_sequence.dart';
import '../../theme/app_colors.dart';
import '../daily/card_review_mixin.dart';
import '../daily/question_answer_view.dart';

/// Öffnet „Der Reihe nach“ für [source].
Future<void> openStudySequence(BuildContext context, String moduleId, StudySequenceSource source) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudySequenceScreen(moduleId: moduleId, source: source),
      ),
    );

/// Einheiten und PDFs eines Fachs, die Aufgaben haben – mit Anzahl.
List<({StudySequenceSource source, int count})> studySequenceSources({
  required List<LectureUnit> units,
  required List<MaterialItem> materials,
  required List<Flashcard> cards,
}) => [
  for (final u in units)
    if (cards.where((c) => c.unitId == u.id).length case final n when n > 0)
      (source: StudySequenceSource(kind: StudySequenceKind.unit, id: u.id, title: u.title), count: n),
  for (final m in materials)
    if (cards.where((c) => c.sourceMaterialId == m.id).length case final n when n > 0)
      (source: StudySequenceSource(kind: StudySequenceKind.material, id: m.id, title: m.fileName), count: n),
];

/// Auswahl im Üben: jede Einheit und jede PDF mit Aufgaben, der Reihe nach.
class StudySequenceSourceList extends StatelessWidget {
  const StudySequenceSourceList({super.key, required this.moduleId});

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sources = studySequenceSources(
      units: context.watch<LectureUnitRepository?>()?.forModule(moduleId) ?? const [],
      materials: context.watch<MaterialRepository?>()?.forModule(moduleId) ?? const [],
      cards: context.watch<FlashcardRepository>().forModule(moduleId),
    );
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Der Reihe nach',
          style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'Aufgaben einer Einheit oder PDF von vorne nach hinten – aufeinander aufbauend. Dein Stand bleibt '
          'gespeichert: Nicht Geschafftes kommt in der nächsten Runde wieder, Gelöstes nicht.',
          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 10),
        for (final (i, s) in sources.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              key: ValueKey('sequence-source-$i'),
              onPressed: () => openStudySequence(context, moduleId, s.source),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14)),
              child: Row(
                children: [
                  Icon(
                    s.source.kind == StudySequenceKind.unit ? Icons.folder_outlined : Icons.picture_as_pdf_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.source.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${s.count}', style: TextStyle(color: c.inkMuted)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        Text(
          'Zufällig',
          style: TextStyle(fontWeight: FontWeight.w700, color: c.ink),
        ),
      ],
    );
  }
}

/// „Der Reihe nach“: Übersicht mit Stand je Aufgabe, Weitermachen, „Kann ich
/// schon“ und Neustart ab einer beliebigen Aufgabe – dann Aufgabe für Aufgabe
/// lösen. Antworten zählen wie beim Üben für FSRS/Ampel.
class StudySequenceScreen extends StatefulWidget {
  const StudySequenceScreen({super.key, required this.moduleId, required this.source});

  final String moduleId;
  final StudySequenceSource source;

  @override
  State<StudySequenceScreen> createState() => _StudySequenceScreenState();
}

class _StudySequenceScreenState extends State<StudySequenceScreen> with CardReviewMixin<StudySequenceScreen> {
  final _repo = StudySequenceRepository();
  StudySequenceProgress? _progress;
  List<Flashcard> _ordered = const [];

  /// Laufende Runde (null = Übersicht).
  List<Flashcard>? _queue;
  int _index = 0;
  int _roundSolved = 0;
  int _roundFailed = 0;
  int _roundSkipped = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final cards = context.read<FlashcardRepository>();
    final materials = context.read<MaterialRepository?>();
    await cards.loadForModule(widget.moduleId);
    if (materials != null && materials.forModule(widget.moduleId).isEmpty) {
      await materials.loadForModule(widget.moduleId);
    }
    final progress = await _repo.load(widget.moduleId, widget.source);
    if (!mounted) return;
    setState(() {
      _ordered = _orderedFor(progress.order);
      _progress = progress;
    });
  }

  List<Flashcard> _orderedFor(StudySequenceOrder order) => StudySequence.ordered(
    context.read<FlashcardRepository>().forModule(widget.moduleId),
    widget.source,
    materialOrder: [
      for (final m in context.read<MaterialRepository?>()?.forModule(widget.moduleId) ?? const <MaterialItem>[]) m.id,
    ],
    order: order,
  );

  /// Reihenfolge umschalten: Der Stand je Aufgabe bleibt, die Runde beginnt
  /// in der neuen Reihenfolge bei der ersten offenen Aufgabe.
  void _setOrder(StudySequenceOrder order) {
    final p = _progress;
    if (p == null || p.order == order) return;
    setState(() => _ordered = _orderedFor(order));
    _update(p.copyWith(order: order, clearNext: true));
  }

  void _update(StudySequenceProgress p) {
    setState(() => _progress = p);
    _repo.save(p);
  }

  void _startRound() {
    final p = _progress!;
    setState(() {
      _queue = StudySequence.round(_ordered, p);
      _index = 0;
      _roundSolved = 0;
      _roundFailed = 0;
      _roundSkipped = 0;
    });
  }

  Future<void> _answered(Flashcard card, {Grade? selfGrade, bool? isCorrect}) async {
    final solved = isCorrect ?? (selfGrade != null && selfGrade != Grade.again);
    _update(
      StudySequence.record(
        _ordered,
        _progress!,
        card.id,
        solved ? StudySequenceStatus.solved : StudySequenceStatus.failed,
      ),
    );
    // Gleich weiter – das Verbuchen (FSRS/Ampel) läuft dahinter.
    setState(() {
      if (solved) {
        _roundSolved++;
      } else {
        _roundFailed++;
      }
      _index++;
    });
    await recordReview(card, selfGrade: selfGrade, isCorrect: isCorrect);
  }

  void _understood(Flashcard card) {
    _update(StudySequence.record(_ordered, _progress!, card.id, StudySequenceStatus.skipped));
    setState(() {
      _roundSkipped++;
      _index++;
    });
  }

  Future<void> _restartDialog() async {
    var value = '1';
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neu starten'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ab welcher Aufgabe (1–${_ordered.length})? Alles davor gilt als erledigt, ab hier ist alles offen.'),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('sequence-restart-field'),
              initialValue: '1',
              onChanged: (v) => value = v,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Aufgabe'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(
            key: const ValueKey('sequence-restart-ok'),
            onPressed: () => Navigator.of(ctx).pop(int.tryParse(value.trim())),
            child: const Text('Neu starten'),
          ),
        ],
      ),
    );
    if (n == null || !mounted) return;
    _update(StudySequence.restartAt(_ordered, _progress!, (n - 1).clamp(0, _ordered.length - 1)));
  }

  Future<void> _itemSheet(int i) async {
    final card = _ordered[i];
    final done = _progress!.isDone(card.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('sequence-item-start'),
              leading: const Icon(Icons.play_arrow_rounded),
              title: Text('Ab Aufgabe ${i + 1} neu starten'),
              subtitle: const Text('Alles davor gilt als erledigt'),
              onTap: () => Navigator.of(ctx).pop('start'),
            ),
            ListTile(
              key: const ValueKey('sequence-item-toggle'),
              leading: Icon(done ? Icons.undo : Icons.done_all),
              title: Text(done ? 'Wieder öffnen' : 'Kann ich schon'),
              subtitle: Text(done ? 'Kommt in der nächsten Runde wieder' : 'Wird übersprungen'),
              onTap: () => Navigator.of(ctx).pop('toggle'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'start') {
      _update(StudySequence.restartAt(_ordered, _progress!, i));
      _startRound();
    } else {
      _update(StudySequence.setUnderstood(_progress!, card.id, !done));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final queue = _queue;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(widget.source.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (queue != null)
            TextButton.icon(
              key: const ValueKey('sequence-overview'),
              onPressed: () => setState(() => _queue = null),
              icon: const Icon(Icons.list_rounded, size: 18),
              label: const Text('Übersicht'),
            ),
        ],
      ),
      body: SafeArea(
        child: _progress == null
            ? const Center(child: CircularProgressIndicator())
            : queue == null
            ? _overview(c)
            : _index >= queue.length
            ? _roundDone(c)
            : _question(c, queue[_index]),
      ),
    );
  }

  Widget _overview(AppColors c) {
    final p = _progress!;
    if (_ordered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Hier gibt es noch keine Aufgaben.',
            style: TextStyle(color: c.inkMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final done = _ordered.where((x) => p.isDone(x.id)).length;
    final failed = _ordered.where((x) => p.status[x.id] == StudySequenceStatus.failed).length;
    final next = StudySequence.nextPosition(_ordered, p);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '$done von ${_ordered.length} erledigt${failed > 0 ? ' · $failed noch nicht geschafft' : ''}',
          key: const ValueKey('sequence-summary'),
          style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: done / _ordered.length,
            minHeight: 6,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation(c.good),
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<StudySequenceOrder>(
          key: const ValueKey('sequence-order'),
          segments: [
            for (final o in StudySequenceOrder.values)
              ButtonSegment(value: o, label: Text(o.label, key: ValueKey('sequence-order-${o.name}'))),
          ],
          selected: {p.order},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _setOrder(s.first),
        ),
        const SizedBox(height: 14),
        if (next != null)
          FilledButton.icon(
            key: const ValueKey('sequence-continue'),
            onPressed: _startRound,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(done == 0 && p.nextId == null ? 'Bei Aufgabe 1 beginnen' : 'Weiter bei Aufgabe $next'),
          )
        else
          Text(
            'Alles erledigt – stark! Mit „Neu starten“ geht es wieder von vorne los.',
            key: const ValueKey('sequence-all-done'),
            style: TextStyle(color: c.good, fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('sequence-restart'),
          onPressed: _restartDialog,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Neu starten …'),
        ),
        const SizedBox(height: 6),
        Text(
          'Tippe eine Aufgabe an, um dort neu zu starten oder sie als „kann ich schon“ zu markieren.',
          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
        ),
        const SizedBox(height: 12),
        for (final (i, card) in _ordered.indexed) _item(c, i, card, isNext: next == i + 1),
      ],
    );
  }

  Widget _item(AppColors c, int i, Flashcard card, {required bool isNext}) {
    final s = _progress!.status[card.id];
    final (icon, color, label) = switch (s) {
      StudySequenceStatus.solved => (Icons.check_circle, c.good, 'gelöst'),
      StudySequenceStatus.skipped => (Icons.done_all, c.accent, 'kann ich schon'),
      StudySequenceStatus.failed => (Icons.cancel_outlined, c.danger, 'noch nicht geschafft'),
      null => (Icons.radio_button_unchecked, c.inkMuted, 'offen'),
    };
    final text = card.front.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: isNext
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: c.accent, width: 2),
            )
          : null,
      child: ListTile(
        key: ValueKey('sequence-item-$i'),
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: color.withAlpha(40),
          child: Text(
            '${i + 1}',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(text.isEmpty ? card.type.label : text, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            if (_progress!.order == StudySequenceOrder.difficulty) StageGate.levelOf(card).label,
            label,
            if (isNext) 'als Nächstes',
          ].join(' · '),
          style: TextStyle(color: color, fontSize: 12),
        ),
        trailing: Icon(icon, color: color, size: 20),
        onTap: () => _itemSheet(i),
      ),
    );
  }

  Widget _question(AppColors c, Flashcard card) {
    final queue = _queue!;
    final position = _ordered.indexWhere((x) => x.id == card.id) + 1;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: position / _ordered.length,
              minHeight: 6,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Aufgabe $position von ${_ordered.length} · noch ${queue.length - _index} in dieser Runde',
                  key: const ValueKey('sequence-position'),
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('sequence-understood'),
                onPressed: () => _understood(card),
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Kann ich schon'),
              ),
            ],
          ),
        ),
        Expanded(
          child: QuestionAnswerView(
            key: ValueKey('sequence-q-${card.id}'),
            card: card,
            isNew: card.reps == 0,
            canGiveUp: true,
            onImageEdited: (bytes) => saveEditedImage(card, bytes),
            onComplete: ({selfGrade, isCorrect}) => _answered(card, selfGrade: selfGrade, isCorrect: isCorrect),
          ),
        ),
      ],
    );
  }

  Widget _roundDone(AppColors c) {
    final p = _progress!;
    final open = StudySequence.open(_ordered, p);
    final next = StudySequence.nextPosition(_ordered, p);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(open.isEmpty ? Icons.emoji_events_outlined : Icons.flag_outlined, size: 56, color: c.good),
            const SizedBox(height: 16),
            Text(
              open.isEmpty
                  ? 'Alles erledigt! Diese Runde: $_roundSolved gelöst'
                        '${_roundSkipped > 0 ? ', $_roundSkipped übersprungen' : ''}.'
                  : 'Runde fertig: $_roundSolved gelöst, $_roundFailed noch nicht geschafft'
                        '${_roundSkipped > 0 ? ', $_roundSkipped übersprungen' : ''}.',
              key: const ValueKey('sequence-round-summary'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (open.isNotEmpty && next != null)
              FilledButton.icon(
                key: const ValueKey('sequence-next-round'),
                onPressed: _startRound,
                icon: const Icon(Icons.replay),
                label: Text('Nächste Runde: ${open.length} offen, ab Aufgabe $next'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('sequence-to-overview'),
              onPressed: () => setState(() => _queue = null),
              child: const Text('Zur Übersicht'),
            ),
          ],
        ),
      ),
    );
  }
}
