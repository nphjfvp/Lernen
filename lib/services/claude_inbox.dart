import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'ai_service.dart';

/// Eine Lieferung im Claude-Postfach: Aufgaben im Import-Format der App
/// ([AiService.parseImportedTasks], dasselbe wie für externe KIs), dazu ein
/// Titel und – als Vorschlag – das Fach.
class InboxDelivery {
  const InboxDelivery({
    required this.id,
    required this.title,
    required this.payload,
    this.subject = '',
    this.note = '',
    this.createdAt,
  });

  final String id;
  final String title;

  /// JSON wie beim Import („tasks“/„flashcards“ …).
  final String payload;

  /// Fach, für das die Aufgaben gedacht sind (Name, nur ein Vorschlag).
  final String subject;
  final String note;
  final DateTime? createdAt;

  /// Wie viele Aufgaben/Fragen sich daraus lesen lassen (0 = unbrauchbar).
  int get taskCount {
    try {
      return AiService.parseImportedTasks(payload).drafts.length;
    } on AiServiceException {
      return 0;
    }
  }

  static InboxDelivery? fromMap(String id, Map<String, dynamic> map) {
    final payload = map['payload'];
    if (payload is! String || payload.trim().isEmpty) return null;
    final created = map['createdAt'];
    return InboxDelivery(
      id: id,
      title: (map['title'] as String?)?.trim().isNotEmpty == true ? (map['title'] as String).trim() : 'Lieferung',
      payload: payload,
      subject: (map['subject'] as String? ?? '').trim(),
      note: (map['note'] as String? ?? '').trim(),
      createdAt: created is Timestamp
          ? created.toDate()
          : created is String
          ? DateTime.tryParse(created)
          : null,
    );
  }
}

/// Wo die Lieferungen liegen (Tests ersetzen Firestore).
abstract class InboxBackend {
  Future<List<(String, Map<String, dynamic>)>> list(String code);
  Future<void> delete(String code, String id);
}

/// Firestore: `inbox/{code}/items/{id}` – lesen und löschen darf, wer den
/// Code kennt (siehe firestore.rules), wie bei den Sync-Codes.
class FirestoreInboxBackend implements InboxBackend {
  CollectionReference<Map<String, dynamic>> _items(String code) =>
      FirebaseFirestore.instance.collection('inbox').doc(code).collection('items');

  @override
  Future<List<(String, Map<String, dynamic>)>> list(String code) async {
    final snap = await _items(code).get().timeout(const Duration(seconds: 20));
    return [for (final d in snap.docs) (d.id, d.data())];
  }

  @override
  Future<void> delete(String code, String id) => _items(code).doc(id).delete().timeout(const Duration(seconds: 20));
}

/// Claude-Postfach: In einer Claude-Code-Sitzung baut Claude Aufgaben im
/// Format der App und legt sie unter dem Postfach-Code ab
/// (tool/postfach.py); die App zeigt sie, man prüft sie im Import und
/// übernimmt sie in ein Fach – danach wird die Lieferung gelöscht.
class ClaudeInbox {
  ClaudeInbox({InboxBackend? backend}) : _backend = backend ?? testBackend ?? FirestoreInboxBackend();

  /// Tests setzen hier ihr eigenes Postfach.
  static InboxBackend? testBackend;

  final InboxBackend _backend;

  /// Ohne Firebase (z.B. Build ohne Projekt) gibt es kein Postfach.
  static bool get isAvailable => testBackend != null || Firebase.apps.isNotEmpty;

  /// Neueste zuerst; Einträge ohne Aufgaben-Text werden übersprungen.
  Future<List<InboxDelivery>> fetch(String code) async {
    final raw = await _backend.list(code);
    final list = [for (final (id, map) in raw) ?InboxDelivery.fromMap(id, map)];
    list.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return list;
  }

  Future<void> remove(String code, String id) => _backend.delete(code, id);
}
