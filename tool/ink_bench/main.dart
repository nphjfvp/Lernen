// Messseite für das Stift-Blatt im Browser (nicht Teil der App):
//   flutter build web -t tool/ink_bench/main.dart -o build/ink_bench
// Verhält sich wie „Selbst rechnen“ mit Stift: setzt der Stift in einer
// anderen Zelle an, wird die vorige Zelle gerendert (wie zum Lesen); nach dem
// Absetzen wird das Blatt neu gezeichnet. Zeiten gehen als „BENCH …“ in die
// Browser-Konsole.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lernen/theme/app_colors.dart';
import 'package:lernen/ui/tasks/ink_sheet.dart';

void main() => runApp(const _Bench());

class _Bench extends StatefulWidget {
  const _Bench();

  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> {
  final _ctrl = InkSheetController();
  final _dirty = <InkCell>{};
  final _watch = Stopwatch()..start();

  void _log(String what) {
    final at = _watch.elapsedMicroseconds / 1000;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // ignore: avoid_print
      print('BENCH $what at=${at.toStringAsFixed(1)} frame=${(_watch.elapsedMicroseconds / 1000).toStringAsFixed(1)}');
    });
  }

  @override
  void initState() {
    super.initState();
    // Ein schon gut gefülltes Blatt: 8 Zeilen mit je 8 Strichen (?fill=0: leer).
    final fill = int.tryParse(Uri.base.queryParameters['fill'] ?? '') ?? 8;
    for (var row = 0; row < fill; row++) {
      for (var k = 0; k < 8; k++) {
        final x0 = 60.0 + k * 40, y0 = row * InkSheetController.rowHeight + 20;
        final pts = [for (var i = 0; i <= 40; i++) Offset(x0 + i * 0.6, y0 + (i % 10) * 2.2)];
        _ctrl.add(pts, 900, widths: [for (var i = 0; i <= 40; i++) 2.2 + (i % 5) * 0.2]);
      }
    }
  }

  Future<void> _read(InkCell cell) async {
    final sw = Stopwatch()..start();
    final png = await renderInkPng(_ctrl.strokesIn(cell));
    // ignore: avoid_print
    print('BENCH read row=${cell.row} bytes=${png?.length} ms=${sw.elapsedMilliseconds}');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(extensions: const [AppColors.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 900,
              child: InkSheet(
                controller: _ctrl,
                onStrokeStart: (cell) {
                  _log('down row=${cell.row}');
                  final others = {for (final c in _dirty) if (c != cell) c};
                  _dirty.removeAll(others);
                  for (final c in others) {
                    _read(c);
                  }
                },
                onCellsChanged: (cells) {
                  _dirty.addAll(cells);
                  _log('up cells=${cells.length}');
                },
              ),
            ),
          ),
        ),
      );
}
