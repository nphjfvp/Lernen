/// Kristallgitter-Aufgaben im Einheitswürfel ([QuestionType.crystal]):
/// Richtungen [u v w] und Ebenen (h k l) einzeichnen oder ablesen, Familien
/// ⟨u v w⟩, Atome in einer Ebene. Die KI liefert nur die gesuchten Indizes –
/// gezeichnet und geprüft wird in der App (siehe CrystalGeometry).
library;

/// Gittertyp: welche Atome im Würfel sitzen.
enum CrystalLattice {
  sc('kubisch primitiv', 'kubisch'),
  bcc('kubisch raumzentriert', 'krz'),
  fcc('kubisch flächenzentriert', 'kfz');

  const CrystalLattice(this.label, this.short);
  final String label;
  final String short;
}

CrystalLattice crystalLatticeFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().trim();
  if (v == 'bcc' || v == 'krz' || v.contains('raum')) return CrystalLattice.bcc;
  if (v == 'fcc' || v == 'kfz' || v.contains('fläch') || v.contains('flaech')) return CrystalLattice.fcc;
  return CrystalLattice.sc;
}

/// Was in einer Teilaufgabe zu tun ist.
enum CrystalPartKind {
  direction('Richtung einzeichnen'),
  readDirection('Richtung ablesen'),
  family('Richtungsfamilie einzeichnen'),
  plane('Ebene einzeichnen'),
  readPlane('Ebene ablesen'),
  planeAtoms('Atome in der Ebene markieren');

  const CrystalPartKind(this.label);
  final String label;

  bool get isPlane => this == plane || this == readPlane || this == planeAtoms;
  bool get isRead => this == readDirection || this == readPlane;
}

CrystalPartKind? crystalPartKindFrom(Object? raw) {
  final v = '${raw ?? ''}'.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (v.isEmpty) return null;
  for (final k in CrystalPartKind.values) {
    if (k.name.toLowerCase() == v) return k;
  }
  if (v.contains('atom')) return CrystalPartKind.planeAtoms;
  if (v.contains('famil')) return CrystalPartKind.family;
  final read = v.contains('read') || v.contains('ables') || v.contains('bestimm') || v.contains('angeb');
  if (v.contains('plane') || v.contains('ebene')) return read ? CrystalPartKind.readPlane : CrystalPartKind.plane;
  if (v.contains('direction') || v.contains('richtung')) return read ? CrystalPartKind.readDirection : CrystalPartKind.direction;
  return null;
}

/// Indizes als Text mit Strich über negativen Zahlen: [1 1̄ 0], (1 1 1), ⟨0 0 1⟩.
String millerText(List<int> v, {String open = '[', String close = ']'}) {
  final parts = [
    for (final n in v)
      n < 0 ? (-n).toString().split('').map((d) => '$d\u0304').join() : '$n',
  ];
  return '$open${parts.join(' ')}$close';
}

/// Liest drei Indizes: "1 -1 0", "1, −1, 0", "[1̄10]", "-110", "(2 0 0)".
List<int>? parseMillerIndices(Object? raw) {
  if (raw is List) {
    final out = <int>[];
    for (final x in raw) {
      final n = x is num ? x.toInt() : int.tryParse('$x'.trim().replaceAll('−', '-'));
      if (n == null) return null;
      out.add(n);
    }
    return out.length == 3 ? out : null;
  }
  var s = '${raw ?? ''}'
      .replaceAll(RegExp(r'[\[\]()⟨⟩<>{}]'), ' ')
      .replaceAll(RegExp('[−–]'), '-')
      .replaceAll('\u0305', '\u0304')
      .trim();
  if (s.isEmpty) return null;
  final separated = RegExp(r'[\s,;]').hasMatch(s);
  final pattern = separated ? RegExp(r'(-?)(\d+)(\u0304?)') : RegExp(r'(-?)(\d)(\u0304?)');
  final out = <int>[];
  for (final m in pattern.allMatches(s)) {
    final n = int.parse(m.group(2)!);
    out.add(m.group(1)!.isNotEmpty || m.group(3)!.isNotEmpty ? -n : n);
  }
  s = s.replaceAll(pattern, '').replaceAll(RegExp(r'[\s,;]'), '');
  if (s.isNotEmpty) return null;
  return out.length == 3 ? out : null;
}

/// Eine Teilaufgabe.
class CrystalPart {
  const CrystalPart({required this.kind, required this.indices, this.lattice, this.uncertain = false, this.prompt = ''});

  final CrystalPartKind kind;

  /// [u v w] bei Richtungen/Familien, (h k l) bei Ebenen.
  final List<int> indices;

  /// Abweichend vom Gitter der Aufgabe (null = das der Aufgabe).
  final CrystalLattice? lattice;

  /// Schlecht lesbar (z.B. ein Strich über einer Zahl) – vor dem Speichern bestätigen.
  final bool uncertain;

  /// Eigener Aufgabentext (sonst ein Standardtext je Art).
  final String prompt;

