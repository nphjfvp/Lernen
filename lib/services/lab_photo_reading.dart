import '../models/lab_experiment.dart';

/// Ein Wert, den die KI von einem Foto in eine Zelle einer Messwerttabelle
/// eintragen will (alle Nummern ab 0).
class LabCellFill {
  const LabCellFill({
    required this.table,
    required this.row,
    required this.col,
    required this.value,
    required this.label,
    this.existing = '',
  });

  final int table;
  final int row;
  final int col;
  final String value;

  /// "Tabelle · Zeile 2 · Spalte U/V" – zum Anzeigen.
  final String label;

  /// Was schon in der Zelle steht (dann ist es ein Überschreiben).
  final String existing;

  bool get overwrites => existing.trim().isNotEmpty && existing.trim() != value.trim();
}

/// Was die KI auf einem Foto eines Laborversuchs gelesen hat: zu welchem
/// Versuch/Teil es gehört, was zu sehen ist, die Werte für Tabellenzellen und
/// weitere Messwerte als Text. Die KI nummeriert ab 1 (Tabelle, Zeile ohne
/// Kopfzeile, Spalte); geprüft wird gegen die echten Tabellen.
class LabPhotoReading {
  const LabPhotoReading({
    this.description = '',
    this.experimentId,
    this.partId,
    this.confidence = '',
    this.cells = const [],
    this.notes = '',
    this.unclear = const [],
  });

  final String description;
  final String? experimentId;
  final String? partId;

  /// "hoch", "mittel" oder "niedrig" – wie sicher die KI bei der Zuordnung ist.
  final String confidence;
  final List<({int table, int row, int col, String value})> cells;

  /// Weitere gelesene Werte und Beobachtungen, die in keine Zelle passen.
  final String notes;

  /// Was nicht lesbar war.
  final List<String> unclear;

  bool get isEmpty => cells.isEmpty && notes.trim().isEmpty && description.trim().isEmpty;

  /// Aus der KI-Antwort; Kennungen werden gegen [experiments] aufgelöst
  /// (genau, als eindeutiger Anfang oder über den Titel), Unbekanntes wird
  /// zu `null` statt zu einer falschen Zuordnung.
  factory LabPhotoReading.fromJson(Map<String, dynamic> json, List<LabExperiment> experiments) {
    final experiment = _resolveExperiment(json['experimentId'] ?? json['experiment'], experiments);
    final part = experiment == null ? null : _resolvePart(json['partId'] ?? json['part'], experiment);
    final cells = <({int table, int row, int col, String value})>[];
    for (final raw in (json['cells'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final table = _int(raw['table']), row = _int(raw['row']), col = _int(raw['col'] ?? raw['column']);
      final value = (raw['value'] ?? '').toString().trim();
      if (table == null || row == null || col == null || value.isEmpty) continue;
      cells.add((table: table - 1, row: row - 1, col: col - 1, value: value));
    }
    List<String> strings(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e.toString().trim().isNotEmpty) e.toString().trim(),
    ];
    final notes = json['notes'];
    return LabPhotoReading(
      description: (json['description'] ?? '').toString().trim(),
      experimentId: experiment?.id,
      partId: part?.id,
      confidence: (json['confidence'] ?? '').toString().trim().toLowerCase(),
      cells: cells,
      notes: notes is List ? strings(notes).join('\n') : (notes ?? '').toString().trim(),
      unclear: strings(json['unclear']),
    );
  }

  /// Wohin die Werte im Versuch [e], Teil [partId] gehen: Zellen, die es
  /// wirklich gibt und die zum Ausfüllen sind, und der Rest als Text (nicht
  /// passende Zellen, weitere Messwerte). Passt das Ziel nicht zu dem, das die
  /// KI gemeint hat, kann die Nummerierung nicht stimmen – dann geht alles in
  /// den Text.
  ({List<LabCellFill> fills, String notes}) targetFor(LabExperiment? e, String? partId) {
    final part = e?.partById(partId);
    final lines = <String>[];
    if (notes.trim().isNotEmpty) lines.add(notes.trim());
    final fills = <LabCellFill>[];
    final sameTarget = part != null && e!.id == experimentId && part.id == this.partId;
    for (final c in cells) {
      LabTable? table;
      if (sameTarget && c.table >= 0 && c.table < part.tables.length) table = part.tables[c.table];
      final fits =
          table != null &&
          c.row >= 0 &&
          c.row < table.rows.length &&
          c.col >= 0 &&
          c.col < table.rows[c.row].length &&
          table.editable[c.row][c.col];
      if (fits) {
        final column = c.col < table.columns.length ? table.columns[c.col] : 'Spalte ${c.col + 1}';
        final title = table.title.trim().isEmpty ? 'Tabelle ${c.table + 1}' : table.title.trim();
        fills.add(
          LabCellFill(
            table: c.table,
            row: c.row,
            col: c.col,
            value: c.value,
            label: '$title · Zeile ${c.row + 1} · $column',
            existing: table.rows[c.row][c.col],
          ),
        );
      } else {
        lines.add('Tabelle ${c.table + 1}, Zeile ${c.row + 1}, Spalte ${c.col + 1}: ${c.value}');
      }
    }
    return (fills: fills, notes: lines.join('\n'));
  }

  /// Trägt [fills] in den Teil [partId] ein und hängt [notes] an dessen Notizen
  /// an (mit [stamp] davor, z.B. "Foto 12.05."). Nicht auszufüllende Zellen
  /// bleiben unberührt.
  static LabExperiment apply(
    LabExperiment e,
    String partId,
    List<LabCellFill> fills, {
    String notes = '',
    String stamp = 'Foto',
  }) {
    return e.updatePart(partId, (p) {
      var tables = p.tables;
      for (final f in fills) {
        if (f.table < 0 || f.table >= tables.length) continue;
        tables = [
          for (var k = 0; k < tables.length; k++) k == f.table ? tables[k].withCell(f.row, f.col, f.value) : tables[k],
        ];
      }
      final extra = notes.trim();
      final old = p.notes.trim();
      return p.copyWith(
        tables: tables,
        notes: extra.isEmpty ? p.notes : (old.isEmpty ? '$stamp:\n$extra' : '$old\n\n$stamp:\n$extra'),
      );
    });
  }

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v'.trim());

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß]+'), ' ').trim();

  static LabExperiment? _resolveExperiment(Object? raw, List<LabExperiment> experiments) {
    final id = '${raw ?? ''}'.trim();
    if (id.isEmpty || id == 'null') return null;
    for (final e in experiments) {
      if (e.id == id) return e;
    }
    if (id.length >= 6) {
      final byPrefix = experiments.where((e) => e.id.startsWith(id)).toList();
      if (byPrefix.length == 1) return byPrefix.first;
    }
    final n = _norm(id);
    if (n.isEmpty) return null;
    final byTitle = experiments.where((e) => _norm(e.title) == n).toList();
    return byTitle.length == 1 ? byTitle.first : null;
  }

  static LabPart? _resolvePart(Object? raw, LabExperiment e) {
    final id = '${raw ?? ''}'.trim();
    if (id.isNotEmpty && id != 'null') {
      for (final p in e.parts) {
        if (p.id == id) return p;
      }
      if (id.length >= 6) {
        final byPrefix = e.parts.where((p) => p.id.startsWith(id)).toList();
        if (byPrefix.length == 1) return byPrefix.first;
      }
      final n = _norm(id);
      final byTitle = e.parts.where((p) => _norm(p.title) == n).toList();
      if (byTitle.length == 1) return byTitle.first;
    }
    return e.parts.length == 1 ? e.parts.first : null;
  }
}
