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
  (iOS möglich). CI: `.github/workflows/android-apk.yml`, `windows-app.yml`
  (Windows: `Lernen-Setup.exe` per Inno Setup aus `windows/installer/lernen.iss`
  plus ZIP; das In-App-Update lädt unter Windows das Setup und installiert
  still, unter Android die APK und öffnet den System-Installer über
  `MainActivity` + FileProvider, siehe `update_installer_io.dart`).
- **State**: `provider` (`ChangeNotifier`-Repositories, in `main.dart`
  registriert). `ModuleRepository` und `SettingsRepository` werden VOR `runApp`
  geladen.
- **Persistenz**: `sembast` (Datei auf IO, IndexedDB via `sembast_web` im Web),
  Singleton `DatabaseService` mit Stores: `modules, materials, summaries,
  concepts, lecture_units, flashcards, settings, mastery_snapshots,
  model_catalog, chat_messages`. Record-Keys im Store `settings`:
  `app_settings` = AppSettings, `study_days` = Lerntage-Protokoll,
  `daily_session` = heutiger Daily-Quiz-Stand, `mock_exam_results` =
  Probeklausur-Verlauf. Gesynct werden inzwischen auch Lerntage,
  Probeklausuren, Daily-Stand (heute), Frage-Chats und Ampel-Trend (siehe
  `applySyncedHistory` in sync_service.dart: Chats/Probeklausuren ersetzen,
  Lerntage/Trend/Daily-Stand zusammenführen); `app_settings` nur die Felder
  aus `syncedSettingsOf` (Geheimes nur übers Konto).
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
  multipleChoice, freeText, fillBlank, dragDrop, dragCategory, html,
  diagramLabel, markImage, table), je nach Typ
  `options`/`correctText`/`blanks`/`dragPairs`/`htmlContent`/`imageTargets`/
  `tableRows`;
  `imageBase64` (Seiten-Screenshot/Bild, nur wenn für die Frage nötig).
- Bildfragen: `imageTargets` (`List<ImageTarget>`, Koordinaten relativ zum
  Bild 0..1; `group` = austauschbare Stellen, geprüft über
  `AnswerChecker.diagramLabelZones`, Zuordnen exakt, Eintippen tolerant +
  `AiService.checkDiagramLabelAnswers`; `fromMap` liest auch `box`
  [l,o,r,u] und erkennt Prozent/Promille). `diagramLabel` = Punkte MIT `label` (nur beschriftete zählen),
  `markImage` = Rechtecke `x,y` (Mitte) + `w,h` (0 = Punkt → Mindestgröße
  `AnswerChecker.minRegionSide`). `ImageTarget.fromMap` liest auch Kreis
  (`radius`) und Vieleck (`points`) der Vorgänger-App. Ohne Bild oder Ziele
  ist die Karte nicht beantwortbar → Karteikarte (`AnswerChecker.isAnswerable`).
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
Seiten-Links). Nach einem neuen Feld: `grep -rn "Flashcard(" lib`. Zuletzt
dazugekommen: `imageTargets`, `stageLevel`/`stageGroup`, `aiHints`,
`tableRows` (auch in `VariantSnapshot`, Stufenwechsel, Export/Import). Bild/Ziele einer gespeicherten Karte ändern:
`Flashcard.copyWithImage` (Lernstand bleibt).

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
  Option zählt (Anzeige gemischt, `optionDisplayOrder`); Multiple-Choice –
  exakte Menge, "Prüfen" erst nach Auswahl; Freitext/Lückentext –
  normalisiert + Levenshtein-Toleranz (1 ab 5 Zeichen, 2 ab 9) + Varianten
  per ";". Bei lokaler Ablehnung KI-Zweitmeinung: Freitext
  `checkFreeTextAnswer`, Lückentext `checkFillBlankAnswers` (ganzer Satz,
  Antwort `{"results":[{"correct","note"}]}`, Temperatur 0; Tippfehler,
  vertauschte gleichrangige Lücken, gleichwertige Begriffe zählen; die KI
  kann nur hochwerten, nie eine lokal richtige Lücke verwerfen). Ergebnis
  und Fehler der KI-Prüfung werden angezeigt (`_checkInfo`); „Als richtig
  werten“ (Freitext/Lückentext, nicht Probeklausur) meldet `isCorrect: true`.
  Zuordnen/Kategorien – INDEX-basiert (`zoneToSource`/`sourceToCategory`),
  nie per Text; ein mehrfach genanntes Ziel macht aus `drag_drop` eine
  Kategorien-Frage (`isCategoryDrag`), Kategorien per Multiset geprüft.
  Unbrauchbare Karten (`!isAnswerable`) werden als Karteikarte gezeigt.

