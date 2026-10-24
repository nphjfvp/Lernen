import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'app_guide.dart';

/// Einführung in die App (Einstellungen → Einführung): startet nie von
/// selbst. Erst eine Übersicht der Kapitel, dann zum Durchblättern – oder
/// direkt zu einem Kapitel springen.
class AppGuideScreen extends StatefulWidget {
  const AppGuideScreen({super.key, this.chapters = appGuideChapters});

  final List<GuideChapter> chapters;

  @override
  State<AppGuideScreen> createState() => _AppGuideScreenState();
}

class _AppGuideScreenState extends State<AppGuideScreen> {
  final _pages = PageController();
  int _page = 0;

  /// Seite 0 = Übersicht, danach ein Kapitel je Seite.
  int get _last => widget.chapters.length;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) =>
      _pages.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Einführung'),
        actions: [
          if (_page > 0)
            TextButton.icon(
              key: const ValueKey('guide-toc'),
              onPressed: () => _go(0),
              icon: const Icon(Icons.list_rounded, size: 18),
              label: const Text('Inhalt'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _Overview(chapters: widget.chapters, onOpen: (i) => _go(i + 1)),
                  for (final ch in widget.chapters) _ChapterPage(chapter: ch),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      key: const ValueKey('guide-prev'),
                      onPressed: () => _go(_page - 1),
                      child: const Text('Zurück'),
                    )
                  else
                    const SizedBox(width: 72),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _page == 0 ? 'Übersicht' : 'Kapitel $_page von $_last',
                          key: const ValueKey('guide-position'),
                          style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(value: _page / _last, minHeight: 4, backgroundColor: c.border),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('guide-next'),
                    onPressed: _page >= _last ? () => Navigator.of(context).pop() : () => _go(_page + 1),
                    child: Text(_page == 0 ? 'Los geht’s' : (_page >= _last ? 'Fertig' : 'Weiter')),
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

class _Overview extends StatelessWidget {
  const _Overview({required this.chapters, required this.onOpen});

  final List<GuideChapter> chapters;
  final void Function(int index) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        Text(
          'Willkommen bei Lernen',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink),
        ),
        const SizedBox(height: 8),
        Text(
          'Hier steht, was die App kann und wo du es findest. Blättere durch oder tippe ein Kapitel an – du kannst '
          'die Einführung jederzeit wieder unter Einstellungen öffnen.',
          style: TextStyle(color: c.inkMuted, height: 1.45),
        ),
        const SizedBox(height: 18),
        for (final (i, ch) in chapters.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: ValueKey('guide-chapter-$i'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => onOpen(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(ch.icon, color: c.accent),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          ch.title,
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.inkMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChapterPage extends StatelessWidget {
  const _ChapterPage({required this.chapter});

  final GuideChapter chapter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(14)),
              child: Icon(chapter.icon, color: c.accentOnSoft, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                chapter.title,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: c.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(chapter.intro, style: TextStyle(color: c.ink, height: 1.45, fontSize: 15)),
        const SizedBox(height: 16),
        for (final item in chapter.items)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: 4),
                Text(item.text, style: TextStyle(color: c.ink, height: 1.4)),
                if (item.where.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_outlined, size: 15, color: c.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.where,
                          style: TextStyle(fontSize: 12.5, color: c.accentOnSoft, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
