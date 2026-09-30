import 'package:flutter/material.dart';

import '../../services/calc_engine.dart';
import '../../services/calc_plan.dart';
import '../../theme/app_colors.dart';
import '../lab/lab_widgets.dart';
import '../widgets/math_text.dart';

/// Eine gegebene Größe zum Prüfen und Korrigieren: Name, wie es im Bild bzw.
/// Text stand, und ein Feld mit dem Wert (Reihen mit `;` getrennt). Ein
/// gültig eingegebener Wert kommt sofort bei [onChanged] an – die Rechnung
/// läuft danach neu.
class CalcGivenRow extends StatefulWidget {
  const CalcGivenRow({super.key, required this.given, required this.onChanged});

  final CalcGiven given;
  final void Function(CalcVec values) onChanged;

  @override
  State<CalcGivenRow> createState() => _CalcGivenRowState();
}

class _CalcGivenRowState extends State<CalcGivenRow> {
  late final TextEditingController _controller = TextEditingController(text: widget.given.valuesText);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edited(String text) {
    final parts = text.split(RegExp(r'[;\n]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    final values = [for (final p in parts) CalcEngine.parseNumber(p)];
    if (parts.isEmpty || values.contains(null)) {
      setState(() => _error = parts.isEmpty ? 'Bitte einen Wert eingeben.' : 'Das ist keine Zahl.');
      return;
    }
    setState(() => _error = null);
    widget.onChanged([for (final v in values) v!]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = widget.given;
    final note = [
      if (g.name.trim().isNotEmpty) g.name.trim(),
      if (g.raw.trim().isNotEmpty) 'gelesen: ${g.raw.trim()}',
      if (g.isConstant) 'Konstante',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(g.symbol, style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: ValueKey('calc-given-${g.symbol}'),
                  controller: _controller,
                  onChanged: _edited,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixText: g.unit,
                    errorText: _error,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  ),
                ),
                if (note.isNotEmpty || g.uncertain)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                      TextSpan(children: [
                        if (g.uncertain)
                          TextSpan(
                            text: 'Unsicher gelesen – bitte prüfen. ',
                            style: TextStyle(color: c.warn, fontWeight: FontWeight.w600),
                          ),
                        TextSpan(text: note),
                      ]),
                      style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ein Rechenschritt: Formel, eingesetzte Werte (bzw. Tabelle bei Messreihen)
/// und das Ergebnis; Fehler stehen mit Grund da.
class CalcStepCard extends StatelessWidget {
  const CalcStepCard({super.key, required this.index, required this.result, required this.isFinal});

  final int index;
  final CalcStepResult result;
  final bool isFinal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final step = result.step;
    final formula = step.latex.trim().isNotEmpty
        ? MathText('\$${step.latex}\$', style: const TextStyle(fontSize: 16))
        : Text('${step.symbol} = ${CalcEngine.substitute(step.expression, const {})}',
            style: const TextStyle(fontSize: 14.5, fontFamily: 'monospace'));
    final values = result.values;
    return LabCard(
      key: ValueKey('calc-step-${step.symbol}'),
      tint: isFinal && result.ok ? c.accentSoft.withValues(alpha: 0.45) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                child: Text('$index', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.name.trim().isEmpty ? step.symbol : step.name.trim(),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (isFinal && result.ok)
                Text('Ergebnis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentOnSoft)),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: formula),
          if (step.explanation.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(step.explanation.trim(), style: TextStyle(fontSize: 12.5, color: c.inkMuted, height: 1.35)),
            ),
          const SizedBox(height: 8),
          if (!result.ok)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(10)),
              child: Text('Nicht berechenbar: ${result.error}', style: TextStyle(fontSize: 13, color: c.danger)),
            )
          else ...[
            if (result.substitution != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(
                  '${step.symbol} = ${result.substitution}',
                  style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace', height: 1.35),
                ),
              ),
            if (values != null && values.length > 1) _SeriesTable(result: result),
            if (values != null && values.length == 1)
              SelectableText(
                '${step.symbol} = ${result.valueText}',
                key: ValueKey('calc-value-${step.symbol}'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
          ],
        ],
      ),
    );
  }
}

/// Messreihe: je Zeile die verwendeten Größen und das Ergebnis.
class _SeriesTable extends StatelessWidget {
  const _SeriesTable({required this.result});

  final CalcStepResult result;

  @override
  Widget build(BuildContext context) {
    final values = result.values!;
    final inputs = result.inputs.entries.where((e) => e.value.length > 1).toList();
    final unit = result.step.unit.trim();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: ValueKey('calc-series-${result.step.symbol}'),
        headingRowHeight: 34,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 34,
        columnSpacing: 22,
        horizontalMargin: 8,
        columns: [
          const DataColumn(label: Text('#')),
          for (final e in inputs) DataColumn(label: Text(e.key), numeric: true),
          DataColumn(label: Text(unit.isEmpty ? result.step.symbol : '${result.step.symbol} in $unit'), numeric: true),
        ],
        rows: [
          for (var i = 0; i < values.length; i++)
            DataRow(cells: [
              DataCell(Text('${i + 1}')),
              for (final e in inputs) DataCell(Text(CalcEngine.format(e.value[i < e.value.length ? i : 0]))),
              DataCell(Text(CalcEngine.format(values[i]), style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
        ],
      ),
    );
  }
}

/// Aufzählung mit Überschrift (Annahmen, Hinweise, was fehlt).
class CalcBulletList extends StatelessWidget {
  const CalcBulletList({super.key, required this.title, required this.items, this.color});

  final String title;
  final List<String> items;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color ?? c.inkMuted)),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('•  $item', style: const TextStyle(fontSize: 13, height: 1.35)),
            ),
        ],
      ),
    );
  }
}