### 5.3 FSRS (`lib/services/fsrs_service.dart`)
FSRS-4.5 mit Default-Gewichten, Ziel-Retention 0,9, **Mindestintervall 1 Tag**
(keine Same-Day-Learning-Steps). Vergangene Zeit in KALENDERTAGEN
(`calendarDaysBetween`, UTC-Daten), `due` = Mitternacht per
`DateTime(j, m, t + n)` (zeitumstellungssicher). `again` erhöht `lapses` nur
bei einer schon gelernten Karte (neu → `state='learning'`, sonst
`'relearning'`). **Erneuter Fehlversuch am selben Tag**
(`FsrsService.isRepeatFailureToday`: heute schon beantwortet, Zustand
learning/relearning) ändert nichts mehr außer `reps`/`lastReview`: kein
Lapse, keine Stabilitäts-/Schwierigkeitsänderung, masteryBox bleibt. Karten auf einer leichten/
mittleren Stufe einer Eskalationskette (nicht der letzten) bekommen höchstens
`transitStageMaxIntervalDays` = 7 Tage Abstand.

**Gewichtung**: `FsrsService.review(..., weight:)` teilt das FSRS-Intervall
durch das effektive Gewicht (`weightedIntervalDays`, min. 1 Tag; der
7-Tage-Deckel greift danach). Effektives Gewicht = `Flashcard.weight` ×
`Module.weight` (`effectiveWeight` in `review_service.dart`), ermittelt in
`CardReviewMixin.recordReview` – gilt also für Daily Quiz, Üben, Sprint und
Probeklausur. Stabilität/Schwierigkeit/Ampel bleiben unberührt: Gewichtung
heißt nur „öfter dran“. Standard: Übungsblatt-Karten 1,5, alles andere 1,0
(`defaultFlashcardWeightFor(MaterialKind)` an jeder Erzeugungsstelle).
Modellgrenzen 0,25–4 (`_sanitizeWeight`), UI-Regler 0,5–3 in 0,25-Schritten.

### 5.4 masteryBox (in `FsrsService.review`)
- `good`/`easy` → +1, gedeckelt bei 4 – **aber nur einmal pro Kalendertag**
  (war `lastReview` heute, bleibt der Wert).
- `hard` → unverändert (richtig, aber mühsam bzw. mit Tipp).
- `again` → −1, Boden 0 – ebenfalls nur einmal pro Tag (ein erneuter
  Fehlversuch am selben Tag zählt nicht; falsch nach einem heute richtigen
  Versuch schon).

### 5.5 Ampel (`MasteryService.levelFor`)
1. `reps == 0` → **neu**
2. `masteryBox <= 0` → **rot** (vor jeder Retrievability-Prüfung! Direkt nach
   einer Wiederholung ist die Retrievability immer ~1,0)
3. aktuelle Retrievability < 0,7 → **rot** (Verfall/vergessen)
4. `masteryBox >= 4` UND Retrievability ≥ 0,9 → **grün**
5. sonst → **gelb**

Folge: Grün braucht mindestens 4 richtige Antworten an 4 verschiedenen Tagen.

