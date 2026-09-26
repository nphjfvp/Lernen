# AUDIT – Lernen

Code-Audit vom 2026-09-26 (Branch `claude/neue-lern-app-fokus-ej3k48`, Commit `96ad468`).
Erfasst potentielle Probleme, Fehler und Verbesserungs-Möglichkeiten. Die Fix-Konzepte
sind **richtungweisend**, nicht final – vor der Umsetzung eines Punkts gemeinsam designen
(siehe „Offene Design-Fragen"). Bei Widerspruch zu `AI_CONTEXT.md` gilt der Code.

## Score

**62/100 – risky.** Architektur solide; FSRS-, Ampel- und Feld-Durchreichen-Invarianten
korrekt umgesetzt. Hauptprobleme: garantierte Crashes in Async-Flows, LaTeX-Korruption in
Display-Formeln, CI ohne Test-Gate, Sync-Code-Key-Injektion im Pull-Pfad.

## Status (Stand nach Commit `971dc7c`)

| Befund | Status |
|---|---|
| B1 setState nach dispose | behoben – `SafeSetState`-Mixin in allen Screens/Sheets mit langen KI-Aufrufen |
| B2 LaTeX in `$$…$$` | behoben – `$$` ist ein Begrenzer; Steuerzeichen-Escapes nur vor Buchstaben verdoppelt, echte `\uXXXX` bleiben |
| B3 CI ohne Tests | behoben – `flutter analyze` + `flutter test` vor APK- und Windows-Build |
| H1 Sync-Code-Key-Injektion | behoben – Pull über Sync-Code übernimmt nie API-Key oder PDF-Speicher-Zugangsdaten (`syncedAiSettingsForPull`) |
| H2 Probeklausur-Race | kein echter Fehler (`QuestionAnswerView` prüft `mounted`); trotzdem Phasen-Guard in `_answer` ergänzt |
| H3 Modul-Löschen verwaist Probeklausuren | behoben – `MockExamRepository.removeModuleIn` im Lösch-Cascade |
| H4 Pull verwaist Chat/Probeklausuren | behoben – `_pull` räumt Chat-Nachrichten und Ergebnisse fremder Fächer auf |
| H5 Daily > 60 Karten | beabsichtigt – Prioritätskarten (selbst gestellte Fragen) kommen immer dazu |
| H6 Hintergrund-Beförderung | behoben – KI-Inhalt wird auf den frisch geladenen Kartenstand angewendet, nur wenn Stufe/Typ unverändert |
| H7 Stats nach Sprint | behoben – Fortschritt lädt nach dem Sprint neu |
| H8 Checkpoint-Fehler | behoben – werden auch nach Schließen des Viewers gespeichert |
| H9 Push ohne Transaktion | **zurückgestellt** (Entscheidung Nutzer: gemerkt, vorerst nicht umsetzen) – selten (zwei Geräte im selben Moment); Auto-Sync-Konfliktschutz über `lastSyncedPushId` fängt den Normalfall ab |
| H10 schwache Sync-Codes | **zurückgestellt** (Entscheidung Nutzer: gemerkt, vorerst nicht umsetzen) – entschärft, da über Sync-Codes keine Schlüssel mehr reisen; Konto-Sync ist der empfohlene Weg |
| H11 `Flashcard.fromMap` | behoben – Defaults + `num`→`int` + `tryParse` für Datumswerte |
| `isCorrect: 1` | behoben |
| Sprint zählt „Schwer" als falsch | behoben |
| `runWithoutTrigger`-Reentrancy | behoben – Zähler statt Flag |
| API-Key-Speichern in `dispose()` | kein Handlungsbedarf – wird schon beim Fokusverlust gespeichert; der Schreibvorgang im Repository läuft nach dem Schließen des Screens zu Ende |
| Web-CI, Tests für `auto_sync_service`/`auth_service`/`model_catalog_service`/`reminder_service`, systematisches `fromMap`-Audit | offen |

Design-Frage 2 (PDF-Sync) ist entschieden und umgesetzt: eigener Speicher des
Nutzers (S3-kompatibel oder WebDAV) statt Firebase Storage – Firebase Storage verlangt
für neue Projekte inzwischen den Blaze-Tarif (Kreditkarte), das widerspricht „kostenlos
ohne eigenes Backend". Details in `DESIGN_IDEEN.md` und README (Setup 3b).

---

## Blocker (vor Release fixen)

### B1. setState-after-dispose-Crashes
`lib/ui/review/review_screen.dart:301,307,313,336,341,346` und
`lib/ui/prepare/prepare_screen.dart:146,150,156,263,268,273` – `setState` nach
mehriminütigen `await ai.…`-Aufrufen ohne `mounted`-Check. Back-Press während der
KI-Generierung → `setState() called after dispose()` Crash.
**Fix-Konzept:** `if (!mounted) return;` vor jedem post-await `setState`.

### B2. LaTeX-Korruption in `$$…$$` (Display-Math)
`lib/services/math_markup.dart:193` – `escapeLatexInJson` toggelt `inMath` pro `$`. Bei
`$$…$$` flippt es zweimal → Formel-Inhalt steht mit `inMath=false` → LaTeX-Befehle mit
gültigen JSON-Escape-Buchstaben (`\frac`→\f, `\beta`→\b, `\nabla`→\n, `\theta`→\t,
`\rho`→\r, `\underline`→\u) werden nicht verdoppelt → korruptes JSON. Trifft jede
abgesetzte Formel.
**Fix-Konzept:** `$$` als eigenes Delimiter-Paar erkennen (Look-ahead wie in `split`),
`inMath` zwischen öffnendem/schließendem `$$` halten. + Testfall in
`test/services/math_markup_test.dart`.

### B3. CI baut nur, testet nicht
`.github/workflows/android-apk.yml` + `windows-app.yml` machen nur `flutter pub get` +
`flutter build`. Weder `flutter test` noch `flutter analyze` → Regressionen shippen
still als grüne APK. Web (primäres Ziel) hat gar keine CI.
**Fix-Konzept:** `flutter analyze` + `flutter test` als Gate vor den Builds (oder
separater `ci.yml`-Workflow). Optional Web-Build-Workflow ergänzen.

---

## High-Value Fixes

### H1. Sync-Code-Pull-Pfad: BYOK-Key-Injektion (Security)
`lib/services/sync_service.dart:323-324` – `_pull` übernimmt `aiSettings.openRouterApiKey`
ungefiltert (`mergeAiSettings` Zeile 40: non-null gewinnt). Push filtert korrekt
(`includeApiKey: target.isAccount`), Pull nicht. Wer einen `sync_codes/{code}` errät
(`firestore.rules:29` nur `code.size() >= 6`, kein Auth/Rate-Limit), setzt
`aiSettings.openRouterApiKey` auf seinen Key → Opfers nächste KI-Anfragen laufen über den
Angreifer-Account (Sichtbarkeit im OpenRouter-Dashboard).
**Fix-Konzept:** `includeApiKey`-Guard auch im Pull-Pfad; Key bei
`target.isAccount == false` verwerfen.

### H2. Probeklausur: Timer-vs-AI-Race
`lib/ui/exam/mock_exam_screen.dart:119` – Timer-`_finish` feuert während laufender async
FreeText-KI-Prüfung → `_finish` markiert Karte falsch + berechnet Note + wechselt Phase;
spätes `_submit` überschreibt `_correctById` und persistiert FSRS-Review → angezeigte Note
≠ gespeicherter Zustand.
**Fix-Konzept:** `_submit`/`_answer` ignorieren wenn `_phase != running` (wie `_next`).

### H3. Modul-Löschen verwaist MockExamResult
`lib/repositories/module_repository.dart:53` – Cascade räumt materials/summaries/concepts/
flashcards/units/chat, aber nicht `mock_exam_results` (tragen `moduleId`) → Orphans.
**Fix-Konzept:** beim Löschen `mock_exam_results`-Einträge mit moduleId herausfiltern.

### H4. Sync-Pull verwaist Chat & Exam
`lib/services/sync_service.dart:279-325` – `_pull` ersetzt modules/materials/…, löscht
aber keine lokalen `chat_messages`/`mock_exam_results` für verschwundene Module → hängen
an nicht-existierenden moduleIds.
**Fix-Konzept:** nach Reinsert prüfen, verwaiste Chat/Exam-Einträge löschen.

### H5. Daily-Session übersteigt max. 60
`lib/services/daily_scheduler_service.dart:212-215` – `dueCards` wird nicht auf
`maxSessionSize` (60) gedeckelt, nur `newCards`. Verletzt dokumentierte Invariante.
**Fix-Konzept:** due-Karten auf 60 deckeln, Rest mit neuen auffüllen (oder Ausnahme
dokumentieren).

### H6. Hintergrund-Beförderung: Race
`lib/ui/daily/card_review_mixin.dart:41,55-67` – `_promoteInBackground` läuft unawaited.
Zweite Review derselben Karte zwischen `repo.update(outcome)` und Hintergrund-
`repo.update(promoted)` wird vom stale promoted-Snapshot überschrieben → FSRS/masteryBox-
Review verloren.
**Fix-Konzept:** per-Karte in-flight-Flag oder Re-read+Merge vor Hintergrund-Schreib.

### H7. Stats aktualisiert nicht nach Sprint (IndexedStack-Pitfall)
`lib/ui/stats/stats_screen.dart:153` – Sprint-Eintrag pusht `SprintScreen` ohne
`await`+Reload. Sprint ändert FSRS/Ampel, Stats ist schon active → `didUpdateWidget`
feuert nicht → Streak/Reviews/Ampel stale bis Refresh.
**Fix-Konzept:** `onTap: () async { await Navigator.push(...); if (mounted) _load(); }`
(wie `_WeaknessEntryCard` Zeile 144).

### H8. Checkpoint-Quiz: verfehlte Karten verloren bei Pop
`lib/ui/modules/material_viewer_screen.dart:374` – Checkpoint-verfehlte Karten nur
`if (… && mounted)` gespeichert. Poppt der Nutzer den Viewer vorher, gehen die als
`Grade.again` für morgen gedachten Karten verloren.
**Fix-Konzept:** `missed` unbedingt über Repo speichern, ohne `mounted`-Gate.

### H9. Push ohne Transaktion (TOCTOU)
`lib/services/sync_service.dart:171-220` – Push macht read-`previous`/check-`abortIf`/
write ohne Transaktion. Zwei Geräte pushen concurrent → beide passieren Konflikt-Check,
letzter Write gewinnt still.
**Fix-Konzept:** Firestore-Transaktion oder `set(..., SetOptions(merge:false))` mit
`lastPushId`-Precondition.

### H10. Schwache Sync-Codes
`firestore.rules:29` – `sync_codes/{code}`: nur `code.size() >= 6`, kein Auth/Rate-Limit.
Codes sind Nutzer-getippt → brutschbar (Firestore-Regeln können nicht throttlen).
**Fix-Konzept:** starke zufällige Codes (≥12 chars base32) generieren statt Freitext.

### H11. Flashcard.fromMap: FSRS-Felder ohne Defaults
`lib/models/flashcard.dart:756-762` – `fromMap` liest `stability`/`difficulty` (`as num`),
`state` (`as String`) usw. ohne `?? default`, anders als spätere Felder → Crash bei
truncated/pre-FSRS-Records.
**Fix-Konzept:** Defaults ergänzen (entspricht Abwärtskompat-Regel).

---

## Verbesserungs-Möglichkeiten (Code)

- **CI-Test-Gate** – siehe B3. Größter Hebel für Langzeitqualität.
- **Web-CI fehlt** – Web ist primäres Ziel, nur APK/Windows werden gebaut.
- **Untestete Services** – `auth_service`, `auto_sync_service`, `model_catalog_service`,
  `reminder_service` haben keine Tests. `auto_sync_service` (Konflikt-Detection,
  `runWithoutTrigger`-Reentrancy) ist kritisch und ungetestet.
- **`lib/services/question_parsing.dart:27`** – `parseOptions` akzeptiert nur `true`/
  `"true"` für `isCorrect`. KI liefert `"isCorrect": 1` → Option still falsch, evtl.
  Fallback auf flashcard-Typ. Fix: auch `1`/`0` als bool akzeptieren.
- **`lib/ui/sprint/sprint_screen.dart:97`** – Sprint-Score zählt `Grade.hard` als falsch.
  Laut AI_CONTEXT 5.1 ist „hard" ein erfolgreicher Abruf → Score undercounts (FSRS
  unbeeinflusst, nur Bestleistung).
