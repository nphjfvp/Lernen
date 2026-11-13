import 'dart:math' as math;

import '../models/visual_scene3d.dart';
import '../models/visual_scene3d_blocks.dart';
import 'ai_service.dart';

/// Prüft eine räumliche Szene geometrisch – ohne KI: Teile, die frei
/// schweben, außerhalb des Raums liegen, keine Ausdehnung haben oder
/// deckungsgleich aufeinander liegen, Pfeile ohne Körper, Beschriftungen
/// übereinander. Genau solche Fehler machen günstige Modelle beim Setzen von
/// Koordinaten.
///
/// Bewusst vorsichtig: lieber eine Auffälligkeit übersehen als eine richtige
/// Szene beanstanden. Kugeln (Kristallgitter!), Raster und bewegte Teile
/// gelten nie als „schwebend“; Formen aus Bausteinen (die rechnet die App
/// selbst) werden nicht beanstandet.
class Scene3DCheck {
  const Scene3DCheck._();

  /// Die Auffälligkeiten der Szene als kurze Sätze, höchstens [max]. Die
  /// Nummern zählen die frei gezeichneten Objekte ab 0 – in der Reihenfolge
  /// von `scene.toMap()['objects']`.
  static List<String> issues(VisualScene3D scene, {int max = 6}) {
    final out = <String>[];
    final free = [
      for (final o in scene.objects)
        if (!o.fromBlock) o,
    ];
    final boxes = {for (final o in scene.objects) o: _bounds(o)};

    bool isSolid(Scene3DObject o) =>
        o.shape == Scene3DShape.sphere || o.shape == Scene3DShape.box || o.shape == Scene3DShape.cylinder;
    final solids = [
      for (final o in scene.objects)
        if (isSolid(o) && boxes[o] != null) o,
    ];

    // Maßstab: Diagonale über alle Körper, sonst der Raum.
    var lo = [double.infinity, double.infinity, double.infinity], hi = [for (final v in lo) -v];
    for (final o in solids) {
      final (a, b) = boxes[o]!;
      lo = [for (var q = 0; q < 3; q++) math.min(lo[q], a[q])];
      hi = [for (var q = 0; q < 3; q++) math.max(hi[q], b[q])];
    }
    final diag = solids.isEmpty
        ? math.sqrt(scene.box.fold<double>(0, (s, v) => s + v * v))
        : math.sqrt([for (var q = 0; q < 3; q++) (hi[q] - lo[q]) * (hi[q] - lo[q])].fold<double>(0, (s, v) => s + v));
    if (!diag.isFinite || diag <= 0) return out;

    String name(Scene3DObject o) {
      final i = free.indexOf(o);
      final text = o.text.trim();
      return 'Objekt $i (${o.shape.name}${text.isEmpty ? '' : ' „${text.length > 24 ? '${text.substring(0, 24)}…' : text}“'})';
    }

    bool moves(Scene3DObject o) => o.keys.any((k) => k.vectors.isNotEmpty || k.points != null);

    // Körper weit außerhalb des Raums – sie zählen nicht als Nachbarn.
    final astray = <Scene3DObject>{};
    List<String> outsideAxes(Scene3DObject o) {
      final b = boxes[o]!;
      return [
        for (var q = 0; q < 3; q++)
          if ((b.$1[q] + b.$2[q]) / 2 < -0.5 * scene.box[q] || (b.$1[q] + b.$2[q]) / 2 > 1.5 * scene.box[q]) 'xyz'[q],
      ];
    }

    for (final o in solids) {
      if (!o.fromBlock && !moves(o) && outsideAxes(o).isNotEmpty) astray.add(o);
    }

    for (final o in free) {
      final b = boxes[o];
      // Ohne Ausdehnung.
      final flat = switch (o.shape) {
        Scene3DShape.sphere => (o.numbers['r'] ?? 1) <= 0,
        Scene3DShape.box => (o.vectors['dims'] ?? const [1.0, 1.0, 1.0]).any((v) => v <= 0),
        Scene3DShape.cylinder => (o.numbers['r'] ?? 1) <= 0 || _dist(o.vectors['from']!, o.vectors['to']!) < 1e-9,
        Scene3DShape.arrow || Scene3DShape.line => _dist(o.vectors['from']!, o.vectors['to']!) < 1e-9,
        _ => false,
      };
      if (flat) {
        out.add('${name(o)}: hat keine Ausdehnung (Länge, Radius oder Maße sind 0).');
        continue;
      }
      if (b == null || !isSolid(o)) continue;

      // Außerhalb des Raums.
      if (astray.contains(o)) {
        final c = [for (var q = 0; q < 3; q++) (b.$1[q] + b.$2[q]) / 2];
        out.add(
          '${name(o)}: liegt weit außerhalb des Raums "box" ${_fmt(scene.box)} '
          '(Mitte bei ${_fmt(c)}, Richtung ${outsideAxes(o).join(', ')}).',
        );
        continue;
      }

      // Schwebt: Quader/Zylinder ohne Kontakt zu irgendeinem anderen Körper.
      if (o.shape == Scene3DShape.sphere || o.copies > 1 || moves(o) || solids.length < 2) continue;
      var gap = double.infinity;
      for (final other in solids) {
        if (identical(other, o) || astray.contains(other)) continue;
        gap = math.min(gap, _gap(b, boxes[other]!));
      }
      final extent = [for (var q = 0; q < 3; q++) b.$2[q] - b.$1[q]]
          .where((v) => v > 1e-9)
          .fold(double.infinity, math.min);
      final tolerance = math.max(diag * 0.03, extent.isFinite ? extent * 0.3 : 0.0);
      if (gap.isFinite && gap > tolerance) {
        out.add('${name(o)}: berührt kein anderes Teil – die Lücke zum nächsten ist etwa ${Scene3DBlocks.fmt(gap)}.');
      }
    }

    // Deckungsgleiche Körper.
    for (var i = 0; i < free.length; i++) {
      for (var j = i + 1; j < free.length; j++) {
        final a = free[i], b = free[j];
        if (a.shape != b.shape || !isSolid(a) || boxes[a] == null || boxes[b] == null) continue;
        final (a0, a1) = boxes[a]!;
        final (b0, b1) = boxes[b]!;
        final same = [for (var q = 0; q < 3; q++) (a0[q] - b0[q]).abs() + (a1[q] - b1[q]).abs()]
            .every((d) => d < diag * 0.01);
        if (same) out.add('${name(a)} und ${name(b)}: liegen deckungsgleich aufeinander.');
      }
    }

    // Pfeile weit weg von jedem Körper.
    if (solids.isNotEmpty) {
      for (final o in free) {
        if (o.shape != Scene3DShape.arrow || moves(o)) continue;
        var near = double.infinity;
        for (final end in [o.vectors['from']!, o.vectors['to']!]) {
          for (final s in solids) {
            near = math.min(near, _gap((end, end), boxes[s]!));
          }
        }
        if (near > diag * 0.15) {
          out.add(
            '${name(o)}: hängt frei im Raum – der Pfeil berührt keinen Körper (Abstand etwa ${Scene3DBlocks.fmt(near)}).',
          );
        }
      }
    }

    // Beschriftungen aufeinander.
    final texts = [
      for (final o in free)
        if (o.shape == Scene3DShape.text && !moves(o)) o,
    ];
    for (var i = 0; i < texts.length; i++) {
      for (var j = i + 1; j < texts.length; j++) {
        if (texts[i].text != texts[j].text && _dist(texts[i].vectors['at']!, texts[j].vectors['at']!) < diag * 0.012) {
          out.add('${name(texts[i])} und ${name(texts[j])}: die Beschriftungen liegen aufeinander.');
        }
      }
    }
    return out.length > max ? out.sublist(0, max) : out;
  }