### 5.6 Schwierigkeits-Eskalation (`Flashcard.copyWithBoxUpdate`)
Läuft für JEDE Karte (Fehler-Leiter), befördert aber nur Karten mit
`variantChain` und nur bei einer ohne Hilfe gewussten Antwort (Grade good/easy,
`promotable`). `FsrsService.review` läuft VORHER (masteryBox enthält die
aktuelle Antwort).
- **Fehler-Leiter** (`variantMissStreak`, jede falsche Antwort zählt – auch in
  der Wiederholungsrunde, jede richtige setzt auf 0): ab 2
  (`Flashcard.hintMissStreak`) zeigt `QuestionAnswerView` vor dem Antworten
  automatisch eine KI-Hilfestellung, ab 3 eine zweite, deutlichere
  (`AiService.generateHint(previousHints:)`, gespeichert in `Flashcard.aiHints`
  per `FlashcardRepository.updateHints`, bei Stufenwechsel verworfen); richtig
  mit Hilfestellung zählt wie „mit Tipp“ (Grade hard). Ab 4
  (`fallbackMissStreak`) Rückfall: Stufenkette → vorige Stufe; getrennte
  Karte → `ReviewOutcome.fallbackRequested`, `CardReviewMixin` holt die
  nächstleichtere Stufe der Gruppe zurück (`StageGate.reactivateEasier`:
  masteryBox höchstens 3, heute fällig) und setzt die Leiter der Karte auf 0.
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
- Rückstufung (Leiter bei 4) auf die letzte Stufe aus `variantHistory`; die
  verlassene Stufe wandert zurück in `pendingVariants`. Rückstufung von der
  schwersten Stufe setzt `masteryBox = 3` (gelb statt rot).
- Die Karte ist immer EIN Datensatz, der seinen Typ wechselt – nie mehrere
  Stufen gleichzeitig im Pool.

### 5.6b Stufen über getrennte Karten (`StageGate`, `stage_gate_service.dart`)
Leicht → Mittel → Schwer für GETRENNTE Karten desselben Sachverhalts.
- Gruppe: `Flashcard.stageGroup` (KI/von Hand) sonst `conceptId`, je Fach;
  Karten mit Stufenkette (>1 Stufe) gehören keiner Gruppe an. Stufe:
  `Flashcard.stageLevel` (0–2) sonst aus dem Typ (`StageGate.levelOfType`:
  Auswahl/markImage leicht, Lücke/Zuordnen/diagramLabel/flashcard mittel,
  Freitext/html schwer).
- Aktive Stufe einer Gruppe = leichteste, in der noch eine Karte nicht
  `masteryBox >= 4` hat (bewusst ohne Retrievability, sonst lebten ruhende
  Karten durch Verfall von selbst wieder auf); sitzen alle, die schwerste.
  Darunter `done` (ruht), darüber `locked` (wartet). Fehlende Stufen rücken
  nach; eine einzelne Stufe läuft normal.
- Angewendet in `DailySchedulerService._eligible` (Plan + Extra-Charge),
  Üben, Sprint, Fehlertagebuch (`StageGate.learnable`) – NICHT in der
  Probeklausur. Ampel: `done` zählt grün, `locked` als neu
  (`MasteryService.levelFor(stage:)`/`breakdown`).
- Neue Karten aus Nachbereiten bringen `level`/`group` von der KI mit
  (`QuestionParsing.parseStageLevel`/`parseStageGroup`, Gruppe je
  Speichervorgang eindeutig gemacht). Bestehende Karten: Kartenliste →
  „Per KI in Ordner sortieren“ (`AiService.assignStages`, Portionen à 80,
  `knownGroups` = Ordnernamen der vorigen Portionen, damit gleiche Namen
  über Portionen zusammenfinden; `StageGate.applyAssignments` hängt
  `#runTag` an), sonst Konzept + Typ. Prompt: nur DASSELBE Wissen in einen
  Ordner (sonst ruht eine leichte Frage mit anderem Inhalt zu früh).
- Anzeige: `StageGate.listEntries` bildet aus der Kartenliste Ordner
  (`StageFolder`, Gruppen ab 2 Karten, Name über `StageGate.groupName`:
  KI-/Handname ohne `#…`, sonst Konzepttitel; `manuell-…`/`einzeln-…` ohne
  Namen → schwerste Frage als Titel). `byConceptOnly` → Hinweis „Per KI
  sortieren“. Von Hand: „Stufe“ je Karte, Ordner umbenennen/auflösen,
  Sammel-Bearbeiten „In Ordner legen“ (vorhandener Ordner = dessen
  `stageGroup ?? conceptId`) / „Aus Ordner nehmen“ (`einzeln-<id>`).
  Stufenketten-Karten zeigen ihre Stufen in `_ChainStages`.

