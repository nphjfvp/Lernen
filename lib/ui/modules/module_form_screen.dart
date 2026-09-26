import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/module.dart';
import '../../repositories/daily_session_repository.dart';
import '../../repositories/flashcard_repository.dart';
import '../../repositories/lecture_unit_repository.dart';
import '../../repositories/module_repository.dart';
import '../../services/home_widget_service.dart';

const _kModuleColors = [
  0xFF3D5AFE, // Indigo
  0xFF2196F3, // Blau
  0xFF00BCD4, // Cyan
  0xFF00897B, // Türkis
  0xFF43A047, // Grün
  0xFF8BC34A, // Hellgrün
  0xFFFDD835, // Gelb
  0xFFFFB300, // Amber
  0xFFFB8C00, // Orange
  0xFFFF5722, // Orangerot
  0xFFE53935, // Rot
  0xFFEC407A, // Pink
  0xFF8E24AA, // Lila
  0xFF5E35B1, // Dunkellila
  0xFF6D4C41, // Braun
  0xFF546E7A, // Blaugrau
];

const _kModuleIcons = [
  '📘', '📗', '📙', '📕',
  '📐', '📏', '🧮', '🔢',
  '🧪', '🔬', '⚗️', '🧬',
  '💻', '🖥️', '⚙️', '🔧',
  '⚖️', '🏛️', '🧠', '💊',
  '🩺', '📊', '📈', '💰',
  '🌍', '🗺️', '🎨', '🎵',
  '🎭', '🗣️', '📖', '🔭',
];

const _kWeekdayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Formular zum Anlegen/Bearbeiten eines Fach-Ordners inkl. Klausurdatum.
class ModuleFormScreen extends StatefulWidget {
  const ModuleFormScreen({super.key, this.existing});

  final Module? existing;

  @override
  State<ModuleFormScreen> createState() => _ModuleFormScreenState();
}

class _ModuleFormScreenState extends State<ModuleFormScreen> {
  late final TextEditingController _nameController;
  late int _colorValue;
  late String _icon;
  DateTime? _examDate;
  late List<LectureSlot> _lectureSlots;

  /// Einmal vergeben: ein zweites "Fach anlegen" (Doppeltippen, solange das
  /// Speichern samt Widget-Aktualisierung noch läuft) legte sonst ein
  /// zweites, gleiches Fach an.
  late final String _id = widget.existing?.id ?? const Uuid().v4();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _colorValue = existing?.colorValue ?? _kModuleColors.first;
    _icon = existing?.icon ?? _kModuleIcons.first;
    _examDate = existing?.examDate;
    _lectureSlots = List.of(existing?.lectureSlots ?? const []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _examDate = picked);
  }

  Future<void> _addLectureSlot() async {
    final startTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Startzeit',
    );
    if (startTime == null || !mounted) return;

    // Vorschlag für die Endzeit: übliche 90-Minuten-Vorlesung.
    final suggestedEndMinutes = (startTime.hour * 60 + startTime.minute + 90) % (24 * 60);
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: suggestedEndMinutes ~/ 60, minute: suggestedEndMinutes % 60),
      helpText: 'Endzeit',
    );
    if (endTime == null || !mounted) return;

    int weekday = DateTime.monday;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('An welchem Wochentag?'),
          content: Wrap(
            spacing: 8,
            children: List.generate(7, (i) {
              final day = i + 1;
              return ChoiceChip(
                label: Text(_kWeekdayLabels[i]),
                selected: weekday == day,
                onSelected: (_) => setDialogState(() => weekday = day),
              );
            }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hinzufügen')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _lectureSlots.add(LectureSlot(
        weekday: weekday,
        hour: startTime.hour,
        minute: startTime.minute,
        endHour: endTime.hour,
        endMinute: endTime.minute,
      ));
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await _saveModule(name);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveModule(String name) async {
    final repo = context.read<ModuleRepository>();
    final existing = widget.existing;
    final module = Module(
      id: _id,
      name: name,
      colorValue: _colorValue,
      icon: _icon,
      examDate: _examDate,
      createdAt: existing?.createdAt ?? DateTime.now(),
      lectureSlots: _lectureSlots.isEmpty ? null : _lectureSlots,
    );
    await repo.save(module);
    if (!mounted) return;
    final lectureUnitRepo = context.read<LectureUnitRepository>();
    final allCards = await context.read<FlashcardRepository>().loadAll();
    final unitCoveredById = await lectureUnitRepo.loadAllCoveredById();
    final introducedToday = await DailySessionRepository().introducedTodayByModule(allCards);
    // Bewusst AWAITED statt unawaited: direkt danach navigieren wir weg
    // (Navigator.pop), und auf manchen Geräten wird die App danach schnell
    // in den Hintergrund gedrängt – ein nicht abgewartetes Future könnte
    // dann abgebrochen werden, bevor die Plattform-Channel-Aufrufe
    // durchlaufen sind, und das Widget bliebe auf dem alten Stand hängen.
    await HomeWidgetService().refresh(
      modules: repo.modules,
      allCards: allCards,
      unitCoveredById: unitCoveredById,
      introducedTodayByModule: introducedToday,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Fach bearbeiten' : 'Neues Fach')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name des Fachs',
              hintText: 'z.B. Analysis 2',
              border: OutlineInputBorder(),
            ),
            autofocus: !isEditing,
          ),
          const SizedBox(height: 24),
          const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _kModuleIcons.map((icon) {
              final selected = icon == _icon;
              return ChoiceChip(
                label: Text(icon, style: const TextStyle(fontSize: 18)),
                selected: selected,
                onSelected: (_) => setState(() => _icon = icon),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Text('Farbe', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _kModuleColors.map((value) {
              final selected = value == _colorValue;
              return GestureDetector(
                onTap: () => setState(() => _colorValue = value),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(value),
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Text('Klausurdatum', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(_examDate == null
                ? 'Kein Datum gesetzt'
                : '${_examDate!.day}.${_examDate!.month}.${_examDate!.year}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                TextButton(onPressed: _pickExamDate, child: const Text('Wählen')),
                if (_examDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _examDate = null),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Vorlesungstermine', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Wöchentlich wiederkehrend, für die Kalender-Ansicht und Erinnerungen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _lectureSlots.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat),
              title: Text(
                '${_kWeekdayLabels[_lectureSlots[i].weekday - 1]} '
                '${_lectureSlots[i].timeLabel} Uhr',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => _lectureSlots.removeAt(i)),
              ),
            ),
          TextButton.icon(
            onPressed: _addLectureSlot,
            icon: const Icon(Icons.add),
            label: const Text('Termin hinzufügen'),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(isEditing ? 'Speichern' : 'Fach anlegen'),
          ),
        ],
      ),
    );
  }
}
