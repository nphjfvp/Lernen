# AI_CONTEXT – Lernen

Kontext für zukünftige KI-Sitzungen. Beschreibt, **was** die App ist, **wie** sie
gebaut ist und **welche Regeln** im Code gelten – insbesondere die exakte
Funktionsweise von Quiz, FSRS und Wissensstand-Ampel. Bei Widerspruch zwischen
dieser Datei und dem Code gilt der Code; diese Datei dann mit aktualisieren.

## 1. Kernzweck und Vision

Persönliche Semester-Lern-App für Studierende (UI komplett auf Deutsch). Ziel:
mit wenig Aufwand ein ganzes Semester Vorlesungsstoff so lernen, dass er zur
Klausur sitzt. Kreislauf:

1. **Material hochladen** (PDF/DOCX/PPTX; Folien, Übungen, Übungsklausur) –
   optional einer Vorlesungs-**Einheit** zugeordnet.
2. **Vorbereiten** (vor der Vorlesung): KI-Zusammenfassung.
3. **Nachbereiten** (nach der Vorlesung): KI erzeugt Konzepte + Karteikarten
   verschiedener Fragetypen; Crosscheck durch ein zweites Modell.
4. **Lernmodus** (`MaterialViewerScreen`): PDF lesen, markieren, Fragen zur Seite
   stellen, Konzepte/Fragen direkt aus einer Seite erzeugen, alle N Seiten ein
   optionaler Zwischen-Check.
5. **Daily Quiz**: täglicher, klausur-bewusst dosierter Spaced-Repetition-Plan
   über alle Fächer (FSRS) + freiwilliges Weiterlernen.
6. **Wissensstand-Ampel** (rot/gelb/grün) + Fortschritt/Streak.

Leitlinien des Nutzers: Lernerfolg vor Gamification (keine Punkte/Shops/
Leaderboards), Daily Quiz soll ≥10 min Stoff bieten, falsch Beantwortetes soll
zeitnah wiederkommen, Ampel muss ehrlich sein (Grün nur bei nachgewiesenem,
über Tage verteiltem Wissen). BYOK: der Nutzer bringt seinen eigenen
OpenRouter-API-Key mit. Die App muss offline voll funktionieren; Cloud ist
optional. Vorgänger-App: `nphjfvp/quiz-app` (PWA) – dient als Referenz für
gewünschtes Verhalten.

## 2. Tech-Stack

- **Flutter / Dart 3** (SDK `^3.13.3`), Zielplattformen Android, Windows, Web
  (iOS möglich). CI: `.github/workflows/android-apk.yml`, `windows-app.yml`.
- **State**: `provider` (`ChangeNotifier`-Repositories, in `main.dart`
  registriert). `ModuleRepository` und `SettingsRepository` werden VOR `runApp`
  geladen.
- **Persistenz**: `sembast` (Datei auf IO, IndexedDB via `sembast_web` im Web),
  Singleton `DatabaseService` mit Stores: `modules, materials, summaries,
  concepts, lecture_units, flashcards, settings, mastery_snapshots,
  model_catalog, chat_messages`. Record-Keys im Store `settings`:
  `app_settings` = AppSettings, `study_days` = Lerntage-Protokoll,
  `daily_session` = heutiger Daily-Quiz-Stand, `mock_exam_results` =
  Probeklausur-Verlauf (alle außer `app_settings` geräte-lokal, nie gesynct).
- **KI**: OpenRouter Chat-Completions über `http` (`lib/services/ai_service.dart`),
  drei Modellrollen (Fragen/Text, Vision, Crosscheck). Timeout 3 min, Transport-
  fehler → `AiServiceException`.
- **PDF**: Syncfusion (`syncfusion_flutter_pdf` Textextraktion,
  `syncfusion_flutter_pdfviewer` Anzeige); DOCX/PPTX über `archive` + `xml`.
- **Optional**: Firebase (`firebase_core`, `cloud_firestore`, `firebase_auth`,
  `google_sign_in`) für Cloud-Sync/Account; `webview_flutter` für den
  interaktiven `html`-Fragetyp (nur Android/iOS, sonst Fallback);
  `flutter_local_notifications` (Lernerinnerung), `home_widget` (Android-Widget),
  `flutter_math_fork` (LaTeX-Formeln, siehe `MathText`).