### 5.7 Daily Quiz / Scheduler (`DailySchedulerService.buildPlan`)
- Nur Karten **bestehender Fächer** (`_eligible`; `FlashcardRepository.loadAll`
  filtert verwaiste Karten ohnehin für alle Verbraucher).
- **Einheiten-Gate**: Karten mit `unitId` einer NICHT behandelten Einheit
  werden ausgelassen – außer `priorityIntroduction` (bewusst beim Lesen
  erstellte Fragen/Zwischen-Check-Fehler). Unbekannte `unitId` → erlaubt.
  „Behandelt“ liefert `LectureUnitRepository.loadAllCoveredById` bereits
  effektiv (abgehakt ODER `scheduledDate` erreicht). Häkchen entfernen bei
  erreichtem Termin entfernt auch den Termin.
- **Stufen-Gate** (5.6b): nur die aktive Stufe je Gruppe, wartende und
  ruhende Karten sind weder fällig noch neu.
- **Fällig**: `reps>0 && due < morgen`, sortiert nach `due`, unbegrenzt.
- **Neu** (`reps==0`) pro Fach budgetiert: Pacing über Tage bis zur Klausur
  (abzüglich 3 Tage Wiederholungspuffer, ohne Klausur 14 Tage Horizont),
  gebremst durch schwachen Wissensstand (50–100 %), Mindestboden 10, dann ×
  `Module.weight` (Fach-Gewichtung), Maximum 15; in den letzten 3 Tagen vor
  der Klausur 0. Davon abgezogen: heute im
  Daily Quiz schon eingeführte neue Karten (`introducedTodayByModule` aus
  `DailySessionState`) – kein zweites Budget durch „Aktualisieren“/Neustart.
  `priorityIntroduction`-Karten kommen immer (auch über das Budget hinaus),
  danach die übrigen nach ältester `createdAt`.
- Sessiongröße max. 60 (Fällige haben Vorrang; gekürzt werden neue Karten
  reihum je Fach, `priorityIntroduction` zuletzt); Fächer werden interleaved.
- Falsch beantwortete Karten kommen am Sessionende erneut (Wiederholungsrunde,
  max. 3 Versuche je Karte; eine inzwischen gelöschte Karte nicht –
  `ReviewOutcome.cardDeleted`); danach „Freiwillig weiterlernen“
  (`buildExtraBatch`, ignoriert das Budget).
- **Tagesstand** (`DailySessionState`/`DailySessionRepository`, Record
  `settings/daily_session`, gilt nur für den Kalendertag): Anzahl
  beantworteter Karten, Wiederholungsrunde (IDs + Versuche), heute eingeführte
  neue Karten. Wird nach jeder Antwort gespeichert und beim Laden des Plans
  wiederhergestellt; ein Tab-Wechsel plant neu, sobald keine Karte mitten in
  der Runde steht.

## 6. Weitere Invarianten / Stolperfallen

- **KI-Ausgabe ist ungeprüfte Eingabe**: alles über `QuestionParsing`
  (`normalizeGeneratedFlashcard`, tolerante `parse*`), nie hart casten;
  Listen über `_mapsIn` (ein kaputter Eintrag fällt einzeln weg). Auch
  Beförderungen (`applyPromotion`) laufen durch die Normalisierung.
- **Antworten auf den gespeicherten Stand**: `recordReview` lädt die Karte
  neu (`loadById`) und wendet die Antwort darauf an; `FlashcardRepository.
  update` schreibt nur bestehende Datensätze (keine „Zombies“ gelöschter
  Karten).
- **Datum**: nie `Duration(days: n)` auf Ortszeit oder `difference().inDays`
  zwischen Mitternächten – `DateTime(j, m, t ± n)` bzw. `calendarDaysBetween`
  (`lib/services/calendar_days.dart`). CI testet mit `TZ=Europe/Berlin`.
