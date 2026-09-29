import 'package:flutter/material.dart';

/// Gewichtung mit deutschem Dezimalkomma und ohne überflüssige Nullen:
/// 1.0 -> "1", 1.5 -> "1,5", 1.25 -> "1,25".
String formatWeight(double weight) {
  var text = ((weight * 100).round() / 100).toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

/// Text zur Gewichtung: "1,5×", bei 0 "Aus".
String weightLabel(double weight) => weight <= 0 ? 'Aus' : '${formatWeight(weight)}×';

/// Regler für eine Gewichtung (siehe Flashcard.weight/Module.weight): wie oft
/// etwas im Vergleich drankommt, von 0,5× bis 3× in Viertelschritten. Mit
/// [allowZero] (Karten) reicht er bis 0 = "Aus": die Frage kommt nie dran.
class WeightSlider extends StatelessWidget {
  const WeightSlider({super.key, required this.value, required this.onChanged, this.allowZero = false});

  final double value;
  final ValueChanged<double> onChanged;

  /// Der Regler geht bis 0 ("Aus"), sonst nur bis [minValue].
  final bool allowZero;

  static const double minValue = 0.5;
  static const double maxValue = 3.0;
  static const double step = 0.25;

  @override
  Widget build(BuildContext context) {
    final min = allowZero ? 0.0 : minValue;
    // Ein Wert außerhalb des Reglerbereichs (z.B. 0,25 ohne Null-Modus) wird
    // auf dessen Rand begrenzt.
    final clamped = value.clamp(min, maxValue).toDouble();
    final label = weightLabel(clamped);
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: clamped,
            min: min,
            max: maxValue,
            divisions: ((maxValue - min) / step).round(),
            label: label,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(label, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
