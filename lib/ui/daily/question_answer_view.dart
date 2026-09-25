import 'dart:convert';

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
  });

  final Flashcard card;
  final bool isNew;

  /// Genau eines von beidem wird gesetzt: [selfGrade] für den offenen
  /// `flashcard`-Typ, [isCorrect] für alle automatisch geprüften Typen.
  final void Function({Grade? selfGrade, bool? isCorrect}) onComplete;

  @override
  State<QuestionAnswerView> createState() => _QuestionAnswerViewState();
}

class _QuestionAnswerViewState extends State<QuestionAnswerView> {
  bool _showBack = false;

  int? _selectedIndex;
  final Set<int> _selectedIndices = {};
  final _freeTextController = TextEditingController();
  late List<TextEditingController> _blankControllers;

  late List<String> _pool;
  final Map<String, String> _assignments = {};

  bool _checked = false;
  AnswerCheckResult? _result;

  /// true, während für eine Freitext-Antwort auf die KI-Zweitmeinung
  /// gewartet wird (siehe [_checkFreeTextAnswer]) – deaktiviert währenddessen
  /// den "Prüfen"-Button, damit nicht doppelt angefragt wird.
  bool _freeTextAiChecking = false;

  // -- html-Typ: interaktive Seite in einer sandboxed WebView -------------
  WebViewController? _webViewController;
  bool _webViewLoading = true;

  /// false, sobald die Seite nicht geladen werden konnte ODER die Plattform
  /// gar keine WebView unterstützt (nur Android/iOS, siehe webview_flutter) –
  /// zeigt dann stattdessen [_buildFlashcard] als Fallback mit
  /// Selbstbewertung (front/back sind bei diesem Typ genau dafür gedacht).
  bool _webViewAvailable = true;

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

  bool get _isCategoryDrag => widget.card.type == QuestionType.dragCategory;