- **Speichern-Knöpfe** mit längerem Speichern sperren sich (`_saving`), und
  das Speichern läuft auch nach Verlassen des Screens vollständig durch
  (Repos vor dem ersten `await` lesen). Screens mit ungespeichertem
  KI-Ergebnis nutzen `DiscardGuard` (Rückfrage bei Zurück).
- **PDF-Markierungen**: jede Annotation trägt die Markierungs-ID in
  `subject` – nur so lässt sie sich nach „Speichern“ (Annotationen werden
  eingebettet) wieder entfernen.
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
- **„Frage erstellen“** (`PageQuestionCreationSheet`): 1–5 Fragen je Aufruf,
  jede mit den gewählten Stufen (Typ je Stufe fest – auch html – oder
  `null` = KI wählt, nie html);
  Fokus optional per markiertem Bildausschnitt (`PageRegionPicker` +
  `cropImageRelative`, geht als zweites Bild mit), Text und Antwort. Antwort
  der KI: `{"questions":[{"flashcards":[…]}]}` (`parsePageQuestionGroups`
  liest auch das alte flache Format); jede Frage wird per
  `mergeTiersIntoChain` EINE Karte mit `pendingVariants`. Wählbar sind
  zusätzlich `diagramLabel`/`markImage` (`selectablePageQuestionTypes`, die
  KI liefert `"targets"`; nie bei „KI entscheidet“); Bildfragen bekommen
  immer das Bild. Eigene Bildfragen ohne KI: „Bildfrage selbst erstellen“
  (`_createImageQuestion`, als `manual` markiert, bleiben bei
  Neu-Generierung erhalten).
- **Bild-Editor** (`showImageEditor`, `lib/ui/widgets/image_editor_screen.dart`):
  Abdecken/Text werden per `applyImageEdits` (`lib/services/image_edit.dart`)
  in Originalauflösung ins PNG gerechnet; im Modus `ImageTargetMode.labels`/
  `regions` setzt er zusätzlich die `imageTargets`. Alles ist darin
  auswähl-, verschieb- und (Rahmen) skalierbar; `ImageEditResult.edits` +
  Ausgangsbild erlauben späteres Weiterbearbeiten (in „Frage erstellen“ je
  Frage in `_GeneratedQuestion.imageBase/imageEdits`; KI-Abdeckungen aus
  `"covers"`/Kästen landen dort, `buildPageQuestionCards(coversOut:)`).
  Für Bildfragen geht das Bild mit `drawCoordinateGrid` an die KI. Aufrufer: Vorschau in
  „Frage erstellen“, Kartenliste (`_editImage`), beim Lernen über
  `QuestionAnswerView.onImageEdited` → `CardReviewMixin.saveEditedImage`
  (lädt die gespeicherte Karte, nicht den Schnappschuss; nicht in der
  Probeklausur). `RelativeImage` zeigt Bilder im echten Seitenverhältnis mit
  Ebenen an relativen Koordinaten (Quiz + Editor).
- **„Fragen aus PDF importieren“** (`PdfQuestionImportScreen` +
  `PdfQuestionImportService`): Seiten paketweise (3) an
  `AiService.scanPdfPagesForQuestions` (Vision-Modell), 3 Pakete parallel,
  `contentOnly`/`fillMissingSolutions`/`referenceText` steuern den Prompt.
  Standard: `PdfPageRenderer` (über `PdfViewerPlatform.instance`, also
  dieselbe Engine wie der Viewer; `PageImageRenderer` als Test-Hook) rendert
  die Seiten als PNG, `drawEdgeRuler` zeichnet eine Randskala, dazu geht der
  Seitentext mit. Die KI liefert `imageBox`/`imageCovers`/`targets` in
  Seitenkoordinaten; `PdfQuestionImportService.attachFigure` schneidet aus,
  rechnet Stellen auf den Ausschnitt um und zeichnet Abdeckungen ein.
  Ohne Renderer (Linux, Tests ohne Hook) geht das Paket per
  `PdfService.extractPages` als PDF-Datei raus. Ergebnis nach Seite
  sortiert, fehlgeschlagene Pakete wiederholbar, Import als Karten mit
  `priorityIntroduction`. Der Nachbereiten-Import (`ReviewScreen`,
  `_importQuestions`) nutzt denselben Dienst für PDFs; nur Nicht-PDFs laufen
  noch über den Text-Import. Die KI erfindet dort nichts.
