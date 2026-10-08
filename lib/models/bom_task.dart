/// Stücklisten-Aufgaben ([QuestionType.bom]): aus einem Erzeugnisbaum
/// (Erzeugnisstruktur) eine Mengenübersichts-, Struktur- oder
/// Baukastenstückliste aufstellen. Die KI liest nur den Baum ab (Sach-Nr.,
/// Bezeichnung, Menge an der Verbindungslinie) – die Listen rechnet und
/// prüft die App (siehe BomCalculator).
library;

/// Welche Stückliste gefragt ist.
enum BomListKind {
  overview('Mengenübersichtsstückliste', 'Mengenübersicht'),
  structure('Strukturstückliste', 'Struktur'),
  modular('Baukastenstückliste', 'Baukasten');

  const BomListKind(this.label, this.short);
  final String label;
  final String short;
}

BomListKind? bomListKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (v.isEmpty) return null;
  for (final k in BomListKind.values) {
    if (k.name == v) return k;
  }
  if (v.contains('mengen') ||
      v.contains('overview') ||
      v.contains('summar') ||
      v.contains('übersicht') ||
      v.contains('uebersicht')) {
    return BomListKind.overview;
  }
  if (v.contains('struktur') || v.contains('structur') || v.contains('indent')) return BomListKind.structure;
  if (v.contains('baukasten') ||
      v.contains('baustelle') ||
      v.contains('baustück') ||
      v.contains('baustueck') ||
      v.contains('modul') ||
      v.contains('single')) {
    return BomListKind.modular;
  }
  return null;
}

/// Zahl ohne überflüssige Nachkommastellen, mit deutschem Komma: 2, 1,5, 0,25.
String bomQuantityText(double value) {
  if ((value - value.roundToDouble()).abs() < 1e-9) return value.round().toString();
  var s = value.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

/// Liest eine Menge: "2", "1,5", "220 g", "2x", "×3".
double? parseBomQuantity(Object? raw) {
  if (raw is num) return raw.toDouble();
  final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch('${raw ?? ''}'.replaceAll(RegExp(r'(?<=\d)\.(?=\d{3}\b)'), ''));
  return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
}

/// Ein Knoten im Erzeugnisbaum.
class BomNode {
  const BomNode({
    required this.number,
    this.name = '',
    this.quantity = 1,
    this.unit = '',
    this.children = const [],
    this.uncertain = false,
  });

  /// Sach-Nr.
  final String number;

  /// Bezeichnung (Benennung).
  final String name;

  /// Menge an der Verbindungslinie: je 1 Stück der übergeordneten Baugruppe
  /// (beim Erzeugnis selbst ohne Bedeutung).
  final double quantity;

  /// Mengeneinheit ("" = Stück).
  final String unit;
  final List<BomNode> children;

  /// Schlecht lesbar (z.B. eine Menge an der Linie) – vor dem Speichern bestätigen.
  final bool uncertain;

  /// Der Knoten und alle darunter, von links nach unten (wie die Strukturstückliste).
  Iterable<({BomNode node, int level, BomNode? parent})> walk([int level = 0, BomNode? parent]) sync* {
    yield (node: this, level: level, parent: parent);
    for (final c in children) {
      yield* c.walk(level + 1, this);
    }
  }

  bool get anyUncertain => uncertain || children.any((c) => c.anyUncertain);

  BomNode copyWith({
    String? number,
    String? name,
    double? quantity,
    String? unit,
    List<BomNode>? children,
    bool? uncertain,
  }) => BomNode(
    number: number ?? this.number,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    children: children ?? this.children,
    uncertain: uncertain ?? this.uncertain,
  );

  BomNode confirmed() => copyWith(uncertain: false, children: [for (final c in children) c.confirmed()]);

  Map<String, dynamic> toMap({bool root = false}) => {
    'nr': number,
    if (name.trim().isNotEmpty) 'name': name.trim(),
    if (!root) 'qty': quantity,
    if (unit.trim().isNotEmpty) 'unit': unit.trim(),
    if (uncertain) 'uncertain': true,
    if (children.isNotEmpty) 'children': [for (final c in children) c.toMap()],
  };

  static BomNode? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final number = '${raw['nr'] ?? raw['number'] ?? raw['sachNr'] ?? raw['sachnr'] ?? raw['id'] ?? ''}'.trim();
    if (number.isEmpty) return null;
    final rawQty = raw['qty'] ?? raw['quantity'] ?? raw['menge'] ?? raw['amount'];
    final list = raw['children'] ?? raw['kinder'] ?? raw['components'] ?? raw['teile'];
    final u = raw['uncertain'] ?? raw['unsicher'];
    final quantity = parseBomQuantity(rawQty);
    return BomNode(
      number: number,
      name: '${raw['name'] ?? raw['bezeichnung'] ?? raw['benennung'] ?? raw['label'] ?? ''}'.trim(),
      quantity: quantity == null || quantity <= 0 ? 1 : quantity,
      unit: '${raw['unit'] ?? raw['einheit'] ?? ''}'.trim(),
      children: list is List ? [for (final c in list) ?BomNode.fromMap(c)] : const [],
      uncertain: u == true || '$u'.toLowerCase() == 'true',
    );
  }
}