  @override
  void initState() {
    super.initState();
    final blanksCount = widget.card.blanks?.length ?? 0;
    _blankControllers = List.generate(blanksCount, (_) => TextEditingController());
    _pool = (widget.card.dragPairs ?? const []).map((p) => p.source).toList()..shuffle();
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
  void _handleHtmlAnswerMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message);
      if (data is Map && data['correct'] is bool) {
        _submit(isCorrect: data['correct'] as bool);
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

  List<String> get _dropZones {
    final pairs = widget.card.dragPairs ?? const [];
    if (_isCategoryDrag) {
      final seen = <String>{};
      final zones = <String>[];
      for (final p in pairs) {
        if (seen.add(p.target)) zones.add(p.target);
      }
      return zones;
    }
    return pairs.map((p) => p.target).toList();
  }

  void _placeInZone(String source, String zone) {
    if (_checked) return;
    setState(() {
      _assignments.removeWhere((k, v) => _isCategoryDrag ? k == source : v == source);
      _pool.remove(source);
      if (_isCategoryDrag) {
        _assignments[source] = zone;
      } else {
        // Belegtes Ziel: der bisherige Begriff muss zurück in den Pool,
        // sonst verschwände er aus der Oberfläche und wäre nicht mehr
        // zuordenbar.
        final displaced = _assignments[zone];
        if (displaced != null && displaced != source && !_pool.contains(displaced)) {
          _pool.add(displaced);
        }
        _assignments[zone] = source;
      }
    });
  }

  void _returnToPool(String source) {
    if (_checked) return;
    setState(() {
      _assignments.removeWhere((k, v) => _isCategoryDrag ? k == source : v == source);
      if (!_pool.contains(source)) _pool.add(source);
    });
  }

  bool get _canCheck {
    if (_freeTextAiChecking) return false;
    switch (widget.card.type) {
      case QuestionType.flashcard:
        return false;
      case QuestionType.singleChoice:
        return _selectedIndex != null;
      case QuestionType.multipleChoice:
        return true;
      case QuestionType.freeText:
        return _freeTextController.text.trim().isNotEmpty;
      case QuestionType.fillBlank:
        return _blankControllers.every((c) => c.text.trim().isNotEmpty);
      case QuestionType.dragDrop:
      case QuestionType.dragCategory:
        return _pool.isEmpty;
      case QuestionType.html:
        return false; // eigener build()-Zweig, siehe _buildHtmlQuestion.
    }
  }

  Future<void> _check() async {
    final card = widget.card;
    if (card.type == QuestionType.freeText) {
      await _checkFreeTextAnswer();
      return;
    }
    final AnswerCheckResult result;
    switch (card.type) {
      case QuestionType.singleChoice:
        result = AnswerChecker.checkSingleChoice(card, _selectedIndex);
      case QuestionType.multipleChoice:
        result = AnswerChecker.checkMultipleChoice(card, _selectedIndices);
      case QuestionType.fillBlank:
        result = AnswerChecker.checkFillBlank(card, _blankControllers.map((c) => c.text).toList());
      case QuestionType.dragDrop:
        result = AnswerChecker.checkDragDrop(card, Map.of(_assignments));
      case QuestionType.dragCategory:
        result = AnswerChecker.checkDragCategory(card, Map.of(_assignments));
      case QuestionType.freeText:
      case QuestionType.flashcard:
      case QuestionType.html:
        return; // freeText: siehe oben; flashcard/html: eigene build()-Zweige.
    }
    setState(() {
      _checked = true;
      _result = result;
    });
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
  Future<void> _checkFreeTextAnswer() async {
    final card = widget.card;
    final localResult = AnswerChecker.checkFreeText(card, _freeTextController.text);
    if (localResult.isCorrect) {
      setState(() {
        _checked = true;
        _result = localResult;
      });
      return;
    }

    final settings = context.read<SettingsRepository>().settings;
    if (!settings.hasApiKey) {
      setState(() {
        _checked = true;
        _result = localResult;
      });
      return;
    }

    setState(() => _freeTextAiChecking = true);
    try {
      final ai = AiService(apiKey: settings.openRouterApiKey!, model: settings.questionModelId);
      final aiCorrect = await ai.checkFreeTextAnswer(
        question: card.front,
        correctAnswer: card.correctText ?? '',
        userAnswer: _freeTextController.text,
      );
      if (!mounted) return;
      setState(() {
        _checked = true;
        _freeTextAiChecking = false;
        _result = AnswerCheckResult(isCorrect: aiCorrect, correctAnswerLabel: localResult.correctAnswerLabel);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checked = true;
        _freeTextAiChecking = false;
        _result = localResult;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.card.type == QuestionType.flashcard) {
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
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
                      Text(
                        widget.card.front,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, height: 1.45),
                      ),
                      if (_showBack) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Divider(height: 1, color: c.border),
                        ),
                        Text(
                          widget.card.back,
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
                child: Text(card.type.label,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.accentOnSoft, letterSpacing: 0.03)),
              ),
              const SizedBox(height: 12),
              _buildCardImage(c),
              if (card.type != QuestionType.fillBlank)
                Text(card.front, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
              const SizedBox(height: 16),
              _buildAnswerInput(c),
            ],
          ),
        ),
        if (_checked) ...[
          const SizedBox(height: 16),
          _buildFeedback(c),
        ],
        const SizedBox(height: 20),
        if (_checked)
          FilledButton(
            onPressed: () => _submit(isCorrect: _result!.isCorrect),
            child: const Text('Weiter'),
          )
        else
          FilledButton(
            onPressed: _canCheck ? _check : null,
            child: _freeTextAiChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Prüfen'),
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
          enabled: !_checked,
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
      children: List.generate(options.length, (i) {
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
                  Expanded(child: Text(option.text)),
                  if (trailingIcon != null) Icon(trailingIcon, size: 18, color: trailingColor),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFillBlank(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.card.front, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 16),
        ...List.generate(_blankControllers.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _blankControllers[i],
              enabled: !_checked,
              decoration: InputDecoration(
                labelText: 'Lücke ${i + 1}',
                filled: true,
                fillColor: c.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDragDrop(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isCategoryDrag ? 'Ordne jeden Begriff der richtigen Kategorie zu.' : 'Ziehe die Begriffe auf die passenden Ziele.',
          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _pool.map((source) => _dragChip(c, source)).toList(),
        ),
        const SizedBox(height: 16),
        ..._dropZones.map((zone) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _dropZone(c, zone),
            )),
      ],
    );
  }

  Widget _dragChip(AppColors c, String source) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
      child: Text(source, style: TextStyle(fontSize: 13, color: c.accentOnSoft, fontWeight: FontWeight.w600)),
    );
    if (_checked) return chip;
    return Draggable<String>(
      data: source,
      feedback: Material(color: Colors.transparent, child: chip),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }

  Widget _dropZone(AppColors c, String zone) {
    final pairs = widget.card.dragPairs ?? const [];
    // Zuordnen: genau ein Begriff pro Ziel. Kategorien: beliebig viele – ALLE
    // anzeigen (einzeln zurücklegbar, nach dem Prüfen einzeln eingefärbt),
    // sonst verschwänden weitere zugeordnete Begriffe unsichtbar.
    final assignedSources = _isCategoryDrag
        ? [for (final e in _assignments.entries) if (e.value == zone) e.key]
        : [if (_assignments[zone] != null) _assignments[zone]!];

    Color? tileColor;
    if (_checked && !_isCategoryDrag) {
      final correctSource =
          pairs.firstWhere((p) => p.target == zone, orElse: () => const DragPair(source: '', target: '')).source;
      tileColor = assignedSources.isNotEmpty && assignedSources.first == correctSource ? c.goodSoft : c.dangerSoft;
    }

    Widget assignedChip(String source) {
      final chipColor = _checked && _isCategoryDrag
          ? (pairs.any((p) => p.source == source && p.target == zone) ? c.goodSoft : c.dangerSoft)
          : c.surface;
      return GestureDetector(
        onTap: _checked ? null : () => _returnToPool(source),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(20)),
          child: Text(source, style: TextStyle(fontSize: 12.5, color: c.ink)),
        ),
      );
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => !_checked,
      onAcceptWithDetails: (details) => _placeInZone(details.data, zone),
      builder: (context, candidateData, rejectedData) {
        final label = Text(zone, style: const TextStyle(fontWeight: FontWeight.w600));
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: tileColor ?? (candidateData.isNotEmpty ? c.accentSoft : c.surfaceAlt),
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: _isCategoryDrag
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    if (assignedSources.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: assignedSources.map(assignedChip).toList()),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    if (assignedSources.isNotEmpty) assignedChip(assignedSources.first),
                  ],
                ),
        );
      },
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
                  Text('Richtige Antwort: ${result.correctAnswerLabel}', style: TextStyle(fontSize: 13, color: c.ink)),
                ],
              ],
            ),
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