  static String _fmt(List<double> v) => '[${v.map(Scene3DBlocks.fmt).join(' | ')}]';

  static double _dist(List<double> a, List<double> b) =>
      math.sqrt([for (var q = 0; q < 3; q++) (a[q] - b[q]) * (a[q] - b[q])].fold<double>(0, (s, v) => s + v));

  /// Abstand zweier achsparalleler Quader (0 bei Berührung/Überschneidung).
  static double _gap((List<double>, List<double>) a, (List<double>, List<double>) b) {
    var sum = 0.0;
    for (var q = 0; q < 3; q++) {
      final d = math.max(0.0, math.max(a.$1[q] - b.$2[q], b.$1[q] - a.$2[q]));
      sum += d * d;
    }
    return math.sqrt(sum);
  }

  /// Umhüllender Quader eines Objekts im Anfangszustand (mit Raster-Kopien).
  static (List<double>, List<double>)? _bounds(Scene3DObject o) {
    final pts = <List<double>>[];
    var r = 0.0;
    switch (o.shape) {
      case Scene3DShape.sphere:
        final at = o.vectors['at'];
        if (at == null) return null;
        r = math.max(0.0, o.numbers['r'] ?? 0);
        pts.add(at);
      case Scene3DShape.box:
        final at = o.vectors['at'];
        if (at == null) return null;
        final size = o.numbers['size'] ?? 1;
        final dims = o.vectors['dims'] ?? [size, size, size];
        pts
          ..add(at)
          ..add([for (var q = 0; q < 3; q++) at[q] + dims[q]]);
      case Scene3DShape.cylinder || Scene3DShape.line || Scene3DShape.arrow:
        final from = o.vectors['from'], to = o.vectors['to'];
        if (from == null || to == null) return null;
        if (o.shape == Scene3DShape.cylinder) r = math.max(o.numbers['r'] ?? 0, o.numbers['r2'] ?? 0);
        pts
          ..add(from)
          ..add(to);
      case Scene3DShape.polygon:
        pts.addAll(o.points);
      case Scene3DShape.text:
        final at = o.vectors['at'];
        if (at == null) return null;
        pts.add(at);
    }
    if (pts.isEmpty) return null;
    final lo = [for (var q = 0; q < 3; q++) pts.map((p) => p[q]).reduce(math.min) - r];
    final hi = [for (var q = 0; q < 3; q++) pts.map((p) => p[q]).reduce(math.max) + r];
    // Raster: alle Kopien.
    for (var q = 0; q < 3; q++) {
      final span = (o.n[q] - 1) * o.d[q];
      if (span > 0) hi[q] += span;
      if (span < 0) lo[q] += span;
    }
    return (lo, hi);
  }
}