/// Eine gefragte Stückliste.
class BomPart {
  const BomPart({
    required this.kind,
    this.includeAssemblies = true,
    this.totals = false,
    this.lists = const [],
    this.prompt = '',
  });

  final BomListKind kind;

  /// Mengenübersicht: auch die Baugruppen aufführen („mit Berücksichtigung
  /// der intern erstellten Baugruppen“) – sonst nur Teile und Rohstoffe.
  final bool includeAssemblies;

  /// Strukturstückliste: Gesamtmenge je Erzeugnis statt Menge je
  /// übergeordnete Baugruppe (nur wenn die Aufgabe das so will).
  final bool totals;

  /// Baukastenstückliste: vorgegebene Formulare (Sach-Nr.); leer = selbst
  /// herausfinden, welche Listen nötig sind.
  final List<String> lists;

  /// Eigener Aufgabentext (sonst ein Standardtext je Art).
  final String prompt;

  String get defaultPrompt => switch (kind) {
    BomListKind.overview =>
      includeAssemblies
          ? 'Erstelle die Mengenübersichtsstückliste (mit Baugruppen): jede Sach-Nr. einmal, mit der Gesamtmenge.'
          : 'Erstelle die Mengenübersichtsstückliste (nur Teile und Rohstoffe): jede Sach-Nr. einmal, mit der Gesamtmenge.',
    BomListKind.structure =>
      totals
          ? 'Erstelle die Strukturstückliste: Stufe, Sach-Nr. und Gesamtmenge je Erzeugnis.'
          : 'Erstelle die Strukturstückliste: Stufe, Sach-Nr. und Menge je übergeordnete Baugruppe.',
    BomListKind.modular =>
      lists.isEmpty
          ? 'Erstelle die nötigen Baukastenstücklisten: je Liste die direkten Bestandteile mit Menge und AK.'
          : 'Fülle die Baukastenstücklisten aus: je Liste die direkten Bestandteile mit Menge und AK.',
  };

  String get promptText => prompt.trim().isNotEmpty ? prompt.trim() : defaultPrompt;

  BomPart copyWith({BomListKind? kind, bool? includeAssemblies, bool? totals, List<String>? lists, String? prompt}) =>
      BomPart(
        kind: kind ?? this.kind,
        includeAssemblies: includeAssemblies ?? this.includeAssemblies,
        totals: totals ?? this.totals,
        lists: lists ?? this.lists,
        prompt: prompt ?? this.prompt,
      );

  Map<String, dynamic> toMap() => {
    'list': kind.name,
    if (kind == BomListKind.overview) 'includeAssemblies': includeAssemblies,
    if (kind == BomListKind.structure && totals) 'totals': true,
    if (kind == BomListKind.modular && lists.isNotEmpty) 'lists': lists,
    if (prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
  };

  static BomPart? fromMap(Object? raw) {
    if (raw is String) {
      final kind = bomListKindFrom(raw);
      return kind == null ? null : BomPart(kind: kind);
    }
    if (raw is! Map) return null;
    final kind = bomListKindFrom(raw['list'] ?? raw['kind'] ?? raw['type'] ?? raw['art']);
    if (kind == null) return null;
    final assemblies = raw['includeAssemblies'] ?? raw['baugruppen'];
    final totals = raw['totals'] ?? raw['gesamt'];
    final lists = raw['lists'] ?? raw['forms'] ?? raw['listen'];
    return BomPart(
      kind: kind,
      includeAssemblies: assemblies == null || assemblies == true || '$assemblies'.toLowerCase() == 'true',
      totals: totals == true || '$totals'.toLowerCase() == 'true',
      lists: lists is List
          ? [
              for (final l in lists)
                if ('$l'.trim().isNotEmpty) '$l'.trim(),
            ]
          : const [],
      prompt: '${raw['prompt'] ?? raw['text'] ?? ''}'.trim(),
    );
  }
}

/// Die ganze Aufgabe: Erzeugnisbaum und gefragte Listen.
class BomTask {
  const BomTask({required this.root, required this.parts, this.baseQuantity = 1});

  /// Das Erzeugnis (Stufe 0) mit seinem Baum.
  final BomNode root;
  final List<BomPart> parts;

  /// Für wie viele Erzeugnisse die Mengenübersicht gilt (meist 1).
  final double baseQuantity;

