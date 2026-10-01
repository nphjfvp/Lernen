
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/page_note.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../theme/app_colors.dart';
import 'math_text.dart';

/// Was zum Fragen an die KI von einer Seite gebraucht wird: ein Bild der Seite,
/// ihre Nummer und die Seitenzahl des Dokuments.
typedef PageCapture = ({Uint8List image, int page, int total});

/// Ein Frage-Antwort-Paar im Seiten-Chat – mit der Seite, auf der es gestellt
/// wurde (das Panel bleibt beim Blättern offen).
class PageQaTurn {
  PageQaTurn({required this.question, required this.answer, required this.page});

  final String question;
  final String answer;
  final int page;

  /// Gesetzt, sobald die Antwort als Seitennotiz gespeichert wurde.
  String? noteId;
}

/// Zustand des Seiten-Chats – getrennt vom Panel, damit das Gespräch erhalten
/// bleibt, wenn das Panel geschlossen und wieder geöffnet wird oder zwischen
/// angedocktem Panel und Bottom-Sheet wechselt.
class PageQaController extends ChangeNotifier {
  final List<PageQaTurn> turns = [];
  bool _asking = false;
  String? _error;

  bool get asking => _asking;
  String? get error => _error;

  void start() {
    _asking = true;
    _error = null;
    notifyListeners();
  }

  void finish({PageQaTurn? turn, String? error}) {
    if (turn != null) turns.add(turn);
    _asking = false;
    _error = error;
    notifyListeners();
  }

  void touch() => notifyListeners();
}

/// Frage-Chat zu einer Seite (siehe AiService.answerPageQuestion) mit zwei
/// Reitern: "Fragen" und "Notizen" (gespeicherte Antworten je Seite). Läuft
/// als angedocktes Seitenfenster neben dem PDF (breite Bildschirme – bei 50 %
/// Zoom bleibt die Seite daneben komplett sichtbar und das Panel kann
/// dauerhaft offen bleiben) oder im Bottom-Sheet. Alle Texte lassen sich
/// markieren und kopieren.
///
/// Jede Frage sieht die Seite, die im Moment des Fragens angezeigt wird
/// ([capturePage]) plus den Volltext des Dokuments.
class PageQaPanel extends StatefulWidget {
  const PageQaPanel({
    super.key,
    required this.controller,
    required this.documentText,
    required this.capturePage,
    required this.currentPage,
    required this.totalPages,
    this.notes = const [],
    this.onSaveNote,
    this.onDeleteNote,
    this.onJumpToPage,
    this.onClose,
    this.onSwapSide,
    this.swapTooltip = 'Auf die andere Seite schieben',
  });

  final PageQaController controller;
  final String documentText;
  final Future<PageCapture?> Function() capturePage;

  /// Die gerade angezeigte Seite und die Seitenzahl – für die Kopfzeile.
  final int currentPage;
  final int totalPages;

  /// Gespeicherte Seitennotizen des Materials. Ohne [onSaveNote] (z.B. bei
  /// einer noch nicht gespeicherten Datei) gibt es kein Speichern.
  final List<PageNote> notes;
  final Future<void> Function(PageNote note)? onSaveNote;
  final Future<void> Function(PageNote note)? onDeleteNote;
  final ValueChanged<int>? onJumpToPage;
  final VoidCallback? onClose;
  final VoidCallback? onSwapSide;
  final String swapTooltip;

  /// Nur für Tests: KI-Zugang (API-Key, Modell) statt der Einstellungen.
  @visibleForTesting
  static AiService Function(String apiKey, String model)? aiFactory;

  @override
  State<PageQaPanel> createState() => _PageQaPanelState();
}

class _PageQaPanelState extends State<PageQaPanel> {
  final _input = TextEditingController();
  int _tab = 0;

  PageQaController get _qa => widget.controller;

  @override
  void initState() {
    super.initState();
    _qa.addListener(_changed);
  }

  @override
  void didUpdateWidget(PageQaPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _qa.removeListener(_changed);
    _input.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _ask() async {
    final question = _input.text.trim();
    if (question.isEmpty || _qa.asking) return;
    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      _qa.finish(error: 'Kein OpenRouter-API-Key hinterlegt. Bitte in den Einstellungen eintragen.');
      return;
    }
    _qa.start();
    try {
      final page = await widget.capturePage();
      if (page == null) {
        _qa.finish(error: 'Die Seite konnte nicht erfasst werden.');
        return;
      }
      final ai = PageQaPanel.aiFactory?.call(settings.openRouterApiKey!, settings.visionModelId) ??
          AiService(apiKey: settings.openRouterApiKey!, model: settings.visionModelId);
      // Frühere Fragen stammen evtl. von einer anderen Seite – dann steht die
      // Seite dabei, damit sich die KI nicht darauf bezieht.
      String label(PageQaTurn t, String text) => t.page == page.page ? text : '[Seite ${t.page}] $text';
      final history = [
        for (final t in _qa.turns) ...[
          (isUser: true, content: label(t, t.question)),
          (isUser: false, content: t.answer),
        ],
      ];
      final answer = await ai.answerPageQuestion(
        question: question,
        pageImageBytes: page.image,
        pageNumber: page.page,
        totalPages: page.total,
        documentText: widget.documentText,
        history: history,
      );
      if (mounted) _input.clear();
      _qa.finish(turn: PageQaTurn(question: question, answer: answer, page: page.page));
    } on AiServiceException catch (e) {
      _qa.finish(error: e.message);
    } catch (e) {
      _qa.finish(error: 'Unerwarteter Fehler: $e');
    }
  }