- **`lib/services/auto_sync_service.dart:104-111`** – `runWithoutTrigger`-Flag ohne
  Reentrancy-Guard → Flag kann bei überlappendem Pull/Debounce zu früh zurückgesetzt →
  spurious Upload partialer Pull-Daten. Fix: Counter oder Check im selben Microtask.
- **DB-Migration/Versionierung** – `fromMap`-Defaults sind inkonsistent (siehe H11).
  Empfehlung: alle `fromMap` systematisch auf Default-Pattern auditieren, ggf.
  Schema-Version einführen.
- **`lib/ui/settings/settings_screen.dart:68`** – API-Key-Persist aus `dispose()`
  unawaited → auf Web/Desktop evtl. nicht flushed. Fix: zusätzlich auf
  `onEditingComplete`/`onSubmitted` persistieren.

---

## Offene Design-Fragen

### 1. Features – was sinnvoll ist und was nicht
(zu brainstormen) Die App ist bewusst minimal (siehe README „Bewusst NICHT enthalten":
keine Mini-Games, Economy, Shop, Leaderboards, Mathe-Formel-Editor, diagramm-/bildbasierte
Fragetypen). Erst Nutzer-Painpoints klären, dann gezielt vorschlagen – statt
Feature-Bloat. Anti-Ziel: die Vorgänger-App-Fülle zurückholen.

