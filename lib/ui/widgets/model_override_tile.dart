import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ai_model_info.dart';
import '../../repositories/model_catalog_repository.dart';
import '../../services/model_catalog_service.dart';
import '../../theme/app_colors.dart';
import '../settings/model_picker_sheet.dart';

/// Modellwahl für EINE Aktion (z.B. "Frage erstellen"): zeigt das Modell, das
/// dafür gerade gilt – standardmäßig das aus den Einstellungen –, und lässt es
/// hier wechseln, ohne die Einstellungen anzufassen. Tabellen, lange
/// Aufgaben oder eine missglückte Frage gelingen mit einem stärkeren Modell
/// oft besser; für den Alltag bleibt das günstige Standard-Modell.
class ModelOverrideTile extends StatelessWidget {
  const ModelOverrideTile({
    super.key,
    required this.defaultId,
    required this.overrideId,
    required this.onChanged,
    this.vision = false,
    this.enabled = true,
    this.hint,
  });

  /// Modell aus den Einstellungen (gilt, solange nichts gewählt ist).
  final String defaultId;

  /// Hier gewähltes Modell, null = Standard.
  final String? overrideId;

  /// Neue Wahl; null = zurück auf das Standard-Modell.
  final ValueChanged<String?> onChanged;

  /// Nur Modelle zur Wahl, die Bilder verstehen.
  final bool vision;
  final bool enabled;

  /// Kleiner Hinweis unter dem Feld (z.B. warum ein stärkeres Modell lohnt).
  final String? hint;

  String get _activeId => overrideId ?? defaultId;

  Future<void> _pick(BuildContext context, List<AiModelInfo> models) async {
    final picked = await showModelPickerSheet(
      context,
      title: vision ? 'Modell für diese Aktion (mit Bildverständnis)' : 'Modell für diese Aktion',
      models: models,
      selectedId: _activeId,
    );
    if (picked == null) return;
    onChanged(picked == defaultId ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final catalog = context.watch<ModelCatalogRepository?>();
    final all = catalog?.models ?? kFallbackModels;
    final models = vision ? all.where((m) => m.supportsVision).toList() : all;
    AiModelInfo? info;
    for (final m in all) {
      if (m.id == _activeId) info = m;
    }
    final name = info?.name ?? _activeId;
    final price = info == null
        ? null
        : info.isFree
            ? 'Gratis'
            : info.promptPricePerMillion == null
                ? null
                : '\$${info.promptPricePerMillion!.toStringAsFixed(2)}/1M';
    final changed = overrideId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('model-override'),
          onTap: enabled ? () => _pick(context, models) : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: changed ? c.accentSoft : c.surface,
              border: Border.all(color: changed ? c.accent : c.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.memory_outlined, size: 18, color: changed ? c.accentOnSoft : c.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        changed ? 'KI-Modell für diese Aktion' : 'KI-Modell (Standard aus den Einstellungen)',
                        style: TextStyle(fontSize: 10.5, color: c.inkMuted),
                      ),
                      Text(
                        price == null ? name : '$name · $price',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: changed ? c.accentOnSoft : c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                if (changed)
                  TextButton(
                    key: const ValueKey('model-override-reset'),
                    onPressed: enabled ? () => onChanged(null) : null,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Standard', style: TextStyle(fontSize: 12)),
                  )
                else
                  Icon(Icons.swap_horiz_rounded, size: 18, color: c.inkMuted),
              ],
            ),
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
            child: Text(hint!, style: TextStyle(fontSize: 11.5, color: c.inkMuted, height: 1.35)),
          ),
      ],
    );
  }
}
