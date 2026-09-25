import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../services/math_markup.dart';

/// Text mit eingebetteten Formeln: `$…$`/`\(…\)` im Satz, `$$…$$`/`\[…\]`
/// abgesetzt (siehe MathMarkup). Ohne Formeln ein ganz normales [Text] –
/// daher überall einsetzbar, wo Fragen, Antworten oder KI-Texte stehen. Eine
/// Formel, die sich nicht setzen lässt, erscheint als Rohtext statt die
/// Karte unbenutzbar zu machen.
class MathText extends StatelessWidget {
  const MathText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final segments = MathMarkup.split(text);
    if (!segments.any((s) => s.isMath)) {
      return Text(text, style: style, textAlign: textAlign);
    }
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    for (final segment in segments) {
      if (!segment.isMath) {
        spans.add(TextSpan(text: segment.content));
        continue;
      }
      final math = Math.tex(
        segment.content,
        mathStyle: segment.isDisplay ? MathStyle.display : MathStyle.text,
        textStyle: effective,
        onErrorFallback: (_) => Text(segment.toString(), style: effective),
      );
      if (segment.isDisplay) {
        // Abgesetzte Formel: eigene Zeile, bei Überbreite horizontal scrollbar.
        spans
          ..add(const TextSpan(text: '\n'))
          ..add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: math),
          ))
          ..add(const TextSpan(text: '\n'));
      } else {
        spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, baseline: TextBaseline.alphabetic, child: math));
      }
    }
    return Text.rich(TextSpan(children: spans), style: style, textAlign: textAlign);
  }
}
