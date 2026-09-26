import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/flashcard.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/answer_checker.dart';
import '../../services/fsrs_service.dart';
import '../../services/html_question_contract.dart';
import '../../theme/app_colors.dart';
import '../widgets/math_text.dart';

/// Rendert und beantwortet EINE Frage, passend zu ihrem [Flashcard.type].
///
/// Der einfache `flashcard`-Typ bleibt beim bisherigen Umdrehen +
/// Selbstbewertung (Nochmal/Schwer/Gut/Leicht). Alle anderen Typen werden
/// automatisch geprüft (siehe AnswerChecker): der Nutzer beantwortet,
/// bekommt sofort Feedback (richtig/falsch + Lösung) und tippt dann auf
/// "Weiter" – die FSRS-Bewertung leitet sich dabei aus der Korrektheit ab
/// (siehe FsrsService.gradeFromResult), keine manuelle Selbsteinschätzung
/// nötig.
///
/// Muss vom Aufrufer mit `key: ValueKey(card.id)` eingebunden werden, damit
/// bei einer neuen Frage ein frischer State (Auswahl/Texteingaben/Drag-
/// Zuordnungen) entsteht, statt alte Eingaben der vorherigen Frage zu zeigen.
class QuestionAnswerView extends StatefulWidget {
  const QuestionAnswerView({
    super.key,
    required this.card,
    required this.isNew,
    required this.onComplete,
    this.examMode = false,
  });

  final Flashcard card;
  final bool isNew;

  /// Probeklausur (siehe MockExamScreen): kein Feedback, keine KI-Hilfe –
  /// "Antwort abgeben" wertet aus und meldet das Ergebnis sofort weiter.
  final bool examMode;

  /// [selfGrade] für den offenen `flashcard`-Typ, [isCorrect] für alle
  /// automatisch geprüften Typen. Ausnahme: richtig beantwortet, aber mit
  /// Tipp – dann kommt beides ([isCorrect] true, [selfGrade] "Schwer"), damit
  /// die Antwort zählt, die Ampel aber nicht steigt (siehe ReviewService).
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;

  @override
  State<QuestionAnswerView> createState() => _QuestionAnswerViewState();
}

/// Anzeige-Reihenfolge von Antwortoptionen (Indizes in [Flashcard.options]):
/// Die KI setzt die richtige Option auffällig oft an den Anfang – ohne
/// Mischen lernt man die Position statt den Inhalt. Optionen wie "Alle
/// genannten"/"Keine der genannten" bleiben am Ende, weil sie sich auf die
/// übrigen beziehen.
@visibleForTesting
List<int> optionDisplayOrder(List<QuizOption> options, {Random? random}) {
  final meta = RegExp(r'^\s*(alle|keine|beide|sowohl)\b', caseSensitive: false);
  final regular = [
    for (var i = 0; i < options.length; i++)
      if (!meta.hasMatch(options[i].text)) i,
  ]..shuffle(random);
  return [
    ...regular,
    for (var i = 0; i < options.length; i++)
      if (meta.hasMatch(options[i].text)) i,
  ];
}

class _QuestionAnswerViewState extends State<QuestionAnswerView> {
  bool _showBack = false;

  int? _selectedIndex;
  final Set<int> _selectedIndices = {};
  final _freeTextController = TextEditingController();
  late List<TextEditingController> _blankControllers;

  /// Noch nicht abgelegte Begriffe als Indizes in [_pairs] – bewusst nicht
  /// der Text: Begriffe und Ziele können gleich lauten (z.B. zweimal
  /// "Metall"), dann würde ein Begriff sonst mehrere Felder belegen.
  late List<int> _pool;

  /// Zuordnen: Ziel-Index -> Index des dort abgelegten Begriffs.
  final Map<int, int> _zoneToSource = {};

  /// Kategorien: Begriff-Index -> gewählte Kategorie.
  final Map<int, String> _sourceToCategory = {};

  /// Per Antippen ausgewählter Begriff (Alternative zum Ziehen): danach ein
  /// Ziel antippen legt ihn dort ab.
  int? _selectedSource;

  bool _checked = false;
  AnswerCheckResult? _result;

  /// true, während für eine Freitext- oder Lückentext-Antwort auf die
  /// KI-Zweitmeinung gewartet wird (siehe [_checkFreeTextAnswer],
  /// [_checkFillBlankAnswer]) – sperrt währenddessen "Prüfen" und die
  /// Eingabe, damit nicht doppelt angefragt oder nachträglich geändert wird.
  bool _aiChecking = false;

