import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/flashcard.dart';
import 'mastery_service.dart';

/// CSV-Export (Backup, Tabellenkalkulation, Anki) und einfacher Import von
/// Vorder-/Rückseite-Karten – z.B. aus einem Anki-Export ("Notizen als
/// Text") oder einer eigenen Tabelle.
class CardCsvService {
  static const _header = ['Vorderseite', 'Rückseite', 'Typ', 'Ampel', 'Fällig', 'Wiederholungen'];

  /// Semikolon-getrennt mit BOM – öffnet sich so direkt richtig in Excel/
  /// LibreOffice; Anki erkennt das Trennzeichen beim Import selbst.
  static String export(List<Flashcard> cards, {MasteryService? mastery, DateTime? now}) {
    final m = mastery ?? MasteryService();
    final rows = <List<String>>[
      _header,
      for (final c in cards)
        [
          c.front,
          c.answerSummary.isNotEmpty ? c.answerSummary : c.back,
          c.type.label,
          m.levelFor(c, now: now).label,
          c.reps == 0 ? '' : _date(c.due),
          '${c.reps}',
        ],
    ];
    return '\uFEFF${rows.map((r) => r.map(_quote).join(';')).join('\r\n')}\r\n';
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _quote(String value) {
    final needsQuotes = value.contains(RegExp('[;"\\r\\n]'));
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  /// Liest Vorder-/Rückseiten aus CSV/TSV. Trennzeichen (Tab, Semikolon,
  /// Komma) wird erkannt; Anki-Kopfzeilen (`#separator:…`) und eine
  /// Kopfzeile wie "Vorderseite;Rückseite" werden übersprungen, einfaches
  /// HTML aus Anki (`<br>`, `&nbsp;` …) wird zu Text.
  static List<({String front, String back})> parse(String input) {
    final raw = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final lines = const LineSplitter().convert(raw);
    final text = lines.where((l) => !l.startsWith('#')).join('\n');
    final firstLine = lines.firstWhere((l) => l.trim().isNotEmpty && !l.startsWith('#'), orElse: () => '');
    final delimiter = _detectDelimiter(firstLine);
    final rows = _parseRows(text, delimiter);
    final result = <({String front, String back})>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 2) continue;
      final front = _cleanHtml(row[0]).trim();
      final back = _cleanHtml(row[1]).trim();
      if (front.isEmpty || back.isEmpty) continue;
      if (i == 0 && _isHeader(front, back)) continue;
      result.add((front: front, back: back));
    }
    return result;
  }

  /// Neue Karteikarten (Typ Karteikarte, noch nie gelernt) für ein Fach.
  static List<Flashcard> toFlashcards(List<({String front, String back})> rows, String moduleId, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return [
      for (var i = 0; i < rows.length; i++)
        Flashcard(
          id: const Uuid().v4(),
          moduleId: moduleId,
          front: rows[i].front,
          back: rows[i].back,
          // Aufsteigend, damit die Reihenfolge der Datei beim Einführen
          // neuer Karten erhalten bleibt.
          createdAt: at.add(Duration(milliseconds: i)),
          due: at,
        ),
    ];
  }

  static bool _isHeader(String front, String back) {
    const fronts = {'vorderseite', 'front', 'frage', 'question'};
    const backs = {'rückseite', 'back', 'antwort', 'answer'};
    return fronts.contains(front.toLowerCase()) && backs.contains(back.toLowerCase());
  }

  static String _detectDelimiter(String line) {
    int count(String d) {
      var n = 0;
      var inQuotes = false;
      for (final ch in line.split('')) {
        if (ch == '"') inQuotes = !inQuotes;
        if (!inQuotes && ch == d) n++;
      }
      return n;
    }

    final candidates = {'\t': count('\t'), ';': count(';'), ',': count(',')};
    final best = candidates.entries.reduce((a, b) => b.value > a.value ? b : a);
    return best.value == 0 ? ';' : best.key;
  }

  /// RFC-4180-artig: Felder in Anführungszeichen dürfen Trennzeichen,
  /// Zeilenumbrüche und verdoppelte Anführungszeichen enthalten.
  static List<List<String>> _parseRows(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }
      if (ch == '"' && field.isEmpty) {
        inQuotes = true;
      } else if (ch == delimiter) {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        if (row.any((f) => f.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
    return rows;
  }

  static String _cleanHtml(String value) {
    if (!value.contains('<') && !value.contains('&')) return value;
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(div|p)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
  }
}
