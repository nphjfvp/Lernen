# DESIGN_IDEEN – Lernen

Design-Entwürfe und Feature-Ideen vom 2026-09-26. Enthält **Umsetzungs-Konzepte**
("wie umgesetzt"), **keinen Code**. Bei Widerspruch zu `AI_CONTEXT.md` gilt der Code.
Bewertungen: SINNVOLL / VIELLEICHT / BEWUSST NICHT.

---

## 1. PDF-Sync ohne Free-Tier-Überschreitung (Design A — freigegeben)

### Ziel
Echte PDFs geräteübergreifend synchronisieren, kostenlos bleiben (Firebase Spark).
Volumen-Annahme: mittel (1–5 GB).

### Ansatz
Firebase Cloud Storage + dünne Firestore-Index-Schicht. PDFs als Dateien, nur Metadaten
in Firestore. Nur Account-Pfad (wie API-Key); `sync_code`-Fallback bleibt text-only.

### Umsetzung (Konzept, kein Code)

**Neue Abhängigkeit:** `firebase_storage`, bedingte Init (offline weiter nutzbar, analog
Firestore).

**Neuer Service** `lib/services/material_file_sync_service.dart`:
- `upload(MaterialItem, bytes)`: sha256 → `FirebaseStorage.ref('users/{uid}/materials/{materialId}.pdf').putData(bytes)`; skip wenn `getMetadata()` gleiches sha256/size liefert.
- `download(MaterialItem)`: `ref(...).getData()` → lokal cachen via `MaterialFileStore`.
- `delete(MaterialItem)`: `ref(...).delete()` — Cascade-Löschung um Material-PDFs erweitern.
- Retry-Queue für fehlgeschlagene Uploads (Netz/Quota), Backoff analog `AutoSyncService`.

**Datenmodell** `lib/models/material_item.dart`:
- Neue Felder: `storagePath` (String?), `fileSha256` (String?), `fileSizeBytes` (int?).
  In `toMap`/`fromMap` mit Defaults (Abwärtskompat — siehe AUDIT H11-Pattern).
- Lokales `filePath`/`fileBytesBase64` unangetastet.

**SyncCodec / SyncService**:
- Push (Account): nach Firestore-Daten-Upload alle lokalen PDFs mit `storagePath`-Referenz in Storage hochladen.
- Pull (Account): nur Metadaten + `storagePath` in lokale DB; PDFs lazy beim Öffnen.
- `sync_code`-Pfad: keine PDFs (text-only wie heute), klarer Nutzer-Hinweis.
- `runWithoutTrigger` auch für Storage-Downloads nutzen (kein Upload-Trigger).

**Storage Security Rules** (`storage.rules`, neu):
- `match /users/{uid}/{allPaths=**}`: read/write nur wenn `request.auth.uid == uid`.
- Default-deny alles andere.

**UI**:
- `MaterialViewer`: falls PDF lokal fehlt + `storagePath` da → vor Öffnen aus Storage laden (Spinner). Offline → Hinweis "PDF nicht offline, Text aber da".
- `ModuleDetail`: Storage-Nutzung anzeigen (Summe `fileSizeBytes` der `storagePath`-PDFs), Warnung bei ~4 GB, Button "alte PDFs entfernen" (löscht Storage + lokale Bytes, Text + Metadaten bleiben).

**Edge-Cases**:
- Upload-Fehler → Retry-Queue.
- Download-Quota 1 GB/Tag → lazy + lokaler Cache; große Pulls nicht blockierend.
- 5 GB-Ceiling → Speicher-Anzeige + Cleanup-Button.
- Account-Wechsel → lokale PDFs bleiben; `storagePath` ist uid-spezifisch (neuer Account = neu hochladen).

**Testing**:
- Service-Logik mit Mock-Storage-Interface (sha256-Vergleich, skip, retry-Queue).
- `storage.rules` manuell in Firebase-Console verifizieren (wie `firestore.rules`).
- Realer Upload/Pull im Web-Build manuell durchklicken.

**Invarianten bewahrt:** PDFs nicht in Firestore, lokales Byte-Persist unangetastet,
Auto-Sync-Trigger unverändert, Account-vs-code-Trennung konsequent. Konsistent mit
AUDIT H1-Fix (Key + Dateien nur Account-Pfad).

---

## 2. Feature-Ideen

### 2.1 OCR-Fallback für gescannte/bildbasierte PDFs — SINNVOLL (Top)
**Was:** Liefert Syncfusion-Textextraktion pro Seite zu wenig Text (bildbasierte PDF),
Seiten rastern + an Vision-Modell senden → Text.
**Warum:** `AI_CONTEXT.md` nennt es selbst als offene Lücke (aktuell klare Fehlermeldung
statt Extraktion). Echte funktionale Lücke; Vision-Modell-Rolle existiert schon
(Seitenscreenshot-Funktion). Macht gescannte Skripte nutzbar.
**Wie umgesetzt:**
- `lib/services/pdf_service.dart` / `material_text_extractor.dart`: nach Extraktion prüfen, ob Textlänge pro Seite < Schwellenwert → Bild-PDF vermuten.
- Seiten als Bild rendern (Syncfusion PDF→Image), base64, an `AiService` Vision-Endpunkt (bestehende `visionModelId`-Rolle) mit Extraktions-Prompt.
- Chunking wie bei Text (große Skripte → mehrere Anfragen, Rolling Context).
- Fallback-Kaskade: Syncfusion-Text → wenn leer, Vision-OCR → bei fehlendem API-Key/Modell klare Fehlermeldung (wie heute).
- Ergebnis als `MaterialItem.extractedText` (wie normale Extraktion) → restliche Pipeline (Chat, Nachbereiten, Markieren) unverändert.
**Aufwand:** mittel. Höchster Feature-Nutzen.

