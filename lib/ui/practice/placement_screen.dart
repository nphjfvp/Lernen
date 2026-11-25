import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../services/answer_signals.dart';
import '../../services/fsrs_service.dart';
import '../../services/placement_service.dart';
import '../../services/stage_gate_service.dart';
import '../../theme/app_colors.dart';
import '../daily/card_review_mixin.dart';
import '../daily/question_answer_view.dart';

/// Einstufung eines Fachs (siehe PlacementService): je Stufen-Gruppe zuerst
/// die schwerste Frage. Sicher und ohne Hilfe gewusst → die leichteren
/// Stufen ruhen; sonst eine Stufe tiefer. Falsche Antworten werden hier
/// nicht verbucht – das ist Messen, nicht Üben.
class PlacementScreen extends StatefulWidget {
  const PlacementScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  /// Höchstens so viele Gruppen je Durchgang.
  static const maxGroups = 15;

  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends State<PlacementScreen> with CardReviewMixin {
  List<PlacementGroup>? _groups;
  int _group = 0;
  int _probe = 0;
  int _placedGroups = 0;
  int _skippedCards = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final cards = await context.read<FlashcardRepository>().loadModuleCards(widget.moduleId);
    if (!mounted) return;
    setState(() => _groups = PlacementService.candidates(cards).take(PlacementScreen.maxGroups).toList());
  }

  void _nextGroup() => setState(() {
        _group += 1;
        _probe = 0;
      });

  Future<void> _answered(Flashcard card, {Grade? selfGrade, bool? isCorrect, AnswerSignals? signals}) async {
    if (_saving) return;
    final groups = _groups!;
    final group = groups[_group];
    final grade = AnswerSignals.gradeFor(selfGrade: selfGrade, isCorrect: isCorrect, signals: signals ?? AnswerSignals.none);
    final solid = grade == Grade.good || grade == Grade.easy;
    if (!solid) {
      if (_probe + 1 < group.probes.length) {
        setState(() => _probe += 1);
      } else {
        _nextGroup();
      }
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<FlashcardRepository>();
    await recordReview(card, selfGrade: selfGrade, isCorrect: isCorrect, signals: signals);
    final changed = PlacementService.placeOutBelow(group, StageGate.levelOf(card));
    if (changed.isNotEmpty) await repo.updateAll(changed);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (changed.isNotEmpty) _placedGroups += 1;
      _skippedCards += changed.length;
    });
    _nextGroup();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = _groups;
    Widget body;
    if (groups == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (groups.isEmpty) {
      body = _Message(
        icon: Icons.check_circle_outline,
        text: 'Hier gibt es nichts einzustufen: Es gibt keine Fragen-Ordner mit mehreren Stufen, deren '
            'schwerere Stufen noch neu sind. (Ordner entstehen beim Nachbereiten oder über „Per KI in Ordner '
            'sortieren“ in der Kartenliste.)',
      );
    } else if (_group >= groups.length) {
      body = _Message(
        icon: Icons.flag_circle_outlined,
        text: _placedGroups == 0
            ? 'Fertig. Diesmal ging es überall bei der leichtesten Stufe los – das Daily Quiz beginnt dort.'
            : 'Fertig. In $_placedGroups Ordnern startest du direkt weiter oben – $_skippedCards leichtere '
                'Fragen ruhen. Geht die schwerere Stufe später mehrmals schief, kommen sie von selbst zurück.',
      );
    } else {
      final group = groups[_group];
      final card = group.probes[_probe];
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: (_group + 1) / groups.length, minHeight: 5),
                const SizedBox(height: 8),
                Text(
                  'Ordner ${_group + 1} von ${groups.length} · Stufe ${StageGate.levelOf(card).label}',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
                if (_group == 0 && _probe == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Erst die schwerste Stufe: Weißt du sie sicher und ohne Tipp, überspringst du die leichteren. '
                      'Falsche Antworten zählen hier nicht.',
                      style: TextStyle(fontSize: 12.5, color: c.ink),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: QuestionAnswerView(
              key: ValueKey('placement-${card.id}-$_group-$_probe'),
              card: card,
              isNew: card.reps == 0,
              canGiveUp: true,
              onSkip: _nextGroup,
              onComplete: ({selfGrade, isCorrect, signals}) =>
                  _answered(card, selfGrade: selfGrade, isCorrect: isCorrect, signals: signals),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Einstufen · ${widget.moduleName}')),
      body: SafeArea(child: body),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: c.accent),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4)),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Zurück')),
          ],
        ),
      ),
    );
  }
}
