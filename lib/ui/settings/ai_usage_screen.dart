import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ai_usage.dart';
import '../../repositories/ai_usage_repository.dart';
import '../../repositories/model_catalog_repository.dart';
import '../../theme/app_colors.dart';

/// Zeile in den Einstellungen: was die KI heute und in diesem Monat gekostet
/// hat; öffnet [AiUsageScreen]. Ohne [AiUsageRepository] unsichtbar.
class AiUsageTile extends StatelessWidget {
  const AiUsageTile({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<AiUsageRepository?>();
    if (usage == null) return const SizedBox.shrink();
    final c = context.colors;
    final today = usage.today();
    final month = usage.thisMonth();
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider.value(value: usage, child: const AiUsageScreen()),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('KI-Kosten', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    usage.isEmpty
                        ? 'Noch keine Anfrage auf diesem Gerät gezählt'
                        : 'Heute ${formatUsd(today.cost)} · diesen Monat ${formatUsd(month.cost)}',
                    key: const ValueKey('ai-usage-summary'),
                    style: TextStyle(fontSize: 12.5, color: c.accentOnSoft, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// Kostenübersicht: Summen (heute, Monat, gesamt), je Modell und die letzten
/// Anfragen einzeln.
class AiUsageScreen extends StatelessWidget {
  const AiUsageScreen({super.key});

  static String _tokens(int value) => value >= 10000
      ? '${(value / 1000).round()}k'
      : value >= 1000
      ? '${(value / 1000).toStringAsFixed(1).replaceAll('.', ',')}k'
      : '$value';

  static String _time(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}. ${two(local.hour)}:${two(local.minute)}';
  }

  /// „≈“ vor geschätzten Beträgen, „–“ für unbekannte.
  static String costOf(AiUsage usage) =>
      usage.cost == null ? 'Preis unbekannt' : '${usage.estimated ? '≈ ' : ''}${formatUsd(usage.cost!)}';

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<AiUsageRepository>();
    final catalog = context.watch<ModelCatalogRepository?>();
    final c = context.colors;
    String name(String id) => catalog?.byId(id)?.name ?? id;
    final total = usage.sum();
    final models = usage.byModelThisMonth();

    return Scaffold(
      appBar: AppBar(
        title: const Text('KI-Kosten'),
        actions: [
          if (!usage.isEmpty)
            IconButton(
              key: const ValueKey('ai-usage-reset'),
              tooltip: 'Zähler zurücksetzen',
              icon: const Icon(Icons.restart_alt),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Zähler zurücksetzen?'),
                    content: const Text(
                      'Die gezählten Kosten und die Liste der Anfragen auf diesem Gerät werden gelöscht. '
                      'Dein Guthaben bei OpenRouter ändert sich dadurch nicht.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                      FilledButton(
                        key: const ValueKey('ai-usage-reset-ok'),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Zurücksetzen'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await usage.clear();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _SumCard(label: 'Heute', total: usage.today(), valueKey: 'ai-usage-today'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SumCard(label: 'Dieser Monat', total: usage.thisMonth(), valueKey: 'ai-usage-month'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SumCard(label: 'Gesamt', total: total, valueKey: 'ai-usage-total'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Gezählt wird, was OpenRouter je Antwort meldet – nur auf diesem Gerät und erst seit dieser '
            'Funktion. Beträge in US-Dollar. „≈“ heißt: aus Tokens und Listenpreis gerechnet, weil die '
            'Antwort keinen Betrag enthielt. Die verbindliche Abrechnung steht bei OpenRouter.',
            style: TextStyle(fontSize: 12, color: c.inkMuted, height: 1.35),
          ),
          if (total.unknownCalls > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${total.unknownCalls} ${total.unknownCalls == 1 ? 'Anfrage' : 'Anfragen'} ohne bekannten Preis '
              'sind in den Summen nicht enthalten.',
              style: TextStyle(fontSize: 12, color: c.warn),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Nach Modell – dieser Monat', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (models.isEmpty)
            Text('In diesem Monat noch nichts.', style: TextStyle(fontSize: 13, color: c.inkMuted))
          else
            for (final m in models)
              Padding(
                key: ValueKey('ai-usage-model-${m.model}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name(m.model), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          Text(
                            '${m.calls} ${m.calls == 1 ? 'Anfrage' : 'Anfragen'} · '
                            '${_tokens(m.promptTokens)} rein, ${_tokens(m.completionTokens)} raus',
                            style: TextStyle(fontSize: 12, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${m.estimatedCalls > 0 ? '≈ ' : ''}${formatUsd(m.cost)}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 20),
          const Text('Letzte Anfragen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (usage.recent.isEmpty)
            Text(
              'Noch keine. Sobald die KI etwas für dich erstellt oder prüft, steht hier, was es gekostet hat.',
              style: TextStyle(fontSize: 13, color: c.inkMuted),
            )
          else
            for (final (i, u) in usage.recent.indexed)
              Padding(
                key: ValueKey('ai-usage-entry-$i'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.label.isEmpty ? 'Anfrage' : u.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            '${_time(u.at)} · ${name(u.model)} · '
                            '${_tokens(u.promptTokens)} rein, ${_tokens(u.completionTokens)} raus',
                            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(costOf(u), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _SumCard extends StatelessWidget {
  const _SumCard({required this.label, required this.total, required this.valueKey});

  final String label;
  final AiUsageTotal total;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.inkMuted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatUsd(total.cost),
              key: ValueKey(valueKey),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${total.calls} ${total.calls == 1 ? 'Anfrage' : 'Anfragen'}',
            style: TextStyle(fontSize: 11.5, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}
