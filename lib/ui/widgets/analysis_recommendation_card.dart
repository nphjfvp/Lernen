import 'package:flutter/material.dart';

import '../../models/app_settings.dart';
import '../../services/content_analyzer.dart';
import '../../theme/app_colors.dart';

/// Zeigt das Ergebnis der Kurzanalyse eines hochgeladenen Materials: Länge,
/// empfohlene Chunk-Granularität, und – falls die aktuellen Einstellungen
/// davon abweichen – einen Button, um die Empfehlung zu übernehmen.
class AnalysisRecommendationCard extends StatelessWidget {
  const AnalysisRecommendationCard({
    super.key,
    required this.analysis,
    required this.currentGranularity,
    required this.onApply,
  });

  final ContentAnalysis analysis;
  final ChunkGranularity currentGranularity;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final matches = currentGranularity == ChunkGranularity.auto ||
        currentGranularity == analysis.recommendedGranularity;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.insights_outlined, color: c.accentOnSoft, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${(analysis.totalChars / 1000).ceil()} Tsd. Zeichen · ${analysis.label}',
                  style: TextStyle(
                      fontSize: 12.5, color: c.ink, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Empfehlung: Chunking „${analysis.recommendedGranularity.label}“'
                  '${analysis.recommendedRollingContext ? ' mit Rolling Context' : ''}',
                  style: TextStyle(fontSize: 12, color: c.inkMuted),
                ),
              ],
            ),
          ),
          if (!matches) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onApply, child: const Text('Übernehmen')),
          ],
        ],
      ),
    );
  }
}
