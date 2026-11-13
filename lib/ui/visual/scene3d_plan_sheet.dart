import 'package:flutter/material.dart';

import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';

/// Was der Nutzer nach der Vorab-Klärung gewählt hat.
class Scene3dPlanChoice {
  const Scene3dPlanChoice._(this.kind, this.plan);

  /// Den Bauplan in 3D umsetzen.
  const Scene3dPlanChoice.build(String plan) : this._('plan', plan);

  /// Ohne Bauplan bauen – genau der ursprüngliche Wunsch.
  const Scene3dPlanChoice.skip() : this._('skip', '');

  /// Dem Vorschlag folgen und flach (2D) zeichnen.
  const Scene3dPlanChoice.flat(String plan) : this._('2d', plan);

  final String kind;
  final String plan;

  bool get isPlan => kind == 'plan';
  bool get isFlat => kind == '2d';
}

/// Vorab-Klärung vor einem 3D-Modell: Ein (günstiges) Modell macht aus dem
/// Wunsch einen konkreten Bauplan und zeigt, wie es ihn verstanden hat. Der
/// Nutzer bestätigt, ergänzt oder überspringt das. Hält die App eine flache
/// Zeichnung für klarer, schlägt sie das nur vor – gebaut wird 3D, solange der
/// Nutzer nichts anderes wählt. null = abgebrochen.
Future<Scene3dPlanChoice?> showScene3dPlanSheet(
  BuildContext context, {
  required AiService? ai,
  required String wish,
  String contextText = '',
  bool offer2d = true,
}) => showModalBottomSheet<Scene3dPlanChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => Scene3dPlanSheet(ai: ai, wish: wish, contextText: contextText, offer2d: offer2d),
);

class Scene3dPlanSheet extends StatefulWidget {
  const Scene3dPlanSheet({super.key, required this.ai, required this.wish, this.contextText = '', this.offer2d = true});

  final AiService? ai;
  final String wish;
  final String contextText;

  /// „Als 2D zeichnen“ anbieten, wenn die Klärung das vorschlägt.
  final bool offer2d;

  @override
  State<Scene3dPlanSheet> createState() => _Scene3dPlanSheetState();
}

class _Scene3dPlanSheetState extends State<Scene3dPlanSheet> with SafeSetState<Scene3dPlanSheet> {
  final _answer = TextEditingController();
  Map<String, dynamic>? _plan;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _clarify();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _clarify({String answer = ''}) async {
    final ai = widget.ai;
    if (ai == null) {
      setState(() {
        _busy = false;
        _error = 'Dafür braucht die App deinen OpenRouter-Key (Einstellungen).';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await ai.clarifyScene3d(
        wish: widget.wish,
        context: widget.contextText,
        previousPlan: answer.isEmpty ? '' : '${_plan?['plan'] ?? ''}',
        answer: answer,
      );
      setState(() {
        _plan = plan;
        _answer.clear();
      });
    } on AiServiceException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Die Vorab-Klärung hat nicht geklappt: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plan = _plan;
    final points = plan == null ? const <String>[] : [for (final p in plan['points'] as List) '$p'];
    final question = '${plan?['question'] ?? ''}';
    final flat = widget.offer2d && plan?['better2d'] == true;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          key: const ValueKey('scene-plan'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('So würde ich es bauen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Stimmt das so? Dann zeichnet das 3D-Modell genau nach diesem Plan.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
              const SizedBox(height: 12),
              if (_busy && plan == null)
                Row(
                  key: const ValueKey('scene-plan-busy'),
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Ich überlege, was du meinst …', style: TextStyle(color: c.inkMuted)),
                    ),
                  ],
                ),
              if (_error != null) ...[
                Text(
                  _error!,
                  key: const ValueKey('scene-plan-error'),
                  style: TextStyle(fontSize: 13, color: c.danger),
                ),
                const SizedBox(height: 4),
                Text(
                  'Du kannst trotzdem bauen lassen – dann ohne Bauplan, wie bisher.',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
                const SizedBox(height: 8),
              ],
              if (plan != null) ...[
                if ('${plan['summary']}'.isNotEmpty) ...[
                  MathText(
                    '${plan['summary']}',
                    key: const ValueKey('scene-plan-summary'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final (i, p) in points.indexed)
                  Padding(
                    key: ValueKey('scene-plan-point-$i'),
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '•  ',
                          style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
                        ),
                        Expanded(child: MathText(p, style: const TextStyle(fontSize: 13.5, height: 1.4))),
                      ],
                    ),
                  ),
                if (flat) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('scene-plan-2d-hint'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vorschlag: als flache Zeichnung (2D)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accentOnSoft),
                        ),
                        if ('${plan['reason2d']}'.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${plan['reason2d']}',
                            style: TextStyle(fontSize: 12.5, color: c.accentOnSoft, height: 1.35),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          'Du entscheidest – ohne deine Wahl bleibt es bei 3D.',
                          style: TextStyle(fontSize: 12, color: c.accentOnSoft),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const ValueKey('scene-plan-2d'),
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).pop(Scene3dPlanChoice.flat('${plan['plan']}')),
                            child: const Text('Als 2D zeichnen'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                if (question.isNotEmpty) ...[
                  MathText(
                    question,
                    key: const ValueKey('scene-plan-question'),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.accentOnSoft, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('scene-plan-answer'),
                        controller: _answer,
                        enabled: !_busy,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _refine(),
                        decoration: InputDecoration(
                          hintText: question.isEmpty ? 'Etwas ändern oder ergänzen …' : 'Antwort oder Änderung …',
                          isDense: true,
                          filled: true,
                          fillColor: c.surfaceAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      key: const ValueKey('scene-plan-refine'),
                      tooltip: 'Bauplan anpassen',
                      onPressed: _busy ? null : _refine,
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      key: const ValueKey('scene-plan-skip'),
                      onPressed: () => Navigator.of(context).pop(const Scene3dPlanChoice.skip()),
                      child: const Text('Ohne Bauplan bauen'),
                    ),
                    if (plan != null)
                      FilledButton.icon(
                        key: const ValueKey('scene-plan-ok'),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(Scene3dPlanChoice.build('${plan['plan']}')),
                        icon: const Icon(Icons.view_in_ar_outlined, size: 18),
                        label: const Text('So in 3D bauen'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _refine() {
    final text = _answer.text.trim();
    if (text.isEmpty || _busy) return;
    _clarify(answer: text);
  }
}