/// Ergebnis von [Scene3DRepair.run].
class Scene3DRepairResult {
  const Scene3DRepairResult({required this.scene, required this.before, required this.after, required this.rounds});

  /// Die beste Szene (JSON) – das Original, wenn keine Runde besser war.
  final Map<String, dynamic> scene;

  /// Auffälligkeiten des Originals bzw. der besten Szene.
  final List<String> before;
  final List<String> after;

  /// So viele Korrekturrunden liefen (jede ist eine KI-Anfrage).
  final int rounds;

  bool get improved => after.length < before.length;
}

/// Lässt eine auffällige 3D-Szene vom selben Modell nachbessern. Übernommen
/// wird eine Korrektur nur, wenn sie WENIGER Auffälligkeiten hat – sonst
/// bleibt das Original. Scheitert eine Runde (Fehler, unlesbare Antwort),
/// zählt sie einfach nicht.
class Scene3DRepair {
  const Scene3DRepair._();

  static Future<Scene3DRepairResult> run({
    required AiService ai,
    required Map<String, dynamic> scene,
    String wish = '',
    int maxRounds = 2,
  }) async {
    final parsed = VisualScene3D.fromMap(scene);
    final before = parsed == null ? const <String>[] : Scene3DCheck.issues(parsed, max: 50);
    var best = scene;
    var bestIssues = before;
    var rounds = 0;
    while (bestIssues.isNotEmpty && rounds < maxRounds) {
      rounds++;
      try {
        final fixed = await ai.repairScene3d(scene: best, issues: bestIssues.take(8).toList(), wish: wish);
        final candidate = VisualScene3D.fromMap(fixed);
        if (candidate == null) continue;
        final issues = Scene3DCheck.issues(candidate, max: 50);
        if (issues.length < bestIssues.length) {
          best = fixed;
          bestIssues = issues;
        }
      } catch (_) {
        // Diese Runde zählt nicht.
      }
    }
    return Scene3DRepairResult(scene: best, before: before, after: bestIssues, rounds: rounds);
  }
}