- KI-Einträge laufen vor der Prüfung durch `QuestionParsing.canonicalize`:
  Typ tolerant (camelCase, Leerzeichen, deutsch, Abkürzungen; fehlend →
  aus der Struktur abgeleitet), Optionen als Texte mit Lösung als
  Buchstabe/Index/Text, `correct` statt `isCorrect`, Paare als left/right
  oder Objekt, Lücken als Text. Vorher fiel jede Abweichung still auf
  „flashcard“ zurück – daher kamen beim Import fast nur offene Karten an.
- Übungs-PDFs werden gespeichert (`MaterialFileStore`), auch im
  Nachbereiten; ältere lassen sich über „Original-PDF hinzufügen“ nachreichen.
- „Frage erstellen“: `questionCount` 0 = KI entscheidet (bis
  `AiService.maxAutoPageQuestions`). Bilder lassen sich überall wieder
  entfernen (`copyWithImage(clearImage: true)`, beim Lernen über
  `onImageEdited(null)` → `CardReviewMixin.saveEditedImage`).
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
sauber, 713 Tests grün (auch mit `TZ=Europe/Berlin`), `flutter build web`
erfolgreich.

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
14. „Frage erstellen“: Typ je Stufe oder „KI entscheidet“, 1–5 Fragen auf
    einmal, Bereich auf der Seite markieren, „Interaktiv“ wählbar.

Dritte Runde (gründliche Code-Analyse, siehe `CODE_ANALYSE.md`):
15. Zuordnen-Blocker (doppelte Ziele) und ~50 weitere Befunde behoben –
    u.a. Lückentext-KI-Prüfung, verlorene Updates/Zombie-Karten,
    Kalendertage/Zeitumstellung, Sync-Download-Schutz, Export mit
    Zusammenfassungen und Lernstand-Wahl, Doppelspeichern, Daily-Quiz-
    Wiederholungsrunde (Fehler zählen einmal pro Tag).
16. Bildfragen „Bild beschriften“/„Bild markieren“ (aus der Vorgänger-App)
    und Bild-Editor (abdecken, beschriften, Stellen/Bereich setzen) in
    „Frage erstellen“, Kartenliste und beim Lernen.
17. Sync-Lücken: geänderte Einstellungen (API-Key, Modelle, PDF-Speicher)
    lösen den Auto-Sync aus; Einstellungsfelder folgen einem Download (vorher
    konnte ein leeres Feld den geholten Key überschreiben); Lerntage,
    Probeklausuren, Chats, Ampel-Trend, Daily-Stand und Vorlieben reisen mit.
    Nach der Anmeldung Cloud-Stand anbieten, „Passwort vergessen“, Editor für
    alle Fragetypen und Suche in der Kartenliste, PdfJs für die Web-Version.
18. Bild beschriften v2: austauschbare Stellen (Gruppen), Eintippen mit
    Tippfehler-Toleranz + KI-Nachprüfung, Bild-Editor mit Verschieben/
    Skalieren/Schriftgröße, KI deckt Original-Beschriftungen selbst ab
    (bearbeitbar) und liest Positionen an einem Koordinatenraster ab.
19. „Fragen aus PDF importieren“ (jede Seite, jede/inhaltliche Fragen,
    fehlende Lösungen ergänzen), Anzahl „KI“ bei „Frage erstellen“, Bilder
    aus Fragen entfernen.
20. Import 1:1: Seiten als Bild an die KI, Aufgabenform bleibt (auch
    interaktiv und Bildfragen), Abbildungen als Ausschnitt; tolerantes
    Einlesen der KI-Antworten (Ursache für „nur Freitext“); Übungs-PDFs
    ansehbar; Nachbereiten-Import nutzt den seitenweisen Import.
