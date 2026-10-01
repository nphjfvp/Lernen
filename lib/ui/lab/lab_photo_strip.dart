import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/lab_experiment.dart';
import '../../models/lab_photo.dart';
import '../../repositories/lab_photo_repository.dart';
import '../../theme/app_colors.dart';

/// Die Fotos eines Versuchs als Streifen kleiner Bilder; Antippen öffnet das
/// Foto groß (mit Beschreibung, Löschen). Zeigt nichts, solange es keine gibt.
class LabPhotoStrip extends StatelessWidget {
  const LabPhotoStrip({super.key, required this.experiment});

  final LabExperiment experiment;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<LabPhotoRepository?>();
    if (repo == null) return const SizedBox.shrink();
    return FutureBuilder<List<LabPhoto>>(
      key: ValueKey('lab-photo-strip-${repo.version}'),
      future: repo.forExperiment(experiment.id),
      builder: (context, snapshot) {
        final photos = snapshot.data ?? const <LabPhoto>[];
        if (photos.isEmpty) return const SizedBox.shrink();
        final c = context.colors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fotos (${photos.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.inkMuted),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => InkWell(
                  key: ValueKey('lab-photo-thumb-${photos[i].id}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _open(context, repo, photos[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      photos[i].bytes,
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, LabPhotoRepository repo, LabPhoto photo) {
    final partTitle = experiment.partById(photo.partId)?.title;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(maxScale: 6, child: Image.memory(photo.bytes, fit: BoxFit.contain)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        ?partTitle,
                        if (photo.description.isNotEmpty) photo.description,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('lab-photo-delete'),
                    tooltip: 'Foto löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      await repo.delete(photo.id);
                    },
                  ),
                  TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Schließen')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
