import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/flashcard.dart';
import '../../models/material_item.dart';
import '../../repositories/concept_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/source_locator.dart';
import '../../theme/app_colors.dart';
import '../modules/material_opener.dart';
import '../widgets/math_text.dart';
import 'socratic_screen.dart';

/// Sucht, wo die Karte in den Unterlagen ihres Fachs steht (siehe
/// [SourceLocator]). `null` ohne Treffer oder ohne Material-Repository.
///
/// [preferScript] true (Standard): die ERKLÄRUNG im Skript; false: die Aufgabe
/// im Original (bei Übungsblatt-Fragen das Übungsblatt).
Future<CardSource?> findCardSource(BuildContext context, Flashcard card, {bool preferScript = true}) async {
  final materials = context.read<MaterialRepository?>();
  if (materials == null) return null;
  final concepts = context.read<ConceptRepository?>();
  await materials.loadForModule(card.moduleId);
  if (concepts != null && card.conceptId != null) await concepts.loadForModule(card.moduleId);
  return SourceLocator().locate(
    card,
    materials: materials.forModule(card.moduleId),
    concepts: concepts?.forModule(card.moduleId) ?? const [],
    preferScript: preferScript,
  );
}

/// Stammt die Frage aus einem Übungsblatt oder einer Altklausur (nicht aus den
/// Folien)? Dann gibt es zwei Ziele: die Aufgabe im Blatt und die Erklärung im
/// Skript.
bool isWorksheetQuestion(BuildContext context, Flashcard card) {
  final id = card.sourceMaterialId;
  if (id == null) return false;
  for (final m in context.read<MaterialRepository?>()?.forModule(card.moduleId) ?? const <MaterialItem>[]) {
    if (m.id == id) return m.kind != MaterialKind.slide;
  }
  return false;
}

/// "Im Skript": öffnet die Seite, auf der die Frage steht. Eine nur
/// vermutete Stelle (Textabgleich) wird als solche angekündigt.
Future<void> openCardSource(BuildContext context, Flashcard card, {bool preferScript = true}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final source = await findCardSource(context, card, preferScript: preferScript);
  if (!context.mounted) return;
  if (source == null) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Keine passende Stelle in den Unterlagen gefunden – durchsucht werden die PDFs des Fachs '
          'auf diesem Gerät. Die kurze Lerneinheit hilft auch ohne.'),
    ));
    return;
  }
  if (source.guessed) {
    messenger?.showSnackBar(SnackBar(
      content: Text('Vermutlich hier: ${source.material.fileName}, Seite ${source.page}'),
      duration: const Duration(seconds: 3),
    ));
  } else if (preferScript && source.material.kind != MaterialKind.slide) {
    // Bei einer Übungsblatt-Frage ohne Erklärung im Skript.
    messenger?.showSnackBar(const SnackBar(
      content: Text('Im Skript keine passende Erklärung gefunden – hier ist das Übungsblatt.'),
      duration: Duration(seconds: 3),
    ));
  }
  await openMaterialAt(context, source.material, page: source.page);
}

AiService? _ai(BuildContext context, Flashcard card) {
  final settings = context.read<SettingsRepository?>()?.settings;
  if (settings == null || !settings.hasApiKey) return null;
  // Mit Bild braucht die KI das Vision-Modell.
  return AiService(
    apiKey: settings.openRouterApiKey!,
    model: card.imageBase64 != null ? settings.visionModelId : settings.effectiveHelpModelId,
  );
}

Uint8List? _imageOf(Flashcard card) {
  final encoded = card.imageBase64;
  if (encoded == null) return null;
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

/// Die richtige Lösung als Text.
String answerTextOf(Flashcard card) => card.answerSummary.isNotEmpty ? card.answerSummary : card.back;

/// "Kurze Lerneinheit" als Sheet – beim ersten Mal von der KI erzeugt und an
/// der Karte gespeichert, danach sofort da.
Future<void> showMiniLesson(BuildContext context, Flashcard card, {AiService? ai}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MiniLessonSheet(card: card, ai: ai ?? _ai(context, card)),
    );

/// Sokrates-Dialog zur Karte ([wrongAnswer] = die letzte falsche Antwort,
/// Ausgangspunkt für die erste Gegenfrage).
Future<void> openSocratic(BuildContext context, Flashcard card, {String? wrongAnswer, AiService? ai}) {
  final service = ai ?? _ai(context, card);
  if (service == null) return Future.value();
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => SocraticScreen(card: card, ai: service, wrongAnswer: wrongAnswer, image: _imageOf(card)),
  ));
}

/// "Im Skript" als eigenständiger, jederzeit sichtbarer Button – anders als
/// [StudyAidsBar] nicht ans Beantworten gekoppelt: beim Durcharbeiten
/// importierter Übungsaufgaben soll das Original-Arbeitsblatt schon VOR der
/// Antwort nachlesbar sein (die KI transkribiert die Aufgabe beim Import oft
/// nicht perfekt), nicht erst danach. Zeigt sich selbst nur, wenn überhaupt
/// ein Material-Repository verfügbar ist.
class SourceLinkButton extends StatelessWidget {
  const SourceLinkButton({super.key, required this.card, this.script = false});

  final Flashcard card;

  /// true: die Erklärung im Skript. false (Standard): die Aufgabe im
  /// Original – bei Übungsblatt-Fragen das Übungsblatt ("Aufgabenblatt"), sonst
  /// die Folie.
  final bool script;

  @override
  Widget build(BuildContext context) {
    final hasMaterials = context.read<MaterialRepository?>() != null;
    if (!hasMaterials) return const SizedBox.shrink();
    final worksheet = !script && isWorksheetQuestion(context, card);
    return TextButton.icon(
      key: ValueKey(script ? 'aid-source-script' : 'aid-source-early'),
      onPressed: () => openCardSource(context, card, preferScript: script),
      icon: Icon(worksheet ? Icons.description_outlined : Icons.menu_book_outlined, size: 18),
      label: Text(worksheet ? 'Aufgabenblatt' : 'Im Skript'),
    );
  }
}

