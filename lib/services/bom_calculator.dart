import '../models/bom_task.dart';

/// Eine Zeile einer Stückliste (Lösung).
class BomRow {
  const BomRow({
    required this.number,
    required this.name,
    required this.quantity,
    this.unit = '',
    this.level = 0,
    this.ak,
  });

  /// Stufe (nur Strukturstückliste, sonst 0).
  final int level;
  final String number;
  final String name;
  final double quantity;
  final String unit;

  /// Auflösungskennzeichen (nur Baukastenstückliste): 1 = eigene Stückliste, 2 = keine.
  final int? ak;

  String get quantityText => '${bomQuantityText(quantity)}${unit.isEmpty ? '' : ' $unit'}';
}

/// Eine Zeile, wie der Nutzer sie eingetragen hat.
class BomInput {
  const BomInput({required this.number, this.level, this.quantity, this.ak});

  final String number;
  final int? level;
  final double? quantity;
  final int? ak;
}

/// Ergebnis einer Prüfung: je eingetragene Zeile null (richtig) oder der
/// Fehler, dazu was fehlt.
class BomVerdict {
  const BomVerdict({required this.rows, this.missing = const [], this.listProblems = const {}});

  final List<String?> rows;

  /// Fehlende Zeilen bzw. Listen (verständlich formuliert, ohne die Lösung zu verraten).
  final List<String> missing;

  /// Nur Baukasten: Fehler je Liste (Sach-Nr. der Liste → Meldung).
  final Map<String, String> listProblems;

  bool get ok => rows.every((r) => r == null) && missing.isEmpty && listProblems.isEmpty;
  int get wrongRows => rows.where((r) => r != null).length;

  String get summary {
    if (ok) return 'Alles richtig!';
    final parts = [
      if (wrongRows > 0) wrongRows == 1 ? '1 Zeile stimmt nicht' : '$wrongRows Zeilen stimmen nicht',
      ...listProblems.values,
      ...missing,
    ];
    return parts.join(' · ');
  }
}

/// Rechnet aus dem Erzeugnisbaum die Stücklisten und prüft Eingaben.
/// Kommt eine Baugruppe mehrfach vor, aber nur einmal mit Kindern, gilt
/// diese Auflösung überall.
class BomCalculator {
  BomCalculator(this.task) {
    for (final e in task.root.walk()) {
      final n = e.node;
      if (n.children.isNotEmpty) _expanded.putIfAbsent(n.number, () => n);
      if (n.name.isNotEmpty) _names.putIfAbsent(n.number, () => n.name);
      if (n.unit.isNotEmpty) _units.putIfAbsent(n.number, () => n.unit);
    }
  }

  final BomTask task;
  final _expanded = <String, BomNode>{};
  final _names = <String, String>{};
  final _units = <String, String>{};

  static bool same(double a, double b) => (a - b).abs() <= 1e-6 * (a.abs() > 1 ? a.abs() : 1);

  String nameOf(String nr) => _names[nr] ?? '';
  String unitOf(String nr) => _units[nr] ?? '';
  String label(String nr) => '$nr ${nameOf(nr)}'.trim();

  /// Hat eine eigene Stückliste (Erzeugnis oder Baugruppe) → AK 1.
  bool hasStructure(String nr) => _expanded.containsKey(nr);

  List<BomNode> childrenOf(BomNode n) =>
      n.children.isNotEmpty ? n.children : (_expanded[n.number]?.children ?? const []);

  /// Alle Vorkommen unter dem Erzeugnis (Baugruppen aufgelöst), von links nach unten.
  List<({BomNode node, int level, List<double> path})> occurrences() {
    final out = <({BomNode node, int level, List<double> path})>[];
    void visit(BomNode n, int level, List<double> path, Set<String> seen) {
      for (final c in childrenOf(n)) {
        final p = [...path, c.quantity];
        out.add((node: c, level: level + 1, path: p));
        // Schutz vor Kreisen (falsch abgelesener Baum).
        if (!seen.contains(c.number)) visit(c, level + 1, p, {...seen, c.number});
      }
    }

    visit(task.root, 0, const [], {task.root.number});
    return out;
  }