21. Lernhilfen: Karten kennen ihre Quellseite (`sourceMaterialId`/
    `sourcePage`, sonst `SourceLocator`: Konzept-Link oder Textabgleich über
    `extractPageTexts`, im Speicher gecacht), „Im Skript“ öffnet sie
    (`openMaterialAt` in `material_opener.dart`, lädt bei Bedarf aus dem
    Cloud-Speicher), „Kurze Lerneinheit“ (`miniLesson`, per
    `FlashcardRepository.updateStudyAids` am gespeicherten Stand), Sokrates-
    Dialog bei oft falschen Karten und im Fehlertagebuch.
22. Drei Farb-Skins ("Ruhig", "Klar", "Lebendig") unter Einstellungen →
    Erscheinungsbild, "Klar" als neuer Standard, jederzeit ohne Neustart
    umschaltbar. Bewusst nur Farben (Nutzer-Entscheidung) – Layout, Formen
    und Typografie bleiben in allen drei Skins identisch. Jeder Skin ist ein
    eigenes, vollständiges `AppColors`-Set für Hell/Dunkel
    (`AppColors.of(AppThemeSkin, Brightness)`), `AppTheme.forSkin(...)` baut
    das passende `ThemeData`; `main.dart` liest den gewählten Skin reaktiv aus
    `SettingsRepository` (kein Neustart nötig). `AppSettings.themeSkin`
    (Standard `'klar'`) reist über Konto-Sync/Sync-Code mit, ein leerer/
    fehlender Cloud-Wert überschreibt nie die lokale Wahl. Grundlage waren
    drei Hell/Dunkel-Mockup-Paare (Design-Richtungen A/B/C), aus denen der
    Nutzer B ("Klar") als Vorlage bestätigt hat.
23. Hell/Dunkel-Vorgabe unabhängig von der Systemeinstellung: drei Optionen
    (System/Hell/Dunkel) unter Einstellungen → Erscheinungsbild.
    `AppSettings.themeModePreference` (Standard `'system'`) wird über
    `AppThemeModePreference.themeMode` (`lib/theme/app_theme.dart`) auf
    `MaterialApp.themeMode` gemappt, reaktiv aus `SettingsRepository` gelesen
    wie der Farb-Skin, reist ebenso über Sync/Sync-Code mit.
24. "Im Skript" beim Lernen jetzt schon VOR dem Antworten sichtbar (neuer
    `SourceLinkButton`, `lib/ui/study/study_aids.dart`), nicht mehr erst nach
    dem Beantworten/Umdrehen – zusätzlich auch in der Durchsicht nach einer
    Probeklausur. Weiterhin ausgenommen: die laufende Probeklausur selbst
    (`examMode`). `PdfQuestionImportScreen` meldet zusätzlich sichtbar, wenn
    das hochgeladene Arbeitsblatt selbst nicht gespeichert werden konnte
    (statt die Karten stillschweigend ohne funktionierende Quellseite zu
    importieren).
25. Import-Fragetyp-Fallback nicht mehr stumm: `QuestionParsing.
    normalizeGeneratedFlashcard` markiert einen Eintrag, dessen erklärter Typ
    (single_choice/free_text/html/…) unvollständig war und deshalb auf
    `flashcard` zurückgestuft wurde (`typeDowngraded`/`requestedType`).
    `PdfQuestionImportScreen` und `ReviewScreen` zeigen das in der Vorschau
    als Warnhinweis und fragen vor dem Speichern, wie damit verfahren werden
    soll (trotzdem speichern oder weglassen) – vorher landeten solche Karten
    ohne jeden Hinweis als einfache Karteikarte in der App. Die Import-
    Prompts (`ai_service.dart`) wurden zusätzlich verschärft: die KI soll vor
    der Typwahl selbst prüfen, ob sie ihn wirklich vollständig ausfüllen
    kann, statt einen Typ zu behaupten, den sie nur halb befüllt.
