import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/flashcard.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/ai_service.dart';
import '../../services/answer_checker.dart';
import '../../services/fsrs_service.dart';
import '../../services/html_question_contract.dart';
import '../../services/weakness_service.dart';
import '../../theme/app_colors.dart';
import '../study/explain_chat.dart';
import '../study/study_aids.dart';
import '../widgets/image_editor_screen.dart';
import '../widgets/math_text.dart';
import '../widgets/relative_image.dart';

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
    this.onImageEdited,
  });

  final Flashcard card;
  final bool isNew;

  /// Gesetzt, wenn das Bild der Karte hier bearbeitet werden darf (z.B. eine
  /// verräterische Beschriftung abdecken, sobald sie beim Lernen auffällt) –
  /// bekommt das bearbeitete Bild zum Speichern, `null`, wenn das Bild ganz
  /// entfernt wurde (unnötig angehängt).
  final Future<void> Function(Uint8List? bytes)? onImageEdited;

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

  // -- Bildfragen -----------------------------------------------------------
  /// Bild beschriften: die Stellen mit ihren Beschriftungen (Nummern 1..n).
  late final List<ImageTarget> _labelTargets = AnswerChecker.labelTargets(widget.card);

  /// Bild beschriften: noch nicht platzierte Beschriftungen (Indizes in
  /// [_labelTargets]) und Stelle -> dort abgelegte Beschriftung.
  late final List<int> _labelPool;
  final Map<int, int> _zoneToLabel = {};
  int? _selectedLabel;

  /// Bild beschriften: statt die vorgegebenen Beschriftungen zuzuordnen
  /// selbst eintippen (schwerer – Tippfehler zählen nicht, die KI prüft
  /// nach, siehe [_checkDiagramLabelAnswer]).
  bool _labelTyping = false;
  late final List<TextEditingController> _labelInputs;

  /// Nach dem Prüfen je Stelle das Ergebnis (austauschbare Stellen
  /// berücksichtigt) und ggf. die Begründung der KI.
  List<LabelZoneResult>? _labelResults;
  List<String?>? _labelNotes;

  /// Bild markieren: angetippte Stelle, relativ zum Bild.
  Offset? _markTap;

  /// Das Bild der Karte, einmal dekodiert (null ohne/mit kaputtem Bild).
  late final Uint8List? _imageBytes = _decodeImage(widget.card.imageBase64);

  static Uint8List? _decodeImage(String? base64) {
    if (base64 == null || base64.isEmpty) return null;
    try {
      return base64Decode(base64);
    } catch (_) {
      return null;
    }
  }

  bool get _isImageQuestion =>
      widget.card.type == QuestionType.diagramLabel || widget.card.type == QuestionType.markImage;

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

  /// Lückentext: kurze Begründung der KI je Lücke (null, wenn die Lücke
  /// schon lokal passte oder die KI nicht gefragt wurde).
  List<String?>? _blankNotes;

  // -- Tabelle ------------------------------------------------------------
  /// Die auszufüllenden Zellen (siehe AnswerChecker.tableBlanks) und je Zelle
  /// ein Eingabefeld, nach dem Prüfen Treffer/KI-Begründung je Zelle.
  late final List<({int row, int col, String solution})> _tableBlanks = AnswerChecker.tableBlanks(widget.card);
  late final List<TextEditingController> _tableControllers;
  List<bool>? _tableHits;
  List<String?>? _tableNotes;

  /// Mindestens [AnswerChecker.tablePartialShare] der Zellen richtig, aber
  /// nicht alle: zählt als "Schwer" (kein Fehler, Ampel steigt nicht).
  bool _tablePartial = false;
  int _tableRight = 0;

  /// Wie die Antwort geprüft wurde – unter dem Ergebnis angezeigt, damit
  /// sichtbar ist, ob die KI nachgeprüft hat oder (z.B. offline) nicht.
  String? _checkInfo;

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

  /// Fehler-Leiter (siehe Flashcard.hintsDueFor): nach wiederholten Fehlern
  /// automatisch gezeigte, an der Karte gespeicherte KI-Hilfestellungen.
  List<String> _ladderHints = const [];
  bool _ladderHintsLoading = false;

  bool get _helpShown => _hint != null || _ladderHints.isNotEmpty;
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
    _labelPool = List.generate(_labelTargets.length, (i) => i)..shuffle();
    _labelInputs = List.generate(_labelTargets.length, (_) => TextEditingController());
    _tableControllers = List.generate(_tableBlanks.length, (_) => TextEditingController());
    if (widget.card.type == QuestionType.html) _setupWebView();
    if (!widget.examMode && Flashcard.hintsDueFor(widget.card.variantMissStreak) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLadderHints());
    }
  }

  /// Zeigt die fälligen Hilfestellungen der Fehler-Leiter: gespeicherte
  /// sofort, fehlende per KI erzeugen (die zweite baut auf der ersten auf)
  /// und an der Karte speichern – beim nächsten Mal sind sie direkt da.
  Future<void> _loadLadderHints() async {
    final card = widget.card;
    final due = Flashcard.hintsDueFor(card.variantMissStreak);
    final hints = [...?card.aiHints];
    if (hints.length >= due) {
      if (mounted) setState(() => _ladderHints = hints.take(due).toList());
      return;
    }
    if (mounted) setState(() => _ladderHints = List.of(hints));
    final ai = _aiOrNull();
    if (ai == null) return;
    final repo = context.read<FlashcardRepository?>();
    final answer = _correctAnswerText;
    setState(() => _ladderHintsLoading = true);
    try {
      while (hints.length < due) {
        hints.add(await ai.generateHint(question: card.promptText, correctAnswer: answer, previousHints: hints));
        if (mounted) setState(() => _ladderHints = List.of(hints));
      }
      await repo?.updateHints(card.id, hints, type: card.type, front: card.front);
    } catch (e) {
      if (mounted) setState(() => _aiHelpError = e is AiServiceException ? e.message : 'Hilfestellung fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _ladderHintsLoading = false);
    }
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
    for (final c in [..._blankControllers, ..._labelInputs, ..._tableControllers]) {
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
      case QuestionType.learn:
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
      case QuestionType.diagramLabel:
        if (_labelTargets.isEmpty) return false;
        return _labelTyping ? _labelInputs.every((c) => c.text.trim().isNotEmpty) : _labelPool.isEmpty;
      case QuestionType.markImage:
        return _markTap != null;
      case QuestionType.table:
        return _tableControllers.any((c) => c.text.trim().isNotEmpty);
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
      case QuestionType.diagramLabel:
        return _checkDiagramLabelAnswer();
      case QuestionType.markImage:
        return AnswerChecker.checkMarkImage(card, _markTap?.dx, _markTap?.dy);
      case QuestionType.table:
        return _checkTableAnswer();
      case QuestionType.flashcard:
      case QuestionType.learn:
      case QuestionType.html:
        return null; // eigene build()-Zweige.
    }
  }

  /// Tabelle, zweistufig wie der Lückentext: zuerst lokal je Zelle, lehnt das
  /// Zellen ab, prüft die KI diese nach (die Tabelle als Text mit "___" an
  /// den fraglichen Stellen) – sie kann nur nachträglich als richtig werten.
  /// Danach Teilpunkte: alle richtig = richtig, ab 80 % "Schwer".
  Future<AnswerCheckResult> _checkTableAnswer() async {
    final card = widget.card;
    final answers = _tableControllers.map((c) => c.text).toList();
    var hits = AnswerChecker.tableHits(card, answers);
    final wrong = [for (var i = 0; i < hits.length; i++) if (!hits[i] && answers[i].trim().isNotEmpty) i];
    final ai = wrong.isEmpty ? null : _aiOrNull();
    final notes = List<String?>.filled(hits.length, null);
    if (ai != null) {
      setState(() => _aiChecking = true);
      try {
        final wrongCells = {for (final i in wrong) (_tableBlanks[i].row, _tableBlanks[i].col)};
        final rows = card.tableRows ?? const <List<QuestionTableCell>>[];
        final text = [
          card.front,
          for (var r = 0; r < rows.length; r++)
            [
              for (var col = 0; col < rows[r].length; col++)
                wrongCells.contains((r, col)) ? '___' : rows[r][col].text,
            ].join(' | '),
        ].join('\n');
        final verdicts = await ai.checkFillBlankAnswers(
          text: text,
          solutions: [for (final i in wrong) _tableBlanks[i].solution],
          answers: [for (final i in wrong) answers[i]],
        );
        for (final (k, i) in wrong.indexed) {
          final verdict = verdicts.elementAtOrNull(k);
          if (verdict == null) continue;
          notes[i] = verdict.note;
          if (verdict.correct) hits = [...hits]..[i] = true;
        }
        _checkInfo = 'Von der KI nachgeprüft.';
      } catch (e) {
        _checkInfo = _aiFailedInfo(e);
      } finally {
        if (mounted) setState(() => _aiChecking = false);
      }
    }
    final result = AnswerChecker.tableResult(card, hits);
    _tableHits = hits;
    _tableNotes = notes;
    _tablePartial = result.partial;
    _tableRight = hits.where((h) => h).length;
    return result.result;
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
      _checkInfo = aiCorrect ? 'Von der KI als richtig erkannt.' : 'Von der KI nachgeprüft.';
      return AnswerCheckResult(isCorrect: aiCorrect, correctAnswerLabel: localResult.correctAnswerLabel);
    } catch (e) {
      _checkInfo = _aiFailedInfo(e);
      return localResult;
    } finally {
      if (mounted) setState(() => _aiChecking = false);
    }
  }

  static String _aiFailedInfo(Object error) {
    var reason = error is AiServiceException ? error.message : '$error';
    if (reason.length > 120) reason = '${reason.substring(0, 120)}…';
    return 'KI-Prüfung fehlgeschlagen, gewertet wurde nur der Textvergleich ($reason).';
  }

  /// Lückentext, zweistufig wie Freitext: zuerst lokal je Lücke (exakt,
  /// kleiner Tippfehler oder eine der per ";" hinterlegten Varianten). Lehnt
  /// das eine Lücke ab, bewertet die KI den ganzen Satz nach
  /// (AiService.checkFillBlankAnswers) – gröbere Rechtschreibfehler,
  /// vertauschte gleichrangige Lücken, Synonyme, andere richtige Begriffe.
  /// Die KI kann eine Lücke nur nachträglich als richtig werten, nie eine
  /// lokal richtige verwerfen. Ohne API-Key oder bei einem Fehler zählt das
  /// lokale Ergebnis – und der Fehler wird angezeigt.
  Future<AnswerCheckResult> _checkFillBlankAnswer() async {
    final card = widget.card;
    final answers = _blankControllers.map((c) => c.text).toList();
    var hits = AnswerChecker.fillBlankHits(card, answers);
    final ai = hits.every((h) => h) ? null : _aiOrNull();
    if (ai != null) {
      setState(() => _aiChecking = true);
      try {
        final verdicts = await ai.checkFillBlankAnswers(text: card.front, solutions: _blanks, answers: answers);
        _blankNotes = [
          for (var i = 0; i < hits.length; i++) hits[i] ? null : verdicts.elementAtOrNull(i)?.note,
        ];
        hits = [for (var i = 0; i < hits.length; i++) hits[i] || (verdicts.elementAtOrNull(i)?.correct ?? false)];
        _checkInfo = 'Von der KI nachgeprüft.';
      } catch (e) {
        _checkInfo = _aiFailedInfo(e);
      } finally {
        if (mounted) setState(() => _aiChecking = false);
      }
    }
    _blankHits = hits;
    return AnswerChecker.fillBlankResult(card, hits);
  }

  /// Bild beschriften. Zuordnen: es zählt der Text der abgelegten
  /// Beschriftung. Eintippen: lokal mit Tippfehler-Toleranz; lehnt das eine
  /// Stelle ab, prüft die KI nach (Rechtschreibung egal, Synonyme,
  /// Abkürzungen) – wie beim Lückentext kann sie nur nachträglich als
  /// richtig werten. Austauschbare Stellen (gleiche Gruppe) nehmen jede
  /// Beschriftung ihrer Gruppe, jede aber nur einmal.
  Future<AnswerCheckResult> _checkDiagramLabelAnswer() async {
    final card = widget.card;
    final answers = _labelTyping
        ? {for (var i = 0; i < _labelInputs.length; i++) i: _labelInputs[i].text}
        : {for (final e in _zoneToLabel.entries) e.key: _labelTargets[e.value].label};
    final zones = AnswerChecker.diagramLabelZones(card, answers, tolerant: _labelTyping);
    final wrong = [for (var i = 0; i < zones.length; i++) if (!zones[i].correct) i];
    final ai = _labelTyping && wrong.isNotEmpty ? _aiOrNull() : null;
    if (ai != null) {
      setState(() => _aiChecking = true);
      try {
        final verdicts = await ai.checkDiagramLabelAnswers(
          question: card.front,
          items: [
            for (final z in wrong)
              (zone: z + 1, allowed: zones[z].allowed, answer: answers[z] ?? '', group: _labelTargets[z].group),
          ],
        );
        final notes = List<String?>.filled(zones.length, null);
        for (final (k, z) in wrong.indexed) {
          final verdict = verdicts.elementAtOrNull(k);
          if (verdict == null) continue;
          notes[z] = verdict.note;
          if (verdict.correct) zones[z] = (correct: true, allowed: zones[z].allowed);
        }
        _labelNotes = notes;
        _checkInfo = 'Von der KI nachgeprüft.';
      } catch (e) {
        _checkInfo = _aiFailedInfo(e);
      } finally {
        if (mounted) setState(() => _aiChecking = false);
      }
    }
    _labelResults = zones;
    return AnswerCheckResult(
      isCorrect: zones.isNotEmpty && zones.every((z) => z.correct),
      correctAnswerLabel: AnswerChecker.diagramLabelSolution(card),
    );
  }

  /// Sicherheitsnetz für Freitext/Lückentext: hält der Nutzer eine als falsch
  /// gewertete Antwort für richtig (Formulierung, Rechtschreibung, andere
  /// Reihenfolge – auch die KI kann danebenliegen), zählt sie als richtig.
  void _acceptAsCorrect() {
    final result = _result;
    if (result == null || result.isCorrect) return;
    setState(() {
      _result = AnswerCheckResult(isCorrect: true, correctAnswerLabel: result.correctAnswerLabel);
      if (_blankHits != null) _blankHits = List.filled(_blankHits!.length, true);
      if (_tableHits != null) {
        _tableHits = List.filled(_tableHits!.length, true);
        _tableRight = _tableHits!.length;
        _tablePartial = false;
      }
      _labelResults = _labelResults?.map((z) => (correct: true, allowed: z.allowed)).toList();
      _checkInfo = 'Von dir als richtig gewertet.';
    });
  }

  bool get _canAcceptAsCorrect =>
      _checked &&
      !widget.examMode &&
      _result != null &&
      !_result!.isCorrect &&
      (widget.card.type == QuestionType.freeText ||
          widget.card.type == QuestionType.fillBlank ||
          widget.card.type == QuestionType.table ||
          (widget.card.type == QuestionType.diagramLabel && _labelTyping));

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
      case QuestionType.diagramLabel:
        if (_labelTyping) {
          return [for (var i = 0; i < _labelInputs.length; i++) '${i + 1} = ${_labelInputs[i].text.trim()}'].join(', ');
        }
        final zones = _zoneToLabel.keys.toList()..sort();
        return [for (final z in zones) '${z + 1} = ${_labelTargets[_zoneToLabel[z]!].label}'].join(', ');
      case QuestionType.markImage:
        final tap = _markTap;
        return tap == null
            ? null
            : 'angetippte Stelle bei ${(tap.dx * 100).round()} % Breite, ${(tap.dy * 100).round()} % Höhe';
      case QuestionType.table:
        final rows = card.tableRows ?? const <List<QuestionTableCell>>[];
        String header(int col) => rows.isNotEmpty && col < rows.first.length ? rows.first[col].text : '';
        return [
          for (var i = 0; i < _tableBlanks.length; i++)
            if (_tableControllers[i].text.trim().isNotEmpty)
              '${[rows[_tableBlanks[i].row].first.text, header(_tableBlanks[i].col)].where((s) => s.isNotEmpty).join(' / ')}: '
                  '${_tableControllers[i].text.trim()}',
        ].join('; ');
      case QuestionType.flashcard:
      case QuestionType.learn:
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
      final hint = await ai.generateHint(question: widget.card.promptText, correctAnswer: _correctAnswerText);
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
        question: widget.card.promptText,
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

  /// "Im Skript" (jederzeit, auch ohne KI) + "Tipp" vor dem Antworten – ein
  /// Denkanstoß ohne Lösung. Eine danach richtige Antwort zählt nur als
  /// "Schwer" (siehe [QuestionAnswerView.onComplete]).
  Widget _buildHintArea(AppColors c) {
    if (widget.examMode) return const SizedBox.shrink();
    final hint = _hint;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_ladderHints.isNotEmpty || _ladderHintsLoading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                key: const ValueKey('ladder-hints'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diese Frage ging zuletzt ${widget.card.variantMissStreak}× in Folge schief – '
                    'deshalb eine Hilfestellung:',
                    style: TextStyle(fontSize: 12, color: c.inkMuted),
                  ),
                  for (var i = 0; i < _ladderHints.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _AiHelpBox(
                        icon: i == 0 ? Icons.lightbulb_outline : Icons.tips_and_updates_outlined,
                        text: _ladderHints.length > 1 ? 'Hilfestellung ${i + 1}: ${_ladderHints[i]}' : _ladderHints[i],
                        color: c.warn,
                        background: c.warnSoft,
                      ),
                    ),
                  if (_ladderHintsLoading)
                    Padding(padding: const EdgeInsets.only(top: 6), child: _smallSpinner()),
                ],
              ),
            ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SourceLinkButton(card: widget.card),
              if (_aiHelpAvailable && hint == null)
                TextButton.icon(
                  onPressed: _hintLoading ? null : _loadHint,
                  icon: _hintLoading ? _smallSpinner() : const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Tipp'),
                ),
            ],
          ),
          if (_aiHelpAvailable && hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _AiHelpBox(icon: Icons.lightbulb_outline, text: hint, color: c.warn, background: c.warnSoft),
            ),
          if (_aiHelpAvailable && _aiHelpError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_aiHelpError!, style: TextStyle(fontSize: 12, color: c.danger)),
            ),
        ],
      ),
    );
  }

  /// Nach dem Antworten: Stelle im Skript, kurze Lerneinheit und – bei
  /// Karten, die öfter schiefgehen – der Sokrates-Dialog.
  Widget _buildStudyAids() {
    final wrong = _result?.isCorrect == false;
    final selfGraded = _result == null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: StudyAidsBar(
        card: widget.card,
        aiAvailable: _aiHelpAvailable,
        wrongAnswer: wrong ? _userAnswerText : null,
        suggestSocratic: selfGraded
            ? WeaknessService.oftenWrong(widget.card)
            : wrong && WeaknessService.oftenWrong(widget.card, wrongNow: true),
      ),
    );
  }

  /// "Erklär mir das" nach dem Antworten, danach optional "Einfacher erklären".
  Widget _buildExplainArea(AppColors c) {
    if (widget.examMode) return const SizedBox.shrink();
    if (!_aiHelpAvailable) return _buildStudyAids();
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
          ExplainChat(
            question: widget.card.promptText,
            correctAnswer: _correctAnswerText,
            userAnswer: _userAnswerText,
            wasCorrect: _result?.isCorrect,
            explanation: explanation,
          ),
          _buildStudyAids(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.card.type == QuestionType.flashcard || widget.card.type == QuestionType.learn || !_answerable) {
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
        if (!_checked && !widget.examMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Align(alignment: Alignment.centerLeft, child: SourceLinkButton(card: widget.card)),
          ),
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
    // Lernaufgabe: lange Aufgabe links, Erklärung darunter, Bewertung "wie
    // gut verstanden" statt "gewusst".
    final learn = widget.card.type == QuestionType.learn;
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
                          if (learn)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                                child: Text(
                                  'Aufgabe zum Verstehen',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft),
                                ),
                              ),
                            ),
                          _buildCardImage(c),
                          MathText(
                            // Ersatzansicht (z.B. Zuordnen mit nur einem
                            // Ziel): mit den Begriffen/Optionen, sonst wüsste
                            // man nicht, worum es geht.
                            widget.card.type == QuestionType.flashcard || learn
                                ? widget.card.front
                                : widget.card.promptText,
                            textAlign: learn ? TextAlign.start : TextAlign.center,
                            style: TextStyle(fontSize: learn ? 16 : 19, fontWeight: FontWeight.w600, height: 1.45),
                          ),
                          if (_showBack) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Divider(height: 1, color: c.border),
                            ),
                            if (learn)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Erklärung / Lösungsweg',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted),
                                ),
                              ),
                            MathText(
                              _backText,
                              textAlign: learn ? TextAlign.start : TextAlign.center,
                              style: TextStyle(fontSize: learn ? 14.5 : 15, height: 1.6, color: learn ? c.ink : c.inkMuted),
                            ),
                          ] else ...[
                            const SizedBox(height: 16),
                            Text(learn ? 'Zur Erklärung tippen' : 'Zum Umdrehen tippen',
                                style: TextStyle(fontSize: 12, color: c.inkMuted)),
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
        if (_showBack && learn)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Text(
              'Wie gut hast du die Aufgabe verstanden?',
              style: TextStyle(fontSize: 12.5, color: context.colors.inkMuted),
            ),
          ),
        if (_showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            child: Row(
              children: [
                Expanded(
                    child: _ActionButton(
                        label: learn ? 'Unklar' : 'Nochmal',
                        fg: c.danger,
                        bg: c.dangerSoft,
                        onTap: () => _submit(selfGrade: Grade.again))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: learn ? 'Teilweise' : 'Schwer',
                        fg: c.warn,
                        bg: c.warnSoft,
                        onTap: () => _submit(selfGrade: Grade.hard))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: learn ? 'Verstanden' : 'Gut',
                        fg: c.good,
                        bg: c.goodSoft,
                        onTap: () => _submit(selfGrade: Grade.good))),
                const SizedBox(width: 9),
                Expanded(
                    child: _ActionButton(
                        label: learn ? 'Sicher' : 'Leicht',
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
    final summary = card.answerSummary.trim();
    final back = card.back.trim();
    // Bei Ersatzansichten ist die Lösung (z.B. die Zuordnung) wichtiger als
    // die Erklärung – beides zeigen.
    if (card.type != QuestionType.flashcard && card.type != QuestionType.html && summary.isNotEmpty) {
      return back.isEmpty || back == summary ? summary : '$summary\n\n$back';
    }
    if (back.isNotEmpty) return card.back;
    return summary.isNotEmpty ? summary : '(Keine Lösung hinterlegt)';
  }

  /// Hier bearbeitetes Bild (ersetzt die Anzeige sofort, gespeichert wird
  /// über [QuestionAnswerView.onImageEdited]).
  Uint8List? _editedImage;
  bool _imageRemoved = false;

  /// Bild unnötig angehängt (die KI hängt lieber einmal zu oft eines an):
  /// nach Rückfrage aus der Karte entfernen.
  Future<void> _removeCardImage() async {
    final save = widget.onImageEdited;
    if (save == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bild entfernen?'),
        content: const Text('Das Bild wird aus dieser Frage gelöscht – die Frage selbst bleibt.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Entfernen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _imageRemoved = true);
    await save(null);
  }

  Future<void> _editCardImage(Uint8List bytes) async {
    final save = widget.onImageEdited;
    if (save == null) return;
    final result = await showImageEditor(context, bytes);
    if (result == null || !result.imageChanged || !mounted) return;
    setState(() => _editedImage = result.bytes);
    await save(result.bytes);
  }

  /// Zeigt den an [Flashcard.imageBase64] hängenden Seiten-Screenshot,
  /// falls vorhanden (siehe PageQuestionCreationSheet – nur bei Fragen
  /// gesetzt, die das Vision-Modell als "needsImage" markiert hat, z.B. weil
  /// sie sich auf ein Diagramm/eine Grafik beziehen). Ein defektes Base64
  /// wird still ignoriert statt die Karte unbenutzbar zu machen.
  /// Mit [QuestionAnswerView.onImageEdited] lässt es sich beim Lernen
  /// bearbeiten (z.B. eine Beschriftung abdecken, die die Antwort verrät).
  Widget _buildCardImage(AppColors c) {
    final bytes = _editedImage ?? _imageBytes;
    if (bytes == null || _imageRemoved) return const SizedBox.shrink();
    final canEdit = widget.onImageEdited != null && !widget.examMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          ),
          if (canEdit)
            Positioned(
              top: 4,
              right: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Bild entfernen',
                    visualDensity: VisualDensity.compact,
                    onPressed: _removeCardImage,
                    icon: const Icon(Icons.hide_image_outlined, size: 18),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Bild bearbeiten (z.B. Antwort abdecken)',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editCardImage(bytes),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
            ),
        ],
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
              if (!_isImageQuestion) _buildCardImage(c),
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
              isCorrect: _result!.isCorrect || _tablePartial,
              // Mit Tipp richtig bzw. Tabelle fast richtig: zählt, aber nur
              // als "Schwer" – die Ampel steigt dadurch nicht.
              selfGrade: _tablePartial || (_helpShown && _result!.isCorrect) ? Grade.hard : null,
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
      case QuestionType.learn:
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
      case QuestionType.diagramLabel:
        return _buildDiagramLabel(c);
      case QuestionType.markImage:
        return _buildMarkImage(c);
      case QuestionType.table:
        return _buildTable(c);
    }
  }

  /// Tabelle zum Ausfüllen: vorgegebene Zellen als Text, die übrigen als
  /// Eingabefelder; nach dem Prüfen je Zelle grün/rot und bei Bedarf die
  /// Lösung darunter. Breite Tabellen lassen sich seitlich scrollen.
  Widget _buildTable(AppColors c) {
    final rows = widget.card.tableRows ?? const <List<QuestionTableCell>>[];
    final columns = rows.fold<int>(0, (n, r) => max(n, r.length));
    final blankIndex = {for (var i = 0; i < _tableBlanks.length; i++) (_tableBlanks[i].row, _tableBlanks[i].col): i};

    Widget cell(int r, int col) {
      final data = col < rows[r].length ? rows[r][col] : const QuestionTableCell(text: '');
      final i = blankIndex[(r, col)];
      if (i == null) {
        return Padding(
          padding: const EdgeInsets.all(8),
          child: MathText(
            data.given ? data.text : '',
            style: TextStyle(fontSize: 13.5, fontWeight: r == 0 ? FontWeight.w700 : FontWeight.w500),
          ),
        );
      }
      final hit = _checked ? _tableHits?.elementAtOrNull(i) : null;
      final solution = _tableBlanks[i].solution;
      final showSolution = hit != null && !(hit && AnswerChecker.answerExactlyMatches(_tableControllers[i].text, solution));
      final note = _checked ? _tableNotes?.elementAtOrNull(i) : null;
      return Container(
        color: hit == null ? null : (hit ? c.goodSoft : c.dangerSoft),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: ValueKey('table-cell-$r-$col'),
              controller: _tableControllers[i],
              enabled: !_checked && !_aiChecking,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (showSolution)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MathText('Lösung: ${AnswerChecker.solutionLabel(solution)}',
                    style: TextStyle(fontSize: 11.5, color: c.ink)),
              ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('KI: $note', style: TextStyle(fontSize: 11, color: c.inkMuted)),
              ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(170),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        border: TableBorder.all(color: c.border, borderRadius: BorderRadius.circular(8)),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: r == 0 ? BoxDecoration(color: c.surfaceAlt) : null,
              children: [for (var col = 0; col < columns; col++) cell(r, col)],
            ),
        ],
      ),
    );
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
          final note = _checked ? _blankNotes?.elementAtOrNull(i) : null;
          final helper = [
            if (showSolution) 'Lösung: ${AnswerChecker.solutionLabel(_blanks[i])}',
            if (note != null) 'KI: $note',
          ].join(' · ');
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
                helperText: helper.isEmpty ? null : helper,
                helperMaxLines: 3,
              ),
              onChanged: (_) => setState(() {}),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Bildfragen
  // ---------------------------------------------------------------------

  /// Bild beschriften: Beschriftung [label] auf Stelle [zone] legen – eine
  /// dort liegende wandert zurück unter das Bild.
  void _placeLabel(int label, int zone) {
    if (_checked) return;
    setState(() {
      _selectedLabel = null;
      _zoneToLabel.removeWhere((_, l) => l == label);
      _labelPool.remove(label);
      final displaced = _zoneToLabel[zone];
      if (displaced != null && displaced != label && !_labelPool.contains(displaced)) _labelPool.add(displaced);
      _zoneToLabel[zone] = label;
    });
  }

  void _returnLabel(int label) {
    if (_checked) return;
    setState(() {
      _selectedLabel = null;
      _zoneToLabel.removeWhere((_, l) => l == label);
      if (!_labelPool.contains(label)) _labelPool.add(label);
    });
  }

  Widget _labelChip(AppColors c, int label, {String? prefix, Color? color}) {
    final selected = _selectedLabel == label && prefix == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? (selected ? c.accentSolid : c.accentSoft),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.surface, width: 1.5),
      ),
      child: Text(
        '${prefix ?? ''}${_labelTargets[label].label}',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: color != null ? Colors.white : (selected ? c.accentInk : c.accentOnSoft),
        ),
      ),
    );
  }

  /// Stelle [zone] im Bild: leer eine nummerierte Markierung, belegt die
  /// abgelegte Beschriftung (verschiebbar, Antippen legt sie zurück).
  Color? _zoneVerdict(AppColors c, int zone) {
    final result = _checked ? _labelResults?.elementAtOrNull(zone) : null;
    return result == null ? null : (result.correct ? c.good : c.danger);
  }

  /// Nummerierte Markierung einer Stelle (Eintippen bzw. noch leer).
  Widget _zoneNumber(AppColors c, int zone, {bool highlighted = false}) {
    final verdict = _zoneVerdict(c, zone);
    return Container(
      key: ValueKey('label-zone-$zone'),
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted ? c.accent : c.surface.withAlpha(235),
        shape: BoxShape.circle,
        border: Border.all(color: verdict ?? c.accent, width: 2),
      ),
      child: Text(
        '${zone + 1}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: highlighted ? c.accentInk : (verdict ?? c.accentOnSoft),
        ),
      ),
    );
  }

  Widget _labelZone(AppColors c, int zone) {
    if (_labelTyping) return _zoneNumber(c, zone);
    final assigned = _zoneToLabel[zone];
    final selected = _selectedLabel;
    final Color? verdict = _zoneVerdict(c, zone);
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => !_checked,
      onAcceptWithDetails: (details) => _placeLabel(details.data, zone),
      builder: (context, candidates, _) {
        final highlighted = !_checked && (candidates.isNotEmpty || selected != null);
        if (assigned != null) {
          final chip = _labelChip(c, assigned, prefix: '${zone + 1} · ', color: verdict ?? c.accent);
          if (_checked) return chip;
          return Draggable<int>(
            data: assigned,
            feedback: Material(color: Colors.transparent, child: chip),
            childWhenDragging: Opacity(opacity: 0.3, child: chip),
            child: GestureDetector(
              onTap: () => selected != null ? _placeLabel(selected, zone) : _returnLabel(assigned),
              child: chip,
            ),
          );
        }
        return GestureDetector(
          onTap: selected == null || _checked ? null : () => _placeLabel(selected, zone),
          child: _zoneNumber(c, zone, highlighted: highlighted),
        );
      },
    );
  }

  /// Was an Stelle [zone] richtig (gewesen) wäre, als Text.
  String _zoneSolution(int zone) {
    final allowed = _labelResults?.elementAtOrNull(zone)?.allowed ?? [_labelTargets[zone].label];
    return allowed.length > 1
        ? 'eine von ${allowed.map((a) => '„$a“').join(', ')}'
        : '„${allowed.firstOrNull ?? ''}“';
  }

  Widget _buildDiagramLabel(AppColors c) {
    final bytes = _imageBytes;
    if (bytes == null) return const SizedBox.shrink();
    final groups = {for (final t in _labelTargets) if (t.group.trim().isNotEmpty) t.group.trim()};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SegmentedButton<bool>(
            key: const ValueKey('label-mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.drag_indicator, size: 18), label: Text('Zuordnen')),
              ButtonSegment(value: true, icon: Icon(Icons.keyboard_outlined, size: 18), label: Text('Eintippen')),
            ],
            selected: {_labelTyping},
            onSelectionChanged:
                _checked || _aiChecking ? null : (value) => setState(() => _labelTyping = value.first),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _labelTyping
              ? 'Schreib zu jeder Nummer, was dort hingehört – Rechtschreibung ist egal.'
              : 'Ziehe die Beschriftungen auf die nummerierten Stellen im Bild – oder antippen und dann die Stelle antippen.',
          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
        ),
        if (groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Stellen derselben Gruppe (${groups.join(', ')}) sind austauschbar – dort zählt nur, dass alles '
              'im richtigen Bereich steht, nicht die Reihenfolge.',
              style: TextStyle(fontSize: 12, color: c.inkMuted),
            ),
          ),
        const SizedBox(height: 12),
        RelativeImage(
          bytes: bytes,
          overlayBuilder: (context, box) => [
            for (var zone = 0; zone < _labelTargets.length; zone++)
              positionedAt(
                box: box,
                x: _labelTargets[zone].x,
                y: _labelTargets[zone].y,
                child: _labelZone(c, zone),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_labelTyping) ..._buildLabelInputs(c) else ..._buildLabelPool(c),
      ],
    );
  }

  List<Widget> _buildLabelPool(AppColors c) => [
        DragTarget<int>(
          onWillAcceptWithDetails: (details) => !_checked && !_labelPool.contains(details.data),
          onAcceptWithDetails: (details) => _returnLabel(details.data),
          builder: (context, candidates, _) => Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 40),
            decoration: candidates.isNotEmpty
                ? BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14))
                : null,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in _labelPool)
                  if (_checked)
                    _labelChip(c, label)
                  else
                    Draggable<int>(
                      data: label,
                      feedback: Material(color: Colors.transparent, child: _labelChip(c, label)),
                      childWhenDragging: Opacity(opacity: 0.3, child: _labelChip(c, label)),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedLabel = _selectedLabel == label ? null : label),
                        child: _labelChip(c, label),
                      ),
                    ),
              ],
            ),
          ),
        ),
        if (_checked)
          for (var zone = 0; zone < _labelTargets.length; zone++)
            if (_labelResults?.elementAtOrNull(zone)?.correct == false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Stelle ${zone + 1}: richtig ist ${_zoneSolution(zone)}',
                  style: TextStyle(fontSize: 12.5, color: c.good, fontWeight: FontWeight.w600),
                ),
              ),
      ];

  /// Eintippen: je Stelle ein Feld; nach dem Prüfen ✓/✗, die richtige
  /// Beschriftung (auch wenn nur dank Tippfehler-Toleranz/KI richtig) und
  /// ggf. die Begründung der KI.
  List<Widget> _buildLabelInputs(AppColors c) => [
        for (var zone = 0; zone < _labelTargets.length; zone++)
          Builder(builder: (context) {
            final result = _checked ? _labelResults?.elementAtOrNull(zone) : null;
            final typed = _labelInputs[zone].text;
            final exact = result != null &&
                result.correct &&
                result.allowed.any((a) => AnswerChecker.answerExactlyMatches(typed, a));
            final note = _checked ? _labelNotes?.elementAtOrNull(zone) : null;
            final helper = [
              if (result != null && !exact) 'Richtig: ${_zoneSolution(zone)}',
              if (note != null) 'KI: $note',
            ].join(' · ');
            final group = _labelTargets[zone].group.trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: ValueKey('label-input-$zone'),
                controller: _labelInputs[zone],
                enabled: !_checked && !_aiChecking,
                textInputAction: zone == _labelTargets.length - 1 ? TextInputAction.done : TextInputAction.next,
                decoration: InputDecoration(
                  labelText: group.isEmpty ? 'Stelle ${zone + 1}' : 'Stelle ${zone + 1} · $group',
                  filled: true,
                  fillColor: result == null ? c.surfaceAlt : (result.correct ? c.goodSoft : c.dangerSoft),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  suffixIcon: result == null
                      ? null
                      : Icon(result.correct ? Icons.check_circle : Icons.cancel,
                          color: result.correct ? c.good : c.danger, size: 20),
                  helperText: helper.isEmpty ? null : helper,
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
              ),
            );
          }),
      ];

  /// Bild markieren: Antippen setzt die Markierung (bis zum Prüfen
  /// verschiebbar); danach erscheinen die richtigen Bereiche grün.
  Widget _buildMarkImage(AppColors c) {
    final bytes = _imageBytes;
    if (bytes == null) return const SizedBox.shrink();
    final tap = _markTap;
    final Color markerColor = !_checked ? c.accent : ((_result?.isCorrect ?? false) ? c.good : c.danger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tippe auf die richtige Stelle im Bild.', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
        const SizedBox(height: 12),
        RelativeImage(
          key: const ValueKey('mark-image'),
          bytes: bytes,
          onTapRelative: _checked ? null : (p) => setState(() => _markTap = p),
          overlayBuilder: (context, box) => [
            if (_checked)
              for (final r in AnswerChecker.markRegions(widget.card))
                Positioned(
                  left: (r.x - r.w / 2) * box.width,
                  top: (r.y - r.h / 2) * box.height,
                  width: r.w * box.width,
                  height: r.h * box.height,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.good.withAlpha(45),
                        border: Border.all(color: c.good, width: 3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
            if (tap != null)
              positionedAt(
                box: box,
                x: tap.dx,
                y: tap.dy,
                child: IgnorePointer(child: Icon(Icons.adjust, key: const ValueKey('mark-marker'), size: 32, color: markerColor)),
              ),
          ],
        ),
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
    final isTable = widget.card.type == QuestionType.table;
    final fg = result.isCorrect ? c.good : (_tablePartial ? c.warn : c.danger);
    final title = result.isCorrect
        ? 'Richtig!'
        : isTable
            ? '$_tableRight von ${_tableBlanks.length} Zellen richtig'
                '${_tablePartial ? ' – fast, zählt als "Schwer".' : '.'}'
            : 'Nicht ganz.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: result.isCorrect ? c.goodSoft : (_tablePartial ? c.warnSoft : c.dangerSoft),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
                // Bei Tabellen stehen die Lösungen direkt in den Zellen.
                if (!result.isCorrect && !isTable && result.correctAnswerLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  MathText('Richtige Antwort: ${result.correctAnswerLabel}', style: TextStyle(fontSize: 13, color: c.ink)),
                ],
                if (_checkInfo != null) ...[
                  const SizedBox(height: 6),
                  Text(_checkInfo!, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                ],
                if (_canAcceptAsCorrect) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _acceptAsCorrect,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Als richtig werten'),
                    ),
                  ),
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
