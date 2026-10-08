import 'package:flutter/material.dart';

import '../../models/bom_task.dart';
import '../../services/bom_calculator.dart';
import '../../theme/app_colors.dart';

/// Zeichnet den Erzeugnisbaum wie im Skript: Stufen von oben nach unten,
/// Mengen an den Verbindungslinien. Breite Bäume lassen sich seitlich
/// scrollen; Antippen eines Knotens meldet die Sach-Nr. ([onTapNode]).
class BomTreeView extends StatelessWidget {
  const BomTreeView({super.key, required this.root, this.assemblies = const {}, this.onTapNode, this.highlight});

  final BomNode root;

  /// Sach-Nr. mit eigener Stückliste (werden hervorgehoben).
  final Set<String> assemblies;
  final ValueChanged<String>? onTapNode;
  final String? highlight;

  static const _boxW = 96.0, _boxH = 46.0, _gap = 12.0, _rowH = 82.0, _labelW = 52.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final layout = _layout();
    final maxLevel = layout.fold(0, (m, e) => e.level > m ? e.level : m);
    final leaves = layout.fold(0.0, (m, e) => e.slot > m ? e.slot : m) + 1;
    final width = _labelW + leaves * (_boxW + _gap);
    final height = (maxLevel + 1) * _rowH - (_rowH - _boxH) + 4;

    Offset topLeft(_Placed p) => Offset(_labelW + p.slot * (_boxW + _gap), p.level * _rowH);

    return Container(
      key: const ValueKey('bom-tree'),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(
                    edges: [
                      for (final p in layout)
                        if (p.parent != null)
                          (
                            topLeft(layout[p.parent!]) + const Offset(_boxW / 2, _boxH),
                            topLeft(p) + const Offset(_boxW / 2, 0),
                          ),
                    ],
                    color: c.inkMuted,
                  ),
                ),
              ),
              for (var level = 0; level <= maxLevel; level++)
                Positioned(
                  left: 0,
                  top: level * _rowH + _boxH / 2 - 8,
                  child: Text('Stufe $level', style: TextStyle(fontSize: 10.5, color: c.inkMuted)),
                ),
              for (final (i, p) in layout.indexed) ...[
                if (p.parent != null)
                  Positioned(
                    left: topLeft(p).dx + _boxW / 2 + 4,
                    top: topLeft(p).dy - 17,
                    child: Text(
                      '${bomQuantityText(p.node.quantity)}${p.node.unit.isEmpty ? '' : ' ${p.node.unit}'}',
                      key: ValueKey('bom-qty-$i'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: p.node.uncertain ? c.warn : c.ink,
                      ),
                    ),
                  ),
                Positioned(left: topLeft(p).dx, top: topLeft(p).dy, width: _boxW, height: _boxH, child: _box(c, p, i)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _box(AppColors c, _Placed p, int i) {
    final isAssembly = assemblies.contains(p.node.number) || p.node.children.isNotEmpty;
    final selected = highlight != null && highlight == p.node.number;
    return Material(
      color: selected ? c.accentSoft : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: p.node.uncertain ? c.warn : (isAssembly ? c.accent : c.border),
          width: isAssembly || selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey('bom-node-$i'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTapNode == null ? null : () => onTapNode!(p.node.number),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                p.node.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              if (p.node.name.isNotEmpty)
                Text(
                  p.node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: c.inkMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Blätter bekommen nebeneinander liegende Plätze, Eltern stehen mittig
  /// über ihren Kindern.
  List<_Placed> _layout() {
    final out = <_Placed>[];
    var next = 0.0;
    int place(BomNode n, int level, int? parent) {
      final index = out.length;
      out.add(_Placed(n, level, parent));
      if (n.children.isEmpty) {
        out[index].slot = next++;
      } else {
        final kids = [for (final c in n.children) place(c, level + 1, index)];
        out[index].slot = (out[kids.first].slot + out[kids.last].slot) / 2;
      }
      return index;
    }

    place(root, 0, null);
    return out;
  }
}

class _Placed {
  _Placed(this.node, this.level, this.parent);
  final BomNode node;
  final int level;
  final int? parent;
  double slot = 0;
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.edges, required this.color});

  final List<(Offset, Offset)> edges;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    for (final (a, b) in edges) {
      final midY = (a.dy + b.dy) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(a.dx, midY)
          ..lineTo(b.dx, midY)
          ..lineTo(b.dx, b.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.edges != edges || old.color != color;
}

/// Die Musterlösung einer Teilaufgabe als Tabelle(n).
class BomSolutionTables extends StatelessWidget {
  const BomSolutionTables({super.key, required this.calc, required this.part});

  final BomCalculator calc;
  final BomPart part;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return switch (part.kind) {
      BomListKind.overview => _table(
        c,
        part.kind.label,
        const ['Pos.', 'Sach-Nr.', 'Bezeichnung', 'Menge'],
        [
          for (final (i, r) in calc.overview(includeAssemblies: part.includeAssemblies).indexed)
            ['${i + 1}', r.number, r.name, r.quantityText],
        ],
      ),
      BomListKind.structure => _table(
        c,
        part.kind.label,
        const ['Stufe', 'Sach-Nr.', 'Bezeichnung', 'Menge'],
        [
          for (final r in calc.structure(totals: part.totals))
            ['${'.' * r.level}${r.level}', r.number, r.name, r.quantityText],
        ],
      ),
      BomListKind.modular => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in calc.modularLists(part)) ...[
            _table(
              c,
              '${part.kind.label} ${calc.label(l)}',
              const ['Pos.', 'Sach-Nr.', 'Bezeichnung', 'Menge', 'AK'],
              [
                for (final (i, r) in calc.modular(l).indexed) ['${i + 1}', r.number, r.name, r.quantityText, '${r.ak}'],
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    };
  }

  static Widget _table(AppColors c, String title, List<String> headers, List<List<String>> rows) {
    TextStyle style(bool head) => TextStyle(fontSize: 12.5, fontWeight: head ? FontWeight.w700 : FontWeight.w400);
    Widget cell(String t, bool head) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Text(t, style: style(head)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        Table(
          border: TableBorder.all(color: c.border),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: {2: const FlexColumnWidth()},
          children: [
            TableRow(
              decoration: BoxDecoration(color: c.surfaceAlt),
              children: [for (final h in headers) cell(h, true)],
            ),
            for (final r in rows) TableRow(children: [for (final t in r) cell(t, false)]),
          ],
        ),
      ],
    );
  }
}
