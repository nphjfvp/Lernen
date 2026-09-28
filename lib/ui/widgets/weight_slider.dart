import 'package:flutter/material.dart';

/// Gewichtung mit deutschem Dezimalkomma und ohne überflüssige Nullen:
/// 1.0 -> "1", 1.5 -> "1,5", 1.25 -> "1,25".
String formatWeight(double weight) {
  var text = ((weight * 100).round() / 100).toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

/// Regler für eine Gewichtung (siehe Flashcard.weight/Module.weight): wie oft
/// etwas im Vergleich drankommt, von 0,5× bis 3× in Viertelschritten.
class WeightSlider extends StatelessWidget {
  const WeightSlider({super.key, required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const double minValue = 0.5;
  static const double maxValue = 3.0;
  static const double step = 0.25;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(minValue, maxValue).toDouble();
    final label = '${formatWeight(clamped)}×';
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: clamped,
            min: minValue,
            max: maxValue,
            divisions: ((maxValue - minValue) / step).round(),
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