- **Tests**: `flutter_test`, reine Logik + Modelle; Repository-Logik über
  statische `…Cascade`/`…In(DatabaseClient)`-Funktionen mit
  `databaseFactoryMemory` (sembast) testbar.

Befehle (Flutter liegt in dieser Umgebung unter `/home/user/flutter-sdk/flutter/bin`):
`flutter analyze` (muss "No issues found!" melden) und `flutter test`.

## 3. Architektur (Ordner)

- `lib/models/` – reine Datenklassen mit `toMap`/`fromMap` (abwärtskompatibel:
  neue Felder immer mit Default in `fromMap`).
- `lib/repositories/` – DB-Zugriff + In-Memory-Cache pro Modul (`forModule`,
  `loadForModule`), `notifyListeners` nach Schreibzugriffen.
- `lib/services/` – reine Logik (FSRS, Mastery, Scheduler, AnswerChecker,
  QuestionParsing, Stats) + I/O-Services (AI, Sync, Export, PDF, Widget).
- `lib/ui/` – Screens. `RootShell` hält die 5 Haupt-Tabs (Fächer, Daily Quiz,
  Kalender, Fortschritt, Einstellungen) in einem **IndexedStack** – alle Tabs
  leben dauerhaft; Daily Quiz und Fortschritt bekommen `isActive` und laden
  beim Sichtbarwerden neu.

## 4. Wichtigste Datenstrukturen

**`Flashcard`** (`lib/models/flashcard.dart`) – Frage + eigener SR-Zustand:
- Inhalt: `front`, `back`, `type` (`QuestionType`: flashcard, singleChoice,
  multipleChoice, freeText, fillBlank, dragDrop, dragCategory, html), je nach Typ
  `options`/`correctText`/`blanks`/`dragPairs`/`htmlContent`; `imageBase64`
  (Seiten-Screenshot, nur wenn für die Frage nötig).
- FSRS: `due, stability, difficulty, elapsedDays, scheduledDays, reps, lapses,
  state, lastReview`.
- Ampel: `masteryBox` (0…`masteryBoxCap`=4).
- Eskalation: `variantChain` (Typfolge), `variantLevel`, `variantBox`,
  `variantMissStreak`, `variantHistory` (verlassene leichtere Stufen),
  `pendingVariants` (vorbereitete, noch nicht erreichte schwerere Stufen).
- Zuordnung: `moduleId`, `conceptId`, `unitId`, `priorityIntroduction`.

Weitere: `Module` (Fach, `examDate`, `lectureSlots`), `LectureUnit`
(Vorlesungseinheit, `covered` = von Hand abgehakt, `scheduledDate` =
Vorlesungstermin, Notizen; „behandelt“ = `isCoveredOn(heute)`: abgehakt ODER
Termin erreicht), `MaterialItem` (extrahierter Text, PDF-Datei/Base64 –
geräte-lokal –, `remotePdfKey` = Ort im eigenen PDF-Speicher, Markierungen,
Notiz, `topicIndex`, `kind`: slide/exercise/practiceExam), `Concept` (inkl.
Seiten-Quasi-Link `linkedMaterialId`/`linkedPageNumber`), `Summary`,
`ChatMessage`, `AppSettings` (inkl. `pdfStorage` = `PdfStorageConfig`,
Auto-Sync-Felder), `MasterySnapshot` (tägliche Ampel-Verteilung für den Trend),
`DailySessionState`, `MockExamResult`.

**Pflicht-Regel „jedes Feld durchreichen“**: Flashcard hat viele manuelle
Rekonstruktionen (`copyWith*`, Export/Import, Sync, `_mergeIntoChain`,
`_editConcept` …). Ein neues Feld MUSS überall ergänzt werden – dieser Fehler
ist in der Historie mehrfach passiert (verlorene `htmlContent`/`masteryBox`/
Seiten-Links). Nach einem neuen Feld: `grep -rn "Flashcard(" lib`.

## 5. Logik-Regeln: Quiz, FSRS und Ampel (exakt)

