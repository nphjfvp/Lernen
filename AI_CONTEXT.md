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
  model_catalog, chat_messages`. Record-Key `settings/app_settings` =
  AppSettings, `settings/study_days` = Lerntage-Protokoll.
- **KI**: OpenRouter Chat-Completions über `http` (`lib/services/ai_service.dart`),
  drei Modellrollen (Fragen/Text, Vision, Crosscheck). Timeout 3 min, Transport-
  fehler → `AiServiceException`.
- **PDF**: Syncfusion (`syncfusion_flutter_pdf` Textextraktion,
  `syncfusion_flutter_pdfviewer` Anzeige); DOCX/PPTX über `archive` + `xml`.
- **Optional**: Firebase (`firebase_core`, `cloud_firestore`, `firebase_auth`,
  `google_sign_in`) für Cloud-Sync/Account; `webview_flutter` für den
  interaktiven `html`-Fragetyp (nur Android/iOS, sonst Fallback);
  `flutter_local_notifications` (Lernerinnerung), `home_widget` (Android-Widget).
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
(Vorlesungseinheit, `covered` = "behandelt", Notizen), `MaterialItem`
(extrahierter Text, PDF-Datei/Base64, Markierungen, Notiz, `topicIndex`,
`kind`: slide/exercise/practiceExam), `Concept` (inkl. Seiten-Quasi-Link
`linkedMaterialId`/`linkedPageNumber`), `Summary`, `ChatMessage`,
`AppSettings`, `MasterySnapshot` (tägliche Ampel-Verteilung für den Trend).

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

| Ort | FSRS/Ampel-Wirkung |
| --- | --- |
| Daily Quiz (`daily_quiz_screen.dart`) | ja |
| Üben (`practice_screen.dart`) | ja |
| Zwischen-Check im Lernmodus | nur falsch Beantwortetes wird gespeichert – als `Grade.again` verbucht (rot, morgen fällig) + `priorityIntroduction` |
| Sprint (Mini-Spiel) | nein (bewusst, im UI angekündigt) |
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
erhöht `lapses`, setzt `state='relearning'`.

### 5.4 masteryBox (in `FsrsService.review`)
- `good`/`easy` → +1, gedeckelt bei 4 – **aber nur einmal pro Kalendertag**
  (war `lastReview` heute, bleibt der Wert).
- `again`/`hard` → −1, Boden 0 (auch mehrfach am selben Tag).

### 5.5 Ampel (`MasteryService.levelFor`)
1. `reps == 0` → **neu**
2. `masteryBox <= 0` → **rot** (vor jeder Retrievability-Prüfung! Direkt nach
   einer Wiederholung ist die Retrievability immer ~1,0)
3. aktuelle Retrievability < 0,7 → **rot** (Verfall/vergessen)
4. `masteryBox >= 4` UND Retrievability ≥ 0,9 → **grün**
5. sonst → **gelb**

Folge: Grün braucht mindestens 4 richtige Antworten an 4 verschiedenen Tagen.

### 5.6 Schwierigkeits-Eskalation (`Flashcard.copyWithBoxUpdate`)
Nur für Karten mit `variantChain` und nur bei `isCorrect != null`.
- richtig: `variantBox+1`; erreicht es `promotionThreshold` (3) und gibt es eine
  nächste Stufe → Beförderung. Liegt die nächste Stufe in `pendingVariants`
  (z.B. aus „Frage erstellen“ mit Leicht/Mittel/Schwer), sofort und ohne KI
  (`needsGeneration=false`); sonst erzeugt der Aufrufer die Stufe per
  `AiService.generateHarderVariant` im Hintergrund (`needsGeneration=true`).
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
- **Fällig**: `reps>0 && due < morgen`, sortiert nach `due`, unbegrenzt.
- **Neu** (`reps==0`) pro Fach budgetiert: Pacing über Tage bis zur Klausur
  (abzüglich 3 Tage Wiederholungspuffer, ohne Klausur 14 Tage Horizont),
  gebremst durch schwachen Wissensstand (50–100 %), Mindestboden 10, Maximum
  15; in den letzten 3 Tagen vor der Klausur 0. Sortierung:
  `priorityIntroduction` zuerst, dann älteste `createdAt`.
- Sessiongröße max. 60 (Fällige haben Vorrang); Fächer werden interleaved.
- Falsch beantwortete Karten kommen am Sessionende erneut (Wiederholungsrunde,
  max. 3 Versuche je Karte); danach „Freiwillig weiterlernen“
  (`buildExtraBatch`, ignoriert das Budget).

## 6. Weitere Invarianten / Stolperfallen

- **KI-Ausgabe ist ungeprüfte Eingabe**: alles über `QuestionParsing`
  (`normalizeGeneratedFlashcard`, tolerante `parse*`), nie hart casten.
- **Löschen kaskadiert**: Fach → Materialien, Zusammenfassungen, Konzepte,
  Karten, Einheiten, Chat + PDF-Dateien; Einheit → entfernt `unitId` überall.
- **Sync** (Firestore, ein Dokument pro Nutzer/Code) überträgt Fächer,
  Einheiten, Materialien, Zusammenfassungen, Konzepte, Karten + KI-Settings;
  Pull ERSETZT lokal komplett. API-Key nur über den Konto-Weg.
- Screens im IndexedStack lesen Daten nicht automatisch reaktiv – neue Screens
  mit „lade einmal im initState“-Muster brauchen einen Refresh-Pfad.
- Code-Kommentare/Doc-Kommentare und UI-Texte sind Deutsch.
- README.md dokumentiert Features ausführlich und wird bei Änderungen
  mitgepflegt.

## 7. Aktueller Stand (September 2026)

Entwicklungszweig: `claude/neue-lern-app-fokus-ej3k48`. Alle oben genannten
Features sind umgesetzt; `flutter analyze` sauber, 327 Tests grün.

Zuletzt behoben (Audit): FSRS-Grade-Zuordnung (falsch → again, richtig → good),
masteryBox max. +1 pro Tag, doppeltes Absenden von Antworten, Wiederholungs-
runde mit wiederverwendetem Antwort-State, Zwischen-Check-Fehler landeten als
„Neu“ statt rot, Single-Choice-Widerspruch UI/Prüfung, Kategorie-Drag&Drop
zeigte nur einen Begriff je Kategorie, Einheit/Fach-Löschen hinterließ
verwaiste Daten, Konzept-Bearbeiten verlor den Seiten-Link, Sync ohne
Einheiten und mit überschriebenen KI-Settings, Widget-Zählung ohne
Einheiten-Gate, KI-Parsing-Abstürze, fehlender KI-Timeout, veraltete Daily-
Quiz-/Fortschritt-Tabs, falsch berechneter Streak.

Freigegebener Backlog (vom Nutzer bestätigt, noch umzusetzen):
1. **Sync-Größe:** Firestore-Dokumentlimit 1 MiB – aktuell liegt alles
   (inkl. PDF-Base64, extrahierter Texte, Screenshots) in EINEM Dokument, der
   Sync scheitert bei größerem Datenbestand. Lösungsidee (nach Vorbild der
   Vorgänger-App `nphjfvp/quiz-app`): Daten auf mehrere Dokumente je
   Kategorie aufteilen (Fächer/Einheiten, Karten, Konzepte/Zusammenfassungen,
   Einstellungen, Meta mit `updatedAt`), jedes vor dem Upload auf < 900 KB
   prüfen; PDF-Dateien selbst nicht über Firestore syncen (oder getrennt,
   in Stücke geteilt). Optional Auto-Sync mit Verzögerung + Offline-Warteschlange.
2. **Beförderung an Ampel-Grün koppeln:** In der Eskalationskette erst dann
   zur nächsten Stufe, wenn die aktuelle Stufe grün ist (statt 3× richtig in
   Folge, was an einem Tag möglich ist); masteryBox je Stufe zurücksetzen.
3. **Sprint-Antworten zählen** für FSRS/Ampel.
4. **„Schwer“-Selbstbewertung** senkt die Ampel nicht mehr.
5. **Gemeinsamer Bewertungs-Service** statt duplizierter Logik in
   `DailyQuizScreen` und `PracticeScreen`.
6. **„Aktualisieren“** nach fertiger Session vergibt kein neues volles
   Neu-Karten-Budget (bereits heute eingeführte Karten zählen mit).
