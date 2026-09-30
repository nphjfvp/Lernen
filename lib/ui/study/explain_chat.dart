import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Gespräch mit der KI über die gerade beantwortete Frage: Rückfragen stellen,
/// in eigenen Worten erklären und prüfen lassen ("stimmt das?"), oder die KI
/// bitten, auf einen Punkt genauer einzugehen (siehe AiService.followUpAnswer).
/// Sitzt unter der KI-Erklärung im Quiz; ohne Erklärung geht es genauso – die KI
/// kennt Frage, Lösung und die Antwort des Lernenden.
class ExplainChat extends StatefulWidget {
  const ExplainChat({
    super.key,
    required this.question,
    required this.correctAnswer,
    this.userAnswer,
    this.wasCorrect,
    this.explanation,
    this.sourceText,
  });

  final String question;
  final String correctAnswer;
  final String? userAnswer;
  final bool? wasCorrect;

  /// Die schon gezeigte KI-Erklärung (kann später dazukommen).
  final String? explanation;
  final String? sourceText;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  @override
  State<ExplainChat> createState() => _ExplainChatState();
}

class _ExplainChatState extends State<ExplainChat> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final List<({bool isUser, String content})> _messages = [];
  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Vorbereiteter Satzanfang: das Feld füllen, der Cursor steht am Ende.
  void _prefill(String stem) {
    _input.value = TextEditingValue(text: stem, selection: TextSelection.collapsed(offset: stem.length));
    _focus.requestFocus();
  }

  Future<void> _send([String? preset]) async {
    final message = (preset ?? _input.text).trim();
    if (message.isEmpty || _busy) return;
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }
    final history = List.of(_messages);
    setState(() {
      _messages.add((isUser: true, content: message));
      _input.clear();
      _busy = true;
      _error = null;
    });
    try {
      final ai = ExplainChat.aiFactory?.call(settings.openRouterApiKey!, settings.questionModelId) ??
          AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final answer = await ai.followUpAnswer(
        question: widget.question,
        correctAnswer: widget.correctAnswer,
        userAnswer: widget.userAnswer,
        wasCorrect: widget.wasCorrect,
        explanation: widget.explanation,
        sourceText: widget.sourceText,
        history: history,
        message: message,
      );
      if (mounted) setState(() => _messages.add((isUser: false, content: answer)));
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is AiServiceException ? e.message : 'Die KI hat nicht geantwortet: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!_open) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('explain-chat-open'),
            onPressed: () => setState(() => _open = true),
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Mit der KI besprechen'),
          ),
        ),
      );
    }
    return Container(
      key: const ValueKey('explain-chat'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 16, color: c.inkMuted),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Mit der KI besprechen', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Zuklappen',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.expand_less_rounded, size: 20),
                onPressed: () => setState(() => _open = false),
              ),
            ],
          ),
          if (_messages.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Stell eine Rückfrage, erklär es in deinen Worten und lass prüfen, ob das stimmt – oder bitte '
                'um mehr Details zu einem Punkt.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.4),
              ),
            ),
          SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in _messages)
                  Align(
                    alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      constraints: const BoxConstraints(maxWidth: 560),
                      decoration: BoxDecoration(
                        color: m.isUser ? c.accentSoft : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: m.isUser
                          ? Text(m.content, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink))
                          : MathText(m.content, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.ink)),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_error!, style: TextStyle(fontSize: 12.5, color: c.danger)),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ActionChip(
                key: const ValueKey('chip-own-words'),
                visualDensity: VisualDensity.compact,
                label: const Text('In meinen Worten erklären'),
                onPressed: _busy ? null : () => _prefill('Ich erkläre es mal in meinen Worten: '),
              ),
              ActionChip(
                key: const ValueKey('chip-deeper'),
                visualDensity: VisualDensity.compact,
                label: const Text('Genauer eingehen auf …'),
                onPressed: _busy ? null : () => _prefill('Geh bitte genauer auf folgenden Punkt ein: '),
              ),
              ActionChip(
                key: const ValueKey('chip-not-understood'),
                visualDensity: VisualDensity.compact,
                label: const Text('Das verstehe ich nicht'),
                onPressed: _busy ? null : () => _prefill('Das habe ich nicht verstanden: '),
              ),
              ActionChip(
                key: const ValueKey('chip-example'),
                visualDensity: VisualDensity.compact,
                label: const Text('Anderes Beispiel'),
                onPressed: _busy ? null : () => _send('Gib mir bitte ein anderes Beispiel dazu.'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
                  },
                  child: TextField(
                    key: const ValueKey('explain-chat-input'),
                    controller: _input,
                    focusNode: _focus,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: 'Deine Nachricht … (Strg+Enter sendet)',
                      filled: true,
                      fillColor: c.surfaceAlt,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('explain-chat-send'),
                tooltip: 'Senden',
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