### 5.1 Wo Antworten verbucht werden
Alle Fragetypen werden über `QuestionAnswerView` beantwortet. Sie ruft
`onComplete` **genau einmal** pro Instanz (Sperre `_submitted`) mit entweder
`selfGrade` (Typ `flashcard` bzw. html-Fallback: Nochmal/Schwer/Gut/Leicht)
oder `isCorrect` (automatisch geprüft). Wiederholt dieselbe Karte angezeigt
werden soll, braucht die View einen neuen Key.

EINE Stelle verbucht Antworten: `ReviewService.evaluate` (rein) +
`CardReviewMixin.recordReview` (speichern, Lerntag, Stufenwechsel-SnackBar,
KI-Erzeugung der nächsten Stufe im Hintergrund – wird auch nach Verlassen des
Screens gespeichert). Neue Lernmodi MÜSSEN darüber laufen.

Sonderfall **Tipp**: wurde vor dem Antworten ein KI-Tipp geholt und die
Antwort ist richtig, meldet `QuestionAnswerView` BEIDES (`isCorrect: true`,
`selfGrade: Grade.hard`): Bewertung „Schwer“ (Ampel steigt nicht), die
Eskalationskette bleibt unberührt, `wasWrong` ist false.

| Ort | FSRS/Ampel-Wirkung |
| --- | --- |
| Daily Quiz (`daily_quiz_screen.dart`) | ja |
| Üben (`practice_screen.dart`, auch `PracticeScreen.cards` aus Schwachstellen/Probeklausur) | ja |
| Sprint (Mini-Spiel) | ja (seit Backlog-Punkt 3) |
| Probeklausur (`mock_exam_screen.dart`, `examMode`) | ja, ohne SnackBar; übersprungene/unbeantwortete zählen nur für die Note |
| Zwischen-Check im Lernmodus | nur falsch Beantwortetes wird gespeichert – als `Grade.again` verbucht (rot, morgen fällig) + `priorityIntroduction` |
| Speedrun (Konzepte) | nein (Konzepte haben keinen SR-Zustand) |
| Vorschau in „Frage erstellen“ | nein (kosmetisch) |

### 5.2 Bewertung → FSRS-Grade (`FsrsService.gradeFromResult`)
- automatisch geprüft **richtig → `Grade.good`**, **falsch → `Grade.again`**
  (binär, FSRS-Empfehlung). NICHT Hard/Easy: Hard ist in FSRS ein
  erfolgreicher Abruf (Intervall würde nach einer falschen Antwort länger),
  Easy gäbe einer neuen Karte ~15 Tage Pause.
- Selbstbewertung: die gewählte Grade direkt.
- Prüfregeln (`AnswerChecker`): Single-Choice – jede als richtig markierte
  Option zählt; Multiple-Choice – exakte Menge; Freitext/Lückentext –
  normalisiert + Levenshtein-Toleranz (1 ab 5 Zeichen, 2 ab 9), Freitext bei
  lokaler Ablehnung zusätzlich KI-Zweitmeinung (`checkFreeTextAnswer`);
  Zuordnen/Kategorien – alle Paare korrekt.

### 5.3 FSRS (`lib/services/fsrs_service.dart`)
FSRS-4.5 mit Default-Gewichten, Ziel-Retention 0,9, **Mindestintervall 1 Tag**
(keine Same-Day-Learning-Steps). `due` = Tagesbeginn + Intervall. `again`
erhöht `lapses`, setzt `state='relearning'`. Karten auf einer leichten/
mittleren Stufe einer Eskalationskette (nicht der letzten) bekommen höchstens
`transitStageMaxIntervalDays` = 7 Tage Abstand.

### 5.4 masteryBox (in `FsrsService.review`)
- `good`/`easy` → +1, gedeckelt bei 4 – **aber nur einmal pro Kalendertag**
  (war `lastReview` heute, bleibt der Wert).
- `hard` → unverändert (richtig, aber mühsam bzw. mit Tipp).
- `again` → −1, Boden 0 (auch mehrfach am selben Tag).

