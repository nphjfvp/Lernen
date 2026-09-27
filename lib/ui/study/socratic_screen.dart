import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../services/ai_service.dart';
import '../../services/source_locator.dart';
import '../../theme/app_colors.dart';
import '../modules/material_opener.dart';
import '../widgets/math_text.dart';
import '../widgets/safe_set_state.dart';
import 'study_aids.dart';

/// Sokrates-Modus für eine Karte, die öfter schiefgeht: die KI verrät die
/// Lösung nicht, sondern führt mit Gegenfragen Schritt für Schritt hin, bis
/// man sie selbst gefunden und begründet hat (siehe AiService.socraticTurn).
/// Bewusst schlank: ein Dialog pro Karte, nichts wird gespeichert.
class SocraticScreen extends StatefulWidget {
  const SocraticScreen({super.key, required this.card, required this.ai, this.wrongAnswer, this.image});

  final Flashcard card;
  final AiService ai;
  final String? wrongAnswer;
  final Uint8List? image;

  @override
  State<SocraticScreen> createState() => _SocraticScreenState();
}

class _SocraticScreenState extends State<SocraticScreen> with SafeSetState<SocraticScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<({bool isUser, String content})> _messages = [];
  CardSource? _source;
  bool _sending = false;
  bool _solved = false;
  bool _answerShown = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Die Stelle in den Unterlagen gibt der KI den Stoff, wie er in der
    // Vorlesung steht – fehlt sie, geht es auch ohne.
    try {
      _source = await findCardSource(context, widget.card);
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    await _nextTurn();
  }

  Future<void> _nextTurn() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final turn = await widget.ai.socraticTurn(
        question: widget.card.front,
        correctAnswer: answerTextOf(widget.card),
        wrongAnswer: widget.wrongAnswer,
        sourceText: _source?.pageText,
        history: List.of(_messages),
        image: widget.image,
      );
      if (!mounted) return;
      setState(() {
        _messages.add((isUser: false, content: turn.reply));
        _solved = turn.solved;
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) setState(() => _error = e is AiServiceException ? e.message : 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _solved) return;
    _controller.clear();
    setState(() => _messages.add((isUser: true, content: text)));
    _scrollToEnd();
    await _nextTurn();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final source = _source;
    final done = _solved || _answerShown;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Sokratisch erarbeiten'),
        actions: [
          if (source != null)
            IconButton(
              tooltip: 'Im Skript ansehen',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => openMaterialAt(context, source.material, page: source.page),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Die Frage', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
                        const SizedBox(height: 4),
                        MathText(widget.card.front, style: const TextStyle(fontSize: 14.5, height: 1.4)),
                        if (widget.image case final image?) ...[
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(image, fit: BoxFit.contain),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Die KI verrät die Lösung nicht – sie stellt dir Fragen, bis du selbst draufkommst.',
                          style: TextStyle(fontSize: 12, color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final m in _messages) _Bubble(isUser: m.isUser, text: m.content),
                  if (_solved)
                    _Banner(
                      key: const ValueKey('socratic-solved'),
                      icon: Icons.emoji_events_outlined,
                      text: 'Geschafft – du hast es dir selbst erarbeitet.',
                      color: c.good,
                      background: c.goodSoft,
                    ),
                  if (_answerShown)
                    _Banner(
                      key: const ValueKey('socratic-answer'),
                      icon: Icons.check_circle_outline,
                      text: 'Lösung: ${answerTextOf(widget.card)}',
                      color: c.accentOnSoft,
                      background: c.accentSoft,
                    ),
                ],
              ),
            ),
            if (_sending)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    Text(_error!, style: TextStyle(color: c.danger), textAlign: TextAlign.center),
                    TextButton(onPressed: _sending ? null : _nextTurn, child: const Text('Erneut versuchen')),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: done
                  ? SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Fertig'),
                      ),
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('socratic-input'),
                                controller: _controller,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                                decoration: InputDecoration(
                                  hintText: 'Deine Antwort oder "weiß nicht" …',
                                  filled: true,
                                  fillColor: c.surface,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accent)),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              key: const ValueKey('socratic-send'),
                              onPressed: _sending ? null : _send,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() => _answerShown = true),
                            child: const Text('Lösung zeigen'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.isUser, required this.text});
  final bool isUser;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? c.accentSoft : c.surface,
          border: isUser ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectionArea(child: MathText(text, style: TextStyle(fontSize: 14, height: 1.4, color: c.ink))),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.text, required this.color, required this.background});
  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4, bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: MathText(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: color))),
          ],
        ),
      );
}
