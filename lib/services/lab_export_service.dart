import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/lab_experiment.dart';

/// Ein Block des Dokuments – dieselbe Gliederung wird als Text und als PDF
/// ausgegeben.
sealed class _Block {
  const _Block();
}

class _Heading extends _Block {
  const _Heading(this.text, this.level);
  final String text;
  final int level;
}

class _Paragraph extends _Block {
  const _Paragraph(this.text, {this.muted = false});
  final String text;
  final bool muted;
}

class _TableBlock extends _Block {
  const _TableBlock(this.table);
  final LabTable table;
}

/// Exportiert Vorbereitung und Bericht eines Laborversuchs – zum Ausdrucken,
/// Abgeben oder Weiterbearbeiten in einem Textverarbeitungsprogramm. Die
/// Einschätzungen der KI sind bewusst nicht enthalten: sie gehören dir, nicht
/// zur Abgabe.
class LabExportService {
  static final _date = DateFormat('dd.MM.yyyy');

  // -- Inhalt ---------------------------------------------------------------

  static List<_Block> _preparation(LabExperiment e, String? moduleName) => [
        _Heading('Vorbereitung: ${e.title}', 1),
        _Paragraph(_meta(e, moduleName), muted: true),
        for (final q in e.prep) ...[
          _Heading('${q.number.isEmpty ? '' : '${q.number}  '}${_oneLine(q.text)}', 3),
          _Paragraph(q.answered ? q.answer.trim() : '(noch nicht beantwortet)', muted: !q.answered),
        ],
      ];

  static List<_Block> _report(LabExperiment e, String? moduleName) {
    final blocks = <_Block>[
      _Heading('Bericht: ${e.title}', 1),
      _Paragraph(_meta(e, moduleName), muted: true),
    ];
    for (final s in e.report) {
      blocks
        ..add(_Heading(s.title, 2))
        ..add(_Paragraph(s.text.trim().isEmpty ? '(noch nicht geschrieben)' : s.text.trim(), muted: s.text.trim().isEmpty));
    }
    final withTables = [for (final p in e.parts) if (p.tables.isNotEmpty) p];
    if (withTables.isNotEmpty) {
      blocks.add(const _Heading('Anhang: Messwerte', 2));
      for (final p in withTables) {
        blocks.add(_Heading(p.title, 3));
        for (final t in p.tables) {
          if (t.title.trim().isNotEmpty) blocks.add(_Paragraph(t.title.trim()));
          blocks.add(_TableBlock(t));
        }
        if (p.notes.trim().isNotEmpty) blocks.add(_Paragraph('Notizen: ${p.notes.trim()}'));
      }
    }
    return blocks;
  }

  static String _meta(LabExperiment e, String? moduleName) => [
        if ((moduleName ?? '').trim().isNotEmpty) moduleName!.trim(),
        if (e.labDate != null) 'Versuch am ${_date.format(e.labDate!)}',
        if (e.reportDue != null) 'Abgabe bis ${_date.format(e.reportDue!)}',
      ].join(' · ');

  static String _oneLine(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

  // -- Text -----------------------------------------------------------------

  static String preparationText(LabExperiment e, {String? moduleName}) => _asText(_preparation(e, moduleName));

  static String reportText(LabExperiment e, {String? moduleName}) => _asText(_report(e, moduleName));

  static String _asText(List<_Block> blocks) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      switch (block) {
        case _Heading(:final text, :final level):
          if (buffer.isNotEmpty) buffer.writeln();
          buffer.writeln('${'#' * level} $text');
        case _Paragraph(:final text):
          if (text.trim().isNotEmpty) buffer.writeln(text);
        case _TableBlock(:final table):
          buffer.writeln(table.asText());
      }
    }
    return buffer.toString().trimRight();
  }

  // -- PDF ------------------------------------------------------------------

  static Uint8List preparationPdf(LabExperiment e, {String? moduleName}) => _asPdf(_preparation(e, moduleName));

  static Uint8List reportPdf(LabExperiment e, {String? moduleName}) => _asPdf(_report(e, moduleName));