  /// Alle Sach-Nr. im Baum (Erzeugnis zuerst), jede einmal, von links nach unten.
  List<String> numbers() => [
    for (final n in {task.root.number, for (final o in occurrences()) o.node.number}) n,
  ];

  static double _product(List<double> path) => path.fold(1.0, (a, b) => a * b);

  // ---------------------------------------------------------------------------
  // Die Listen
  // ---------------------------------------------------------------------------

  List<BomRow> structure({bool totals = false}) => [
    for (final o in occurrences())
      BomRow(
        level: o.level,
        number: o.node.number,
        name: nameOf(o.node.number),
        quantity: totals ? _product(o.path) * task.baseQuantity : o.node.quantity,
        unit: unitOf(o.node.number),
      ),
  ];

  List<BomRow> overview({bool includeAssemblies = true}) {
    final sums = <String, double>{};
    for (final o in occurrences()) {
      if (!includeAssemblies && hasStructure(o.node.number)) continue;
      sums[o.node.number] = (sums[o.node.number] ?? 0) + _product(o.path) * task.baseQuantity;
    }
    final keys = sums.keys.toList()..sort(_compareNumbers);
    return [for (final k in keys) BomRow(number: k, name: nameOf(k), quantity: sums[k]!, unit: unitOf(k))];
  }

  static int _compareNumbers(String a, String b) {
    final x = num.tryParse(a), y = num.tryParse(b);
    if (x != null && y != null) return x.compareTo(y);
    if (x != null) return -1;
    if (y != null) return 1;
    return a.compareTo(b);
  }

  /// Sach-Nr., die eine eigene Baukastenstückliste brauchen (Erzeugnis zuerst,
  /// dann Stufe für Stufe).
  List<String> assemblies() {
    final out = <String>[];
    var level = [task.root];
    final seen = <String>{};
    while (level.isNotEmpty) {
      final next = <BomNode>[];
      for (final n in level) {
        if (hasStructure(n.number) && seen.add(n.number)) {
          out.add(n.number);
          next.addAll(childrenOf(n));
        }
      }
      level = next;
    }
    return out;
  }

  /// Baukastenstückliste einer Baugruppe: die direkten Bestandteile je 1 Stück.
  List<BomRow> modular(String nr) {
    final node = nr == task.root.number ? task.root : _expanded[nr];
    if (node == null) return const [];
    final order = <String>[];
    final sums = <String, double>{};
    for (final c in childrenOf(node)) {
      if (!sums.containsKey(c.number)) order.add(c.number);
      sums[c.number] = (sums[c.number] ?? 0) + c.quantity;
    }
    return [
      for (final k in order)
        BomRow(number: k, name: nameOf(k), quantity: sums[k]!, unit: unitOf(k), ak: hasStructure(k) ? 1 : 2),
    ];
  }

  /// Die Listen, die in einer Baukasten-Teilaufgabe auszufüllen sind.
  List<String> modularLists(BomPart part) => part.lists.isNotEmpty ? part.lists : assemblies();

  // ---------------------------------------------------------------------------
  // Prüfen
  // ---------------------------------------------------------------------------

  String? _common(BomInput input) {
    if (input.number.trim().isEmpty) return 'Sach-Nr. fehlt.';
    if (input.number == task.root.number) {
      return 'Das Erzeugnis selbst steht nicht in der Liste – nur seine Bestandteile.';
    }
    if (!numbers().contains(input.number)) return 'Sach-Nr. ${input.number} kommt im Erzeugnisbaum nicht vor.';
    if (input.quantity == null) return 'Menge fehlt.';
    return null;
  }

  static String _count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

