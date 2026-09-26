# Lernen

Eine schlanke Klausur-Lern-App für Windows, iPad (iOS) und Android – der
Nachfolger von [Quiz-app](https://github.com/nphjfvp/quiz-app), diesmal mit
engerem Fokus statt Feature-Fülle.

## Was die App macht

- **Modul-Verwaltung** – Fächer-Ordner mit Klausurdatum, in denen Folien und
  Übungsaufgaben gesammelt werden.
- **Vorbereiten-Modus, zwei Varianten** – Vorlesungsfolien als PDF, Word oder
  PowerPoint hochladen, dann Wahl zwischen: **Kurz** (die KI erstellt eine
  strukturierte Zusammenfassung mit hervorgehobenen Kernkonzepten,
  Zusammenfassungen lassen sich danach jederzeit bearbeiten oder löschen)
  oder **Ausführlich** (die KI liest ALLE hochgeladenen Folien, markiert die
  relevantesten Stellen wie bei der Folien-Markierung, siehe unten, UND
  beantwortet direkt gestellte Rückfragen dazu, live gestützt auf genau
  diesen Foliensatz – jede gestellte Frage wird beim Abschließen automatisch
  als Merkpunkt an die gewählte Einheit angehängt, siehe
  `lib/ui/prepare/prepare_screen.dart`).
- **Nachbereiten-Modus, drei Wege zu Karteikarten** – **KI erstellt**: Folien
  hochladen (Übungsaufgaben optional, verbessern aber die generierten
  Konzepte) → die KI erstellt Lernkonzepte und Karteikarten mit Fokus auf
  tiefem Verständnis der Übungen, sofern vorhanden (nicht nur Theorie-
  Wiedergabe). **Fragen importieren**: statt neuer Fragen werden die in
  einem hochgeladenen Übungsdokument (z.B. einer alten Klausur) bereits
  VORHANDENEN Fragen samt Musterlösung möglichst originalgetreu als
  Karteikarten übernommen – Pendant zum Import-Feature der Vorgänger-App
  (`AiService.importQuestionsFromExercises`). Der Typ wird dabei
  AUSSCHLIESSLICH aus der tatsächlichen Original-Struktur bestimmt (Prompt
  gibt eine feste Prüfreihenfolge vor) statt "free_text" als bequemen
  Auffangtyp für alles zu nutzen, das nicht auf Anhieb offensichtlich passt –
  eine Zuordnungs-/Matrixstruktur oder eine Frage mit mehreren erwarteten
  Kernpunkten wird zu "html" (siehe Fragetyp "Interaktiv" unten), nicht zu
  einer vereinfachten Freitextfrage. **JSON einfügen**: kein
  API-Call dieser App – ein extern (z.B. ChatGPT/Gemini/Claude.ai) bereits
  fertig generiertes JSON wird direkt eingefügt (siehe Fragetyp "Interaktiv"
  weiter unten für den genauen Anwendungsfall). Einzelne Konzepte und
  Karteikarten lassen sich im Modul-Detail bzw. in der Karteikarten-
  Übersicht jederzeit bearbeiten oder löschen. Zusätzlich: **Speedrun** –
  schneller Selbsteinschätzungs-Durchlauf durch alle Konzepte eines Fachs
  (Titel zeigen, selbst einschätzen, Erklärung aufdecken); was man nicht
  wusste, landet in einer wiederholbaren Vertiefen-Runde
  (`lib/ui/speedrun/speedrun_screen.dart`, bewusst ohne FSRS-Effekt – ein
  Verständnis-Check, keine spaced-repetition-wirksame Wiederholung).
- **Übungsklausur als Stil-Referenz** – optional lässt sich pro Fach eine
  alte Klausur hochladen (`MaterialKind.practiceExam`, ModuleDetailScreen →
  "Material hochladen" → "Übungsklausur"). Die KI berücksichtigt sie dann bei
  der Karteikarten-Generierung (Nachbereiten) und beim Lernmodus-Zwischen-
  Check (siehe unten) als Stil-Referenz für Frageart/-schwierigkeit – ohne
  selbst Teil des normalen Frage-Chat-Materials zu werden.
- **Einheiten** – Materialien/Konzepte/Karteikarten eines Fachs lassen sich
  zu Vorlesungseinheiten gruppieren (z.B. "Einheit 3"); man kann ruhig den
  ganzen Semesterstoff im Voraus hochladen, das Daily Quiz fragt aber nur
  Karten aus Einheiten ab, die explizit als "behandelt" markiert wurden
  (`lib/models/lecture_unit.dart`, echtes Zugriffs-Gate im Scheduler, anders
  als die rein informative Behandelt-Markierung einzelner Materialien).
  Jede Einheit trägt zusätzlich frei erweiterbare Textfelder (eigene
  Zusammenfassung, Merksätze, offene Fragen) – direkt im Modul-Detail
  anlegbar/editierbar. Damit man das Abhaken nicht vergisst, kann jede
  Einheit einen **Termin** bekommen (`LectureUnit.scheduledDate`): ab diesem
  Tag gilt sie automatisch als behandelt (`LectureUnit.isCoveredOn`), ohne
  dass jemand etwas anklicken muss. "Termine aus Stundenplan" verteilt die
  nächsten Vorlesungstermine des Fachs (`Module.lectureSlots`) der Reihe nach
  auf alle noch offenen Einheiten (`UnitScheduleService`), einzelne Termine
  lassen sich per Tipp ändern; ein manuelles "nicht behandelt" löscht den
  Termin wieder. "Einheiten vorschlagen" (mit API-Key) lässt die KI die noch
  keiner Einheit zugeordneten Materialien zu sinnvollen Einheiten gruppieren
  (`AiService.suggestLectureUnits`) – als Vorschlag zum Abhaken, nichts wird
  ungefragt angelegt.
- **Daily Quiz (Exam-Scheduler) + freier Lernmodus** – tägliche Lernsession
  über alle Fächer hinweg. FSRS-Spaced-Repetition für fällige
  Wiederholungen; die Menge neuer Karten wird pro Fach dynamisch an
  Wissensstand und Klausurnähe angepasst, mit einem Mindestbudget-Boden
  (`DailySchedulerService.minDailyNewCardsPerModule`, Standard 10): bei
  fernem Klausurdatum (z.B. zu Semesterbeginn ein ganzes Semester Stoff
  hochgeladen) würde die reine Pacing-Formel sonst auf 1-2 Karten/Tag
  einfrieren – der Boden garantiert eine sinnvolle Lernmenge, solange
  Rückstand vorhanden ist (siehe `lib/services/daily_scheduler_service.dart`).
  Falsch beantwortete Karten der Hauptrunde werden am Ende derselben Session
  automatisch nochmal abgefragt (max. 3 Versuche je Karte), statt erst am
  nächsten natürlichen FSRS-Fälligkeitsdatum wiederzukommen. Ist die Session
  (inkl. Wiederholungsrunde) fertig, lässt sich per Button "Freiwillig
  weiterlernen" trotzdem freiwillig weitermachen: `DailySchedulerService.
  buildExtraBatch` ignoriert dafür bewusst das Klausur-Pacing-Budget und holt
  bis zu 10 weitere neue bzw. (falls keine mehr da sind) noch nicht fällige
  Karten nach – als eigene Warteschlange statt den laufenden Tagesplan zu
  vergrößern, um das positionsbasierte Session-Tracking nicht durcheinander
  zu bringen. Der Tagesfortschritt (erledigte Karten, Wiederholungsrunde,
  heute eingeführte neue Karten) wird gespeichert (`DailySessionState`/
  `DailySessionRepository`): ein App-Neustart setzt dort fort, und
  "Aktualisieren" vergibt kein zweites volles Neu-Karten-Budget – heute schon
  eingeführte Karten werden abgezogen (gezielt selbst erstellte Fragen kommen
  trotzdem noch heute dran). Ergänzend dazu pro Fach ein freier **Üben-Modus** (`lib/ui/practice/practice_screen.dart`):
  übt das gesamte Kartenset unabhängig von Fälligkeit/Klausur-Pacing/
  Einheiten-Status, optional gefiltert nach Ampel-Stufe (siehe unten) – jede
  Antwort aktualisiert trotzdem den echten FSRS-Zustand.
- **KI-Hilfe beim Lernen** (`QuestionAnswerView`, `AiService.generateHint`/
  `explainAnswer`, nur mit API-Key): vor dem Antworten ein **Tipp** (Denkanstoß
  ohne Lösung – eine danach richtige Antwort zählt nur als "Schwer", die
  Ampel steigt dadurch nicht und die Stufe bleibt), nach dem Antworten
  **"Erklär mir das"** (warum die Lösung stimmt, wo der Denkfehler lag, mit
  Merkhilfe) und bei Bedarf **"Einfacher erklären"**. Gilt in Daily Quiz,
  Üben, Sprint und Zwischen-Check.
- **Karteikarten-Liste: Mehrfachauswahl + Löschen** (`lib/ui/flashcards/
  flashcard_list_screen.dart`) – lang auf eine Karte drücken startet den
  Auswahlmodus (Checkbox pro Karte, "Alle auswählen", gemeinsames Löschen in
  einer Transaktion über `FlashcardRepository.deleteMany`), zum Aufräumen
  nach einer größeren Generierung ohne jede Karte einzeln aufklappen zu
  müssen. Einzelne Karten lassen sich weiterhin wie bisher aufklappen und
  per Button bearbeiten/löschen. Über das Menü oben rechts: **"Als CSV
  exportieren"** (Vorderseite, Rückseite, Typ, Ampel, Fällig, Wiederholungen;
  Semikolon + BOM, öffnet sich direkt richtig in Excel/LibreOffice, Anki
  liest es ebenfalls) und **"CSV importieren"** – z.B. ein Anki-Export
  ("Notizen als Text") oder eine eigene Tabelle mit Vorder-/Rückseite.
  Trennzeichen (Tab, Semikolon, Komma), Anki-Kopfzeilen und einfaches HTML
  werden erkannt, vor dem Import zeigt eine Vorschau die Anzahl
  (`lib/services/card_csv_service.dart`). Importierte Karten starten als
  neue Karteikarten.
- **Wissensstand-Ampel** – jede Karte bekommt eine Rot/Gelb/Grün-Einstufung
  (siehe `lib/services/mastery_service.dart`), sichtbar in der
  Karteikarten-Liste, im Modul-Detail (Aufschlüsselung) und in der
  Fortschritts-Übersicht. Primäre Grundlage ist ein eigenständiger
  Mastery-Box-Zähler (`Flashcard.masteryBox`, separat von der Typ-
  Eskalationskette unten): `masteryBox <= 0` (kein einziger bestätigter
  Kenntnisstand, z.B. direkt nach einer komplett falsch beantworteten Karte)
  ist immer sofort "Rot" – bewusst NICHT primär die momentane FSRS-
  Behaltensrate, die direkt nach JEDER Wiederholung (egal ob richtig oder
  falsch) ohnehin nahe 100% liegt (die Vergessenskurve bei Elapsed-Zeit 0 ist
  per Definition ~1) und eine frisch falsch beantwortete Karte sonst
  fälschlich nicht als "Rot" zeigen würde. "Grün" braucht zusätzlich
  `masteryBox >= Flashcard.masteryBoxCap` (4 erfolgreiche Wiederholungen an
  verschiedenen Tagen – mehrfach am selben Tag richtig, z.B. im Üben-Modus,
  zählt nur einmal; eine Selbstbewertung "Schwer" lässt den Zähler stehen,
  nur "Nochmal" bzw. eine falsche Antwort senkt ihn)
  UND eine weiterhin ausreichende Behaltensrate – die Retrievability dient
  hier nur noch als Verfalls-Signal, das eine lange nicht wiederholte,
  eigentlich gemeisterte Karte wieder zurückstuft.
- **Fragetypen & adaptive Schwierigkeit** – die KI erzeugt beim Nachbereiten
  neben klassischen Karteikarten auch Single-Choice, Multiple-Choice,
  Freitext, Lückentext sowie Drag&Drop-Zuordnung/-Kategorisierung (Auswahl je
  nach Inhalt, `lib/models/flashcard.dart` `QuestionType`,
  `lib/services/answer_checker.dart` prüft automatisch inkl. toleranter
  Tippfehler-Erkennung bei Freitext/Lückentext). Freitext-Antworten laufen
  zweistufig: zuerst der schnelle lokale Fuzzy-Vergleich (kein API-Call);
  lehnt der die Antwort ab, holt `AiService.checkFreeTextAnswer` eine
  KI-Zweitmeinung ein, die inhaltlich andere Formulierungen als richtig
  erkennt (ein reiner 1:1-Textvergleich wäre für frei formulierte Antworten
  fast unmöglich zu erfüllen) – ohne API-Key oder bei einem Fehler bleibt es
  beim strengeren lokalen Ergebnis. Ausgewählte Single-Choice-
  Fragen tragen zusätzlich eine Eskalationskette (Single-Choice → Lückentext
  → Freitext): steht die aktuelle Stufe in der Ampel auf Grün (richtig an 4
  verschiedenen Tagen), wird die Frage befördert – liegt der Inhalt der
  nächsten Stufe nicht schon vor, erzeugt die KI ihn im Hintergrund lazy,
  ohne alle Stufen vorab zu generieren. Die neue Stufe startet neu (morgen
  fällig, Ampel gelb, `FsrsService.restartForNewStage`); leichte und
  mittlere Stufen kommen höchstens alle 7 Tage dran
  (`FsrsService.transitStageMaxIntervalDays`), erst die schwerste Stufe
  bekommt die vollen Spaced-Repetition-Abstände. Adaptiv in BEIDE Richtungen: zwei Fehlversuche IN FOLGE auf
  einer beförderten Stufe stufen automatisch zur vorherigen (leichteren)
  Stufe zurück – ohne erneuten KI-Aufruf, der alte Wortlaut liegt bereits in
  `Flashcard.variantHistory` (siehe `Flashcard.copyWithBoxUpdate`). Auf der
  SCHWERSTEN Stufe der Kette gilt eine höhere Rückstufungs-Schwelle
  (`Flashcard.demotionMissStreakThresholdOnLastStage`, 5 statt 2
  Fehlversuche in Folge): diese Stufe wurde bereits als sicher gelernt
  nachgewiesen (Ampel stand grün) und wird ohnehin durch normale Spaced-
  Repetition nur noch selten wiederholt, ein einzelner Ausrutscher soll sie
  nicht sofort zurückwerfen. Die Rückstufung startet die Ampel danach
  bewusst bei Gelb statt Rot (`masteryBox = masteryBoxCap - 1`) – ein
  Vertrauensvorschuss für den bereits nachgewiesenen Kenntnisstand. Über die
  Seiten-Frage-Funktion (siehe unten) erzeugte Mehrfach-Schwierigkeitsgrade
  landen dabei NICHT als unabhängige Karten im selben Lern-Pool, sondern
  werden zu genau einer solchen Kette zusammengeführt: nur die leichteste
  gewählte Stufe ist sofort aktiv, die übrigen liegen als
  `Flashcard.pendingVariants` bereits fertig ausformuliert bereit (derselbe
  Screenshot als Grundlage aller Stufen) und werden bei Beförderung ohne
  weiteren KI-Aufruf sichtbar – genau das war vorher der gemeldete Bug
  ("leicht/mittel/schwer landen gemischt im selben Pool statt nacheinander").
  Auf-/Abstufung wird per SnackBar direkt sichtbar gemacht (Daily Quiz +
  Üben-Modus), lief vorher komplett unsichtbar im Hintergrund; der
  Generierungs-Prompt verlangt außerdem pro erkanntem Konzept nach
  Möglichkeit mindestens eine Frage mit voller Eskalationskette, damit das
  Feature spürbar öfter zum Einsatz kommt statt nur bei zufällig passenden
  Einzelfragen. Einen eigenen Mathe-Formel-Fragetyp mit Formel-Editor wie in
  der Vorgänger-App gibt es nicht – Formeln werden aber in allen Fragetypen
  als LaTeX dargestellt (siehe "Mathe/Formeln").
- **Fragetyp "Interaktiv" (html) + externer KI-Prompt** – für Vorlagen, die in
  keinen der obigen Typen passen (z.B. eine Zuordnungs-Matrix/Tabelle mit
  mehreren Kriterien-Zeilen, oder eine offene Diskussionsfrage, bei der ein
  Text-Exakt-Vergleich zu streng wäre): die KI baut dafür selbst eine
  eigenständige, interaktive HTML/CSS/JS-Seite inkl. eigener Prüf-Logik
  (`Flashcard.htmlContent`, gerendert über `webview_flutter` in einer per
  Content-Security-Policy abgeriegelten Sandbox ohne jeden Netzwerkzugriff,
  siehe `lib/services/html_question_contract.dart`). Die Seite meldet ihr
  Ergebnis rein lokal über einen JavaScript-Kanal zurück – keine erneute
  API-Anfrage beim Beantworten. Nur auf Android/iOS tatsächlich interaktiv;
  auf Plattformen ohne WebView-Unterstützung (z.B. Windows-Desktop) oder bei
  einem Ladefehler fällt die Karte automatisch auf eine einfache
  Frage/Antwort-Ansicht mit manueller Selbstbewertung zurück (wie beim
  einfachen `flashcard`-Typ). Reicht das hier per BYOK hinterlegte Modell für
  eine besonders ungewöhnliche Vorlage nicht aus, bietet der
  Nachbereiten-Modus einen dritten Weg **"JSON einfügen"**: ein Button kopiert
  einen eigenständigen Prompt (`AiService.externalJsonPromptTemplate`) in die
  Zwischenablage, der sich in ein beliebiges externes KI-Modell (ChatGPT,
  Gemini, Claude.ai, ...) einfügen lässt – die dortige JSON-Antwort wird ohne
  weiteren API-Call dieser App direkt eingelesen und übernimmt exakt denselben
  Validierungs-/Rettungspfad wie die beiden anderen Erzeugungswege
  (`QuestionParsing.normalizeGeneratedFlashcard`).
- **Interleaving statt Blockübung** – die Session-Reihenfolge des Daily
  Quiz mischt Karten aus verschiedenen Fächern per Round-Robin durch
  (`DailySchedulerService.interleaveByModule`), statt erst alle fälligen/
  neuen Karten eines Fachs zu zeigen und dann die des nächsten. Nachgewiesen
  wirksamer als Blockübung (Interleaving-Effekt), ohne dass sich an
  Fälligkeit oder Neu-Karten-Budget etwas ändert – nur die Reihenfolge
  innerhalb der Session.
- **Ampel-Trend** – im Fortschritts-Tab ein täglicher Schnappschuss der
  Ampel-Aufschlüsselung + Behaltensrate (`lib/models/mastery_snapshot.dart`,
  ein Eintrag pro Kalendertag, kein volles Review-Log), verglichen mit dem
  Stand von vor ~7 Tagen (`lib/services/mastery_trend_service.dart`, reine
  Logik). Bewusst ein Vergleich mit dem EIGENEN früheren Stand statt mit
  anderen Nutzern – Kompetenz-Feedback motiviert nachhaltiger als sozialer
  Vergleich/Leaderboards (Selbstbestimmungstheorie, Deci & Ryan).
- **Mathe/Formeln (LaTeX)** (`lib/ui/widgets/math_text.dart`,
  `lib/services/math_markup.dart`, Paket `flutter_math_fork`): Formeln in
  `$…$`/`\(…\)` (im Satz) bzw. `$$…$$`/`\[…\]` (abgesetzt) werden in Fragen,
  Antwortoptionen, Rückseiten, Lösungen, KI-Erklärungen, Chat, Karteikarten-
  Liste, Probeklausur-Durchsicht und Schwachstellen sauber gesetzt; eine
  fehlerhafte Formel erscheint als Rohtext statt abzustürzen, Geldbeträge wie
  "5 $" bleiben Text. Alle Erzeugungs-Prompts verlangen Formeln in LaTeX.
  Da Modelle in JSON gern einfache Backslashes schreiben (`\frac` wäre in JSON
  ein Seitenvorschub + "rac", `\theta` ein Tab …), repariert
  `MathMarkup.escapeLatexInJson` solche Formeln vor dem Dekodieren (KI-Antworten
  und "JSON einfügen").
- **Probeklausur mit Note** (`lib/ui/exam/mock_exam_screen.dart`, im
  Fach unter "Probeklausur"): 10/20/30 zufällige Fragen aus dem bereits
  behandelten Stoff, optional mit Zeitlimit (15/30/60 min), OHNE Feedback,
  Tipps oder Erklärungen während der Bearbeitung (`QuestionAnswerView.examMode`),
  Überspringen/vorzeitiges Abgeben möglich. Danach: Note nach der üblichen
  Hochschulskala (`MockExamService.germanGrade`: ab 50 % 4,0, ab 95 % 1,0),
  Trefferquote je Einheit (schwächste zuerst), Durchsicht aller Fragen mit
  Lösung und KI-Erklärung, "falsche üben" und ein lokaler Verlauf der
  bisherigen Noten. Beantwortete Fragen zählen normal für FSRS/Ampel.
- **Schwachstellen (Fehlertagebuch)** (`lib/ui/stats/weakness_screen.dart`,
  Einstieg im Fortschritt-Tab): sammelt die Karten, mit denen man sich
  schwertut, direkt aus dem Lernzustand (`WeaknessService`: wie oft eine
  gelernte Karte vergessen wurde, zuletzt falsch, Fehlerserie auf der
  aktuellen Stufe, Ampel rot) – sortiert nach Dringlichkeit, filterbar nach
  Fach, Lösung aufklappbar. "Die 20 schwächsten üben" startet eine
  Übungsrunde genau damit (`PracticeScreen.cards`, zählt normal für
  FSRS/Ampel); "KI: Muster erkennen" (mit API-Key) fasst zusammen, welche
  Themen/Denkfehler dahinterstecken und was gezielt zu wiederholen ist.
- **Sprint (Pausenmodus)** – ein optionales, klar vom Kernlernkreislauf
  abgegrenztes Mini-Spiel im Fortschritts-Tab: 60 Sekunden Zeitdruck gegen
  die fachübergreifend schwächsten (Ampel-rot, notfalls +gelb) Karten,
  wiederverwendet dieselben Fragetypen/dieselbe Auswertung wie Daily Quiz.
  Jede Antwort zählt wie im Daily Quiz für FSRS, Ampel und Stufen (gemeinsamer
  `ReviewService`/`CardReviewMixin`), aber OHNE Münzen/Shop/Fremdvergleich – nur eine geräte-lokale persönliche
  Bestleistung (`AppSettings.bestSprintScore`). Gamification erhöht
  nachweislich Engagement/Wiederkehrrate, aber nicht zuverlässig den
  Lerngewinn pro Sitzung – deshalb bewusst als Auflockerung positioniert,
  nicht als Ersatz für Daily Quiz/Üben/Nachbereiten.
- **Materialien & Vorarbeiten** – im Modul-Detail lässt sich beliebig viel
  Material (z.B. der komplette Semesterinhalt, als PDF/Word/PowerPoint)
  direkt hochladen, ohne dass dafür eine KI-Anfrage anfällt – reine
  Textextraktion (`lib/services/material_text_extractor.dart`) + Ablage,
  auch wieder löschbar. Jedes Material hat eine manuelle
  "Behandelt"-Markierung, die der Nutzer setzt, sobald das Thema in der
  Vorlesung dran war; sie blockiert nichts (man kann jederzeit weiter
  vorarbeiten), dient aber als zusätzlicher Kontext für den Frage-Chat.
  Einmal hochgeladenes Material lässt sich in Vorbereiten UND Nachbereiten
  über "Vorhandenes Material verwenden" direkt wiederverwenden (siehe
  `lib/ui/widgets/existing_material_picker.dart`) – kein erneutes Hochladen
  derselben Datei nötig, kein erneuter Extraktions-Aufwand; für diese Dateien
  wird beim Speichern kein doppeltes MaterialItem angelegt.
- **Texterkennung für gescannte PDFs** (`lib/services/pdf_ocr_service.dart`,
  nur mit API-Key): enthält beim Hochladen mindestens die Hälfte der Seiten
  keinen Text (Scan, abfotografiertes Skript), schickt die App genau diese
  Seiten – in Blöcken von höchstens 8 – als PDF an das eingestellte
  **Vision-Modell** (`AiService.transcribePdfPages`) und übernimmt die
  Abschrift seitengenau in den extrahierten Text (Formeln als LaTeX). Seiten
  mit echtem Text werden nie verschickt. Einzelne leere Seiten in einem
  sonst normalen Foliensatz (Titelbild, Grafik) lösen das bewusst NICHT
  automatisch aus, um keine Kosten zu verursachen; dafür gibt es an jedem
  PDF in der Materialliste den Knopf "Texterkennung für gescannte Seiten". Ohne
  API-Key bleibt es bei der bisherigen Meldung.
- **Fortschritt** – eigener Tab mit Streak (aufeinanderfolgende Lerntage),
  Gesamtzahl Wiederholungen und geschätzter Behaltensrate (aus dem
  FSRS-Zustand der Karten), gesamt und pro Fach (siehe
  `lib/services/stats_service.dart`). Lerntage für den Streak werden
  zusätzlich geräte-lokal protokolliert (`StudyLogRepository`) –
  `Flashcard.lastReview` allein kennt nur die jeweils letzte Wiederholung
  je Karte, frühere Lerntage gingen sonst verloren.
- **Kalender** – eigener Tab mit Monatsansicht: zeigt wöchentlich
  wiederkehrende Vorlesungstermine (pro Fach im Bearbeiten-Formular als
  Wochentag + Uhrzeit hinterlegt, `Module.lectureSlots`) zusammen mit den
  Klausurterminen an, plus einen kleinen Countdown zur nächsten Klausur oben
  rechts. Die Termin-Logik selbst ist reine, getestete Logik
  (`lib/services/calendar_service.dart`), die UI navigiert nur Monate und
  zeigt die Tagesagenda für den gewählten Tag.
- **Lernerinnerung** – tägliche Push-Benachrichtigung zu einer selbst
  gewählten Uhrzeit (Einstellungen → Lernerinnerung), lokal geplant über
  `flutter_local_notifications` (kein eigener Server, wiederholt sich nach
  dem ersten Planen selbst täglich). Auf Web ohne Wirkung, da das Paket dort
  nicht unterstützt wird – der Schalter bleibt sichtbar, tut aber nichts.
- **Startbildschirm-Widget (Android)** – zeigt die nächste Vorlesung, die
  Anzahl heute fälliger Karten und einen Klausur-Countdown direkt auf dem
  Android-Homescreen, ohne die App zu öffnen (`home_widget`-Package +
  natives `CalendarWidgetProvider.kt`). Die drei Textzeilen werden aus
  denselben Daten wie Kalender/Daily-Quiz berechnet
  (`lib/services/home_widget_service.dart`) und bei jeder Fach-Änderung
  sowie nach jeder Daily-Quiz-Wiederholung aktualisiert. Bewusst nur
  Android: ein iOS-Widget bräuchte zusätzlich eine native
  Swift/WidgetKit-Extension, die sich in dieser Umgebung ohnehin nicht in
  einem iOS-Simulator testen ließe.
- **Frage-Chat** – pro Modul durch die hochgeladenen Materialien gehen und
  Fragen dazu stellen/sich Dinge erklären lassen, ausschließlich auf
  explizite Nachfrage (nichts wird automatisch erklärt). Zweistufig statt
  "alles in den Kontext kippen": beim ersten Chat pro Material erstellt die
  KI einmalig einen kurzen Index-Eintrag (Thema + grobe Kurzfassung,
  `MaterialItem.topicIndex`) und speichert ihn dauerhaft. Bei jeder Frage
  sieht die KI zuerst nur diese kompakten Einträge aller Materialien
  (chronologisch, mit Behandelt-Status) und wählt aus, welche für GENAU
  diese Frage wirklich relevant sind; erst von denen wird der volle Text
  nachgeladen und in die eigentliche Antwort-Anfrage gegeben (siehe
  `lib/services/chat_context_builder.dart`, `AiService.summarizeForIndex` /
  `.selectRelevantMaterials`). Bezieht sich die Frage auf frühere oder noch
  nicht behandelte Folien, kann die Auswahl das entsprechend einbeziehen.
  Die Auswahl ist bewusst NICHT verpflichtend: findet sich zu einer Frage
  erkennbar KEIN Bezug zum Fach (reiner Small Talk), liefert sie eine leere
  Auswahl statt krampfhaft irgendetwas einzubeziehen – die Frage wird dann
  ganz normal ohne Materialbezug beantwortet. Der Auswahl-Prompt ist bewusst
  eher großzügig als streng formuliert: schon ein plausibler thematischer
  Bezug reicht, damit ein Material einbezogen wird, statt Material nur bei
  eindeutigem Volltreffer zu nutzen. Unter jeder Antwort zeigt der Chat
  zudem an, welche Materialien (falls welche) tatsächlich als Kontext
  herangezogen wurden (`ChatMessage.sourceFileNames`) – macht die
  Entscheidung nachvollziehbar statt einer stillen Blackbox. Über den "Mit
  Materialien"-Schalter im Chat kann der Nutzer den Materialbezug auch
  komplett abschalten, um bewusst allgemein zu fragen. Schlägt die
  Auswahl-Anfrage selbst fehl (Fehler statt Ergebnis), greift ein
  Sicherheitsnetz auf ein Zeichenbudget-basiertes Zusammenstellen aller
  Materialien zurück (Vorrang für behandelte).
- **BYOK** – die KI läuft über [OpenRouter](https://openrouter.ai) mit einem
  selbst mitgebrachten API-Key. Es gibt keinen App-eigenen Server; Anfragen
  gehen direkt vom Gerät an OpenRouter. Der Modell-Katalog wird live von
  OpenRouter abgerufen (Cache in der lokalen DB, wöchentlicher Refresh) statt
  fest in der App hinterlegt zu sein – neue Modelle stehen so automatisch
  zur Verfügung. Getrennte Modell-Einstellungen für drei Rollen:
  **Fragenerstellen**, **Vision** (bildfähige Modelle, z.B. für gescannte
  Foliensätze) und **Crosscheck** (bewusst ein zweites Modell, das die
  Ergebnisse des ersten gegenprüft). Große Foliensätze/Übungsaufgaben werden
  automatisch in mehrere Anfragen zerlegt ("Rolling-Context-Chunking" –
  jeder weitere Abschnitt bekommt die bereits erfassten Kernkonzepte als
  Kontext, um Wiederholungen zu vermeiden); Vorbereiten/Nachbereiten
  unterstützen dabei mehrere PDF-Uploads gleichzeitig und zeigen vorab eine
  kurze Analyse (Länge → empfohlene Chunk-Granularität).
- **Cloud-Sync (optional)** – zwei Wege, über ein eigenes Firebase-Projekt.
  **Mit Account** (empfohlen): läuft automatisch über das Firebase-Konto
  (`users/{uid}`, per Firestore-Regel exakt auf den eingeloggten Nutzer
  beschränkt) – kein Code zum Teilen/Abtippen, einfach auf jedem Gerät mit
  demselben Konto anmelden und synchronisieren. **Ohne Account**:
  Sync-Code-basiert wie beim Vorgänger (`sync_codes/{code}`, funktioniert
  wie ein Passwort) – bleibt als Fallback erhalten. Beide Wege übertragen
  Fächer, Einheiten, Materialien, Konzepte, Karteikarten und die Modellwahl. Der
  eigentliche API-Key wird bewusst NUR über den Konto-Weg übertragen (dort
  regel-geschützt auf den Besitzer) – ein frei getippter Sync-Code hat keine
  Mindestkomplexität/Ratenbegrenzung und darf kein potenziell
  kostenpflichtiges API-Zugangsmittel offenlegen können. Geräte-lokales wie
  die Lernerinnerungs-Uhrzeit bleibt bewusst lokal. Ohne Konfiguration läuft
  die App komplett offline. **Größenlimit gelöst** (`lib/services/sync_codec.dart`):
  Firestore erlaubt nur 1 MiB pro Dokument – der Datenbestand wird jetzt
  gzip-komprimiert (Text schrumpft auf ~10–25 %) und bei Bedarf auf mehrere
  Dokumente (`…/sync_parts/0..n`) verteilt; die PDF-Dateien selbst reisen
  nicht mit (lokal vorhandene bleiben beim Herunterladen erhalten, der
  extrahierte Text wird übertragen). Wer die Original-PDFs auch auf den
  anderen Geräten sehen will, trägt einen **eigenen PDF-Speicher** ein
  (S3-kompatibel oder WebDAV, siehe Setup 3b) – analog zum eigenen API-Key:
  ohne Eintrag bleibt nur der PDF-Sync aus. Jeder Upload trägt eine `pushId`, damit
  nie Teile zweier Uploads gemischt werden; alte Cloud-Stände (ein
  Klartext-Dokument) bleiben lesbar. **Auto-Sync** (Schalter in den
  Einstellungen, `lib/services/auto_sync_service.dart`): lädt Änderungen
  30 s nach der letzten Änderung hoch, beim Verlassen der App sofort, offline
  mit wachsenden Abständen erneut und beim Zurückkehren in die App sofort. Hat seit dem letzten
  Abgleich ein anderes Gerät hochgeladen, überschreibt der Auto-Sync das NICHT,
  sondern bittet erst um "Herunterladen".
- **Account (optional)** – E-Mail/Passwort oder Google-Anmeldung über
  Firebase Auth, aus den Einstellungen heraus. Nie erzwungen: die App bleibt
  auch ohne Account voll nutzbar. Der Hauptzweck ist der automatische
  Cloud-Sync oben (siehe dort) statt des manuellen Sync-Codes.

## Bewusst NICHT enthalten (verglichen mit der Vorgänger-App)

Der Vorgänger hatte 9 Fragetypen (inkl. Mathe-Formel-Fragen mit Formel-Editor
und Diagramm-Beschriftung/Bild-Markierung), 6 Mini-Games, eine
Coin-Economy/Shop, Mock-Klausuren, Formelsammlungen, Sokrates-Modus u.v.m.
Diese App übernimmt 6 der 9 Fragetypen inkl. der adaptiven
Schwierigkeits-Eskalation (siehe oben) sowie inzwischen Probeklausur,
Fehlertagebuch, KI-Tipp/-Erklärung und LaTeX-Darstellung, lässt aber bewusst
den Mathe-Formel-Fragetyp mit Formel-Editor sowie diagramm-/bildbasierte
Fragetypen (Diagramm beschriften, Bild markieren) weg und konzentriert sich ansonsten auf den
Kernkreislauf **Vorbereiten → Nachbereiten → Daily Quiz** ohne Mini-Games,
Economy o.ä. Die Vision-Modell-Rolle wird für die Seiten-Fragefunktion
(siehe 5b) und die Texterkennung gescannter PDFs genutzt.

Aus der Ideen-Liste (`DESIGN_IDEEN.md`) bewusst nicht übernommen: Vorlesen
(TTS), ein automatischer Wochenplan, eigene Markdown-Notizen neben den
Einheiten-Notizen sowie alles unter "Bewusst nicht" (Mini-Games, Coins,
Leaderboards, Social-Features, eigenes Backend).

## Architektur

```
lib/
  models/        Module, MaterialItem, Summary, Concept, Flashcard, AppSettings,
                 AiModelInfo, ChatMessage
  services/
    database_service.dart          Sembast (lokale, dateibasierte NoSQL-DB)
    pdf_service.dart                PDF-Textextraktion (syncfusion_flutter_pdf)
    office_text_extractor.dart      Word-/PowerPoint-Textextraktion (archive + xml,
                                     reines Dart – beide Formate sind ZIP+XML)
    material_text_extractor.dart    Wählt den Extraktor anhand der Dateiendung
    material_file_store.dart        Persistiert Original-PDF-Bytes (Datei/Base64,
                                     Conditional Import für Web)
    highlight_matcher.dart           Findet ein KI-Zitat in PDF-Textzeilen wieder
    highlight_context.dart          Baut den "besonders wichtig"-Kontextblock aus
                                     Markierungen + Notiz eines Materials
    ai_service.dart                 OpenRouter-Anbindung (BYOK), Chunking/Rolling
                                     Context, Crosscheck-Pass, Frage-Chat + JSON-Reparatur,
                                     Markier-Vorschläge (suggestHighlights)
    text_chunker.dart                Zerlegt lange Texte für ai_service.dart
    content_analyzer.dart            Kurzanalyse (Länge → Chunking-Empfehlung)
    chat_context_builder.dart        Baut den Material-Kontext für den Frage-Chat
    model_catalog_service.dart      Ruft OpenRouters Modell-Katalog live ab
    fsrs_service.dart               FSRS-4.5 Spaced-Repetition-Algorithmus
    daily_scheduler_service.dart    Exam-Scheduler (fällige + neue Karten)
    stats_service.dart              Streak/Wiederholungen/Behaltensrate aus
                                     vorhandenen Modul-/Karteikarten-Daten
    sync_service.dart               Firestore Push/Pull (optional)
    sync_codec.dart                 Komprimieren + Aufteilen für Firestore
    auto_sync_service.dart          Automatischer Upload + Konfliktschutz
    question_parsing.dart           Parst/validiert von der KI (oder extern) gelieferte
                                     Fragen-JSON-Objekte, rettet unvollständige Einträge
    html_question_contract.dart     CSP-Sandbox-Rahmen + JS-Rückkanal-Vertrag für den
                                     Fragetyp "Interaktiv" (siehe oben), reine Strings
    pdf_ocr_service.dart            Texterkennung leerer PDF-Seiten über das Vision-Modell
    pdf_cloud_store.dart            Eigener PDF-Speicher: S3 (SigV4) / WebDAV, reines HTTP
    pdf_cloud_sync_service.dart     PDFs hochladen/bei Bedarf herunterladen
    unit_schedule_service.dart      Einheiten-Termine aus dem Stundenplan
    card_csv_service.dart           CSV-Export/-Import von Karteikarten
  repositories/    ChangeNotifier-Wrapper um die DB, für Provider/Consumer
  theme/           Design-Tokens ("Ruhig & Fokussiert") + Light-/Dark-Theme
  ui/              home, modules, prepare, review, daily, stats, chat,
                   flashcards, settings
```

Lokale Persistenz läuft über [Sembast](https://pub.dev/packages/sembast)
(reines Dart, keine nativen Bindings nötig – funktioniert identisch auf
Windows/iOS/Android). State-Management ist bewusst einfach gehalten:
`ChangeNotifier`-Repositories + `provider`, keine zusätzliche Abstraktion.

### Design

Eigenständigeres Look-and-Feel statt Standard-Material: warmes Off-White/
Tinte im Hellmodus, sanftes Dunkelblau-Grau im Dunkelmodus, ein entsättigtes
Periwinkle als einziger Akzent, [Public Sans](https://fonts.google.com/specimen/Public+Sans)
(über `google_fonts`), weiche Ecken statt Schatten, schwebende Pillen-
Navigation statt Vollbreiten-Bottom-Bar. Alle Tokens liegen zentral in
`lib/theme/app_colors.dart` als `ThemeExtension` (`context.colors.accent`
usw.) – Screens greifen darauf zu statt Farben zu hardcoden. Ursprung ist
eine Design-Grundlage (Light/Dark-Mockups) für Fächer-Liste, Modul-Detail,
Daily Quiz und Einstellungen, die 1:1 in echten App-Code übernommen wurde.

## Setup

### 1. Flutter

Dieses Projekt wurde mit Flutter 3.47 (stable) angelegt. `flutter pub get`
im Projektverzeichnis installiert alle Abhängigkeiten.

Zum Testen im Browser immer zuerst den aktuellsten Stand holen, dann
Abhängigkeiten aktualisieren, dann starten:

```
git pull
flutter pub get
flutter run -d chrome
```

`./update.sh` macht genau diese drei Schritte in einem Rutsch (macOS/Linux/
Git-Bash unter Windows). So läuft nie versehentlich ein veralteter Stand.

### 2. OpenRouter-API-Key (BYOK)

Key unter <https://openrouter.ai> erstellen und in der App unter
**Einstellungen** eintragen. Es ist kein Backend nötig.

### 3. Cloud-Sync

Ist bereits eingerichtet: `lib/firebase_options.dart` enthält die Config des
Firebase-Projekts **lernenwing**, `main.dart` initialisiert Firebase damit
beim Start. Fehlt `firebase_options.dart` oder schlägt die Initialisierung
fehl (kein Netz, eigener Fork ohne Projekt), läuft die App einfach offline
weiter – die Einstellungen zeigen dann "Cloud-Sync nicht konfiguriert".

Die **Firestore Security Rules** (`firestore.rules` im Repo-Root) müssen
einmalig manuell in der Firebase Console eingetragen werden (Firebase liest
sie nicht automatisch aus dem Repo): **Firebase Console → Firestore Database
→ Rules-Tab → Inhalt von `firestore.rules` einfügen → Veröffentlichen.**
Sie beschränken den Zugriff auf `users/{uid}` (nur der authentifizierte
Besitzer) und `sync_codes/{code}` (kein Auflisten/Erraten existierender
Codes möglich) samt deren Unterdokumenten `sync_parts/*` und sperren alles
andere per Default. **Nach dem Update auf den aufgeteilten Sync einmal neu
veröffentlichen** – ohne die `sync_parts`-Regel klappt der Upload nur,
solange der komprimierte Bestand in ein Dokument passt (die App meldet es
dann verständlich).

Für ein komplett eigenes Firebase-Projekt (z.B. eigener Fork): Projekt unter
<https://console.firebase.google.com> anlegen, eine Web-App registrieren,
die angezeigte `firebaseConfig` in `lib/firebase_options.dart` eintragen,
Firestore Database aktivieren, obige Rules einfügen.

### 3a. Fach exportieren/importieren (JSON-Datei)

Unabhängig vom Cloud-Sync (der immer den GESAMTEN lokalen Datenbestand
spiegelt): ein einzelnes Fach lässt sich als eigenständige JSON-Datei
sichern oder weitergeben – z.B. um es an ein anderes Gerät ohne Account zu
übertragen, mit jemand anderem zu teilen, oder einfach als Backup vor dem
Löschen (`ModuleExportService`).

- **Exportieren**: Im Modul-Detail oben rechts (Teilen-Symbol) – schreibt
  Modul, Einheiten, Materialien (inkl. Original-PDF-Bytes, plattform-
  unabhängig als Base64 eingebettet, siehe `ModuleExportService.embedBytes`),
  Konzepte und Karteikarten in eine `.json`-Datei (Speichern-Dialog über
  `file_picker`, funktioniert auch im Web als Download). Bewusst NICHT
  enthalten: Chat-Verlauf und Ampel-Trend-Snapshots – geräte-/sitzungs-
  bezogene Verlaufsdaten ohne Bezug zum eigentlichen Fach-Inhalt.
- **Importieren**: Auf dem Start-Bildschirm ("Meine Fächer") über das
  Symbol neben dem Titel – legt aus einer solchen Datei ein NEUES Fach an.
  Alle IDs (Modul, Einheiten, Materialien, Konzepte, Karteikarten) werden
  dabei frisch vergeben, alle Querverweise dazwischen konsistent
  mitübersetzt (`ModuleExportService.parse`) – dieselbe Datei lässt sich
  daher beliebig oft importieren, auch mehrfach auf demselben Gerät, ohne
  mit vorhandenen Daten zu kollidieren.

### 3b. Eigener PDF-Speicher (optional)

Der Firestore-Sync überträgt nur Text und Lernstand – Firebase Storage für die
Dateien bräuchte den kostenpflichtigen Blaze-Tarif. Stattdessen bringt man
(wie beim API-Key) seinen eigenen Speicher mit: **Einstellungen →
PDF-Speicher**. Ohne Eintrag passiert nichts.

- **Cloudflare R2** (10 GB kostenlos, kein Traffic-Entgelt): Bucket anlegen,
  unter "R2 → API-Token verwalten" ein Token mit "Objekt lesen & schreiben"
  für diesen Bucket erstellen. In der App: S3-kompatibel, Endpunkt
  `https://<konto-id>.r2.cloudflarestorage.com`, Bucket-Name, Region `auto`,
  Access Key ID + Secret Access Key, Pfad-Adressierung an.
- **Backblaze B2** (10 GB kostenlos): Bucket (privat) + Application Key
  anlegen. Endpunkt `https://s3.<region>.backblazeb2.com`, Region z.B.
  `eu-central-003`, keyID als Access Key, applicationKey als Secret.
- **AWS S3 / MinIO**: wie oben; neue AWS-Buckets brauchen Pfad-Adressierung
  aus.
- **WebDAV** (Nextcloud, Uni-Cloud, ownCloud): Ordner-URL wie
  `https://cloud.example.de/remote.php/dav/files/NAME/Lernen`, Benutzername,
  **App-Passwort** (in Nextcloud unter Einstellungen → Sicherheit erzeugen).

"Speichern & testen" prüft Adresse und Zugangsdaten. Danach lädt jeder Sync
(automatisch oder "Hochladen") noch nicht hochgeladene PDFs vorab hoch
(`lernen-pdfs/<material-id>.pdf`); öffnet man auf einem anderen Gerät ein
Material ohne lokale Datei, wird sie dort bei Bedarf geholt. Gelöschte
Materialien werden auch im Speicher entfernt. Die Zugangsdaten reisen wie der
API-Key nur über den Konto-Sync, nie über einen Sync-Code.

**Web-Version:** der Browser lässt die Anfragen nur zu, wenn der Speicher
CORS für die Adresse der App erlaubt. Bei R2/B2 in den Bucket-Einstellungen
eine CORS-Regel anlegen, z.B.:

```json
[{"AllowedOrigins": ["https://<deine-app-adresse>"],
  "AllowedMethods": ["GET", "PUT", "DELETE", "HEAD"],
  "AllowedHeaders": ["*"], "MaxAgeSeconds": 3600}]
```

(B2 nutzt im Web-UI ein eigenes Format mit denselben Angaben.) Nextcloud
erlaubt fremde Web-Origins meist nicht – dort funktioniert der PDF-Speicher
in den nativen Apps (Android/Windows/iOS), die kein CORS brauchen.

### 4. Account (E-Mail/Passwort + Google)

Nutzt dasselbe Firebase-Projekt wie Cloud-Sync, braucht aber zusätzlich
aktivierte Sign-in-Methoden: **Firebase Console → Authentication →
Sign-in-Methode → "E-Mail/Passwort" und "Google" aktivieren.** Ohne das
schlägt die jeweilige Anmeldung mit einer Fehlermeldung fehl, der Rest der
App bleibt unberührt.

Google-Sign-In läuft im Web direkt über Firebases Popup-Flow (kein Zusatz-
Setup nötig, sobald der Google-Provider oben aktiviert ist). Für
Android/iOS braucht `google_sign_in` zusätzlich eine **echte, in der
Firebase-Console registrierte App** (Package-Name + SHA-1-Fingerabdruck
bzw. Bundle-ID) – ohne das zeigt die App dort eine klare Fehlermeldung
statt eines Absturzes. E-Mail/Passwort funktioniert überall ohne
Zusatz-Setup.

### 5. PDF-Textextraktion + -Ansicht (Syncfusion)

`syncfusion_flutter_pdf` wird für die reine Textextraktion genutzt (kein
UI-Widget), `syncfusion_flutter_pdfviewer` zusätzlich für die visuelle
Folien-Ansicht + Markier-Funktion (`MaterialViewerScreen`, siehe unten). Für
Privatpersonen/kleine Unternehmen ist die kostenlose
[Syncfusion Community License](https://www.syncfusion.com/sales/communitylicense)
ausreichend; für größere Organisationen ggf. Lizenz prüfen und
`SyncfusionLicense.registerLicense(...)` beim App-Start ergänzen.

### 5a. Folien markieren (rot/grün/gelb) + KI-Vorschläge

Ein Tippen auf ein hochgeladenes PDF-Foliendokument (Materialien-Liste im
Fach) öffnet `MaterialViewerScreen`: Text auswählen und mit rot (eignet
sich als Prüfungsfrage), grün (Antwort/Schlüsselfakt) oder gelb (sonst
relevant) markieren, dazu eine kurze Notiz. Der "KI-Vorschläge"-Button
lässt das Fragenerstellen-Modell (`AiService.suggestHighlights`) selbst
wichtige Stellen vorschlagen; sie werden per Text-Matching
(`HighlightMatcher`) im PDF wiedergefunden und automatisch platziert – nicht
auffindbare Zitate bleiben als reiner Kontext-Eintrag erhalten (erscheinen
unten in der Liste, aber nicht sichtbar im Dokument). Alle Markierungen +
die Notiz fließen als "vom Nutzer als besonders wichtig markiert"-Kontext
in Vorbereiten/Nachbereiten/Chat mit ein (`HighlightContext`). Nur für
PDF-Folien verfügbar (Original-Bytes werden dafür beim Upload zusätzlich
gespeichert, siehe `MaterialFileStore`); andere Formate/Übungsaufgaben
funktionieren weiterhin rein textbasiert.

Diese Original-Bytes werden bei JEDEM Upload-Weg gespeichert – nicht nur
beim direkten "Material hochladen" in `ModuleDetailScreen`, sondern
genauso beim Foliten-Upload in `PrepareScreen` (Kurz **und** Ausführlich)
und in `ReviewScreen` (Nachbereiten). Dadurch ist eine Folie unabhängig
vom Weg, über den sie ins Fach kam, immer über `MaterialViewerScreen`
einsehbar, markierbar und für "Frage zur Seite" (siehe 5b) nutzbar – ohne
das läge nach Vorbereiten/Nachbereiten nur der extrahierte Text vor
(`hasViewablePdf == false`), die eigentlichen Folien wären unsichtbar.

### 5a2. Folie direkt in Vorbereiten/Nachbereiten ansehen

Die reine Bytes-Persistenz (siehe oben) reicht für sich genommen nicht: die
Session-Ansicht von "Ausführlich vorbereiten" zeigte bis eben nur die von
der KI markierten Textstellen + den Frage-Chat, nie die Folie selbst – die
Bytes lagen zwar im Speicher, aber ohne UI-Zugriff darauf. Deshalb öffnet ein
Augen-Symbol pro Foliendatei – im Dateien-Auswahlschritt (Kurz **und**
Ausführlich, in `PrepareScreen`) sowie zusätzlich pro markierter Datei direkt
in der Ausführlich-Session – `PdfPreviewScreen`: eine reine Lese-Ansicht der
tatsächlichen, noch nicht gespeicherten PDF-Bytes samt eigenem "Frage zur
Seite"-Button (nutzt denselben `PageQuestionSheet`/`AiService.answerPageQuestion`
wie `MaterialViewerScreen`, nur ohne Markier-Funktion, da dafür ein
gespeichertes `MaterialItem` fehlt). Dieselbe Ansicht steht in `ReviewScreen`
(Nachbereiten) für die Folien-Liste zur Verfügung. Nach dem Speichern ist die
Folie zusätzlich wie gewohnt über `MaterialViewerScreen` mit voller
Markier-Funktion erreichbar.

### 5b. Frage zur aktuellen Seite (Vision-Modell)

Im selben `MaterialViewerScreen` öffnet der Button "Frage zur Seite" (in der
AppBar) einen Frage-Chat zu genau der Seite, die gerade sichtbar ist: ein
Screenshot des aktuellen PDF-Viewer-Ausschnitts (`RepaintBoundary` um
`SfPdfViewer`, kein PDF-Rendering – 1:1 das, was der Nutzer gerade sieht,
inkl. Zoom) geht zusammen mit dem Volltext des GESAMTEN Dokuments als
zusätzlicher Kontext an das **Vision-Modell** aus den Einstellungen
(`AppSettings.visionModelId` – bis hierhin nur vorbereitet, aber ungenutzt;
dies ist die erste tatsächliche Verwendung). So sieht die KI Diagramme,
Formeln oder Layout, die reiner Text nicht wiedergibt, UND kann Begriffe
einordnen, die an anderer Stelle im Dokument erklärt werden
(`AiService.answerPageQuestion`). Der Chat ist session-lokal (nicht
persistiert) und öffnet als Bottom-Sheet, ohne den restlichen
Viewer-Zustand (Markierungen/Notiz) zu beeinflussen.

### 5c. Lernmodus-Zwischen-Check (Checkpoint-Quiz)

`MaterialViewerScreen` ist damit schon ein vollwertiger "Lernmodus": Folie
ansehen, markieren, Notiz schreiben, Fragen zur Seite stellen, speichern –
alles an einem Ort. Zusätzlich bietet der Viewer alle
`AppSettings.checkpointQuizPageInterval` gelesenen Seiten (Einstellungen →
"Lernmodus", Default 5, 0 = aus) einen kurzen, überspringbaren Zwischen-
Check per SnackBar an: 2-3 KI-generierte Kurzfragen NUR zum gerade gelesenen
Seitenabschnitt (`AiService.generateCheckpointQuiz`, per-Seite-Textextraktion
über `PdfTextExtractor`), angezeigt über dieselbe `QuestionAnswerView` wie
Daily Quiz/Üben. Wer den Check ignoriert oder abbricht ("Später"), verliert
nichts – bewusst nicht blockierend. Falsch beantwortete Fragen werden aber
automatisch als neue, fällige Karteikarte gespeichert (`due: jetzt`): so
"merkt sich die KI", wo es hakt, ohne dass man selbst etwas dafür tun müsste
– die nächste Daily-Quiz-Session enthält sie automatisch. Ist eine
Übungsklausur hochgeladen (siehe oben), fließt sie hier als Stil-Referenz
mit ein.

### 5d. Direkt aus einer Seite: Konzept speichern / Frage erstellen

Zwei weitere Buttons in derselben AppBar machen den Lernmodus vollständig:
Während man eine Vorlesung durchgeht, lässt sich zu JEDER einzelnen Seite
sofort ein Konzept oder eine Frage erzeugen, statt dafür extra in den
Nachbereiten-Modus zu wechseln.

- **Konzept speichern** (`PageConceptSheet`) – die KI erstellt aus dem Text
  GENAU dieser Seite einen Titel + eine ausführliche Erklärung
  (`AiService.generatePageConcept`). Nachbarseiten-Text wird nur als
  optionaler Zusatzkontext mitgegeben – die KI nutzt ihn laut Systemprompt
  ausschließlich, wenn die aktuelle Seite allein sonst unklar/unvollständig
  wäre, statt ihn immer einzuarbeiten. Vor dem Speichern lässt sich das
  Ergebnis direkt bearbeiten oder per freier Anweisung ("kürzer",
  "umformulieren", "mehr Fokus auf …") iterativ überarbeiten. Gespeichert
  wird es als ganz normales Konzept in der Konzepte-Liste des Fachs, aber
  mit einem Quasi-Link zurück zu Material + Seite
  (`Concept.linkedMaterialId`/`linkedPageNumber`) – ein Klick auf "Seite N"
  im Modul-Detail öffnet den Viewer direkt auf genau dieser Seite
  (`MaterialViewerScreen.initialPage`).
- **Frage erstellen** (`PageQuestionCreationSheet`) – erzeugt aus derselben
  Seite **1 oder 2 Fragen** auf einmal (mehrere prüfen unterschiedliche
  Aspekte), jede in bis zu drei Stufen **Leicht/Mittel/Schwer** desselben
  Fakts. Jede Stufe ist einzeln an-/abwählbar, der Fragetyp pro Stufe per
  Dropdown wählbar oder auf **"KI entscheidet"** (Standard) – dann wählt die
  KI das Format passend zur Stufe (leicht eher Auswahl, schwer eher freies
  Erinnern, siehe `_variantTypeRule`/Schwierigkeits-Eskalation).
  **Fokus**, alles optional und kombinierbar: per **"Bereich markieren"**
  einen Rahmen um einen Teil der Seite ziehen (`PageRegionPicker` – ideal für
  Diagramme/Formeln, die sich nicht als Text auswählen lassen; der
  Ausschnitt geht als zweites Bild an die KI, `cropImageRelative`), eine
  Textstelle bzw. eigene Anweisung vorgeben (vorbelegt aus der Textauswahl
  im PDF oder einer roten Markierung) und optional die erwartete Antwort.
  Bleibt alles leer, wählt die KI selbst das Wichtigste der Seite.
  Bewusst IMMER multimodal (Seiten-Screenshot ans Vision-Modell) statt
  optional umschaltbar – einfacher UND robuster, da Folienseiten oft
  Diagramme/Formeln enthalten, die reiner Text nicht wiedergibt. Die
  generierten Karten lassen sich vor dem Speichern eins zu eins wie im
  echten Quiz durchklicken (`QuestionAnswerView`, dieselbe Ansicht wie
  Daily Quiz/Üben statt einer reinen Textvorschau), per freier Anweisung
  ("einfacher formulieren", "anderer Fokus") überarbeiten und bei zwei
  Fragen einzeln abwählen. Beim Speichern werden die Stufen einer Frage NICHT
  als unabhängige Karten abgelegt, sondern zu einer Eskalationskette
  zusammengeführt (siehe oben): nur die leichteste Stufe landet sofort
  fällig (`due: jetzt`) im Daily Quiz, die übrigen liegen bereits fertig
  ausformuliert als `Flashcard.pendingVariants` bereit und werden erst bei
  Beförderung sichtbar.
  Die KI entscheidet zusätzlich pro Karte, ob der Seiten-Screenshot für den
  Kontext der Frage nötig ist (`"needsImage"` im JSON-Ergebnis, z.B. bei
  einem Diagramm/einer Formel/einer Skizze, ohne die die Frage nicht
  verständlich wäre) – nur dann wird der Screenshot (bzw. mit markiertem
  Bereich genau dieser Ausschnitt) als `Flashcard.imageBase64`
  mitgespeichert und später beim Beantworten (Daily Quiz, Üben, überall wo
  `QuestionAnswerView` genutzt wird) oberhalb der Frage angezeigt. Rein
  textbasierte Fragen bekommen bewusst KEIN Bild angehängt, um die lokale
  Datenbank nicht unnötig aufzublähen.
  Solche direkt beim Betrachten selbst erstellten Fragen tragen zusätzlich
  `Flashcard.priorityIntroduction = true`: sie umgehen damit das Einheiten-
  "behandelt"-Gate im DailyScheduler (eine bewusst JETZT gestellte Frage ist
  per Definition schon relevant, unabhängig davon, ob die zugehörige
  Vorlesungseinheit separat als "behandelt" markiert wurde) und werden beim
  Auffüllen des Tages-Budgets vor der reinen createdAt-Reihenfolge
  einsortiert – ohne das würde eine frisch gestellte Frage sonst hinter
  einem großen Altbestand noch nicht eingeführter Bulk-generierter Karten
  verschwinden und tagelang nicht im Daily Quiz auftauchen.

### 6. Ausführen

**Am einfachsten zum Ausprobieren: im Browser**, kein Visual Studio/Android
SDK/Xcode nötig – nur Flutter + ein Chrome/Edge:

```bash
flutter run -d chrome
```

Web läuft mit derselben Codebasis (lokale Daten liegen dann im
IndexedDB des Browsers statt in einer Datei). Für die Ziel-Plattformen:

```bash
flutter run -d windows   # Windows-Desktop (braucht Visual Studio C++-Workload)
flutter run -d ios       # iOS (benötigt Xcode + Mac)
flutter run -d android   # Android (Emulator oder Gerät mit USB-Debugging)
```

`flutter devices` zeigt an, was auf dem jeweiligen Rechner tatsächlich
verfügbar ist.

### Android-APK ohne eigenen Rechner (GitHub Actions)

Bei jedem Push baut `.github/workflows/android-apk.yml` automatisch eine
installierbare APK – auch komplett vom Handy aus nutzbar, ohne PC. Vor dem
Build laufen `flutter analyze` und `flutter test`; schlägt eins davon fehl,
wird keine neue APK veröffentlicht (gilt ebenso für die Windows-App):

- **Direkter Download (empfohlen):** GitHub-Repo → Tab **Releases** → den
  Release **"Android APK (aktueller Stand)"** (Tag `android-latest`) öffnen
  → `app-release.apk` antippen. Lädt die `.apk` direkt herunter, kein
  ZIP-Umweg. Dieser eine Release wird bei jedem Push aktualisiert, die URL
  bleibt also immer gleich.
- **Pro Commit (Artifact):** Tab **Actions** → gewünschten Workflow-Lauf
  öffnen → unten bei **Artifacts** `lernen-apk` herunterladen (als ZIP,
  30 Tage aufbewahrt) – falls mal genau der Build zu einem bestimmten Commit
  gebraucht wird, nicht nur der neueste Stand.

Auf dem Handy die `.apk` antippen; Android fragt einmalig nach der
Erlaubnis, Apps aus dieser Quelle zu installieren ("Unbekannte Quellen
zulassen") – die APK ist nur mit dem Debug-Keystore signiert (kein
Play-Store-Eintrag nötig), das ist für den Eigengebrauch aber
unproblematisch.

`.github/workflows/windows-app.yml` baut analog eine native Windows-App
(`flutter build windows`), gepackt als ZIP unter Release **"Windows-App
(aktueller Stand)"** (Tag `windows-latest`) – entpacken, `lernen.exe`
starten, keine Installation nötig.

### In-App-Update-Hinweis

Damit man nicht von Hand auf GitHub nachschauen muss, ob es einen neueren
Build gibt: beide Workflows setzen `--build-number=${{ github.run_number }}`
(eine garantiert fortlaufende Zahl über alle Pushes hinweg) und
veröffentlichen zusätzlich ein `version.json`
(`{"buildNumber": ..., "sha": "...", "tag": "..."}`) unter derselben
Release-URL wie die APK/das ZIP. `UpdateCheckerService` vergleicht das beim
App-Start (und über "Nach Updates suchen" in den Einstellungen) mit der
Build-Nummer der laufenden App (`package_info_plus`) – findet es eine
neuere, gibt es eine SnackBar bzw. einen Button mit direktem Download-Link.
Rein informativ (kein Auto-Install): Android öffnet die `.apk` im Browser
zum Herunterladen/Installieren, Windows lädt das ZIP zum manuellen
Entpacken – für echte automatische Updates bräuchte es Play Store (Android)
bzw. ein MSIX-Paket mit App-Installer-Manifest (Windows), beides mit
deutlich mehr Einrichtungsaufwand.

## Tests

```bash
flutter analyze   # statische Analyse
flutter test       # FSRS-Algorithmus, Exam-Scheduler, KI-JSON-Parsing, App-Smoke-Test
```

Die Kernlogik (FSRS-Scheduling, Exam-Scheduler-Dosierung, robuste
JSON-Extraktion aus KI-Antworten, Sync-Codec, LaTeX-Reparatur, CSV, S3-
Signatur gegen die offiziellen AWS-Beispielwerte) ist mit `flutter test` ohne
Gerät abgedeckt; dieselben Tests laufen in CI vor jedem Build. Texterkennung
und PDF-Speicher sind nur gegen nachgebaute HTTP-Antworten getestet – echte
OpenRouter-/R2-/Nextcloud-Aufrufe einmal von Hand ausprobieren. Zusätzlich wurde der komplette Kernablauf – Fach anlegen,
Navigation zwischen Fächer/Daily-Quiz/Einstellungen, Settings-UI – als
Web-Build (`flutter build web`) in einem echten (headless) Chromium
durchgeklickt und per Screenshot verifiziert. Native Windows/iOS/Android-
Builds selbst (PDF-Upload-Flows, echte Gerätespezifika) wurden in diesem
Sandbox-Environment nicht getestet, da hierfür Visual Studio/Xcode/Android-
SDK fehlen – das lohnt sich vor dem ersten echten Einsatz nachzuholen
(`flutter run -d <platform>`). Das gilt besonders für das
Android-Startbildschirm-Widget (`android/app/src/main/kotlin/com/pius/lernen/CalendarWidgetProvider.kt`
+ die zugehörigen `res/xml`/`res/layout`-Dateien): rein aus Code-Review
erstellt und mit den offiziellen `home_widget`-Beispielen abgeglichen, aber
nie in einem echten Android-Build/-Emulator gerendert – vor dem ersten
Release unbedingt auf einem echten Gerät/Emulator ausprobieren (Widget zum
Homescreen hinzufügen, prüfen ob Text/Klick-Verhalten stimmen).