### 5.5 Ampel (`MasteryService.levelFor`)
1. `reps == 0` → **neu**
2. `masteryBox <= 0` → **rot** (vor jeder Retrievability-Prüfung! Direkt nach
   einer Wiederholung ist die Retrievability immer ~1,0)
3. aktuelle Retrievability < 0,7 → **rot** (Verfall/vergessen)
4. `masteryBox >= 4` UND Retrievability ≥ 0,9 → **grün**
5. sonst → **gelb**

Folge: Grün braucht mindestens 4 richtige Antworten an 4 verschiedenen Tagen.

### 5.6 Schwierigkeits-Eskalation (`Flashcard.copyWithBoxUpdate`)
Nur für Karten mit `variantChain`, nur bei `isCorrect != null` und ohne Tipp.
`FsrsService.review` läuft VORHER (masteryBox enthält die aktuelle Antwort).
- richtig UND Stufe grün (`masteryBox >= 4`, d.h. an 4 verschiedenen Tagen
  richtig) UND es gibt eine nächste Stufe → Beförderung. `variantBox` (richtig
  in Folge) ist nur noch informativ. Liegt die nächste Stufe in
  `pendingVariants` (z.B. aus „Frage erstellen“ mit Leicht/Mittel/Schwer),
  sofort und ohne KI (`needsGeneration=false`); sonst erzeugt
  `ReviewService.generatePromotion` sie per `AiService.generateHarderVariant`
  im Hintergrund (`needsGeneration=true`; schlägt das fehl, bleibt die Karte
  grün auf ihrer Stufe und der nächste richtige Versuch probiert es erneut).
- Die neue Stufe startet neu (`FsrsService.restartForNewStage`): morgen fällig,
  Anfangs-Stabilität wie nach erstem „Gut“, `masteryBox = 1` (gelb).
- falsch: `variantMissStreak+1`; ab 2 in Folge (auf der schwersten Stufe ab 5)
  Rückstufung auf die letzte Stufe aus `variantHistory`; die verlassene Stufe
  wandert zurück in `pendingVariants`. Rückstufung von der schwersten Stufe
  setzt `masteryBox = 3` (gelb statt rot).
- Die Karte ist immer EIN Datensatz, der seinen Typ wechselt – nie mehrere
  Stufen gleichzeitig im Pool.

### 5.7 Daily Quiz / Scheduler (`DailySchedulerService.buildPlan`)
- **Einheiten-Gate**: Karten mit `unitId` einer NICHT behandelten Einheit
  werden ausgelassen – außer `priorityIntroduction` (bewusst beim Lesen
  erstellte Fragen/Zwischen-Check-Fehler). Unbekannte `unitId` → erlaubt.
  „Behandelt“ liefert `LectureUnitRepository.loadAllCoveredById` bereits
  effektiv (abgehakt ODER `scheduledDate` erreicht). Häkchen entfernen bei
  erreichtem Termin entfernt auch den Termin.
- **Fällig**: `reps>0 && due < morgen`, sortiert nach `due`, unbegrenzt.
- **Neu** (`reps==0`) pro Fach budgetiert: Pacing über Tage bis zur Klausur
  (abzüglich 3 Tage Wiederholungspuffer, ohne Klausur 14 Tage Horizont),
  gebremst durch schwachen Wissensstand (50–100 %), Mindestboden 10, Maximum
  15; in den letzten 3 Tagen vor der Klausur 0. Davon abgezogen: heute im
  Daily Quiz schon eingeführte neue Karten (`introducedTodayByModule` aus
  `DailySessionState`) – kein zweites Budget durch „Aktualisieren“/Neustart.
  `priorityIntroduction`-Karten kommen immer (auch über das Budget hinaus),
  danach die übrigen nach ältester `createdAt`.
- Sessiongröße max. 60 (Fällige haben Vorrang); Fächer werden interleaved.
- Falsch beantwortete Karten kommen am Sessionende erneut (Wiederholungsrunde,
  max. 3 Versuche je Karte); danach „Freiwillig weiterlernen“
  (`buildExtraBatch`, ignoriert das Budget).
