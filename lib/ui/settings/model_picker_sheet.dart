import 'package:flutter/material.dart';

import '../../models/ai_model_info.dart';
import '../../theme/app_colors.dart';

/// Durchsuchbare Modell-Auswahl als Bottom-Sheet. Der Katalog kommt live von
/// OpenRouter (siehe ModelCatalogRepository) und kann je nach Kategorie
/// schnell einige hundert Einträge haben – Suche statt einer langen
/// Radio-Liste hält das bedienbar.
Future<String?> showModelPickerSheet(
  BuildContext context, {
  required String title,
  required List<AiModelInfo> models,
  required String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ModelPickerSheet(title: title, models: models, selectedId: selectedId),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({required this.title, required this.models, required this.selectedId});
  final String title;
  final List<AiModelInfo> models;
  final String? selectedId;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.models
        : widget.models.where((m) => m.name.toLowerCase().contains(query) || m.id.toLowerCase().contains(query)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    Text('${widget.models.length} Modelle', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Modell suchen…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accent)),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text('Keine Treffer.', style: TextStyle(color: c.inkMuted)))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => _ModelRow(
                          model: filtered[i],
                          selected: filtered[i].id == widget.selectedId,
                          onTap: () => Navigator.of(ctx).pop(filtered[i].id),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.selected, required this.onTap});
  final AiModelInfo model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface,
          border: Border.all(color: selected ? c.accent : c.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(model.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(model.id, style: TextStyle(fontSize: 11, color: c.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (model.isFree)
                        _Badge(label: 'Gratis', fg: c.good, bg: c.goodSoft)
                      else if (model.promptPricePerMillion != null)
                        _Badge(
                          label: '\$${model.promptPricePerMillion!.toStringAsFixed(2)}/1M',
                          fg: c.inkMuted,
                          bg: c.surfaceAlt,
                        ),
                      if (model.supportsVision) _Badge(label: 'Vision', fg: c.accentOnSoft, bg: c.accentSoft),
                      if (model.contextLength != null)
                        _Badge(label: '${(model.contextLength! / 1000).round()}K Kontext', fg: c.inkMuted, bg: c.surfaceAlt),
                    ],
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: c.accent, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.fg, required this.bg});
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
