import 'source_locator.dart';

/// Ein Abschnitt beim fortlaufenden Import: [pages] sind die NEUEN Seiten,
/// [overlap] ist die letzte Seite des vorigen Abschnitts – sie wird noch
/// einmal mitgeschickt, damit die KI prüfen kann, ob dort begonnene Aufgaben
/// auf den neuen Seiten weitergehen (siehe AiService.scanPdfWindow).
class ScanWindow {
  const ScanWindow({this.overlap, required this.pages});

  final int? overlap;
  final List<int> pages;

  /// Alle gezeigten Seiten in Dokument-Reihenfolge.
  List<int> get shown => [?overlap, ...pages];

  /// Der Abschnitt ohne Überlappung (z.B. wenn der vorige fehlgeschlagen ist
  /// und die Seite deshalb noch nicht bearbeitet wurde).
  ScanWindow get withoutOverlap => ScanWindow(pages: shown);

  /// "Seite 4–6" bzw. "Seite 4".
  String get label => pages.length == 1 ? 'Seite ${pages.first}' : 'Seite ${pages.first}–${pages.last}';
}

/// Teilt die Seiten [firstPage]..[lastPage] in Abschnitte: höchstens
/// [maxNewPages] neue Seiten und – bei viel Text – weniger, damit ein Abschnitt
/// nicht über [charBudget] Zeichen Seitentext wächst (mindestens eine Seite).
/// Jeder Abschnitt außer dem ersten beginnt mit der letzten Seite des
/// vorigen. [pageTexts] (Index 0 = Seite 1) dürfen leer oder zu kurz sein –
/// unbekannte Seiten zählen als leicht.
List<ScanWindow> planScanWindows(
  List<String> pageTexts, {
  required int firstPage,
  required int lastPage,
  int maxNewPages = 4,
  int charBudget = 7000,
}) {
  int textLength(int page) => page - 1 >= 0 && page - 1 < pageTexts.length ? pageTexts[page - 1].length : 0;
  final windows = <ScanWindow>[];
  var page = firstPage;
  int? previousLast;
  while (page <= lastPage) {
    final pages = <int>[];
    var chars = 0;
    while (page <= lastPage && pages.length < maxNewPages) {
      final length = textLength(page);
      if (pages.isNotEmpty && chars + length > charBudget) break;
      pages.add(page);
      chars += length;
      page++;
    }
    windows.add(ScanWindow(overlap: previousLast, pages: pages));
    previousLast = pages.last;
  }
  return windows;
}

/// Eine Seite eines Begleitdokuments (z.B. eine Musterlösung).
class ImportReferencePage {
  const ImportReferencePage({required this.owner, required this.label, required this.text});

  /// Datei, aus der die Seite stammt – die eigenen Seiten einer Datei dienen
  /// ihr nicht als Nachschlagewerk.
  final String owner;

  /// z.B. "Lösung.pdf, Seite 3".
  final String label;
  final String text;
}

/// Nachschlagewerk für Lösungen beim Import mehrerer Dateien: statt jedes Mal
/// alle anderen Dateien mitzuschicken (und irgendwo abzuschneiden), wählt es
/// zu jedem Abschnitt die dazu passenden Seiten – beliebig viele Dateien,
/// begrenzt nur der Umfang je Anfrage.
class ImportReference {
  ImportReference(List<ImportReferencePage> pages)
      : _pages = [for (final p in pages) if (p.text.trim().isNotEmpty) p] {
    _index = PageIndex([for (final p in _pages) p.text]);
  }

  final List<ImportReferencePage> _pages;
  late final PageIndex _index;

  bool get isEmpty => _pages.isEmpty;

  /// Zerlegt den Text einer Datei ohne Seiten (Word, PowerPoint …) in Stücke
  /// von etwa [chunk] Zeichen an Absatzgrenzen.
  static List<ImportReferencePage> pagesOfText(String owner, String text, {int chunk = 3000}) {
    final result = <ImportReferencePage>[];
    final buffer = StringBuffer();
    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) {
        result.add(ImportReferencePage(owner: owner, label: '$owner, Teil ${result.length + 1}', text: value));
      }
      buffer.clear();
    }

    for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
      if (buffer.length + paragraph.length > chunk && buffer.isNotEmpty) flush();
      buffer.writeln(paragraph);
      // Ein einzelner überlanger Absatz wird hart geteilt.
      while (buffer.length > chunk * 2) {
        final value = buffer.toString();
        buffer
          ..clear()
          ..write(value.substring(chunk));
        result.add(ImportReferencePage(
          owner: owner,
          label: '$owner, Teil ${result.length + 1}',
          text: value.substring(0, chunk),
        ));
      }
    }
    flush();
    return result;
  }

  /// Die zum Abschnitt passenden Seiten (in Dokument-Reihenfolge) als Text,
  /// leer wenn nichts passt. Passt alles in [charBudget], wird alles
  /// mitgegeben; sonst die am besten passenden (gleiche seltene Begriffe wie
  /// [windowText]), höchstens [maxPages]. Seiten von [excludeOwner] zählen
  /// nicht.
  String forWindow(String windowText, {String? excludeOwner, int charBudget = 20000, int maxPages = 8}) {
    final candidates = [
      for (var i = 0; i < _pages.length; i++)
        if (_pages[i].owner != excludeOwner) i,
    ];
    if (candidates.isEmpty) return '';
    final total = candidates.fold<int>(0, (sum, i) => sum + _pages[i].text.length);
    List<int> chosen;
    if (total <= charBudget) {
      chosen = candidates;
    } else {
      final keywords = SourceLocator.keywords(windowText).take(80).toList();
      if (keywords.isEmpty) return '';
      final ranked = _index.rank((question: keywords, answer: const []), limit: _pages.length);
      chosen = [];
      var chars = 0;
      for (final r in ranked) {
        if (excludeOwner != null && _pages[r.index].owner == excludeOwner) continue;
        final length = _pages[r.index].text.length;
        if (chosen.isNotEmpty && chars + length > charBudget) continue;
        chosen.add(r.index);
        chars += length;
        if (chosen.length >= maxPages) break;
      }
      chosen.sort();
    }
    return [for (final i in chosen) '=== ${_pages[i].label} ===\n${_pages[i].text}'].join('\n\n');
  }
}