- **Tagesstand** (`DailySessionState`/`DailySessionRepository`, Record
  `settings/daily_session`, gilt nur für den Kalendertag): Anzahl
  beantworteter Karten, Wiederholungsrunde (IDs + Versuche), heute eingeführte
  neue Karten. Wird nach jeder Antwort gespeichert und beim Laden des Plans
  wiederhergestellt; ein Tab-Wechsel plant neu, sobald keine Karte mitten in
  der Runde steht.

## 6. Weitere Invarianten / Stolperfallen

- **KI-Ausgabe ist ungeprüfte Eingabe**: alles über `QuestionParsing`
  (`normalizeGeneratedFlashcard`, tolerante `parse*`), nie hart casten.
- **Löschen kaskadiert**: Fach → Materialien, Zusammenfassungen, Konzepte,
  Karten, Einheiten, Chat + PDF-Dateien; Einheit → entfernt `unitId` überall.
- **Sync** (Firestore, `users/{uid}` bzw. `sync_codes/{code}`, Format 2):
  Fächer, Einheiten, Materialien (OHNE `filePath`/`fileBytesBase64`),
  Zusammenfassungen, Konzepte, Karten als gzip-JSON (`SyncCodec`); passt es in
  900 KB, direkt im Hauptdokument (`data`), sonst in `…/sync_parts/0..n-1`
  (braucht die aktuellen `firestore.rules`). `pushId` im Hauptdokument und in
  jedem Teil – Download prüft, dass alles zusammenpasst. Alte Ein-Dokument-
  Stände bleiben lesbar. Pull ERSETZT lokal komplett, behält aber lokale PDFs.
  API-Key nur über den Konto-Weg. **Auto-Sync** (`AutoSyncService`, Schalter
  `autoSyncEnabled`): lauscht auf Änderungen der Daten-Stores, lädt 30 s nach
  der letzten Änderung hoch, sofort beim Verlassen der App und bei
  App-Resume, Retry mit Backoff (1/3/10/30 min); blockiert (`conflict`), wenn der Cloud-Stand seit dem letzten
  Abgleich (`lastSyncedPushId`) von einem anderen Gerät (`deviceId`) stammt.
  Downloads laufen über `runWithoutTrigger`, damit sie keinen Upload auslösen.
- **LaTeX**: Formeln in `$…$`/`$$…$$`/`\(…\)`/`\[…\]`, dargestellt über
  `MathText` (fällt bei Fehlern auf Rohtext zurück). KI-JSON läuft vor
  `jsonDecode` durch `MathMarkup.escapeLatexInJson` (einfache Backslashes in
  Formeln wären sonst Steuerzeichen wie `\f`/`\t`/`\n` oder ungültig).
- **Sync-Code vs. Konto**: Geheimnisse (OpenRouter-Key, PDF-Speicher-
  Zugangsdaten) reisen nur über den Konto-Weg; beim Download über einen
  Sync-Code werden sie verworfen (`syncedAiSettingsForPull`). Leere
  Cloud-Werte löschen nie lokale (`mergeAiSettings`).
- **Eigener PDF-Speicher** (`PdfCloudStore`: S3-kompatibel mit Signatur V4
  oder WebDAV; `PdfCloudSyncService`): vor jedem Daten-Upload werden lokale
  PDFs ohne `remotePdfKey` hochgeladen (Fehler dort blockieren den Daten-Sync
  nicht, siehe `AutoSyncService.lastPdfError`); andere Geräte laden beim
  Öffnen herunter. Geänderte PDF (eingebettete Markierungen) setzt
  `remotePdfKey` zurück → Neu-Upload. Löschen entfernt die Cloud-Kopie.
  Ohne Zugangsdaten: aus. Web braucht CORS am Speicher.
- **Texterkennung** (`PdfOcrService`): Seiten mit < 25 Zeichen gelten als
  gescannt; automatisch beim Upload nur, wenn ≥ 50 % der Seiten leer sind
  (sonst Kosten bei normalen Foliensätzen), manuell pro Material für jede
  leere Seite. Nur diese Seiten gehen (max. 8 je Anfrage, als eigene PDF) an
  das Vision-Modell (OpenRouter-PDF-Input, Marker `<<<SEITE n>>>`).