  BomVerdict checkOverview(BomPart part, List<BomInput> inputs) {
    final expected = {for (final r in overview(includeAssemblies: part.includeAssemblies)) r.number: r};
    final seen = <String>{};
    final rows = <String?>[];
    for (final input in inputs) {
      final common = _common(input);
      if (common != null) {
        rows.add(common);
        continue;
      }
      final nr = input.number;
      if (!seen.add(nr)) {
        rows.add(
          '${label(nr)} steht doppelt – in der Mengenübersicht jede Sach-Nr. nur einmal, die Mengen zusammengezählt.',
        );
        continue;
      }
      final row = expected[nr];
      if (row == null) {
        rows.add('${label(nr)} ist eine Baugruppe – hier sind nur Teile und Rohstoffe gefragt.');
        continue;
      }
      rows.add(same(input.quantity!, row.quantity) ? null : _overviewQuantityProblem(nr, input.quantity!));
    }
    final missing = expected.keys.where((k) => !seen.contains(k)).length;
    return BomVerdict(
      rows: rows,
      missing: [if (missing > 0) 'Es ${missing == 1 ? 'fehlt' : 'fehlen'} noch ${_count(missing, 'Zeile', 'Zeilen')}.'],
    );
  }

  String _overviewQuantityProblem(String nr, double given) {
    final occ = [
      for (final o in occurrences())
        if (o.node.number == nr) o,
    ];
    final totals = [for (final o in occ) _product(o.path) * task.baseQuantity];
    final multiplied = occ.length > 1 && totals.any((t) => same(t, given));
    if (multiplied) {
      return '${label(nr)} kommt ${occ.length}-mal im Baum vor – alle Vorkommen zusammenzählen.';
    }
    final notMultiplied =
        occ.any((o) => o.path.length > 1 && same(o.node.quantity * task.baseQuantity, given)) ||
        same(occ.fold(0.0, (a, o) => a + o.node.quantity), given);
    if (notMultiplied) {
      return 'Menge von ${label(nr)} nicht multipliziert – entlang des Pfads alle Mengen bis zum Erzeugnis malnehmen.';
    }
    if (task.baseQuantity != 1 && same(given * task.baseQuantity, totals.fold(0.0, (a, b) => a + b))) {
      return 'Menge von ${label(nr)} gilt für 1 Erzeugnis – gefragt sind ${bomQuantityText(task.baseQuantity)} Stück.';
    }
    return 'Menge von ${label(nr)} stimmt nicht.';
  }

