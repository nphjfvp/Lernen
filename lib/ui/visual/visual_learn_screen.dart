import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/material_item.dart';
import '../../models/visual_lesson.dart';
import '../../repositories/material_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/visual_lesson_repository.dart';
import '../../services/ai_service.dart';
import '../../services/image_crop.dart';
import '../../services/material_file_store.dart';
import '../../services/pdf_page_renderer.dart';
import '../../services/pdf_service.dart';
import '../../services/visual_math.dart';
import '../../theme/app_colors.dart';
import '../widgets/safe_set_state.dart';
import 'visual_lesson_screen.dart';

/// Welcher Teil einer PDF erklärt wird.
enum VisualScope { page, range, all }

/// Modus „Visuell lernen“ eines Fachs: gespeicherte Lektionen und „Neue
/// Lektion“ – aus einem Thema / eigenen Beispiel und/oder einer PDF (eine
/// Seite, ein Bereich oder alles), mit wählbarem Detailgrad.
class VisualLearnScreen extends StatefulWidget {
  const VisualLearnScreen({super.key, required this.moduleId, this.moduleName = ''});

  final String moduleId;
  final String moduleName;

  /// Test-Hooks: KI, PDF-Auswahl, Seitenbilder.
  static AiService? Function(String apiKey, String model)? aiFactory;
  static Future<({String name, Uint8List bytes})?> Function()? pickPdfHook;
  static Future<List<Uint8List>> Function(Uint8List pdf, List<int> pages)? renderPagesHook;

  /// Bis zu so vielen Seiten gehen auch als Bild an die KI (Formeln, Grafiken).
  static const maxImagePages = 4;

  @override
  State<VisualLearnScreen> createState() => _VisualLearnScreenState();
}

class _VisualLearnScreenState extends State<VisualLearnScreen> with SafeSetState<VisualLearnScreen> {
  final _topic = TextEditingController();
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController();
  List<VisualLesson> _lessons = const [];
  bool _loading = true;

  /// Gewählte PDF: aus dem Fach (Material-ID) oder hochgeladen.
  String? _materialId;
  ({String name, Uint8List bytes})? _upload;
  Uint8List? _pdfBytes;
  int _pageCount = 0;
  VisualScope _scope = VisualScope.page;
  String _detail = 'normal';
  VisualStyle _style = VisualStyle.explain;

