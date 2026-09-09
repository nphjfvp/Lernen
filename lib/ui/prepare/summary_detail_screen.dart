import 'package:flutter/material.dart';

import '../../models/summary.dart';

class SummaryDetailScreen extends StatelessWidget {
  const SummaryDetailScreen({super.key, required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(summary.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (summary.keyPoints.isNotEmpty) ...[
            Text('Kernkonzepte', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: summary.keyPoints
                      .map((k) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  '),
                                Expanded(child: Text(k)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text('Zusammenfassung', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(summary.overview),
        ],
      ),
    );
  }
}