  bool get isUsable =>
      root.children.isNotEmpty && parts.isNotEmpty && root.walk().every((e) => e.node.number.trim().isNotEmpty);
  bool get hasUncertain => root.anyUncertain;

  BomTask confirmed() => copyWith(root: root.confirmed());

  BomTask copyWith({BomNode? root, List<BomPart>? parts, double? baseQuantity}) =>
      BomTask(root: root ?? this.root, parts: parts ?? this.parts, baseQuantity: baseQuantity ?? this.baseQuantity);

  /// Kurzfassung (Kartenliste, Antwort-Vorschau).
  String describe() {
    final count = {for (final e in root.walk().skip(1)) e.node.number}.length;
    final lists = [for (final p in parts) p.kind.label].join(' · ');
    return '$lists zu ${'${root.number} ${root.name}'.trim()} ($count Sach-Nr.)';
  }

  Map<String, dynamic> toMap() => {
    'kind': 'bom',
    'root': root.toMap(root: true),
    'parts': [for (final p in parts) p.toMap()],
    if (baseQuantity != 1) 'baseQuantity': baseQuantity,
  };

  static BomTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final root = BomNode.fromMap(raw['root'] ?? raw['tree'] ?? raw['baum'] ?? raw['product'] ?? raw['erzeugnis']);
    if (root == null) return null;
    final list = raw['parts'] ?? raw['lists'] ?? raw['stuecklisten'] ?? raw['stücklisten'];
    var parts = list is List ? [for (final p in list) ?BomPart.fromMap(p)] : <BomPart>[];
    if (parts.isEmpty) parts = [for (final k in BomListKind.values) BomPart(kind: k)];
    final base = parseBomQuantity(raw['baseQuantity'] ?? raw['menge']);
    return BomTask(root: root, parts: parts, baseQuantity: base == null || base <= 0 ? 1 : base);
  }

  // ---------------------------------------------------------------------------
  // Textform für den Editor: eine Zeile je Knoten wie in der
  // Strukturstückliste – "Stufe; Sach-Nr.; Bezeichnung; Menge; Einheit".
  // ---------------------------------------------------------------------------

  /// Der Baum als Text (Zeile 1 = Erzeugnis auf Stufe 0).
  static String outline(BomNode root) => [
    for (final e in root.walk())
      [
        '${e.level}',
        e.node.number,
        e.node.name,
        if (e.level > 0 || e.node.unit.isNotEmpty) bomQuantityText(e.node.quantity),
        if (e.node.unit.isNotEmpty) e.node.unit,
      ].join('; '),
  ].join('\n');

  /// Liest die Textform. Fehler als Text (Zeilennummer + Grund).
  static ({BomNode? root, String? error}) parseOutline(String text) {
    final lines = [
      for (final (i, l) in text.split('\n').indexed)
        if (l.trim().isNotEmpty) (line: i + 1, text: l.trim()),
    ];
    if (lines.isEmpty) return (root: null, error: 'Der Baum ist leer.');
    final rows = <({int level, String nr, String name, double qty, String unit})>[];
    for (final l in lines) {
      final cells = l.text.split(RegExp(r'\s*[;|\t]\s*'));
      final level = int.tryParse(cells.first.trim());
      if (level == null || level < 0) return (root: null, error: 'Zeile ${l.line}: zuerst die Stufe (0, 1, 2 …).');
      if (cells.length < 2 || cells[1].trim().isEmpty) return (root: null, error: 'Zeile ${l.line}: Sach-Nr. fehlt.');
      final qty = cells.length > 3 && cells[3].trim().isNotEmpty ? parseBomQuantity(cells[3]) : 1.0;
      if (qty == null || qty <= 0)
        return (root: null, error: 'Zeile ${l.line}: Menge „${cells[3].trim()}“ ist keine Zahl.');
      rows.add((
        level: level,
        nr: cells[1].trim(),
        name: cells.length > 2 ? cells[2].trim() : '',
        qty: qty,
        unit: cells.length > 4 ? cells[4].trim() : '',
      ));
    }
    if (rows.first.level != 0) return (root: null, error: 'Die erste Zeile ist das Erzeugnis (Stufe 0).');
    if (rows.skip(1).any((r) => r.level == 0)) return (root: null, error: 'Nur ein Erzeugnis auf Stufe 0.');
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].level > rows[i - 1].level + 1) {
        return (
          root: null,
          error: 'Zeile ${lines[i].line}: Stufe ${rows[i].level} direkt nach Stufe ${rows[i - 1].level}.',
        );
      }
    }
    var index = 0;
    BomNode build() {
      final r = rows[index++];
      final children = <BomNode>[];
      while (index < rows.length && rows[index].level == r.level + 1) {
        children.add(build());
      }
      return BomNode(number: r.nr, name: r.name, quantity: r.qty, unit: r.unit, children: children);
    }

    return (root: build(), error: null);
  }
}