  bool _busy = false;
  String _progress = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _topic.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await context.read<MaterialRepository?>()?.loadForModule(widget.moduleId);
    if (!mounted) return;
    final lessons = await context.read<VisualLessonRepository>().forModule(widget.moduleId);
    setState(() {
      _lessons = lessons;
      _loading = false;
    });
  }

  List<MaterialItem> get _pdfs => [
    for (final m in context.read<MaterialRepository?>()?.forModule(widget.moduleId) ?? const <MaterialItem>[])
      if (m.hasViewablePdf && m.fileName.toLowerCase().endsWith('.pdf')) m,
  ];

  Future<void> _choosePdf(MaterialItem? material) async {
    setState(() {
      _materialId = material?.id;
      _upload = null;
      _pdfBytes = null;
      _pageCount = 0;
    });
    if (material == null) return;
    final bytes = await MaterialFileStore.load(filePath: material.filePath, fileBytesBase64: material.fileBytesBase64);
    _setPdf(bytes);
  }

  Future<void> _uploadPdf() async {
    ({String name, Uint8List bytes})? picked;
    final hook = VisualLearnScreen.pickPdfHook;
    if (hook != null) {
      picked = await hook();
    } else {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      if (files.isEmpty) return;
      picked = (name: files.first.name, bytes: await files.first.readAsBytes());
    }
    if (picked == null) return;
    setState(() {
      _materialId = null;
      _upload = picked;
    });
    _setPdf(picked.bytes);
  }

  void _setPdf(Uint8List? bytes) {
    var count = 0;
    if (bytes != null) {
      try {
        count = PdfService().pageCount(bytes);
      } catch (_) {
        count = 0;
      }
    }
    setState(() {
      _pdfBytes = bytes;
      _pageCount = count;
      _error = bytes == null
          ? 'Die PDF ist auf diesem Gerät nicht verfügbar.'
          : (count == 0 ? 'Die PDF lässt sich nicht lesen.' : null);
      _from.text = '1';
      _to.text = '${count == 0 ? 1 : count}';
    });
  }

  String get _pdfName =>
      _upload?.name ?? _pdfs.where((m) => m.id == _materialId).map((m) => m.fileName).firstOrNull ?? 'PDF';

  /// Die gewählten Seiten (1-basiert).
  List<int> get _pages {
    if (_pdfBytes == null || _pageCount == 0) return const [];
    final from = (int.tryParse(_from.text.trim()) ?? 1).clamp(1, _pageCount);
    final to = (int.tryParse(_to.text.trim()) ?? from).clamp(from, _pageCount);
    return switch (_scope) {
      VisualScope.page => [from],
      VisualScope.range => [for (var p = from; p <= to; p++) p],
      VisualScope.all => [for (var p = 1; p <= _pageCount; p++) p],
    };
  }

  AiService? _ai({required bool vision}) {
    final settings = context.read<SettingsRepository?>()?.settings;
    if (settings == null || !settings.hasApiKey) return null;
    final model = vision ? settings.visionModelId : settings.questionModelId;
    return VisualLearnScreen.aiFactory?.call(settings.openRouterApiKey!, model) ??
        AiService(apiKey: settings.openRouterApiKey!, model: model);
  }

  Future<List<Uint8List>> _render(Uint8List pdf, List<int> pages) async {
    final hook = VisualLearnScreen.renderPagesHook;
    if (hook != null) return hook(pdf, pages);
    final renderer = await PdfPageRenderer.open(pdf, maxSide: 1400);
    if (renderer == null) return const [];
    try {
      final out = <Uint8List>[];
      for (final p in pages) {
        final png = await renderer.renderPng(p);
        if (png != null) out.add(await prepareImageForAi(png));
      }
      return out;
    } finally {
      await renderer.close();
    }
  }

  Future<void> _create() async {
    final pages = _pages;
    final topic = _topic.text.trim();
    if (topic.isEmpty && pages.isEmpty) {
      setState(() => _error = 'Gib ein Thema oder Beispiel ein – oder wähle eine PDF.');
      return;
    }
    final withImages = pages.isNotEmpty && pages.length <= VisualLearnScreen.maxImagePages;
    final ai = _ai(vision: withImages);
    if (ai == null) {
      setState(() => _error = 'Für „Visuell lernen“ braucht die App deinen OpenRouter-Key (Einstellungen).');
      return;
    }
    final repo = context.read<VisualLessonRepository>();
    setState(() {
      _busy = true;
      _error = null;
      _progress = pages.isEmpty ? 'Die KI baut die Lektion …' : 'PDF wird gelesen …';
    });
    try {
      var material = '';
      var images = const <Uint8List>[];
      if (pages.isNotEmpty) {
        final texts = PdfService().extractPageTexts(_pdfBytes!);
        material = [
          for (final p in pages)
            if (p - 1 < texts.length && texts[p - 1].trim().isNotEmpty) '--- Seite $p ---\n${texts[p - 1].trim()}',
        ].join('\n\n');
        if (withImages) images = await _render(_pdfBytes!, pages);
        if (material.isEmpty && images.isEmpty) {
          images = await _render(_pdfBytes!, pages.take(VisualLearnScreen.maxImagePages).toList());
        }
        setState(() => _progress = 'Die KI baut die Lektion …');
      }
      final maxLessons = switch (_scope) {
        _ when pages.isEmpty => 1,
        VisualScope.page => 1,
        VisualScope.range => pages.length > 3 ? 3 : 1,
        VisualScope.all => 6,
      };
      final raws = await ai.generateVisualLessons(
        topic: topic,
        material: material,
        images: images,
        detail: _detail,
        maxLessons: maxLessons,
        socratic: _style == VisualStyle.socratic,
      );
      final now = DateTime.now();
      final source = pages.isEmpty
          ? (topic.isEmpty ? '' : 'eigenes Beispiel')
          : '$_pdfName, ${pages.length == 1 ? 'S. ${pages.first}' : 'S. ${pages.first}–${pages.last}'}';
      final lessons = <VisualLesson>[
        for (final (i, raw) in raws.indexed)
          ?VisualLesson.fromMap(
            raw,
            id: const Uuid().v4(),
            moduleId: widget.moduleId,
            createdAt: now.add(Duration(milliseconds: raws.length - i)),
            source: source,
            detail: _detail,
            style: _style,
          ),
      ].map(VisualMath.sanitize).where((l) => l.isUsable).toList();
      if (lessons.isEmpty) {
        throw AiServiceException('Die KI-Antwort ließ sich nicht als Lektion lesen – bitte erneut versuchen.');
      }
      await repo.saveAll(lessons);
      if (!mounted) return;
      _topic.clear();
      await _load();
      if (!mounted) return;
      _open(lessons.first);
    } on AiServiceException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Das hat nicht geklappt: $e');
    } finally {
      setState(() {
        _busy = false;
        _progress = '';
      });
    }
  }

  void _open(VisualLesson lesson) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VisualLessonScreen(lesson: lesson)));

  Future<void> _delete(VisualLesson lesson) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lektion löschen?'),
        content: Text(lesson.title),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            key: const ValueKey('visual-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<VisualLessonRepository>().delete(lesson.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pdfs = _pdfs;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(widget.moduleName.isEmpty ? 'Visuell lernen' : 'Visuell lernen · ${widget.moduleName}'),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  'Die KI erklärt ein Thema Schritt für Schritt – die App simuliert es (z.B. ein Auto zu Weg und '
                  'Geschwindigkeit), zeigt Umformungen langsam und gibt dir danach eine Übung.',
                  style: TextStyle(color: c.inkMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                Text('Neue Lektion', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('visual-topic'),
                  controller: _topic,
                  minLines: 2,
                  maxLines: 6,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Thema, eigenes Beispiel oder Aufgabe (optional)',
                    hintText: 'z.B. „Ableitung: vom Weg zur Geschwindigkeit“ oder „∫ 2t dt mit einem Auto“',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Leer lassen: Die KI sucht sich selbst ein passendes Beispiel (zur PDF oder zum Fach).',
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<String?>(
                      key: const ValueKey('visual-material'),
                      value: _materialId,
                      hint: const Text('PDF aus dem Fach'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Keine PDF')),
                        for (final m in pdfs)
                          DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text(m.fileName, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _busy ? null : (id) => _choosePdf(pdfs.where((m) => m.id == id).firstOrNull),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('visual-upload'),
                      onPressed: _busy ? null : _uploadPdf,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(_upload == null ? 'PDF hochladen' : _upload!.name),
                    ),
                  ],
                ),
                if (_pdfBytes != null && _pageCount > 0) ...[
                  const SizedBox(height: 10),
                  Text('$_pdfName · $_pageCount Seiten', style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                  const SizedBox(height: 6),
                  SegmentedButton<VisualScope>(
                    key: const ValueKey('visual-scope'),
                    segments: const [
                      ButtonSegment(value: VisualScope.page, label: Text('Eine Seite')),
                      ButtonSegment(value: VisualScope.range, label: Text('Bereich')),
                      ButtonSegment(value: VisualScope.all, label: Text('Ganze PDF')),
                    ],
                    selected: {_scope},
                    showSelectedIcon: false,
                    onSelectionChanged: _busy ? null : (s) => setState(() => _scope = s.first),
                  ),
                  if (_scope != VisualScope.all) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: TextField(
                            key: const ValueKey('visual-page-from'),
                            controller: _from,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _scope == VisualScope.page ? 'Seite' : 'von Seite',
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (_scope == VisualScope.range) ...[
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              key: const ValueKey('visual-page-to'),
                              controller: _to,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'bis Seite',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Bei der ganzen PDF entstehen mehrere Lektionen (je Thema eine, höchstens 6).',
                        style: TextStyle(fontSize: 12, color: c.inkMuted),
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                Text(
                  'Wie genau?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  key: const ValueKey('visual-detail'),
                  segments: const [
                    ButtonSegment(value: 'kurz', label: Text('Kurz')),
                    ButtonSegment(value: 'normal', label: Text('Normal')),
                    ButtonSegment(value: 'ausführlich', label: Text('Ausführlich')),
                  ],
                  selected: {_detail},
                  showSelectedIcon: false,
                  onSelectionChanged: _busy ? null : (s) => setState(() => _detail = s.first),
                ),
                const SizedBox(height: 14),
                Text(
                  'Wie lernen?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted),
                ),
                const SizedBox(height: 6),
                SegmentedButton<VisualStyle>(
                  key: const ValueKey('visual-create-style'),
                  segments: const [
                    ButtonSegment(
                      value: VisualStyle.explain,
                      label: Text('Erklären'),
                      icon: Icon(Icons.menu_book_outlined),
                    ),
                    ButtonSegment(
                      value: VisualStyle.socratic,
                      label: Text('Sokratisch'),
                      icon: Icon(Icons.psychology_alt_outlined),
                    ),
                  ],
                  selected: {_style},
                  showSelectedIcon: false,
                  onSelectionChanged: _busy ? null : (s) => setState(() => _style = s.first),
                ),
                const SizedBox(height: 4),
                Text(
                  _style == VisualStyle.explain ? 'Jeder Schritt wird dir erklärt und gezeigt.' : 'Du erarbeitest dir jeden Schritt selbst – die KI führt dich mit Fragen hin, ohne die Lösung zu verraten.',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('visual-create'),
                  onPressed: _busy ? null : _create,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_busy ? _progress : 'Lektion erstellen'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    key: const ValueKey('visual-error'),
                    style: TextStyle(color: c.danger),
                  ),
                ],
                const SizedBox(height: 24),
                Text('Deine Lektionen', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_lessons.isEmpty)
                  Text('Noch keine – erstelle oben die erste.', style: TextStyle(color: c.inkMuted))
                else
                  for (final (i, l) in _lessons.indexed)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        key: ValueKey('visual-lesson-$i'),
                        leading: Icon(l.hasCar ? Icons.directions_car_outlined : Icons.show_chart, color: c.accent),
                        title: Text(l.title),
                        subtitle: Text(
                          [
                            '${l.steps.length} Schritte',
                            if (l.style == VisualStyle.socratic) 'sokratisch',
                            if (l.exercise != null) 'mit Übung',
                            if (l.source.isNotEmpty) l.source,
                          ].join(' · '),
                        ),
                        onTap: () => _open(l),
                        trailing: IconButton(
                          key: ValueKey('visual-lesson-delete-$i'),
                          tooltip: 'Löschen',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(l),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