  bool get isValid =>
      indices.length == 3 &&
      indices.any((n) => n != 0) &&
      indices.every((n) => n.abs() <= 6) &&
      (kind != CrystalPartKind.family || familySize <= 12);

  /// Wie viele Richtungen zur Familie ⟨u v w⟩ gehören (kubisch).
  int get familySize {
    if (indices.length != 3) return 0;
    final seen = <String>{};
    final a = indices.map((n) => n.abs()).toList();
    const perms = [
      [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0],
    ];
    for (final p in perms) {
      for (var signs = 0; signs < 8; signs++) {
        final v = [
          for (var i = 0; i < 3; i++) a[p[i]] * ((signs >> i) & 1 == 1 ? -1 : 1),
        ];
        seen.add(v.join(','));
      }
    }
    return seen.length;
  }

  String get notation => switch (kind) {
        CrystalPartKind.family => millerText(indices, open: '⟨', close: '⟩'),
        CrystalPartKind.plane || CrystalPartKind.readPlane || CrystalPartKind.planeAtoms =>
          millerText(indices, open: '(', close: ')'),
        _ => millerText(indices),
      };

  /// Aufgabentext ohne die Indizes (die stehen daneben, siehe [notation]).
  String get defaultPrompt => switch (kind) {
        CrystalPartKind.direction => 'Zeichne die Richtung ein:',
        CrystalPartKind.readDirection => 'Welche Richtung zeigt der Pfeil? Gib [u v w] an.',
        CrystalPartKind.family => 'Zeichne alle Richtungen der Familie ein:',
        CrystalPartKind.plane => 'Zeichne die Ebene ein:',
        CrystalPartKind.readPlane => 'Welche Ebene ist eingezeichnet? Gib (h k l) an.',
        CrystalPartKind.planeAtoms => 'Tippe alle Atome an, die in dieser Ebene liegen:',
      };

  String get promptText => prompt.trim().isNotEmpty ? prompt.trim() : defaultPrompt;

  CrystalPart copyWith({CrystalPartKind? kind, List<int>? indices, CrystalLattice? lattice, bool clearLattice = false, bool? uncertain, String? prompt}) =>
      CrystalPart(
        kind: kind ?? this.kind,
        indices: indices ?? this.indices,
        lattice: clearLattice ? null : (lattice ?? this.lattice),
        uncertain: uncertain ?? this.uncertain,
        prompt: prompt ?? this.prompt,
      );

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'indices': indices,
        if (lattice != null) 'lattice': lattice!.name,
        if (uncertain) 'uncertain': true,
        if (prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
      };

  static CrystalPart? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = crystalPartKindFrom(raw['kind'] ?? raw['type'] ?? raw['art']);
    final indices = parseMillerIndices(raw['indices'] ?? raw['miller'] ?? raw['target'] ?? raw['hkl'] ?? raw['uvw']);
    if (kind == null || indices == null) return null;
    final lattice = raw['lattice'] ?? raw['gitter'];
    final u = raw['uncertain'] ?? raw['unsicher'];
    return CrystalPart(
      kind: kind,
      indices: indices,
      lattice: lattice == null ? null : crystalLatticeFrom(lattice),
      uncertain: u == true || '$u'.toLowerCase() == 'true',
      prompt: '${raw['prompt'] ?? raw['text'] ?? ''}'.trim(),
    );
  }
}

/// Die ganze Aufgabe: Gitter und Teilaufgaben.
class CrystalTask {
  const CrystalTask({required this.parts, this.lattice = CrystalLattice.sc});

  final List<CrystalPart> parts;
  final CrystalLattice lattice;

  bool get isUsable => parts.isNotEmpty && parts.every((p) => p.isValid);
  bool get hasUncertain => parts.any((p) => p.uncertain);

  CrystalLattice latticeOf(CrystalPart part) => part.lattice ?? lattice;

  CrystalTask confirmed() => copyWith(parts: [for (final p in parts) p.copyWith(uncertain: false)]);

  CrystalTask copyWith({List<CrystalPart>? parts, CrystalLattice? lattice}) =>
      CrystalTask(parts: parts ?? this.parts, lattice: lattice ?? this.lattice);

  /// Kurzfassung (Kartenliste, Antwort-Vorschau).
  String describe() => [
        for (final p in parts) '${p.kind.label} ${p.notation}${latticeOf(p) == CrystalLattice.sc ? '' : ' (${latticeOf(p).short})'}',
      ].join(' · ');

  Map<String, dynamic> toMap() => {
        'kind': 'crystal',
        'lattice': lattice.name,
        'parts': [for (final p in parts) p.toMap()],
      };

  static CrystalTask? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['parts'] ?? raw['teilaufgaben'] ?? raw['tasks'];
    if (list is! List) return null;
    final parts = [for (final p in list) ?CrystalPart.fromMap(p)];
    if (parts.isEmpty) return null;
    return CrystalTask(parts: parts, lattice: crystalLatticeFrom(raw['lattice'] ?? raw['gitter']));
  }
}