  /// Die eingebauten PDF-Schriften kennen nur Latin-1: Zeichen, die dort
  /// fehlen (Ω, µ als griechisches My, Pfeile, Gedankenstriche …), werden
  /// ersetzt statt als Kästchen zu erscheinen.
  static String latin1Safe(String text) {
    const replacements = {
      '\u03A9': 'Ohm', '\u2126': 'Ohm', '\u03BC': '\u00B5', '–': '-', '—': '-', '‑': '-', '−': '-', '…': '...',
      '→': '->', '←': '<-', '⇒': '=>', '≈': '~', '≤': '<=', '≥': '>=', '≠': '!=', '∞': 'unendlich',
      '„': '"', '“': '"', '”': '"', '‚': "'", '‘': "'", '’': "'", '•': '-', '✓': 'ok', '√': 'Wurzel',
      'π': 'pi', 'Δ': 'Delta', 'α': 'alpha', 'β': 'beta', 'τ': 'tau', 'φ': 'phi', 'ω': 'omega',
      '\t': '    ',
    };
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (replacements.containsKey(ch)) {
        buffer.write(replacements[ch]);
      } else if (rune == 10 || (rune >= 32 && rune <= 255)) {
        buffer.write(ch);
      } else {
        buffer.write('?');
      }
    }
    return buffer.toString();
  }

  static Uint8List _asPdf(List<_Block> blocks) {
    final document = PdfDocument();
    try {
      document.pageSettings.margins.all = 42;
      var page = document.pages.add();
      var y = 0.0;
      final format = PdfLayoutFormat(layoutType: PdfLayoutType.paginate);

      double width() => page.getClientSize().width;
      double height() => page.getClientSize().height;

      for (final block in blocks) {
        if (y > height() - 70) {
          page = document.pages.add();
          y = 0;
        }
        switch (block) {
          case _Heading(:final text, :final level):
            final size = switch (level) { 1 => 17.0, 2 => 13.5, _ => 11.5 };
            final element = PdfTextElement(
              text: latin1Safe(text),
              font: PdfStandardFont(PdfFontFamily.helvetica, size, style: PdfFontStyle.bold),
            );
            if (level > 1) y += 6;
            final result = element.draw(page: page, bounds: Rect.fromLTWH(0, y, width(), 0), format: format);
            if (result != null) {
              page = result.page;
              y = result.bounds.bottom + 4;
            }
          case _Paragraph(:final text, :final muted):
            if (text.trim().isEmpty) continue;
            final element = PdfTextElement(
              text: latin1Safe(text),
              font: PdfStandardFont(PdfFontFamily.helvetica, 10.5, style: muted ? PdfFontStyle.italic : PdfFontStyle.regular),
              brush: muted ? PdfBrushes.gray : PdfBrushes.black,
            );
            final result = element.draw(page: page, bounds: Rect.fromLTWH(0, y, width(), 0), format: format);
            if (result != null) {
              page = result.page;
              y = result.bounds.bottom + 6;
            }
          case _TableBlock(:final table):
            final columns = table.columns.isNotEmpty
                ? table.columns.length
                : (table.rows.isEmpty ? 0 : table.rows.first.length);
            if (columns == 0) continue;
            final grid = PdfGrid()
              ..style = PdfGridStyle(
                font: PdfStandardFont(PdfFontFamily.helvetica, 9.5),
                cellPadding: PdfPaddings(left: 3, right: 3, top: 2, bottom: 2),
              );
            grid.columns.add(count: columns);
            if (table.columns.isNotEmpty) {
              grid.headers.add(1);
              final header = grid.headers[0];
              for (var i = 0; i < columns; i++) {
                header.cells[i].value = latin1Safe(i < table.columns.length ? table.columns[i] : '');
                header.cells[i].style.font = PdfStandardFont(PdfFontFamily.helvetica, 9.5, style: PdfFontStyle.bold);
              }
            }
            for (final row in table.rows) {
              final gridRow = grid.rows.add();
              for (var i = 0; i < columns; i++) {
                gridRow.cells[i].value = latin1Safe(i < row.length ? row[i] : '');
              }
            }
            final result = grid.draw(page: page, bounds: Rect.fromLTWH(0, y, width(), 0), format: format);
            if (result != null) {
              page = result.page;
              y = result.bounds.bottom + 8;
            }
        }
      }
      return Uint8List.fromList(document.saveSync());
    } finally {
      document.dispose();
    }
  }

  /// Dateiname ohne Zeichen, die Dateisysteme nicht mögen.
  static String fileName(String title, String kind, String extension) {
    final safe = title.replaceAll(RegExp(r'[^\w\säöüÄÖÜß-]'), '').trim();
    return '${safe.isEmpty ? 'Laborversuch' : safe} – $kind.$extension';
  }
}