  Future<void> _saveNote(PageQaTurn turn) async {
    final save = widget.onSaveNote;
    if (save == null || turn.noteId != null) return;
    final note = PageNote(
      id: const Uuid().v4(),
      page: turn.page,
      question: turn.question,
      text: turn.answer,
      createdAt: DateTime.now(),
    );
    turn.noteId = note.id;
    _qa.touch();
    try {
      await save(note);
    } catch (_) {
      turn.noteId = null;
      _qa.touch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.bg,
      child: Column(
        children: [
          _header(c),
          Divider(height: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  const ButtonSegment(value: 0, label: Text('Fragen')),
                  ButtonSegment(value: 1, label: Text('Notizen${widget.notes.isEmpty ? '' : ' (${widget.notes.length})'}')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
          ),
          Expanded(child: _tab == 0 ? _questions(c) : _notes(c)),
          if (_tab == 0) _inputRow(c),
        ],
      ),
    );
  }

  Widget _header(AppColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
        child: Row(
          children: [
            Icon(Icons.forum_outlined, size: 18, color: c.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Frage zur Seite', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(
                    'Seite ${widget.currentPage} von ${widget.totalPages} · sieht die angezeigte Seite + den Dokumenttext',
                    key: const ValueKey('qa-page-label'),
                    style: TextStyle(fontSize: 11, color: c.inkMuted),
                  ),
                ],
              ),
            ),
            if (widget.onSwapSide != null)
              IconButton(
                key: const ValueKey('qa-swap'),
                tooltip: widget.swapTooltip,
                icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                onPressed: widget.onSwapSide,
              ),
            if (widget.onClose != null)
              IconButton(
                key: const ValueKey('qa-close'),
                tooltip: 'Schließen',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: widget.onClose,
              ),
          ],
        ),
      );

  Widget _questions(AppColors c) {
    final turns = _qa.turns;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (turns.isEmpty)
            Text('Stell eine Frage zur angezeigten Seite. Blätterst du weiter, bezieht sich die nächste Frage auf die neue Seite.',
                style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4)),
          for (final t in turns)
            Padding(
              key: ValueKey('qa-turn-${turns.indexOf(t)}'),
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Seite ${t.page}', style: TextStyle(fontSize: 11, color: c.inkMuted)),
                  const SizedBox(height: 2),
                  MathText(t.question, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35)),
                  const SizedBox(height: 4),
                  MathText(t.answer, style: TextStyle(fontSize: 13.5, color: c.ink, height: 1.45)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (widget.onSaveNote != null)
                        t.noteId != null
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline, size: 16, color: c.good),
                                    const SizedBox(width: 4),
                                    Text('Als Notiz auf Seite ${t.page} gespeichert',
                                        style: TextStyle(fontSize: 12, color: c.good)),
                                  ],
                                ),
                              )
                            : TextButton.icon(
                                key: ValueKey('qa-save-${turns.indexOf(t)}'),
                                onPressed: () => _saveNote(t),
                                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                                label: Text('Auf Seite ${t.page} speichern'),
                              ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Antwort kopieren',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: t.answer)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_qa.asking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_qa.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_qa.error!, style: TextStyle(color: c.danger, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _notes(AppColors c) {
    final notes = [...widget.notes]..sort((a, b) {
        final byPage = a.page.compareTo(b.page);
        return byPage != 0 ? byPage : a.createdAt.compareTo(b.createdAt);
      });
    if (notes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Noch keine Notizen. Unter jeder KI-Antwort kannst du sie mit "Auf Seite N speichern" an ihre Seite heften.',
          style: TextStyle(fontSize: 13, color: c.inkMuted, height: 1.4),
        ),
      );
    }
    final here = notes.where((n) => n.page == widget.currentPage).toList();
    final elsewhere = notes.where((n) => n.page != widget.currentPage).toList();
    Widget card(PageNote n) => Container(
          key: ValueKey('note-${n.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.description_outlined, size: 15),
                    label: Text('Seite ${n.page}', style: const TextStyle(fontSize: 12)),
                    onPressed: widget.onJumpToPage == null ? null : () => widget.onJumpToPage!(n.page),
                  ),
                  const Spacer(),
                  if (widget.onDeleteNote != null)
                    IconButton(
                      key: ValueKey('note-delete-${n.id}'),
                      tooltip: 'Notiz löschen',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.delete_outline, size: 18, color: c.inkMuted),
                      onPressed: () => widget.onDeleteNote!(n),
                    ),
                ],
              ),
              if (n.question.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: MathText(n.question, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
                ),
              MathText(n.text, style: TextStyle(fontSize: 13, color: c.ink, height: 1.45)),
            ],
          ),
        );
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (here.isNotEmpty) ...[
            Text('DIESE SEITE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
            const SizedBox(height: 6),
            for (final n in here) card(n),
          ],
          if (elsewhere.isNotEmpty) ...[
            if (here.isNotEmpty) const SizedBox(height: 6),
            Text(here.isEmpty ? 'ALLE NOTIZEN' : 'ANDERE SEITEN',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
            const SizedBox(height: 6),
            for (final n in elsewhere) card(n),
          ],
        ],
      ),
    );
  }

  Widget _inputRow(AppColors c) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('qa-input'),
                  controller: _input,
                  enabled: !_qa.asking,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Frage zu dieser Seite …',
                    filled: true,
                    fillColor: c.surfaceAlt,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _ask(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('qa-send'),
                tooltip: 'Fragen',
                onPressed: _qa.asking ? null : _ask,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      );
}