- Screens mit langen KI-Aufrufen nutzen `SafeSetState` (kein `setState` nach
  Verlassen). Context-Zugriffe (Repos, ScaffoldMessenger) VOR dem ersten
  `await` auslesen.
- Screens im IndexedStack lesen Daten nicht automatisch reaktiv – neue Screens
  mit „lade einmal im initState“-Muster brauchen einen Refresh-Pfad.
- CI (`android-apk.yml`, `windows-app.yml`) baut nur nach grünem
  `flutter analyze` + `flutter test`.
- Code-Kommentare/Doc-Kommentare und UI-Texte sind Deutsch.
- README.md dokumentiert Features ausführlich und wird bei Änderungen
  mitgepflegt.

## 7. Aktueller Stand (September 2026)

Entwicklungszweig: `claude/neue-lern-app-fokus-ej3k48`. `flutter analyze`
sauber, 420 Tests grün, `flutter build web` erfolgreich.

Umgesetzt (alle vom Nutzer freigegebenen Punkte, je ein Commit):
1. Gemeinsamer `ReviewService`/`CardReviewMixin` für Daily Quiz, Üben, Sprint,
   Probeklausur.
2. Beförderung erst bei Ampel-Grün, Neustart der neuen Stufe, 7-Tage-Deckel
   für Durchgangsstufen; „Schwer“ senkt die Ampel nicht; Sprint zählt.
3. Daily-Quiz-Tagesstand übersteht Neustart; „Aktualisieren“ ohne zweites
   Neu-Karten-Budget.
4. Sync komprimiert + aufgeteilt (1-MiB-Limit gelöst), PDFs reisen nicht mit,
   Auto-Sync mit Offline-Retry und Schutz vor Überschreiben.
5. KI-Tipp vor, KI-Erklärung („Erklär mir das“, „Einfacher erklären“) nach
   der Antwort.
6. Schwachstellen/Fehlertagebuch (`WeaknessService`, `WeaknessScreen`) inkl.
   „die 20 schwächsten üben“ und KI-Musteranalyse.
7. Probeklausur mit Zeitlimit, Note (Hochschulskala), Auswertung je Einheit,
   Durchsicht mit KI-Erklärung, Verlauf.
8. LaTeX-Darstellung + JSON-Reparatur für Formeln.

Zweite Runde (nach `AUDIT.md`/`DESIGN_IDEEN.md`, Stand 26.09.2026):
9. Audit-Fixes B1–B3, H1, H3, H4, H6–H8, H11 + Kleinkram (siehe AUDIT.md).
10. Einheiten mit Termin (automatisch behandelt), „Termine aus Stundenplan“,
    KI-Einheitenvorschläge.
11. Texterkennung für gescannte PDFs (automatisch + manuell).
12. PDF-Sync über den eigenen Speicher (S3/WebDAV), ohne Zugangsdaten aus.
13. CSV-Export/-Import von Karten (Backup, Anki).
Bewusst nicht: Vorlesen (TTS), KI-Wochenplan, Markdown-Notizen und alles unter
„BEWUSST NICHT“ in DESIGN_IDEEN.md.

Offen / zu beachten:
- `firestore.rules` muss nach dem Sync-Umbau einmal neu in der Firebase-
  Konsole veröffentlicht werden (Regel für `sync_parts`); ohne das klappt der
  Upload nur, solange der komprimierte Bestand unter 900 KB bleibt (die App
  meldet es verständlich).
- Auto-Sync ist standardmäßig aus (Schalter in den Einstellungen).
- Auto-Sync-Konfliktlösung ist bewusst einfach (ganzer Stand gewinnt, kein
  Zusammenführen einzelner Karten).
- Zurückgestellt aus dem Audit (Nutzer: gemerkt, vorerst nicht umsetzen):
  H9 (gleichzeitiger Push zweier Geräte ohne Transaktion), H10 (selbst
  gewählte Sync-Codes; Konto-Weg empfohlen).
- H5 ist Absicht (fällige Karten werden nicht gedeckelt).
- Texterkennung und PDF-Speicher sind nur mit Mocks getestet; echter
  OpenRouter-PDF-Input und echte R2/B2/WebDAV-Speicher einmal von Hand prüfen.