  /// Lückentext nach dem Prüfen: je Lücke, ob sie (lokal oder laut KI)
  /// richtig war.
  List<bool>? _blankHits;

  // -- html-Typ: interaktive Seite in einer sandboxed WebView -------------
  WebViewController? _webViewController;
  bool _webViewLoading = true;

  /// false, sobald die Seite nicht geladen werden konnte ODER die Plattform
  /// gar keine WebView unterstützt (nur Android/iOS, siehe webview_flutter) –
  /// zeigt dann stattdessen [_buildFlashcard] als Fallback mit
  /// Selbstbewertung (front/back sind bei diesem Typ genau dafür gedacht).
  bool _webViewAvailable = true;

  // -- KI-Hilfe: Tipp vor dem Antworten, Erklärung danach -----------------
  String? _hint;
  bool _hintLoading = false;
  String? _explanation;
  bool _explanationLoading = false;
  bool _explainedSimpler = false;
  String? _aiHelpError;

  /// Die Aufrufer speichern asynchron (DB-Write), bevor sie zur nächsten
  /// Karte wechseln – ohne diese Sperre würde ein zweites Tippen auf
  /// "Weiter"/eine Bewertung in dieser Zeit (oder eine doppelt gesendete
  /// Nachricht einer html-Seite) dieselbe Karte zweimal bewerten und die
  /// folgende Karte überspringen.
  bool _submitted = false;

  void _submit({Grade? selfGrade, bool? isCorrect}) {
    if (_submitted) return;
    _submitted = true;
    widget.onComplete(selfGrade: selfGrade, isCorrect: isCorrect);
  }

  /// Zuordnen-Fragen mit mehrfach genannten Zielen gelten als Kategorien
  /// (siehe AnswerChecker.isCategoryDrag).
  late final bool _isCategoryDrag = AnswerChecker.isCategoryDrag(widget.card);
  late final List<DragPair> _pairs = AnswerChecker.usableDragPairs(widget.card);
  late final List<String> _blanks = AnswerChecker.solvableBlanks(widget.card);

  /// Karten mit unbrauchbaren Daten (keine richtige Option, leere Lösung …)
  /// werden wie eine Karteikarte selbst bewertet statt unlösbar abgefragt.
  late final bool _answerable = AnswerChecker.isAnswerable(widget.card);

  /// Anzeige-Reihenfolge der Antwortoptionen (Indizes in [Flashcard.options]).
  late final List<int> _optionOrder = optionDisplayOrder(widget.card.options ?? const []);

  @override
  void initState() {
    super.initState();
    _blankControllers = List.generate(_blanks.length, (_) => TextEditingController());
    _pool = List.generate(_pairs.length, (i) => i)..shuffle();
    if (widget.card.type == QuestionType.html) _setupWebView();
  }

