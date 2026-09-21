import 'package:flutter/material.dart';

import '../../models/material_item.dart';

String _kindLabel(MaterialKind kind) => switch (kind) {
      MaterialKind.slide => 'Folie',
      MaterialKind.exercise => 'Übungsaufgabe',
      MaterialKind.practiceExam => 'Übungsklausur',
    };

/// Öffnet eine Auswahlliste bereits im Fach hochgeladener Materialien (siehe
/// MaterialRepository.forModule) zur Wiederverwendung in Vorbereiten/
/// Nachbereiten – verhindert, dass dieselbe Datei jedes Mal erneut über den
/// Datei-Picker hochgeladen werden muss, nur weil sie schon einmal (z.B.
/// direkt über ModuleDetailScreen) im Fach abgelegt wurde. Nur Materialien
/// mit tatsächlich extrahiertem Text sind sinnvoll wiederverwendbar; die
/// Übungsklausur (dient als eigene Stil-Referenz, siehe
/// MaterialItem.practiceExamTextFrom) wird bewusst nicht angeboten.
Future<List<MaterialItem>?> showExistingMaterialPicker(
  BuildContext context, {
  required List<MaterialItem> available,
  required Set<String> alreadyPickedIds,
}) {
  final selectable = available
      .where((m) =>
          m.kind != MaterialKind.practiceExam &&
          m.extractedText.trim().isNotEmpty &&
          !alreadyPickedIds.contains(m.id))
      .toList();

  if (selectable.isEmpty) {
    return showDialog<List<MaterialItem>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kein Material verfügbar'),
        content: const Text(
          'Für dieses Fach ist kein weiteres wiederverwendbares Material '
          'hinterlegt. Materialien lassen sich z.B. im Modul-Detail direkt '
          'hochladen, ohne dafür eine KI-Anfrage auszulösen.',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  return showModalBottomSheet<List<MaterialItem>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ExistingMaterialSheet(available: selectable),
  );
}

class _ExistingMaterialSheet extends StatefulWidget {
  const _ExistingMaterialSheet({required this.available});
  final List<MaterialItem> available;

  @override
  State<_ExistingMaterialSheet> createState() => _ExistingMaterialSheetState();
}

class _ExistingMaterialSheetState extends State<_ExistingMaterialSheet> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Vorhandenes Material auswählen', style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.available.length,
                itemBuilder: (ctx, i) {
                  final m = widget.available[i];
                  final selected = _selectedIds.contains(m.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedIds.add(m.id);
                      } else {
                        _selectedIds.remove(m.id);
                      }
                    }),
                    title: Text(m.fileName),
                    subtitle: Text(_kindLabel(m.kind)),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () => Navigator.of(context)
                              .pop(widget.available.where((m) => _selectedIds.contains(m.id)).toList()),
                      child: const Text('Übernehmen'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