/// Lernhilfen nach dem Beantworten: "Im Skript", "Kurze Lerneinheit" und –
/// bei Karten, die öfter schiefgehen ([suggestSocratic]) oder im
/// Fehlertagebuch ([showSocratic]) – "Sokratisch erarbeiten".
class StudyAidsBar extends StatelessWidget {
  const StudyAidsBar({
    super.key,
    required this.card,
    required this.aiAvailable,
    this.wrongAnswer,
    this.suggestSocratic = false,
    this.showSocratic = false,
  });

  final Flashcard card;
  final bool aiAvailable;
  final String? wrongAnswer;
  final bool suggestSocratic;
  final bool showSocratic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasMaterials = context.read<MaterialRepository?>() != null;
    final socratic = aiAvailable && (suggestSocratic || showSocratic);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (suggestSocratic && aiAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Diese Frage geht öfter schief – erarbeite sie dir Schritt für Schritt selbst.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
          ),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (socratic && suggestSocratic)
              FilledButton.tonalIcon(
                key: const ValueKey('aid-socratic'),
                onPressed: () => openSocratic(context, card, wrongAnswer: wrongAnswer),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Sokratisch erarbeiten'),
              ),
            if (hasMaterials)
              TextButton.icon(
                key: const ValueKey('aid-source'),
                onPressed: () => openCardSource(context, card),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Im Skript'),
              ),
            // Bei Übungsblatt-Fragen zusätzlich die Aufgabe im Original.
            if (hasMaterials && isWorksheetQuestion(context, card))
              TextButton.icon(
                key: const ValueKey('aid-worksheet'),
                onPressed: () => openCardSource(context, card, preferScript: false),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Aufgabenblatt'),
              ),
            if (aiAvailable || card.miniLesson != null)
              TextButton.icon(
                key: const ValueKey('aid-lesson'),
                onPressed: () => showMiniLesson(context, card),
                icon: const Icon(Icons.school_outlined, size: 18),
                label: const Text('Kurze Lerneinheit'),
              ),
            if (socratic && !suggestSocratic)
              TextButton.icon(
                key: const ValueKey('aid-socratic'),
                onPressed: () => openSocratic(context, card, wrongAnswer: wrongAnswer),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Sokratisch erarbeiten'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Inhalt des Lerneinheit-Sheets (siehe [showMiniLesson]).
class MiniLessonSheet extends StatefulWidget {
  const MiniLessonSheet({super.key, required this.card, this.ai});

  final Flashcard card;
  final AiService? ai;

  @override
  State<MiniLessonSheet> createState() => _MiniLessonSheetState();
}

class _MiniLessonSheetState extends State<MiniLessonSheet> {
  String? _lesson;
  CardSource? _source;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool regenerate = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final flashcards = context.read<FlashcardRepository?>();
    final concepts = context.read<ConceptRepository?>();
    try {
      // Gespeicherten Stand lesen: die Lerneinheit kann in dieser Sitzung
      // schon erzeugt worden sein, die übergebene Karte ist ein Schnappschuss.
      final stored = await flashcards?.loadById(widget.card.id) ?? widget.card;
      if (!mounted) return;
      _source ??= await findCardSource(context, stored);
      if (!mounted) return;
      final cached = stored.miniLesson;
      if (cached != null && cached.trim().isNotEmpty && !regenerate) {
        setState(() => _lesson = cached);
        return;
      }
      final ai = widget.ai;
      if (ai == null) {
        setState(() => _error = 'Für die Lerneinheit wird ein OpenRouter-API-Key gebraucht.');
        return;
      }
      String? conceptExplanation;
      for (final c in concepts?.forModule(stored.moduleId) ?? const []) {
        if (c.id == stored.conceptId) conceptExplanation = c.explanation;
      }
      final lesson = await ai.generateMiniLesson(
        question: stored.promptText,
        correctAnswer: answerTextOf(stored),
        sourceText: _source?.pageText,
        conceptExplanation: conceptExplanation,
        image: _imageOf(stored),
      );
      await flashcards?.updateStudyAids(stored.id, miniLesson: lesson);
      if (mounted) setState(() => _lesson = lesson);
    } catch (e) {
      if (mounted) setState(() => _error = e is AiServiceException ? e.message : 'Lerneinheit fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _labels = ['Worum es geht:', 'Kern:', 'Beispiel:', 'Merke:'];

  List<Widget> _paragraphs(AppColors c) {
    final widgets = <Widget>[];
    for (final line in (_lesson ?? '').split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;
      String? label;
      for (final l in _labels) {
        if (text.toLowerCase().startsWith(l.toLowerCase())) label = l;
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Text(label.substring(0, label.length - 1),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
            MathText(
              label == null ? text : text.substring(label.length).trim(),
              style: TextStyle(fontSize: 14, height: 1.45, color: c.ink),
            ),
          ],
        ),
      ));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final source = _source;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Kurze Lerneinheit', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          MathText(widget.card.front, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: TextStyle(color: c.danger))
          else
            SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _paragraphs(c))),
          if (source != null) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: const ValueKey('lesson-open-source'),
              onPressed: () => openMaterialAt(context, source.material, page: source.page),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text('${source.guessed ? 'Vermutlich ' : ''}${source.material.fileName}, Seite ${source.page}'),
            ),
          ],
          if (!_loading && widget.ai != null && _lesson != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _load(regenerate: true),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Neu erstellen'),
              ),
            ),
        ],
      ),
    );
  }
}
