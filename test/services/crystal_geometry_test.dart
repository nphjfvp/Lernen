import 'package:flutter_test/flutter_test.dart';
import 'package:lernen/models/crystal_task.dart';
import 'package:lernen/services/crystal_geometry.dart';

void main() {
  group('Indizes lesen und schreiben', () {
    test('verschiedene Schreibweisen', () {
      expect(parseMillerIndices('1 -1 0'), [1, -1, 0]);
      expect(parseMillerIndices('[1̄10]'), [-1, 1, 0]);
      expect(parseMillerIndices('(1 1 1)'), [1, 1, 1]);
      expect(parseMillerIndices('−1, 2, 0'), [-1, 2, 0]);
      expect(parseMillerIndices('-110'), [-1, 1, 0]);
      expect(parseMillerIndices([2, 0, '-1']), [2, 0, -1]);
      expect(parseMillerIndices('1 1'), isNull);
      expect(parseMillerIndices('a b c'), isNull);
    });

    test('Strich über negativen Zahlen', () {
      expect(millerText([1, -1, 0]), '[1 1̄ 0]');
      expect(millerText([1, 1, 1], open: '(', close: ')'), '(1 1 1)');
    });

    test('Aufgabe speichern und wieder lesen', () {
      const task = CrystalTask(lattice: CrystalLattice.fcc, parts: [
        CrystalPart(kind: CrystalPartKind.plane, indices: [1, 1, 0]),
        CrystalPart(kind: CrystalPartKind.readDirection, indices: [2, -2, 1], uncertain: true),
      ]);
      final again = CrystalTask.fromMap(task.toMap())!;
      expect(again.toMap(), task.toMap());
      expect(task.toMap()['kind'], 'crystal');
      expect(again.hasUncertain, isTrue);
      expect(again.confirmed().hasUncertain, isFalse);
    });

    test('tolerant: Art und Gitter auf Deutsch', () {
      final t = CrystalTask.fromMap({
        'gitter': 'kfz',
        'parts': [
          {'art': 'Ebene einzeichnen', 'hkl': '(1 1 1)'},
          {'type': 'Richtung ablesen', 'uvw': [1, 2, 0]},
          {'kind': 'Atome in der Ebene', 'indices': '111'},
          {'kind': 'unbekannt', 'indices': '111'},
        ],
      })!;
      expect(t.lattice, CrystalLattice.fcc);
      expect(t.parts.map((p) => p.kind), [CrystalPartKind.plane, CrystalPartKind.readDirection, CrystalPartKind.planeAtoms]);
    });
  });

  group('Richtungen', () {
    test('[111] vom Ursprung ist richtig, andersherum und falsches Vorzeichen werden erkannt', () {
      expect(CrystalGeometry.judgeDirection([1, 1, 1], [0, 0, 0], [2, 2, 2]).ok, isTrue);
      final back = CrystalGeometry.judgeDirection([1, 1, 1], [2, 2, 2], [0, 0, 0]);
      expect(back.ok, isFalse);
      expect(back.text, contains('andersherum'));
      final sign = CrystalGeometry.judgeDirection([1, 1, 1], [0, 0, 2], [2, 2, 0]);
      expect(sign.text, contains('bei z stimmt das Vorzeichen nicht'));
    });

    test('[1̄1̄1] mit verschobenem Ursprung, halbe Schritte werden gekürzt', () {
      final v = CrystalGeometry.judgeDirection([-1, -1, 1], [2, 2, 0], [0, 0, 2]);
      expect(v.ok, isTrue);
      expect(v.text, contains('Ursprung nach (1, 1, 0)'));
      // Von (0,1,0) nach (1,0,½): (1, −1, ½) → [2 2̄ 1].
      expect(CrystalGeometry.directionOf([0, 2, 0], [2, 0, 1]), [2, -2, 1]);
      expect(CrystalGeometry.judgeDirection([2, -2, 1], [0, 2, 0], [2, 0, 1]).ok, isTrue);
    });

    test('Lage, in der die App zeichnet', () {
      List<List<int>> seg(List<int> v) {
        final s = CrystalGeometry.gridSegment(v)!;
        return [s.$1, s.$2];
      }

      expect(seg([1, 1, 1]), [[0, 0, 0], [2, 2, 2]]);
      expect(seg([-1, -1, 1]), [[2, 2, 0], [0, 0, 2]]);
      expect(seg([1, 2, 0]), [[0, 0, 0], [1, 2, 0]]);
      expect(CrystalGeometry.gridSegment([1, 2, 3]), isNull);
      expect(CrystalGeometry.drawableDirection([1, 2, 3]), isFalse);
    });

    test('Ablesen: gekürzt, nicht gekürzt, andersherum', () {
      expect(CrystalGeometry.judgeReadDirection([2, -2, 1], [2, -2, 1]).ok, isTrue);
      expect(CrystalGeometry.judgeReadDirection([1, 1, 0], [2, 2, 0]).text, contains('gekürzt'));
      expect(CrystalGeometry.judgeReadDirection([2, -2, 1], [-2, 2, -1]).text, contains('andersherum'));
      expect(CrystalGeometry.judgeReadDirection([1, 1, 0], null).ok, isFalse);
    });

    test('Familien', () {
      expect(CrystalGeometry.familyMembers([0, 0, 1]), hasLength(6));
      expect(CrystalGeometry.familyMembers([1, 1, 1]), hasLength(8));
      expect(CrystalGeometry.familyMembers([1, 1, 0]), hasLength(12));
      expect(CrystalGeometry.familyMembers([0, 0, 1]).first, [0, 0, 1]);
    });
  });

  group('Ebenen', () {
    test('(110) durch drei Punkte und über Achsenabschnitte', () {
      final r = CrystalGeometry.planeFromPoints([
        [2, 0, 0], [0, 2, 0], [0, 2, 2],
      ]);
      expect(r.plane!.n, [1, 1, 0]);
      expect(r.plane!.d, 1);
      expect(r.plane!.millerFrom(const [0, 0, 0]), [1, 1, 0]);
      expect(r.plane!.interceptsFrom(const [0, 0, 0]), ['1', '1', '∞']);
      expect(CrystalGeometry.judgePlane([1, 1, 0], r.plane).ok, isTrue);
      final i = CrystalGeometry.planeFromIntercepts(['1', '1', '∞'])!;
      expect(CrystalGeometry.judgePlane([1, 1, 0], i).ok, isTrue);
    });

    test('parallele Ebene an anderer Stelle ist (2 2 0), nicht (1 1 0)', () {
      final half = CrystalGeometry.planeFromIntercepts(['½', '½', '∞'])!;
      expect(half.millerFrom(const [0, 0, 0]), [2, 2, 0]);
      final v = CrystalGeometry.judgePlane([1, 1, 0], half);
      expect(v.ok, isFalse);
      expect(v.text, contains('Parallel'));
      expect(v.text, contains('(2 2 0)'));
    });

    test('(111) auch als x + y + z = 2 (Achsenabschnitte 2) richtig', () {
      final r = CrystalGeometry.planeFromPoints([
        [2, 2, 0], [2, 0, 2], [0, 2, 2],
      ]);
      expect(CrystalGeometry.judgePlane([1, 1, 1], r.plane).ok, isTrue);
    });

    test('negative Indizes: (1 1̄ 0) geht durch den verschobenen Ursprung', () {
      final std = CrystalGeometry.standardPlane([1, -1, 0]);
      expect(std.equation, 'x − y = 0');
      final r = CrystalGeometry.planeFromPoints([
        [0, 0, 0], [2, 2, 0], [0, 0, 2],
      ]);
      expect(CrystalGeometry.judgePlane([1, -1, 0], r.plane).ok, isTrue);
      // Eine Ebene durch den Ursprung passt nicht zu (1 1 0).
      final through0 = CrystalGeometry.planeFromPoints([
        [0, 0, 0], [0, 0, 2], [2, 2, 0],
      ]);
      expect(CrystalGeometry.judgePlane([1, 1, 0], through0.plane).ok, isFalse);
    });

    test('drei Punkte auf einer Geraden', () {
      final r = CrystalGeometry.planeFromPoints([
        [0, 0, 0], [1, 1, 1], [2, 2, 2],
      ]);
      expect(r.collinear, isTrue);
      expect(CrystalGeometry.judgePlane([1, 1, 1], null, collinear: true).text, contains('Geraden'));
    });

    test('Schnitt mit dem Würfel', () {
      expect(CrystalGeometry.section(CrystalGeometry.standardPlane([1, 1, 1])), hasLength(3));
      expect(CrystalGeometry.section(CrystalGeometry.standardPlane([1, 1, 0])), hasLength(4));
      expect(CrystalGeometry.section(CrystalGeometry.standardPlane([1, 0, 0])), hasLength(4));
    });

    test('Ablesen', () {
      expect(CrystalGeometry.judgeReadPlane([1, 1, 1], [1, 1, 1]).ok, isTrue);
      expect(CrystalGeometry.judgeReadPlane([1, 1, 0], [-1, -1, 0]).ok, isTrue);
      expect(CrystalGeometry.judgeReadPlane([1, 1, 0], [2, 2, 0]).ok, isFalse);
    });
  });

  group('Atome in der Ebene', () {
    test('kfz (111): 3 Ecken + 3 Flächenmitten, kfz (110): 4 Ecken + 2 Flächenmitten', () {
      final a111 = CrystalGeometry.atomsIn([1, 1, 1], CrystalLattice.fcc);
      expect(a111, hasLength(6));
      expect(CrystalGeometry.atomsSummary(a111), '3 Ecken, 3 Flächenmitten');
      expect(CrystalGeometry.atomsIn([1, 1, 0], CrystalLattice.fcc), hasLength(6));
      // krz (110): 4 Ecken + Würfelmitte.
      expect(CrystalGeometry.atomsSummary(CrystalGeometry.atomsIn([1, 1, 0], CrystalLattice.bcc)), '4 Ecken, die Würfelmitte');
    });

    test('Prüfen: richtig, zu viel, zu wenig', () {
      final want = CrystalGeometry.atomsIn([1, 1, 1], CrystalLattice.fcc);
      expect(CrystalGeometry.judgeAtoms([1, 1, 1], CrystalLattice.fcc, want).ok, isTrue);
      final extra = CrystalGeometry.judgeAtoms([1, 1, 1], CrystalLattice.fcc, [...want, [0, 0, 0]]);
      expect(extra.text, contains('(0, 0, 0) liegt nicht in der Ebene x + y + z = 1'));
      expect(CrystalGeometry.judgeAtoms([1, 1, 1], CrystalLattice.fcc, want.take(4).toList()).text, contains('es fehlen noch 2'));
    });
  });

  test('Prüfung der Aufgabe: nicht zeichenbare Teile werden gemeldet', () {
    const ok = CrystalTask(parts: [
      CrystalPart(kind: CrystalPartKind.direction, indices: [1, 1, 1]),
      CrystalPart(kind: CrystalPartKind.plane, indices: [1, 1, 0]),
      CrystalPart(kind: CrystalPartKind.family, indices: [0, 0, 1]),
    ]);
    expect(CrystalGeometry.problems(ok), isEmpty);
    expect(CrystalGeometry.playable(ok), isTrue);
    const bad = CrystalTask(parts: [
      CrystalPart(kind: CrystalPartKind.direction, indices: [1, 2, 3]),
      CrystalPart(kind: CrystalPartKind.plane, indices: [1, 2, 3]),
      CrystalPart(kind: CrystalPartKind.family, indices: [1, 2, 0]),
    ]);
    final problems = CrystalGeometry.problems(bad);
    expect(problems, hasLength(3));
    expect(problems[1], contains('Ebene ablesen'));
  });

  test('Tipps nennen konkrete Punkte bzw. Achsenabschnitte', () {
    final dir = CrystalGeometry.hints(const CrystalPart(kind: CrystalPartKind.direction, indices: [-1, -1, 1]), CrystalLattice.sc);
    expect(dir.last, 'Starte bei (1, 1, 0) und gehe nach (0, 0, 1).');
    final plane = CrystalGeometry.hints(const CrystalPart(kind: CrystalPartKind.plane, indices: [1, 1, 0]), CrystalLattice.fcc);
    expect(plane.first, contains('1, 1, ∞'));
    expect(plane.last, startsWith('Tippe '));
  });
}