  /// Strukturstückliste: Reihenfolge zählt. Die Zeilen werden über die
  /// längste gemeinsame Folge der Sach-Nr. zugeordnet – eine vergessene
  /// Zeile macht nicht alle folgenden falsch.
  BomVerdict checkStructure(BomPart part, List<BomInput> inputs) {
    final expected = structure(totals: part.totals);
    final occ = occurrences();
    final n = inputs.length, m = expected.length;
    final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i][j] = inputs[i].number == expected[j].number
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }
    final match = List<int?>.filled(n, null);
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (inputs[i].number == expected[j].number) {
        match[i++] = j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    final rows = <String?>[];
    for (var k = 0; k < n; k++) {
      final input = inputs[k];
      final common = _common(input);
      if (common != null) {
        rows.add(common);
        continue;
      }
      final e = match[k];
      if (e == null) {
        rows.add(
          '${label(input.number)} steht hier an der falschen Stelle oder zu oft – den Baum von links nach ganz unten '
          'durchgehen, jede Baugruppe sofort auflösen.',
        );
        continue;
      }
      final want = expected[e];
      if (input.level == null) {
        rows.add('Stufe fehlt.');
      } else if (input.level != want.level) {
        rows.add(
          'Stufe von ${label(input.number)} stimmt nicht – zähle die Ebenen unter dem Erzeugnis (direkt darunter = 1).',
        );
      } else if (!same(input.quantity!, want.quantity)) {
        final total = _product(occ[e].path) * task.baseQuantity;
        if (!part.totals && same(input.quantity!, total)) {
          rows.add(
            'In der Strukturstückliste steht die Menge je übergeordnete Baugruppe (die Zahl an der Linie), '
            'nicht die Gesamtmenge.',
          );
        } else if (part.totals && same(input.quantity!, occ[e].node.quantity)) {
          rows.add('Hier ist die Gesamtmenge gefragt – entlang des Pfads alle Mengen bis zum Erzeugnis malnehmen.');
        } else {
          rows.add('Menge von ${label(input.number)} stimmt nicht.');
        }
      } else {
        rows.add(null);
      }
    }
    final missing = m - match.whereType<int>().length;
    return BomVerdict(
      rows: rows,
      missing: [if (missing > 0) 'Es ${missing == 1 ? 'fehlt' : 'fehlen'} noch ${_count(missing, 'Zeile', 'Zeilen')}.'],
    );
  }

  /// Baukasten: [lists] = Sach-Nr. der angelegten Listen, [inputs] je Liste die Zeilen.
  BomVerdict checkModular(BomPart part, Map<String, List<BomInput>> inputs) {
    final needed = modularLists(part);
    final rows = <String?>[];
    final listProblems = <String, String>{};
    var missingRows = 0;
    for (final entry in inputs.entries) {
      final list = entry.key;
      if (!hasStructure(list)) {
        listProblems[list] =
            '${label(list)} hat keine eigene Stückliste – ein Teil/Rohstoff (AK 2) wird nicht aufgelöst.';
        rows.addAll([for (final _ in entry.value) null]);
        continue;
      }
      final expected = {for (final r in modular(list)) r.number: r};
      final seen = <String>{};
      for (final input in entry.value) {
        final nr = input.number;
        if (nr.trim().isNotEmpty && nr == list) {
          rows.add('${label(nr)} ist die Baugruppe selbst – in ihre Liste gehören nur ihre Bestandteile.');
          continue;
        }
        final common = nr == task.root.number ? null : _common(input);
        if (common != null) {
          rows.add(common);
          continue;
        }
        final want = expected[nr];
        if (want == null) {
          rows.add(
            _isBelow(list, nr)
                ? '${label(nr)} ist kein direkter Bestandteil von ${label(list)} – eine Baukastenstückliste geht nur eine Stufe tief.'
                : '${label(nr)} gehört nicht zu ${label(list)}.',
          );
          continue;
        }
        if (!seen.add(nr)) {
          rows.add('${label(nr)} steht doppelt in dieser Liste.');
          continue;
        }
        if (input.quantity == null) {
          rows.add('Menge fehlt.');
        } else if (!same(input.quantity!, want.quantity)) {
          rows.add(
            _isMultiplied(list, nr, input.quantity!)
                ? 'Menge je 1 Stück ${label(list)} – in der Baukastenstückliste nicht multiplizieren.'
                : 'Menge von ${label(nr)} stimmt nicht.',
          );
        } else if (input.ak == null) {
          rows.add('AK fehlt (1 = eigene Stückliste, 2 = keine).');
        } else if (input.ak != want.ak) {
          rows.add(
            want.ak == 1
                ? 'AK von ${label(nr)}: hat eine eigene Stückliste (Baugruppe) → AK 1.'
                : 'AK von ${label(nr)}: wird nicht weiter aufgelöst (Teil/Rohstoff) → AK 2.',
          );
        } else {
          rows.add(null);
        }
      }
      missingRows += expected.keys.where((k) => !seen.contains(k)).length;
    }
    final missingLists = needed.where((l) => !inputs.containsKey(l)).length;
    return BomVerdict(
      rows: rows,
      listProblems: listProblems,
      missing: [
        if (missingLists > 0)
          'Es ${missingLists == 1 ? 'fehlt' : 'fehlen'} noch ${_count(missingLists, 'Liste', 'Listen')} '
              '(jede Baugruppe mit AK 1 und das Erzeugnis brauchen eine eigene).',
        if (missingRows > 0)
          'Es ${missingRows == 1 ? 'fehlt' : 'fehlen'} noch ${_count(missingRows, 'Zeile', 'Zeilen')}.',
      ],
    );
  }

  bool _isBelow(String list, String nr) {
    final node = list == task.root.number ? task.root : _expanded[list];
    if (node == null) return false;
    bool visit(BomNode n, Set<String> seen) {
      for (final c in childrenOf(n)) {
        if (c.number == nr) return true;
        if (seen.add(c.number) && visit(c, seen)) return true;
      }
      return false;
    }

    return visit(node, {list});
  }

  bool _isMultiplied(String list, String nr, double given) {
    final listTotal = list == task.root.number
        ? 1.0
        : occurrences().where((o) => o.node.number == list).map((o) => _product(o.path)).firstOrNull ?? 1;
    final want = modular(list).where((r) => r.number == nr).firstOrNull?.quantity ?? 0;
    return !same(listTotal, 1) && same(given, want * listTotal);
  }

  // ---------------------------------------------------------------------------
  // Tipps und Lösung
  // ---------------------------------------------------------------------------

  List<String> hints(BomPart part) => switch (part.kind) {
    BomListKind.overview => [
      part.includeAssemblies
          ? 'Jede Sach-Nr. genau einmal aufführen – Baugruppen, Teile und Rohstoffe, aber nicht das Erzeugnis selbst.'
          : 'Nur Teile und Rohstoffe (was nicht weiter aufgelöst wird), jede Sach-Nr. genau einmal.',
      'Gesamtmenge = die Mengen entlang des Pfads bis zum Erzeugnis malnehmen; kommt eine Sach-Nr. mehrfach vor, '
          'alle Vorkommen zusammenzählen.',
      'Es sind ${_count(overview(includeAssemblies: part.includeAssemblies).length, 'Zeile', 'Zeilen')}.',
    ],
    BomListKind.structure => [
      'Von links beginnend nach ganz unten, dann systematisch nach rechts: jede Baugruppe sofort mit ihren Teilen auflösen.',
      part.totals
          ? 'Stufe = Ebene im Baum (direkt unter dem Erzeugnis = 1); Menge = alle Mengen entlang des Pfads malnehmen.'
          : 'Stufe = Ebene im Baum (direkt unter dem Erzeugnis = 1); Menge = die Zahl an der Linie '
                '(je 1 Stück der übergeordneten Baugruppe).',
      'Es sind ${_count(structure().length, 'Zeile', 'Zeilen')} – eine Sach-Nr. steht so oft da, wie sie im Baum vorkommt.',
    ],
    BomListKind.modular => [
      'Für das Erzeugnis und jede Baugruppe eine eigene Liste – darin nur die direkten Bestandteile (eine Stufe tiefer).',
      'Menge je 1 Stück der Baugruppe, nicht multiplizieren. AK 1 = hat selbst eine Stückliste, AK 2 = keine.',
      'Gebraucht werden Listen für: ${[for (final l in modularLists(part)) label(l)].join(', ')}.',
    ],
  };

  /// Musterlösung als Text (Rückseite der Karte, Lösung anzeigen).
  String solutionText(BomPart part) {
    String line(BomRow r, {bool level = false, bool ak = false}) => [
      if (level) 'Stufe ${r.level}',
      r.number,
      if (r.name.isNotEmpty) r.name,
      r.quantityText,
      if (ak) 'AK ${r.ak}',
    ].join(' | ');
    return switch (part.kind) {
      BomListKind.overview => [
        part.kind.label,
        for (final r in overview(includeAssemblies: part.includeAssemblies)) line(r),
      ].join('\n'),
      BomListKind.structure => [
        part.kind.label,
        for (final r in structure(totals: part.totals)) '${'.' * r.level}${line(r, level: true)}',
      ].join('\n'),
      BomListKind.modular => [
        for (final l in modularLists(part)) ...[
          '${part.kind.label} ${label(l)}',
          for (final r in modular(l)) line(r, ak: true),
        ],
      ].join('\n'),
    };
  }

  String fullSolution() => [for (final p in task.parts) solutionText(p)].join('\n\n');

  /// Unstimmigkeiten im Baum, die beim Speichern auffallen sollten.
  List<String> problems() {
    final out = <String>[];
    final names = <String, String>{};
    for (final e in task.root.walk()) {
      final n = e.node;
      final known = names[n.number];
      if (known != null && n.name.isNotEmpty && known.toLowerCase() != n.name.toLowerCase()) {
        out.add('Sach-Nr. ${n.number} hat zwei Bezeichnungen („$known“ und „${n.name}“).');
      }
      if (n.name.isNotEmpty) names.putIfAbsent(n.number, () => n.name);
    }
    for (final p in task.parts) {
      for (final l in p.lists) {
        if (!hasStructure(l)) out.add('Liste für $l: diese Sach-Nr. hat im Baum keine Bestandteile.');
      }
    }
    return out;
  }
}