26. Gewichtung von Karten und Fächern (`Flashcard.weight`, `Module.weight`,
    Standard 1,0; Karten aus Übungsblättern 1,5): höher gewichtet = kürzere
    Abstände (FSRS-Intervall ÷ Gewicht), beim Fach zusätzlich mehr neue
    Karten pro Tag. Einstellbar im Fach-Formular („Gewichtung“) und je Karte
    in der Kartenliste (Knopf „Gewichtung“, Statuszeile zeigt „1,5×
    gewichtet“). Export/Import und „Lernstand zurücksetzen“ behalten die
    Gewichte; CSV-Import legt 1,0 an.
27. Stufen-Fix (Nutzer-Befund: „alle erstellten Fragen werden abgefragt“):
    getrennte Karten desselben Konzepts liefen bisher unabhängig. Jetzt
    Leicht → Mittel → Schwer je Gruppe (5.6b), Fehler-Leiter mit zwei
    KI-Hilfestellungen und Rückfall (5.6), Nachbereiten liefert Stufe/Gruppe
    gleich mit, KI-Knopf ordnet Altbestand ein. Dazu: Ampel-Balken je Fach
    auf der Startseite (`MasteryBar`, wie im Design-Entwurf), sichtbarer
    „Auswählen“-Modus in der Kartenliste mit Sammel-Bearbeiten (Gewichtung,
    Stufe, zusammenfassen/einzeln, Einheit, Lernstand zurücksetzen, Löschen).
28. Fragetyp Tabelle (`QuestionType.table`, `Flashcard.tableRows` =
    Zeilen aus `QuestionTableCell {text, given}`; gespeichert als
    `{'t': …, 'fill': true}`, `QuestionTableCell.parse` liest auch
    `{"answer": …}` und `"[[Lösung]]"`). Prüfung `AnswerChecker.tableHits`/
    `tableResult` (lokal + KI über `checkFillBlankAnswers` für abgelehnte
    Zellen); alle richtig = richtig, ≥ `tablePartialShare` (0,8) = richtig
    mit `Grade.hard`, sonst falsch; Probeklausur: nur komplett richtig.
    Stufe schwer. Editor in `card_edit_screen.dart` (Schloss je Zelle),
    Anzeige in Listen über `TablePreview`. Klasse heißt bewusst nicht
    `TableCell` (Kollision mit Flutters Widget).
29. Ordner in der Kartenliste (Nutzer: „weiß die KI, was zusammengehört?
    Das soll sichtbar sein“): zusammengehörige Fragen als zugeklappter
    Ordner mit Name, schwerster Frage und Stufenstand, aufgeklappt nach
    Leicht/Mittel/Schwer; KI-Sortierung über das ganze Fach mit
    portionsübergreifenden Ordnernamen und strengerer Regel (5.6b).
30. Audit (September 2026), behoben: Tippfehler-Toleranz
    (`AnswerChecker._isTypo`) nie bei abweichenden Ziffern oder reiner
    Vorsilbe (homogen/inhomogen), Dezimalpunkt = -komma; Rückfall-Karten
    (`ReviewOutcome.reopened`) kommen sofort in die laufende Runde (Daily:
    Wiederholungsrunde, Üben: als Nächstes); wiederhergestellte
    Wiederholungsrunde ohne inzwischen gesperrte Karten; „Als richtig
    werten“ auch bei Tabellen; `copyWithContent` verwirft `aiHints`, wenn
    Frage/Lösung sich ändern; KI-Hilfen bekommen `Flashcard.promptText`
    (Optionen bzw. Tabelle mit „___“); Probeklausur je ausdrücklichem Ordner
    nur die schwerste Stufe (`StageGate.hardestPerFolder`, Konzept-Ordner
    vollständig); „In Ordner legen“ in einen Konzept-Ordner gibt ihm einen
    eigenen Gruppenwert (keine Konzept-ID als Name), Import übersetzt eine
    als Gruppe gespeicherte Konzept-ID; Ordnername-Dialog besitzt seinen
    Controller selbst; CSV-Ampel mit Stufen; Startseite lädt die Ampel nur
    sichtbar neu; KI-Sortierung schickt höchstens 200 bekannte Ordnernamen.
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