### 2. PDFs synchronisieren ohne Free-Tier-Überschreitung
**Aktueller Stand:** PDF-Bytes reisen NICHT mit dem Sync mit (nur extrahierter Text +
Metadaten). `SyncCodec` gzip+chunkt die Textdaten in Firestore (1-MiB-Doc-Limit, aufgeteilt
in `sync_parts`). Lokale PDFs bleiben beim Pull erhalten.
**Problem:** echte PDFs geräteübergreifend verfügbar haben, ohne den kostenlosen Speicher
zu sprengen.
**Kandidaten (richtungweisend, zu bewerten):**
- **Firebase Cloud Storage** – 5 GB free, separat vom Firestore-1-GB; zweites Backend,
  nativer Auth-Schutz, purpose-built für Dateien.
- **Eigene Cloud einbinden** (WebDAV / Dropbox / Google Drive / S3) – BYO-Storage analog
  zu BYOK, kein Firebase-Limit.
- **In Firestore bleiben** (PDF gzip+chunk in `sync_parts`) – ohne neues Backend, aber
  1-GB-Ceiling + Write-Ops schnell verbraucht.
→ wird gemeinsam designt (siehe Klärungsfragen in der Session).

---

## Verifizierte Befunde

Per Eigen-Lese verifiziert (nicht nur Agent-Aussage): B1, B2, H1 (Pull-Pfad),
`firestore.rules`, CI-Workflows. Übrige Befunde aus vollständiger Datei-Lese durch
parallele Audit-Agenten; Zeilennummern gegen Gelesenes abgeglichen.