### 2.2 Text-to-Speech für Zusammenfassungen/Konzepte — SINNVOLL (optional)
**Was:** Zusammenfassungen, Konzepte, Karten-Rückseiten vorlesen lassen.
**Warum:** Pendeln, Sport — "wenig Aufwand, viel Stoff". On-device TTS, kein API-Call,
offline. Passt zur Philosophie.
**Wie umgesetzt:**
- Paket `flutter_tts` (on-device, plattform-nativ, offline).
- Neues Widget `lib/ui/widgets/tts_button.dart`: Play/Pause/Stop, an Textquelle gebunden.
- Einsatz: `SummaryDetailScreen`, Konzept-Detail, `QuestionAnswerView` (Rückseite/Erklärung).
- Sprache `de-DE`, Rate einstellbar.
- LaTeX vor TTS: `MathMarkup`-Formeln als "Formel übersprungen" oder einfache Lesart (`\frac{a}{b}` → "a durch b") — optional, erst roh.
**Aufwand:** niedrig. Echter Nutzen, kein Risiko.

### 2.3 Auto-Erkennung Vorlesungs-Einheiten — SINNVOLL (optional)
**Was:** KI gruppiert hochgeladene Materialien zu Vorlesungs-Einheiten.
**Warum:** Convenience (manuelle Einheiten-Gruppierung entfällt); KI liest Folien ohnehin.
**Wie umgesetzt:**
- `AiService.suggestLectureUnits(module, materials)`: Prompt mit Material-Titeln + `topicIndex`-Einträgen → schlägt Einheiten (Name + Material-IDs) vor.
- UI im `ModuleDetail`: "Einheiten vorschlagen" → Vorschau (editierbar) → übernimmt `LectureUnit` + setzt `material.unitId`.
- Bestehende `LectureUnit`-Logik + Scheduler-Gate unverändert.
**Aufwand:** niedrig-mittel. Rein Convenience.

### 2.4 KI-Wochen-Lernplan — VIELLEICHT
**Was:** "Was diese Woche tun" pro Fach (Einheiten / Karten-Typen).
**Wie umgesetzt:** `AiService` + `DailySchedulerService`-Daten → Wochenplan-Text.
**Bewertung:** Risiko Redundanz mit Exam-Scheduler (macht schon Pacing). Nur bei echtem
Mehrwert. Aufwand niedrig, Nutzen fraglich.

### 2.5 Karten-Import/Export (Anki/CSV) — VIELLEICHT
**Was:** Anki-Deck/CSV importieren/exportieren.
**Wie umgesetzt:** Parser für Anki `.apkg` (SQLite+ZIP) oder CSV → `Flashcard`; Export
analog `ModuleExportService`.
**Bewertung:** Migration-Nutzen, aber App ist KI-Generations-fokussiert. Aufwand mittel.

### 2.6 Markdown-Notizen — VIELLEICHT
**Was:** Notizen/Markierungen mit Markdown + LaTeX formatieren.
**Wie umgesetzt:** `flutter_markdown` + bestehendes `MathText` in Notiz-Feldern.
**Bewertung:** niedrig. LaTeX geht schon; Markdown nice-to-have.

### 2.7 BEWUSST NICHT (Bloat / bricht Philosophie)
- Mini-Games, Coins/Shop, Leaderboards — Gamification ≠ Lerngewinn.
- Mathe-Formel-Editor mit Editor — LaTeX reicht.
- Diagramm-/bildbasierte Fragetypen — bewusst draußen.
- Externe Web-Suche im Chat — bricht offline-first.
- On-device KI-Modell — zu schwer für Flutter-mobile.
- FSRS für Konzepte — Speedrun ist bewusst kein SR (Verständnis-Check).

---

## Priorität
1. **PDF-Sync (Design A)** — freigegeben, konkret umsetzbar.
2. **OCR-Fallback** — höchster Feature-Nutzen, echte Lücke.
3. **TTS** — niedriger Aufwand, echter Nutzen.
4. **Auto-Einheiten** — Convenience.
Rest: abwägbar / bewusst weggelassen.

---

## Bezug zu AUDIT.md
- PDF-Sync greift AUDIT H1 (Key+Dateien nur Account-Pfad) auf.
- `MaterialItem.fromMap`-neue Felder brauchen das Default-Pattern aus AUDIT H11.
- Sync-Cascade-Erweiterung greift AUDIT H3/H4 (Orphans beim Löschen/Pull vermeiden).