  void _setupWebView() {
    final html = widget.card.htmlContent;
    final supportsWebView = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (html == null || html.trim().isEmpty || !supportsWebView) {
      setState(() => _webViewAvailable = false);
      return;
    }
    try {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (_) => NavigationDecision.prevent,
          onPageFinished: (_) {
            if (mounted) setState(() => _webViewLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _webViewAvailable = false);
          },
        ))
        ..addJavaScriptChannel(htmlAnswerChannelName, onMessageReceived: _handleHtmlAnswerMessage)
        ..loadHtmlString(wrapHtmlQuestionPage(html));
    } catch (_) {
      setState(() => _webViewAvailable = false);
    }
  }

  /// Reagiert auf `window.FlutterAnswer.postMessage(...)` aus der
  /// KI-generierten Seite (siehe AiService-Prompts für den Vertrag). Eine
  /// kaputte/unerwartete Nachricht wird still ignoriert statt die App
  /// abstürzen zu lassen – der Nutzer kann die Seite dann einfach nicht
  /// sinnvoll beenden und würde zum nächsten Öffnen dieser Karte erneut
  /// einen Versuch bekommen.
  ///
  /// Außerhalb der Probeklausur geht es danach NICHT sofort weiter: die
  /// Seite zeigt meist ihr eigenes Feedback, das sonst nie zu sehen wäre –
  /// die App zeigt ihr Ergebnis darunter mit "Weiter". Nur der erste
  /// gemeldete Versuch zählt.
  void _handleHtmlAnswerMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);
      if (data is Map && data['correct'] is bool) {
        final correct = data['correct'] as bool;
        if (widget.examMode) {
          _submit(isCorrect: correct);
          return;
        }
        if (!mounted || _checked) return;
        setState(() {
          _checked = true;
          _result = AnswerCheckResult(isCorrect: correct, correctAnswerLabel: widget.card.back);
        });
      }
    } catch (_) {
      // Siehe Doc-Kommentar oben.
    }
  }

  @override
  void dispose() {
    _freeTextController.dispose();
    for (final c in _blankControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Legt Begriff [source] auf Ziel [zone] (Zuordnen) – ein dort liegender
  /// Begriff wandert zurück in den Pool, sonst verschwände er aus der
  /// Oberfläche und wäre nicht mehr zuordenbar.
  void _placeOnZone(int source, int zone) {
    if (_checked) return;
    setState(() {
      _selectedSource = null;
      _zoneToSource.removeWhere((_, s) => s == source);
      _pool.remove(source);
      final displaced = _zoneToSource[zone];
      if (displaced != null && displaced != source && !_pool.contains(displaced)) {
        _pool.add(displaced);
      }
      _zoneToSource[zone] = source;
    });
  }

  void _placeInCategory(int source, String category) {
    if (_checked) return;
    setState(() {
      _selectedSource = null;
      _pool.remove(source);
      _sourceToCategory[source] = category;
    });
  }

  void _returnToPool(int source) {
    if (_checked) return;
    setState(() {
      _selectedSource = null;
      _zoneToSource.removeWhere((_, s) => s == source);
      _sourceToCategory.remove(source);
      if (!_pool.contains(source)) _pool.add(source);
    });
  }

  bool get _canCheck {
    if (_aiChecking) return false;
    switch (widget.card.type) {
      case QuestionType.flashcard:
        return false;
      case QuestionType.singleChoice:
        return _selectedIndex != null;
      case QuestionType.multipleChoice:
        return _selectedIndices.isNotEmpty;
      case QuestionType.freeText:
        return _freeTextController.text.trim().isNotEmpty;
      case QuestionType.fillBlank:
        return _blankControllers.every((c) => c.text.trim().isNotEmpty);
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return _pool.isEmpty && _pairs.isNotEmpty;
      case QuestionType.html:
        return false; // eigener build()-Zweig, siehe _buildHtmlQuestion.
    }
  }

  Future<void> _check() async {
    final result = await _computeResult();
    if (result == null || !mounted) return;
    setState(() {
      _checked = true;
      _result = result;
    });
  }

  /// Probeklausur: auswerten und direkt weitermelden, ohne Feedback.
  Future<void> _submitExamAnswer() async {
    final result = await _computeResult();
    if (result == null || !mounted) return;
    _submit(isCorrect: result.isCorrect);
  }

  Future<AnswerCheckResult?> _computeResult() async {
    final card = widget.card;
    switch (card.type) {
      case QuestionType.singleChoice:
        return AnswerChecker.checkSingleChoice(card, _selectedIndex);
      case QuestionType.multipleChoice:
        return AnswerChecker.checkMultipleChoice(card, _selectedIndices);
      case QuestionType.fillBlank:
        return _checkFillBlankAnswer();
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return _isCategoryDrag
            ? AnswerChecker.checkDragCategory(card, Map.of(_sourceToCategory))
            : AnswerChecker.checkDragDrop(card, Map.of(_zoneToSource));
      case QuestionType.freeText:
        return _checkFreeTextAnswer();
      case QuestionType.flashcard:
      case QuestionType.html:
        return null; // eigene build()-Zweige.
    }
  }

  /// Zweistufige Freitext-Prüfung: zuerst der schnelle, rein lokale
  /// Fuzzy-Vergleich (siehe AnswerChecker.checkFreeText) – erkennt er die
  /// Antwort als richtig, reicht das (kein API-Call nötig). Ein reiner
  /// Text-/Tippfehler-Abgleich ist für frei formulierte Antworten aber fast
  /// unmöglich zu erfüllen (eine inhaltlich richtige, nur anders formulierte
  /// Antwort würde sonst als falsch gewertet) – deshalb bei lokaler Ablehnung
  /// eine KI-Zweitmeinung einholen (AiService.checkFreeTextAnswer), die
  /// Umformulierungen versteht. Ohne hinterlegten API-Key oder bei einem
  /// Fehler bleibt es beim (strengeren) lokalen Ergebnis statt die Frage
  /// unbeantwortet zu lassen.
  Future<AnswerCheckResult> _checkFreeTextAnswer() async {
    final card = widget.card;
    final localResult = AnswerChecker.checkFreeText(card, _freeTextController.text);
    if (localResult.isCorrect) return localResult;

    final ai = _aiOrNull();
    if (ai == null) return localResult;

    setState(() => _aiChecking = true);
    try {
      final aiCorrect = await ai.checkFreeTextAnswer(
        question: card.front,
        correctAnswer: card.correctText ?? '',
        userAnswer: _freeTextController.text,
      );
      return AnswerCheckResult(isCorrect: aiCorrect, correctAnswerLabel: localResult.correctAnswerLabel);
    } catch (_) {
      return localResult;
    } finally {
      if (mounted) setState(() => _aiChecking = false);
    }
  }

  /// Lückentext, zweistufig wie Freitext: zuerst lokal je Lücke (exakt,
  /// kleiner Tippfehler oder eine der per ";" hinterlegten Varianten). Lehnt
  /// das eine Lücke ab, bewertet die KI jede Lücke nach
  /// (AiService.checkFillBlankAnswers) – andere richtige Begriffe, Synonyme,
  /// gröbere Rechtschreibfehler. Die KI kann eine Lücke nur nachträglich als
  /// richtig werten, nie eine lokal richtige verwerfen. Ohne API-Key oder bei
  /// einem Fehler zählt das lokale Ergebnis.
  Future<AnswerCheckResult> _checkFillBlankAnswer() async {
    final card = widget.card;
    final answers = _blankControllers.map((c) => c.text).toList();
    var hits = AnswerChecker.fillBlankHits(card, answers);
    final ai = hits.every((h) => h) ? null : _aiOrNull();
    if (ai != null) {
      setState(() => _aiChecking = true);
      try {
        final verdicts = await ai.checkFillBlankAnswers(text: card.front, solutions: _blanks, answers: answers);
        hits = [for (var i = 0; i < hits.length; i++) hits[i] || (i < verdicts.length && verdicts[i])];
      } catch (_) {
        // Lokales Ergebnis bleibt, siehe oben.
      } finally {
        if (mounted) setState(() => _aiChecking = false);
      }
    }
    _blankHits = hits;
    return AnswerChecker.fillBlankResult(card, hits);
  }

  AiService? _aiOrNull() {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    return AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
  }

  bool get _aiHelpAvailable => context.read<SettingsRepository?>()?.settings.hasApiKey ?? false;

  /// Die richtige Lösung als Text – Grundlage für Tipp und Erklärung.
  String get _correctAnswerText {
    final label = _result?.correctAnswerLabel;
    if (label != null && label.isNotEmpty) return label;
    final summary = widget.card.answerSummary;
    return summary.isNotEmpty ? summary : widget.card.back;
  }

  /// Was der Nutzer geantwortet hat, als Text für die Erklärung.
  String? get _userAnswerText {
    final card = widget.card;
    final options = card.options ?? const [];
    switch (card.type) {
      case QuestionType.singleChoice:
        final i = _selectedIndex;
        return i == null || i >= options.length ? null : options[i].text;
      case QuestionType.multipleChoice:
        final indices = _selectedIndices.toList()..sort();
        return [for (final i in indices) if (i < options.length) options[i].text].join('; ');
      case QuestionType.freeText:
        return _freeTextController.text;
      case QuestionType.fillBlank:
        return _blankControllers.map((c) => c.text).join('; ');
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return _isCategoryDrag
            ? [for (final e in _sourceToCategory.entries) '${_pairs[e.key].source} -> ${e.value}'].join('; ')
            : [for (final e in _zoneToSource.entries) '${_pairs[e.value].source} -> ${_pairs[e.key].target}'].join('; ');
      case QuestionType.flashcard:
      case QuestionType.html:
        return null;
    }
  }

  Future<void> _loadHint() async {
    final ai = _aiOrNull();
    if (ai == null) return;
    setState(() {
      _hintLoading = true;
      _aiHelpError = null;
    });
    try {
      final hint = await ai.generateHint(question: widget.card.front, correctAnswer: _correctAnswerText);
      if (mounted) setState(() => _hint = hint);
    } catch (e) {
      if (mounted) setState(() => _aiHelpError = e is AiServiceException ? e.message : 'Tipp fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _hintLoading = false);
    }
  }

  Future<void> _loadExplanation({bool simpler = false}) async {
    final ai = _aiOrNull();
    if (ai == null) return;
    setState(() {
      _explanationLoading = true;
      _aiHelpError = null;
    });
    try {
      final text = await ai.explainAnswer(
        question: widget.card.front,
        correctAnswer: _correctAnswerText,
        userAnswer: _userAnswerText,
        wasCorrect: _result?.isCorrect,
        previousExplanation: simpler ? _explanation : null,
      );
      if (!mounted) return;
      setState(() {
        _explanation = text;
        if (simpler) _explainedSimpler = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _aiHelpError = e is AiServiceException ? e.message : 'Erklärung fehlgeschlagen: $e');
      }
    } finally {
      if (mounted) setState(() => _explanationLoading = false);
    }
  }

  static Widget _smallSpinner() =>
      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2));

  /// "Tipp" vor dem Antworten – ein Denkanstoß ohne Lösung. Eine danach
  /// richtige Antwort zählt nur als "Schwer" (siehe [QuestionAnswerView.onComplete]).
  Widget _buildHintArea(AppColors c) {
    if (widget.examMode || !_aiHelpAvailable) return const SizedBox.shrink();
    final hint = _hint;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hint == null)
            TextButton.icon(
              onPressed: _hintLoading ? null : _loadHint,
              icon: _hintLoading ? _smallSpinner() : const Icon(Icons.lightbulb_outline, size: 18),
              label: const Text('Tipp'),
            )
          else
            _AiHelpBox(icon: Icons.lightbulb_outline, text: hint, color: c.warn, background: c.warnSoft),
          if (_aiHelpError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_aiHelpError!, style: TextStyle(fontSize: 12, color: c.danger)),
            ),
        ],
      ),
    );
  }

  /// "Erklär mir das" nach dem Antworten, danach optional "Einfacher erklären".
  Widget _buildExplainArea(AppColors c) {
    if (widget.examMode || !_aiHelpAvailable) return const SizedBox.shrink();
    final explanation = _explanation;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (explanation == null)
            OutlinedButton.icon(
              onPressed: _explanationLoading ? null : () => _loadExplanation(),
              icon: _explanationLoading ? _smallSpinner() : const Icon(Icons.psychology_alt_outlined, size: 18),
              label: Text(_result?.isCorrect == true ? 'Warum ist das richtig?' : 'Erklär mir das'),
            )
          else ...[
            _AiHelpBox(
              icon: Icons.psychology_alt_outlined,
              text: explanation,
              color: c.accentOnSoft,
              background: c.accentSoft,
            ),
            if (!_explainedSimpler)
              TextButton.icon(
                onPressed: _explanationLoading ? null : () => _loadExplanation(simpler: true),
                icon: _explanationLoading ? _smallSpinner() : const Icon(Icons.child_care_outlined, size: 18),
                label: const Text('Einfacher erklären'),
              ),
          ],
          if (_aiHelpError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_aiHelpError!, style: TextStyle(fontSize: 12, color: c.danger)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.card.type == QuestionType.flashcard || !_answerable) {
      return _buildFlashcard(c);
    }
    if (widget.card.type == QuestionType.html) {
      return _buildHtmlQuestion(c);
    }
    return _buildInteractive(c);
  }

  // ---------------------------------------------------------------------
  // html: KI-generierte interaktive Seite (siehe AiService-Prompts) in
  // einer sandboxed WebView; ohne WebView-Unterstützung (Windows/Web/
  // Linux) oder bei Ladefehler Fallback auf dieselbe Umdrehen +
  // Selbstbewertung-Ansicht wie beim einfachen `flashcard`-Typ.
  // ---------------------------------------------------------------------
  Widget _buildHtmlQuestion(AppColors c) {
    if (!_webViewAvailable) return _buildFlashcard(c);
    return Column(
      children: [
        if (_webViewLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: WebViewWidget(controller: _webViewController!)),
        if (_checked)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFeedback(c),
                  _buildExplainArea(c),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _submit(isCorrect: _result!.isCorrect),
                    child: const Text('Weiter'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Flashcard: unverändert Umdrehen + Selbstbewertung.
  // ---------------------------------------------------------------------
  Widget _buildFlashcard(AppColors c) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _showBack ? null : () => setState(() => _showBack = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.border),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _newBadge(c),
                          _buildCardImage(c),
                          MathText(
                            widget.card.front,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.45),
                          ),
                          if (_showBack) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Divider(height: 1, color: c.border),
                            ),
                            MathText(
                              _backText,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 15, height: 1.6, color: c.inkMuted),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            Text('Zum Umdrehen tippen', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_showBack) _buildExplainArea(c) else _buildHintArea(c),
                ],
              ),
            ),
          ),
        ),
        if (_showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            child: Row(
              children: [
                Expanded(
                    child: _ActionButton(
                        label: 'Nochmal',
                        fg: c.danger,
                        bg: c.dangerSoft,
                        onTap: () => _submit(selfGrade: Grade.again))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: 'Schwer',
                        fg: c.warn,
                        bg: c.warnSoft,
                        onTap: () => _submit(selfGrade: Grade.hard))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: 'Gut',
                        fg: c.good,
                        bg: c.goodSoft,
                        onTap: () => _submit(selfGrade: Grade.good))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: 'Leicht',
                        fg: c.accentOnSoft,
                        bg: c.accentSoft,
                        onTap: () => _submit(selfGrade: Grade.easy))),
              ],
            ),
          )
        else
          const SizedBox(height: 30),
      ],
    );
  }

  /// Rückseite in der Karteikarten-Ansicht – bei der Ersatzansicht für
  /// Karten mit kaputten Daten die bestmögliche Lösung.
  String get _backText {
    final card = widget.card;
    if (card.back.trim().isNotEmpty) return card.back;
    final summary = card.answerSummary.trim();
    return summary.isNotEmpty ? summary : '(Keine Lösung hinterlegt)';
  }

  /// Zeigt den an [Flashcard.imageBase64] hängenden Seiten-Screenshot,
  /// falls vorhanden (siehe PageQuestionCreationSheet – nur bei Fragen
  /// gesetzt, die das Vision-Modell als "needsImage" markiert hat, z.B. weil
  /// sie sich auf ein Diagramm/eine Grafik beziehen). Ein defektes Base64
  /// wird still ignoriert statt die Karte unbenutzbar zu machen.
  Widget _buildCardImage(AppColors c) {
    final base64 = widget.card.imageBase64;
    if (base64 == null || base64.isEmpty) return const SizedBox.shrink();
    Uint8List bytes;
    try {
      bytes = base64Decode(base64);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
      ),
    );
  }

  Widget _newBadge(AppColors c) {
    if (!widget.isNew) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(20)),
        child: Text('NEU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.warn, letterSpacing: 0.03)),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Automatisch geprüfte Typen: Frage + typspezifische Eingabe + Prüfen/Weiter.
  // ---------------------------------------------------------------------
  Widget _buildInteractive(AppColors c) {
    final card = widget.card;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        _newBadge(c),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                child: Text(_isCategoryDrag ? QuestionType.dragCategory.label : card.type.label,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft, letterSpacing: 0.03)),
              ),
              const SizedBox(height: 12),
              _buildCardImage(c),
              if (card.type != QuestionType.fillBlank)
                MathText(card.front, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
              const SizedBox(height: 16),
              _buildAnswerInput(c),
            ],
          ),
        ),
        if (!_checked) _buildHintArea(c),
        if (_checked) ...[
          const SizedBox(height: 16),
          _buildFeedback(c),
          _buildExplainArea(c),
        ],
        const SizedBox(height: 20),
        if (_checked)
          FilledButton(
            onPressed: () => _submit(
              isCorrect: _result!.isCorrect,
              // Mit Tipp richtig: zählt, aber nur als "Schwer" – die Ampel
              // steigt dadurch nicht.
              selfGrade: _hint != null && _result!.isCorrect ? Grade.hard : null,
            ),
            child: const Text('Weiter'),
          )
        else
          FilledButton(
            onPressed: _canCheck ? (widget.examMode ? _submitExamAnswer : _check) : null,
            child: _aiChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.examMode ? 'Antwort abgeben' : 'Prüfen'),
          ),
      ],
    );
  }

  Widget _buildAnswerInput(AppColors c) {
    switch (widget.card.type) {
      case QuestionType.flashcard:
      case QuestionType.html:
        return const SizedBox.shrink(); // eigene build()-Zweige.
      case QuestionType.singleChoice:
        return _buildChoiceOptions(c, multiple: false);
      case QuestionType.multipleChoice:
        return _buildChoiceOptions(c, multiple: true);
      case QuestionType.freeText:
        return TextField(
          controller: _freeTextController,
          enabled: !_checked && !_aiChecking,
          decoration: InputDecoration(
            hintText: 'Antwort eingeben …',
            filled: true,
            fillColor: c.surfaceAlt,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() {}),
        );
      case QuestionType.fillBlank:
        return _buildFillBlank(c);
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return _buildDragDrop(c);
    }
  }

  Widget _buildChoiceOptions(AppColors c, {required bool multiple}) {
    final options = widget.card.options ?? const [];
    return Column(
      children: _optionOrder.map((i) {
        final option = options[i];
        final selected = multiple ? _selectedIndices.contains(i) : _selectedIndex == i;
        Color? tileColor;
        IconData? trailingIcon;
        Color? trailingColor;
        if (_checked) {
          if (option.isCorrect) {
            tileColor = c.goodSoft;
            trailingIcon = Icons.check_circle;
            trailingColor = c.good;
          } else if (selected) {
            tileColor = c.dangerSoft;
            trailingIcon = Icons.cancel;
            trailingColor = c.danger;
          }
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _checked
                ? null
                : () => setState(() {
                      if (multiple) {
                        if (_selectedIndices.contains(i)) {
                          _selectedIndices.remove(i);
                        } else {
                          _selectedIndices.add(i);
                        }
                      } else {
                        _selectedIndex = i;
                      }
                    }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: tileColor ?? (selected ? c.accentSoft : c.surfaceAlt),
                border: Border.all(color: selected && tileColor == null ? c.accent : c.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    multiple
                        ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                        : (selected ? Icons.radio_button_checked : Icons.radio_button_off),
                    size: 20,
                    color: c.inkMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: MathText(option.text)),
                  if (trailingIcon != null) Icon(trailingIcon, size: 18, color: trailingColor),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Bei mehreren Lücken werden sie im Text nummeriert, damit klar ist,
  /// welches Eingabefeld zu welcher Lücke gehört.
  String get _fillBlankFront {
    final front = widget.card.front;
    if (_blanks.length < 2) return front;
    var n = 0;
    return front.replaceAllMapped(RegExp(r'_{3,}'), (m) => '${m[0]} (${++n})');
  }

  Widget _buildFillBlank(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MathText(_fillBlankFront, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 16),
        ...List.generate(_blankControllers.length, (i) {
          // Nach dem Prüfen je Lücke ✓/✗; die hinterlegte Lösung erscheint,
          // wenn die Eingabe falsch war oder nur dank Tippfehler-Toleranz/KI
          // als richtig galt (dann sieht man die korrekte Schreibweise).
          final hit = _checked ? _blankHits?.elementAtOrNull(i) : null;
          final showSolution = hit != null &&
              !(hit && AnswerChecker.answerExactlyMatches(_blankControllers[i].text, _blanks[i]));
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _blankControllers[i],
              enabled: !_checked && !_aiChecking,
              decoration: InputDecoration(
                labelText: 'Lücke ${i + 1}',
                filled: true,
                fillColor: hit == null ? c.surfaceAlt : (hit ? c.goodSoft : c.dangerSoft),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                suffixIcon: hit == null
                    ? null
                    : Icon(hit ? Icons.check_circle : Icons.cancel, color: hit ? c.good : c.danger, size: 20),
                helperText: showSolution ? 'Lösung: ${AnswerChecker.solutionLabel(_blanks[i])}' : null,
                helperMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDragDrop(AppColors c) {
    final correctPlacements =
        _checked && _isCategoryDrag ? AnswerChecker.correctCategoryPlacements(widget.card, _sourceToCategory) : const <int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isCategoryDrag
              ? 'Ordne jeden Begriff der richtigen Kategorie zu – ziehen oder antippen und dann die Kategorie antippen.'
              : 'Ziehe die Begriffe auf die passenden Ziele – oder antippen und dann das Ziel antippen.',
          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
        ),
        const SizedBox(height: 12),
        DragTarget<int>(
          onWillAcceptWithDetails: (details) => !_checked && !_pool.contains(details.data),
          onAcceptWithDetails: (details) => _returnToPool(details.data),
          builder: (context, candidates, _) => Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 40),
            decoration: candidates.isNotEmpty
                ? BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14))
                : null,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final source in _pool) _dragChip(c, source)],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_isCategoryDrag)
          for (final category in AnswerChecker.dragCategories(widget.card))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _categoryZone(c, category, correctPlacements),
            )
        else
          for (var zone = 0; zone < _pairs.length; zone++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _pairZone(c, zone),
            ),
      ],
    );
  }

  /// Ein Begriff im Pool: ziehen oder antippen (auswählen).
  Widget _dragChip(AppColors c, int source) {
    final selected = _selectedSource == source;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? c.accentSolid : c.accentSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _pairs[source].source,
        style: TextStyle(fontSize: 13, color: selected ? c.accentInk : c.accentOnSoft, fontWeight: FontWeight.w600),
      ),
    );
    if (_checked) return chip;
    return Draggable<int>(
      data: source,
      feedback: Material(color: Colors.transparent, child: chip),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: GestureDetector(
        onTap: () => setState(() => _selectedSource = selected ? null : source),
        child: chip,
      ),
    );
  }

  /// Ein bereits abgelegter Begriff: antippen legt ihn zurück, ziehen
  /// verschiebt ihn auf ein anderes Ziel.
  Widget _assignedChip(AppColors c, int source, {Color? color}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color ?? c.surface, borderRadius: BorderRadius.circular(20)),
      child: Text(_pairs[source].source, style: TextStyle(fontSize: 12.5, color: c.ink)),
    );
    if (_checked) return chip;
    return Draggable<int>(
      data: source,
      feedback: Material(color: Colors.transparent, child: chip),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: GestureDetector(onTap: () => _returnToPool(source), child: chip),
    );
  }

  Widget _zoneFrame(
    AppColors c, {
    required Color? tileColor,
    required bool highlighted,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: tileColor ?? (highlighted ? c.accentSoft : c.surfaceAlt),
          border: Border.all(color: highlighted ? c.accent : c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }

  /// Zuordnen: genau ein Begriff pro Ziel.
  Widget _pairZone(AppColors c, int zone) {
    final assigned = _zoneToSource[zone];
    final Color? tileColor =
        _checked ? (AnswerChecker.dragZoneCorrect(widget.card, zone, assigned) ? c.goodSoft : c.dangerSoft) : null;
    final selected = _selectedSource;
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => !_checked,
      onAcceptWithDetails: (details) => _placeOnZone(details.data, zone),
      builder: (context, candidates, _) => _zoneFrame(
        c,
        tileColor: tileColor,
        highlighted: candidates.isNotEmpty || (selected != null && !_checked),
        onTap: selected == null || _checked ? null : () => _placeOnZone(selected, zone),
        child: Row(
          children: [
            Expanded(child: Text(_pairs[zone].target, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (assigned != null) _assignedChip(c, assigned),
          ],
        ),
      ),
    );
  }

  /// Kategorien: beliebig viele Begriffe – ALLE anzeigen (einzeln
  /// zurücklegbar, nach dem Prüfen einzeln eingefärbt).
  Widget _categoryZone(AppColors c, String category, Set<int> correctPlacements) {
    final assigned = [
      for (final e in _sourceToCategory.entries)
        if (e.value == category) e.key,
    ];
    final selected = _selectedSource;
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => !_checked,
      onAcceptWithDetails: (details) => _placeInCategory(details.data, category),
      builder: (context, candidates, _) => _zoneFrame(
        c,
        tileColor: null,
        highlighted: candidates.isNotEmpty || (selected != null && !_checked),
        onTap: selected == null || _checked ? null : () => _placeInCategory(selected, category),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (assigned.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final source in assigned)
                    _assignedChip(
                      c,
                      source,
                      color: _checked ? (correctPlacements.contains(source) ? c.goodSoft : c.dangerSoft) : null,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback(AppColors c) {
    final result = _result!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: result.isCorrect ? c.goodSoft : c.dangerSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: result.isCorrect ? c.good : c.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.isCorrect ? 'Richtig!' : 'Nicht ganz.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: result.isCorrect ? c.good : c.danger)),
                if (!result.isCorrect && result.correctAnswerLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  MathText('Richtige Antwort: ${result.correctAnswerLabel}', style: TextStyle(fontSize: 13, color: c.ink)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiHelpBox extends StatelessWidget {
  const _AiHelpBox({required this.icon, required this.text, required this.color, required this.background});

  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: SelectionArea(child: MathText(text, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.ink))),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.fg, required this.bg, required this.onTap});
  final String label;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}
