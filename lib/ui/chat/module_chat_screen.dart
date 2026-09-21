import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/chat_message.dart';
import '../../models/material_item.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/model_catalog_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/chat_context_builder.dart';
import '../../theme/app_colors.dart';

/// Frage-Chat zu den hochgeladenen Materialien eines Fachs. Reagiert
/// ausschließlich auf explizite Fragen – nichts wird von selbst erklärt.
///
/// Zweistufig statt "alles reinkippen": zuerst sieht die KI nur einen
/// kompakten Index aller Materialien (Thema + Kurzfassung, siehe
/// [MaterialItem.topicIndex]/[ChatContextBuilder.buildIndexContext]) und
/// wählt die für die konkrete Frage relevanten aus; erst von GENAU diesen
/// wird dann der volle Text nachgeladen. So bleibt der Kontext auch bei
/// einem ganzen Semester an hochgeladenen Folien fokussiert statt lossy
/// zusammengekürzt.
class ModuleChatScreen extends StatefulWidget {
  const ModuleChatScreen({super.key, required this.moduleId, required this.moduleName});

  final String moduleId;
  final String moduleName;

  @override
  State<ModuleChatScreen> createState() => _ModuleChatScreenState();
}

class _ModuleChatScreenState extends State<ModuleChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _useContext = true;
  String _statusLabel = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    await context.read<ChatRepository>().loadForModule(widget.moduleId);
    if (!mounted) return;
    await context.read<MaterialRepository>().loadForModule(widget.moduleId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Holt fehlende Kurz-Indizes nach (einmalig pro Material, danach
  /// dauerhaft gecacht in der DB) – Voraussetzung für die
  /// Relevanz-Auswahl im zweiten Schritt.
  Future<void> _ensureIndexed(AiService ai, List<MaterialItem> materials) async {
    final materialRepo = context.read<MaterialRepository>();
    final missing = materials.where((m) => (m.topicIndex ?? '').trim().isEmpty).toList();
    for (var i = 0; i < missing.length; i++) {
      if (!mounted) return;
      setState(() => _statusLabel = 'Materialien werden analysiert (${i + 1}/${missing.length}) …');
      try {
        final gist = await ai.summarizeForIndex(missing[i].extractedText);
        await materialRepo.setTopicIndex(missing[i].id, widget.moduleId, gist);
      } catch (_) {
        // Bleibt unindiziert – buildIndexContext greift dann auf einen
        // Rohtext-Anriss zurück, statt das Material zu ignorieren.
      }
    }
  }

  Future<void> _send() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _sending) return;

    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() => _error = 'Kein OpenRouter-API-Key hinterlegt. Bitte zuerst in den Einstellungen eintragen.');
      return;
    }

    final chatRepo = context.read<ChatRepository>();
    final materialRepo = context.read<MaterialRepository>();
    final initialMaterials = _useContext ? materialRepo.forModule(widget.moduleId) : const <MaterialItem>[];
    if (_useContext && initialMaterials.isEmpty) {
      setState(() => _error =
          'Noch keine Materialien hochgeladen – lade zuerst Folien/Übungen hoch, oder schalte '
          '"Mit Materialien" aus, um allgemein zu fragen.');
      return;
    }
    final modelInfo = context.read<ModelCatalogRepository>().byId(settings.questionModelId);
    final history = chatRepo.forModule(widget.moduleId);
    final recentHistory = history.length > 12 ? history.sublist(history.length - 12) : history;
    final historyTurns = [
      for (final m in recentHistory) (isUser: m.role == ChatRole.user, content: m.content),
    ];

    _controller.clear();
    setState(() {
      _sending = true;
      _statusLabel = _useContext ? 'Sende Frage …' : 'Antwort wird erstellt …';
      _error = null;
    });

    await chatRepo.save(ChatMessage(
      id: const Uuid().v4(),
      moduleId: widget.moduleId,
      role: ChatRole.user,
      content: question,
      createdAt: DateTime.now(),
    ));
    if (!mounted) return;
    _scrollToBottom();

    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);

      String? materialsContext;
      // Dateinamen der tatsächlich als Kontext genutzten Materialien – null,
      // solange "Mit Materialien" aus ist (nicht anwendbar), sonst mindestens
      // eine (ggf. leere) Liste, sichtbar in _ChatBubble statt einer stillen
      // Blackbox-Entscheidung.
      List<String>? usedFileNames;
      if (_useContext) {
        final charBudget = ChatContextBuilder.charBudgetForContextTokens(modelInfo?.contextLength);

        await _ensureIndexed(ai, initialMaterials);
        if (!mounted) return;
        final indexedMaterials = materialRepo.forModule(widget.moduleId);

        setState(() => _statusLabel = 'Relevante Materialien werden ausgewählt …');
        List<String>? relevantIds;
        try {
          relevantIds = await ai.selectRelevantMaterials(
            question: question,
            indexContext: ChatContextBuilder.buildIndexContext(indexedMaterials),
            history: historyTurns,
          );
        } catch (_) {
          relevantIds = null; // Auswahl fehlgeschlagen -> Sicherheitsnetz: alles einbeziehen.
        }

        if (relevantIds == null) {
          materialsContext = ChatContextBuilder.build(indexedMaterials, charBudget: charBudget);
          usedFileNames = indexedMaterials.map((m) => m.fileName).toList();
        } else if (relevantIds.isNotEmpty) {
          final ids = relevantIds.toSet();
          final matched = indexedMaterials.where((m) => ids.contains(m.id)).toList();
          // Kein erzwungenes "irgendwas nehmen": passt keine der (evtl.
          // halluzinierten) IDs zu einem echten Material, bleibt es bei
          // "kein Material relevant" statt alles reinzukippen.
          materialsContext = matched.isEmpty ? null : ChatContextBuilder.build(matched, charBudget: charBudget);
          usedFileNames = matched.map((m) => m.fileName).toList();
        } else {
          usedFileNames = const [];
        }
        // relevantIds == [] (bewusst "nichts passt"): materialsContext
        // bleibt null, die Frage wird dann ganz normal ohne Materialbezug
        // beantwortet (siehe answerQuestion-Systemprompt).

        setState(() => _statusLabel = 'Antwort wird erstellt …');
      }

      final answer = await ai.answerQuestion(
        question: question,
        materialsContext: materialsContext,
        history: historyTurns,
      );
      await chatRepo.save(ChatMessage(
        id: const Uuid().v4(),
        moduleId: widget.moduleId,
        role: ChatRole.assistant,
        content: answer,
        createdAt: DateTime.now(),
        sourceFileNames: usedFileNames,
      ));
      if (!mounted) return;
      _scrollToBottom();
    } on AiServiceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Unerwarteter Fehler: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final messages = context.watch<ChatRepository>().forModule(widget.moduleId);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text('Fragen · ${widget.moduleName}')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Stell eine Frage zu deinen hochgeladenen Materialien – z.B. "Erklär mir Thema X" '
                          'oder "Wie hängt das mit der letzten Vorlesung zusammen?". Es passiert nichts von '
                          'selbst, nur wenn du fragst. Mit "Mit Materialien" unten kannst du auch ganz ohne '
                          'Materialbezug allgemein fragen.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.inkMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) => _ChatBubble(message: messages[i]),
                    ),
            ),
            if (_sending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(_statusLabel, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Mit Materialien'),
                  avatar: Icon(_useContext ? Icons.folder_outlined : Icons.folder_off_outlined, size: 16),
                  selected: _useContext,
                  onSelected: (v) => setState(() => _useContext = v),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Frage stellen …',
                        filled: true,
                        fillColor: c.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accent)),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded),
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isUser = message.role == ChatRole.user;
    final sources = message.sourceFileNames;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? c.accentSoft : c.surface,
          border: isUser ? null : Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.content, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink)),
            if (!isUser && sources != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sources.isEmpty ? Icons.folder_off_outlined : Icons.folder_outlined,
                      size: 12, color: c.inkMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      sources.isEmpty ? 'Ohne Material-Kontext beantwortet' : 'Quellen: ${sources.join(', ')}',
                      style: TextStyle(fontSize: 11, color: c.inkMuted, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
