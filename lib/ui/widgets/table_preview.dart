import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/flashcard.dart';
import '../../services/answer_checker.dart';
import '../../theme/app_colors.dart';
import 'math_text.dart';

/// Eine Tabellen-Frage zum Ansehen (Kartenliste, Vorschau): vorgegebene
/// Zellen normal, auszufüllende mit ihrer Lösung hervorgehoben.
class TablePreview extends StatelessWidget {
  const TablePreview({super.key, required this.rows});

  final List<List<QuestionTableCell>> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (rows.isEmpty) {
      return Text('Keine Tabelle hinterlegt.', style: TextStyle(color: c.danger, fontSize: 12.5));
    }
    final columns = rows.fold<int>(0, (n, r) => max(n, r.length));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: c.border, borderRadius: BorderRadius.circular(6)),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: r == 0 ? BoxDecoration(color: c.surfaceAlt) : null,
              children: [
                for (var col = 0; col < columns; col++)
                  Builder(builder: (context) {
                    final cell = col < rows[r].length ? rows[r][col] : const QuestionTableCell(text: '');
                    return Container(
                      constraints: const BoxConstraints(maxWidth: 220),
                      color: cell.given ? null : c.goodSoft,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: MathText(
                        cell.given ? cell.text : AnswerChecker.solutionLabel(cell.text),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: r == 0 && cell.given ? FontWeight.w700 : FontWeight.w400,
                          color: cell.given ? c.ink : c.good,
                        ),
                      ),
                    );
                  }),
              ],
            ),
        ],
      ),
    );
  }
}
