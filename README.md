# Lernen

Eine schlanke Klausur-Lern-App für Windows, iPad (iOS) und Android – der
Nachfolger von [Quiz-app](https://github.com/nphjfvp/quiz-app), diesmal mit
engerem Fokus statt Feature-Fülle.

## Was die App macht

- **Modul-Verwaltung** – Fächer-Ordner mit Klausurdatum, in denen Folien und
  Übungsaufgaben gesammelt werden.
- **Laborversuche** (nur in Fächern mit Schalter **Laborfach**) – Vorbereitung,
  Durchführung und Bericht eines Praktikumsversuchs an einem Ort, mit Termin im
  Kalender, Fotos von Messprotokollen mit automatischem Auslesen; die KI liest
  deine selbst geschriebenen Antworten und Berichtsabschnitte **gegen**
  (sie schreibt nichts für dich), siehe Abschnitt 5p.
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
  Übersicht jederzeit bearbeiten oder löschen.
- **Fragen aus PDF importieren** (`lib/ui/import/pdf_question_import_screen.dart`,
  im Fach als eigener Eintrag und im ⋮-Menü jeder PDF unter
  "Materialien") – die KI liest **beliebig viele PDFs auf einmal** (aus dem
  Fach mit "Alle hinzufügen", hochgeladen oder per Drag-and-drop) nach den
  Fragen und Aufgaben durch, die dort schon stehen (Altklausur,
  Übungsblatt, Fragen auf Folien), und übernimmt sie ins Quiz, statt neue
  zu erfinden. Vorher wählt man: **"Jede Frage"** (wirklich alles inkl.
  Teilaufgaben und Zwischenfragen auf Folien) oder **"Nur inhaltliche"**
  (ohne Organisatorisches, rhetorische oder Meinungsfragen), ob **fehlende
  Lösungen von der KI ergänzt** werden (sonst werden Fragen ohne Lösung im
  Dokument übersprungen; eine Musterlösung in einer anderen der gewählten
  PDFs wird dafür nachgeschlagen) und – nur bei einer einzelnen PDF –
  optional einen Seitenbereich. **Es gibt keine Begrenzung bei Seiten oder
  Dateien.** Die Seiten werden auf dem Gerät als **Bild** gerendert
  (`PdfPageRenderer`, dieselbe Engine wie der PDF-Viewer) und mit einer
  Randskala und ihrem Text an das Vision-Modell geschickt – **fortlaufend**
  (`PdfQuestionImportService`, `AiService.scanPdfWindow`): Ein Abschnitt
  besteht aus einer sinnvollen Zahl neuer Seiten (bis zu 4, bei viel Text
  weniger) **plus der letzten Seite des vorigen Abschnitts**. Dazu bekommt
  die KI die daraus schon übernommenen Fragen und prüft, ob auf den neuen
  Seiten etwas steht, das zu ihnen gehört – Fortsetzung der Aufgabe, weitere
  Teilaufgaben, die Musterlösung, eine Abbildung. Ja → die Frage wird
  überarbeitet ("N Fragen wurden durch die nächste Seite vervollständigt"),
  nein → es geht einfach mit den neuen Seiten weiter. So wird eine Aufgabe
  über den Seitenumbruch nicht zerrissen. Die Abschnitte **einer** Datei
  laufen nacheinander (sie bauen aufeinander auf), verschiedene Dateien bis
  zu zwei gleichzeitig. Meldet die KI eine Seite nicht gelesen zu haben
  (jede Antwort nennt alle gezeigten Seiten mit der Zahl gefundener
  Aufgaben) und übernimmt daraus nichts, wird sie einzeln nachgelesen. Die
  KI übernimmt jede Aufgabe **1:1 in ihrer Form** – Ankreuzen, Lücken,
  Zuordnen/Kategorien, Tabellen und Matrizen als interaktive Frage,
  Abbildung beschriften/markieren als Bildfrage – und gibt für nötige
  Abbildungen, Tabellen, Schaltungen o.ä. den Bereich auf der Seite an: der
  wird ausgeschnitten und hängt an der Frage (Lösungen im Bild werden
  abgedeckt). Lässt sich die PDF auf dem Gerät nicht rendern, geht sie als
  Datei an die KI, Abbildungen sind dann nur beschrieben. Ein
  fehlgeschlagener Abschnitt lässt sich einzeln wiederholen (die nächste
  Überlappung liest dessen letzte Seite trotzdem als neue Seite). Die
  Treffer erscheinen nach Datei und Seite sortiert mit Typ, Lösung,
  Abbildung (einzeln entfernbar) und dem Hinweis "Lösung von der KI" zum
  Abwählen; importiert werden sie als Karten des Fachs (Einheit des
  Materials, jede Frage kennt Datei und Seite, `priorityIntroduction`) –
  danach direkt **"Jetzt üben"**. Derselbe fortlaufende Import läuft auch im
  **Nachbereiten-Modus "Fragen importieren"** für PDFs (mehrere auf einmal;
  weitere Dateien, auch Word/PowerPoint, dienen als Nachschlagewerk für
  Lösungen – je Abschnitt werden nur die zum Text passenden Seiten
  mitgeschickt, deshalb geht es mit beliebig vielen Dateien). Übungs-PDFs
  werden jetzt wie Folien gespeichert und lassen sich ansehen; bei früher
  hochgeladenen Übungen lässt sich die PDF über ⋮ → "Original-PDF
hinzufügen" nachreichen. Zusätzlich: **Speedrun** –
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
  nächsten natürlichen FSRS-Fälligkeitsdatum wiederzukommen. Ein erneuter
  Fehlversuch am selben Tag zählt dabei nicht noch einmal
  (`FsrsService.isRepeatFailureToday`): die Ampel sinkt höchstens einen
  Schritt pro Tag (wie sie auch höchstens einen pro Tag steigt), das
  Fehlertagebuch zählt kein weiteres "vergessen", und eine Rückstufung der
  Schwierigkeitsstufe braucht Fehlversuche an verschiedenen Tagen. Geplant
  werden nur Karten bestehender Fächer (verwaiste Karten ohne Fach bleiben
  außen vor, auch in Statistik, Fehlertagebuch und Sprint); wird die Session
  mit über 60 Karten zu groß, kürzt sie neue Karten reihum je Fach, gezielt
  selbst erstellte Fragen zuletzt. Ist die Session
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
- **Lernhilfen nach dem Antworten** (`lib/ui/study/`): **"Im Skript"**
  öffnet die Seite, auf der die Frage steht – gespeichert, wenn die Karte aus
  einer Seite entstanden ist (Frage erstellen, Zwischen-Check, PDF-Import,
  Nachbereiten-Import: `Flashcard.sourceMaterialId`/`sourcePage`), sonst über
  das Konzept der Karte oder einen lokalen Textabgleich mit den PDFs des
  Fachs (`SourceLocator`, zuerst in derselben Einheit; als "vermutlich"
  gekennzeichnet). Bei Fragen aus **Übungsblättern** zeigt "Im Skript" die
  beim Erstellen abgeglichene Erklärung in den Folien (siehe 5m), das Blatt
  selbst bleibt als "Aufgabenblatt" erreichbar. **"Kurze Lerneinheit"** (mit API-Key): Worum es geht,
  Kern, Beispiel, Merksatz – auf Basis der gefundenen Seite bzw. der
  Konzept-Erklärung, einmal erzeugt und an der Karte gespeichert
  (`Flashcard.miniLesson`, reist mit dem Sync). **"Sokratisch erarbeiten"**
  bei Karten, die öfter schiefgehen (ab dem zweiten Fehlversuch,
  `WeaknessService.oftenWrong`) und im Fehlertagebuch: die KI verrät die
  Lösung nicht, sondern führt mit einer Gegenfrage nach der anderen hin,
  ausgehend von der falschen Antwort, bis man sie selbst begründet hat
  (`SocraticScreen`, `AiService.socraticTurn`); "Lösung zeigen" beendet den
  Dialog jederzeit. Bewusst schlank: ein Dialog pro Karte, nichts wird
  gespeichert, kein eigener Modus im Menü.
- **Karteikarten-Liste: Mehrfachauswahl + Löschen** (`lib/ui/flashcards/
  flashcard_list_screen.dart`) – lang auf eine Karte drücken startet den
  Auswahlmodus (Checkbox pro Karte, "Alle auswählen", gemeinsames Löschen in
  einer Transaktion über `FlashcardRepository.deleteMany`), zum Aufräumen
  nach einer größeren Generierung ohne jede Karte einzeln aufklappen zu
  müssen. Einzelne Karten lassen sich aufklappen und per Button
  bearbeiten/löschen – **"Bearbeiten" gibt es für jeden Fragetyp**
  (`lib/ui/flashcards/card_edit_screen.dart`): Frage, Antwortoptionen und
  welche davon richtig sind, Musterantwort, Lückentext samt Lösungen (je
  "___" ein Feld, Varianten mit ";"), Zuordnungspaare – eine von der KI
  falsch erzeugte Frage lässt sich so korrigieren statt nur löschen;
  Lernstand, Typ und Stufenkette bleiben (`Flashcard.copyWithContent`). Ein
  **Suchfeld** oben filtert nach Wörtern in Frage, Antwort und Optionen
  ("Alle auswählen" nimmt dann nur die Treffer). Über das Menü oben rechts: **"Als CSV
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
  beim strengeren lokalen Ergebnis. **Lückentexte** genauso, je Lücke: lokal
  zählen die hinterlegte Lösung, jede per ";" hinterlegte Variante
  ("Mitochondrium; Mitochondrien") und kleine Tippfehler – nie bei Zahlen
  (eine andere Ziffer ist ein anderes Ergebnis; "3.5" = "3,5") und nie bei
  einer fehlenden/zusätzlichen Vorsilbe ("homogen" ≠ "inhomogen"); lehnt das eine
  Lücke ab, bewertet `AiService.checkFillBlankAnswers` den ganzen Satz nach
  – geprüft wird Wissen, nicht Rechtschreibung: gröbere Tippfehler
  ("debinrten" für "definierten"), vertauschte gleichrangige Lücken ("bei
  Produktion und Entwicklung" statt umgekehrt), gleichwertige Begriffe und
  fachlich ebenso richtige Antworten zählen; im Zweifel zugunsten des
  Lernenden. Die KI kann eine Lücke nur nachträglich als richtig werten, nie
  eine lokal richtige verwerfen; nach dem Prüfen zeigt jede Lücke ✓/✗, die
  hinterlegte Schreibweise und die kurze Begründung der KI, darunter steht,
  ob die KI nachgeprüft hat oder (z.B. offline) nicht. Liegt die Prüfung
  trotzdem daneben, wertet **"Als richtig werten"** eine abgelehnte
  Freitext-/Lückentext-/Tabellen-Antwort als richtig (nicht in der
  Probeklausur).
  **Keine geschenkten Fragen:** Die KI soll Zuordnen nur mit mindestens 3
  Paaren (Kategorien: mindestens 2 Kategorien, 4 Begriffe) und Auswahlfragen
  nur mit plausiblen falschen Optionen erstellen; die Lösung darf nicht im
  Fragetext stehen. Kommt trotzdem eine Zuordnung mit nur einem Ziel an
  (ein einziges Paar oder alles in dieselbe Kategorie), wird daraus eine
  Freitextfrage ("… „Begriff“" → Ziel eintippen); schon gespeicherte
  solche Karten werden als Karteikarte abgefragt (Begriff in der Frage,
  Zuordnung auf der Rückseite) und in der Kartenliste markiert.
  **Zuordnen/Kategorien** arbeitet mit Positionen statt Texten: gleich
  lautende Begriffe oder Ziele (z.B. zweimal "Metall") belegen nie mehrere
  Felder; kommt ein Ziel mehrfach vor, wird die Frage als Kategorien-Frage
  angezeigt und geprüft. Begriffe lassen sich ziehen oder antippen und dann
  ein Feld antippen; abgelegte Begriffe sind wieder verschiebbar. Die
  Optionen von Single-/Multiple-Choice erscheinen gemischt ("Alle/Keine der
  genannten" bleiben am Ende). Karten mit unbrauchbaren Daten (z.B. keine
  richtige Option) werden als Karteikarte zum Selbstbewerten gezeigt statt
  unlösbar abgefragt. Ausgewählte Single-Choice-
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
- **Bildfragen: "Bild beschriften" und "Bild markieren"** (aus der
  Vorgänger-App übernommen, `QuestionType.diagramLabel`/`markImage`). Beide
  nutzen das Bild der Karte (`Flashcard.imageBase64`) und dieselbe Liste
  `Flashcard.imageTargets` mit Koordinaten relativ zum Bild (0..1, siehe
  `ImageTarget`): **Bild beschriften** – nummerierte Stellen im Bild; zwei
  Wege, umschaltbar über "Zuordnen / Eintippen": die Beschriftungen liegen
  gemischt darunter und werden per Ziehen oder Antippen (Beschriftung, dann
  Stelle) zugeordnet – oder man tippt sie selbst ein (schwerer; kleine
  Tippfehler zählen lokal, bei Abweichungen prüft die KI nach –
  Rechtschreibung, Synonyme, Abkürzungen egal, sie kann nur nachträglich als
  richtig werten; "Als richtig werten" gibt es auch hier). **Austauschbare
  Stellen:** Stellen mit derselben Gruppe (`ImageTarget.group`, z.B. fünf
  Inputs eines Prozesses) nehmen jede Beschriftung ihrer Gruppe, jede aber
  nur einmal – dort zählt nur der richtige Bereich, nicht die Reihenfolge
  (`AnswerChecker.diagramLabelZones`). Gleich lautende Beschriftungen sind
  ohnehin austauschbar; falsche Stellen zeigen danach, was dort richtig
  gewesen wäre. **Bild markieren** – eine Stelle im Bild antippen;
  richtig, wenn sie in einem der hinterlegten Bereiche liegt (Rechtecke,
  mit etwas Toleranz; Punkte ohne Größe bekommen eine Mindestgröße). Die
  Formate der Vorgänger-App (`diagram_labels`, `mark_regions` mit Kreis
  bzw. Vieleck) werden beim Import/JSON-Einfügen gelesen. Ohne Bild oder
  ohne Stellen wird so eine Karte als Karteikarte gezeigt. Erstellen:
  in **Frage erstellen** als Fragetyp wählbar ("KI entscheidet" wählt sie
  nie von allein) oder unter **"Bildfrage selbst erstellen"** komplett von
  Hand. Die KI bekommt dafür das Bild mit einem **Koordinatenraster** in
  Zehnteln (`drawCoordinateGrid`, nur für die Anfrage), liefert je Stelle
  den Kasten um die im Bild stehende Beschriftung (`"box"`), Gruppen für
  austauschbare Stellen und weitere verräterische Textstellen
  (`"covers"`). Diese Kästen werden **automatisch weiß abgedeckt** – als
  bearbeitbare Abdeckungen: in der Vorschau mit "Bild & Stellen bearbeiten"
  lassen sie sich verschieben, vergrößern oder entfernen, genauso die
  Stellen selbst (die KI liegt nicht immer genau).
- **Bild-Editor** (`lib/ui/widgets/image_editor_screen.dart`) – Bilder von
  Karten lassen sich bearbeiten: **Abdecken** (Rahmen ziehen, weiß oder
  schwarz – z.B. Beschriftungen, die bei einer Zuordnen-/Beschriften-Frage
  sonst die Antwort verraten) und **Text** (antippen, Text und
  **Schriftgröße** wählen). Bei Bildfragen setzt derselbe Editor die
  **Stellen** (antippen, Beschriftung und optional Gruppe) bzw. den
  **Bereich** (Rahmen ziehen). Alles bleibt bis zum Übernehmen einzeln
  bearbeitbar: **ziehen verschiebt** (Abdeckungen, Texte, Stellen,
  Bereiche), ein ausgewählter Rahmen lässt sich an der Ecke **vergrößern/
  verkleinern**, umfärben oder entfernen, Texte und Stellen öffnen sich per
  Antippen zum Ändern; "Rückgängig" nimmt jeden Schritt zurück. Abdeckungen
  und Text werden beim Übernehmen in Originalauflösung ins Bild
  eingerechnet (`lib/services/image_edit.dart`). Erreichbar in der Vorschau von "Frage
  erstellen" ("Bild bearbeiten" / "Bild & Stellen bearbeiten"), in der
  Kartenliste (Knopf "Bild"/"Stellen"/"Bereich") und direkt beim Lernen
  (Stift-Knopf oben rechts am Bild im Daily Quiz, Üben und Sprint – nicht in
  der Probeklausur); gespeichert wird in die Karte, der Lernstand bleibt.
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
  behandelten Stoff (aus einem Ordner Leicht/Mittel/Schwer nur die schwerste
  Stufe – dasselbe Wissen kommt nicht dreimal dran), optional mit Zeitlimit (15/30/60 min), OHNE Feedback,
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
  zur Verfügung. Getrennte Modell-Einstellungen für vier Rollen:
  **Fragenerstellen**, **Erklärungen & Hilfe** (Erklär mir das, Tipps, Rückfragen
  im Quiz, Lerneinheit, Sokrates, Frage-Chat, Fehlertagebuch, Gegenlesen im
  Laborversuch – ohne eigene Wahl wie Fragenerstellen), **Vision** (bildfähige
  Modelle, z.B. für gescannte Foliensätze) und **Crosscheck** (bewusst ein
  zweites Modell, das die Ergebnisse des ersten gegenprüft). Große Foliensätze/Übungsaufgaben werden
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
  Fächer, Einheiten, Materialien, Konzepte, Karteikarten, Frage-Chats,
  Probeklausur-Verlauf, Lerntage (Streak), Ampel-Trend, den heutigen
  Daily-Quiz-Stand sowie Modellwahl und Vorlieben (Chunking, Rolling-Context,
  Zwischen-Check-Intervall, Sprint-Rekord). Lerntage, Ampel-Trend und der
  heutige Daily-Stand werden beim Herunterladen ZUSAMMENGEFÜHRT statt
  ersetzt: der Streak wird nie kürzer, und heute auf einem Gerät eingeführte
  neue Karten zählen auch auf dem anderen gegen das Tagesbudget (sonst gäbe
  es mit Handy + iPad doppelt so viele neue Karten am Tag). Der
  eigentliche API-Key und die Zugangsdaten zum eigenen PDF-Speicher werden
  bewusst NUR über den Konto-Weg übertragen (dort
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
  sondern **führt beide Stände zusammen** (siehe "Abgleichen" unten und Abschnitt
  5s) – das passiert auch beim Start und beim Zurückkehren in die App, damit
  der Stand des anderen Geräts ohne Zutun ankommt. Auch geänderte Einstellungen, die
  mitreisen (API-Key, Modelle, PDF-Speicher, Vorlieben), lösen den Auto-Sync
  aus – vorher kamen sie erst mit der nächsten gelernten Karte an. Nach einem
  Download zeigen die Einstellungsfelder sofort die übernommenen Werte (vorher
  blieben sie leer und konnten beim Verlassen den gerade geholten API-Key
  wieder überschreiben).
- **Sync-Diagnose** – Einstellungen → Cloud-Sync → **"Verbindung prüfen"**
  (`SyncService.diagnose`, `lib/ui/settings/sync_diagnosis_dialog.dart`): geht
  Schritt für Schritt durch, woran der Sync hängt, und zeigt es als Liste
  (Kopieren-Knopf für den Support): ist Firebase verbunden, welches **Ziel**
  nutzt dieses Gerät (Konto mit E-Mail und Kennungsende oder Sync-Code –
  beide Geräte müssen dasselbe nutzen, ein Konto auf dem einen und ein Code
  auf dem anderen sehen nie dieselben Daten), liegt dort ein Stand, wann und
  von welchem Gerät, ist er vollständig lesbar, wie groß ist der lokale Stand
  (komprimiert, in wie vielen Teilen) und darf dieses Gerät schreiben (eine
  Schreibprobe legt ein Testdokument an und löscht es sofort). Fehler kommen
  mit einer Erklärung statt eines nackten Codes (z.B. `permission-denied` →
  Regeln nicht veröffentlicht oder Sync-Code unter 6 Zeichen; `unavailable` →
  Firewall/VPN/Port 443). Der Sync liest immer **vom Server** (nie aus dem
  Firestore-Zwischenspeicher, der offline sonst einen alten Stand als
  "erfolgreich heruntergeladen" geliefert hätte) und hat Fristen, damit ein
  Upload bei abgerissener Verbindung nicht endlos hängt und den Auto-Sync
  blockiert. Auf Android ist `INTERNET` ausdrücklich im Manifest angefordert.
- **Sicherungen auf dem Gerät** – ein Download ersetzt den lokalen Stand
  vollständig, und ein Gerät mit altem Stand kann den Cloud-Stand
  überschreiben. Deshalb legt die App **vor jedem Download automatisch eine
  Sicherung** an (dazu einmal täglich eine weitere; die letzten 5 bzw. 3
  bleiben) – in derselben lokalen Datenbank, also auch im Web, und nie in der
  Cloud. Einstellungen → Cloud-Sync → **"Sicherungen (auf diesem Gerät)"**
  zeigt sie mit Datum, Fächern und Karten; **"Wiederherstellen"** holt einen
  Stand zurück (vorher wird der jetzige gesichert, es lässt sich also
  zurücknehmen; lokal gespeicherte PDFs bleiben). Schlägt die Sicherung vor
  einem Download fehl, wird nichts heruntergeladen.
  **Rückfragen mit Zahlen:** vor "Herunterladen" steht, was in der Cloud liegt
  (Fächer, Karten, wann, von welchem Gerät) und was hier überschrieben wird;
  vor "Hochladen" fragt die App, wenn in der Cloud ein Stand eines ANDEREN
  Geräts liegt, den dieses nicht kennt – und bietet dann **"Abgleichen"**
  (beides behalten) oder bewusst "Cloud ersetzen" an.
  **Abgebrochene Uploads** lassen den Cloud-Stand nicht mehr unlesbar zurück
  (Cloud-Format 3): große Stände werden in Teilen `sync_parts/{pushId}_n`
  unter neuen Kennungen geschrieben, erst das Hauptdokument schaltet den neuen
  Stand ein, dann werden die alten Teile gelöscht. Frühere Stände (Format 1
  und 2) werden weiter gelesen; eine ältere App-Version meldet bei einem
  Format-3-Stand "neuere App-Version – bitte aktualisieren". In der
  Diagnose ("Verbindung prüfen") kopiert **"Regeln kopieren"** den Inhalt von
  `firestore.rules` für die Firebase-Konsole.
- **Abgleichen** (Einstellungen → Cloud-Sync, Knopf "Abgleichen (empfohlen)") –
  führt den Stand dieses Geräts mit dem der Cloud zusammen, statt einen der
  beiden zu ersetzen: neue Fächer, Karten, Materialien usw. von BEIDEN Seiten
  bleiben, bei derselben Karte gilt der spätere Lernstand. Beispiel: auf dem
  Handy liegt ein neuer Kurs, auf dem PC ein alter, an dem du weiter bist –
  danach haben beide beides, der Kurs am PC mit dem weiteren Fortschritt. Details
  und Grenzen: Abschnitt 5s.
- **Frühere Cloud-Stände** (Knopf "Frühere Cloud-Stände") – lädt ein Gerät hoch
  und ersetzt dabei den Stand eines anderen, bleibt dieser in der Cloud liegen
  (die letzten fünf); ein Klick holt ihn zurück. Dazu die lokalen Sicherungen
  (siehe oben).
- **Anmelden auf einem neuen Gerät** – direkt nach der Anmeldung fragt die
  App, ob der Stand aus dem Konto abgeglichen werden soll (mit Anzahl Fächer/
  Karten; nichts wird überschrieben). Ist
  das Konto noch leer, bietet sie stattdessen an, den Stand dieses Geräts
  hochzuladen. "Passwort vergessen?" im Anmeldebildschirm schickt eine
  E-Mail zum Zurücksetzen.
- **Account (optional)** – E-Mail/Passwort oder Google-Anmeldung über
  Firebase Auth, aus den Einstellungen heraus. Nie erzwungen: die App bleibt
  auch ohne Account voll nutzbar. Der Hauptzweck ist der automatische
  Cloud-Sync oben (siehe dort) statt des manuellen Sync-Codes.

## Bewusst NICHT enthalten (verglichen mit der Vorgänger-App)

Der Vorgänger hatte 9 Fragetypen (inkl. Mathe-Formel-Fragen mit Formel-Editor
und Diagramm-Beschriftung/Bild-Markierung), 6 Mini-Games, eine
Coin-Economy/Shop, Mock-Klausuren, Formelsammlungen, Sokrates-Modus u.v.m.
Diese App übernimmt 8 der 9 Fragetypen (inzwischen auch Bild beschriften
und Bild markieren) inkl. der adaptiven Schwierigkeits-Eskalation (siehe
oben) sowie inzwischen Probeklausur, Fehlertagebuch, KI-Tipp/-Erklärung und
LaTeX-Darstellung, lässt aber bewusst den Mathe-Formel-Fragetyp mit
Formel-Editor weg und konzentriert sich ansonsten auf den
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

#### Farb-Skins (Einstellungen → Erscheinungsbild)

Neben dem oben beschriebenen Standard-Look ("Ruhig") gibt es zwei weitere,
komplett eigenständige Farbpaletten – **"Klar"** (kühles Blau/Grau, Standard)
und **"Lebendig"** (warmes Terrakotta) –, zwischen denen jederzeit unter
Einstellungen → Erscheinungsbild gewechselt werden kann, ohne die App neu zu
starten. Nur die Farben ändern sich; Layout, Formen und Typografie bleiben in
allen drei Skins identisch. Jeder Skin definiert einen eigenen, in sich
stimmigen Satz aller 17 `AppColors`-Rollen für Hell- und Dunkelmodus
(`AppColors.of(skin, brightness)` in `lib/theme/app_colors.dart`), wobei
Status-/Ampelfarben (Erfolg/Warnung/Fehler) und die Akzentfarbe je Skin immer
klar unterscheidbar bleiben. Die Wahl wird in `AppSettings.themeSkin`
gespeichert, reist über Konto-Sync/Sync-Code mit (ein leerer Cloud-Wert
überschreibt nie eine lokal getroffene Wahl) und wird beim App-Start in
`main.dart` reaktiv aus der `SettingsRepository` gelesen.

Unabhängig davon lässt sich unter Einstellungen → Erscheinungsbild auch
Hell/Dunkel selbst festlegen (drei Kacheln: "System", "Hell", "Dunkel") statt
nur der Geräte-Einstellung zu folgen – `AppSettings.themeModePreference`
("system" ist Standard), gemappt über `AppThemeModePreference.themeMode` in
`lib/theme/app_theme.dart` auf `MaterialApp.themeMode`. Reist wie der
Farb-Skin über Sync/Sync-Code mit und wirkt sofort ohne Neustart.

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
  Zusammenfassungen (Vorbereiten), Konzepte und Karteikarten in eine
  `.json`-Datei (Speichern-Dialog über
  `file_picker`, funktioniert auch im Web als Download). Bewusst NICHT
  enthalten: Chat-Verlauf und Ampel-Trend-Snapshots – geräte-/sitzungs-
  bezogene Verlaufsdaten ohne Bezug zum eigentlichen Fach-Inhalt.
- **Importieren**: Auf dem Start-Bildschirm ("Meine Fächer") über das
  Symbol neben dem Titel – legt aus einer solchen Datei ein NEUES Fach an.
  Alle IDs (Modul, Einheiten, Materialien, Konzepte, Karteikarten) werden
  dabei frisch vergeben, alle Querverweise dazwischen konsistent
  mitübersetzt (`ModuleExportService.parse`) – dieselbe Datei lässt sich
  daher beliebig oft importieren, auch mehrfach auf demselben Gerät, ohne
  mit vorhandenen Daten zu kollidieren. Enthält die Datei einen Lernstand,
  fragt der Import "Übernehmen" oder "Neu beginnen" (bei weitergegebenen
  Fächern: alle Karten neu, Stufen-Ketten wieder auf der leichtesten Stufe);
  gespeichert wird in einer einzigen Transaktion (kein halbes Fach beim
  Abbruch).

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
API-Key nur über den Konto-Sync, nie über einen Sync-Code – einmal eintragen
reicht, die anderen Geräte bekommen sie beim nächsten "Abgleichen" (mit
Auto-Sync wird die Änderung sofort hochgeladen und beim Öffnen der App geholt).

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

Platz für die Folie: eine schmale Werkzeugzeile über der PDF. Links blendet
der Stift die Markier-Farben ein und aus, rechts öffnet "Markierungen &
Notiz" den unteren Bereich (standardmäßig zu). Beides merkt sich die App bis
zum Neustart. Dazwischen der Zoom wie in Word: − / + in Stufen oder direkt
10 %, 25 %, 50 %, 75 %, 100 % (Seitenbreite) bis 800 %; Zoomen per Geste oder
Mausrad wird übernommen. Unter 100 % wird die Seite verkleinert und
zentriert (der PDF-Viewer selbst zoomt nicht unter die Seitenbreite).

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
  Seite **1 bis 5 Fragen** auf einmal – oder mit Anzahl **"KI"** so viele,
  wie die Seite hergibt (eine je prüfungsrelevantem Fakt, höchstens
  `AiService.maxAutoPageQuestions` = 8; eine inhaltsarme Seite ergibt eine
  Frage) – (mehrere prüfen unterschiedliche
  Aspekte), jede in bis zu drei Stufen **Leicht/Mittel/Schwer** desselben
  Fakts. Jede Stufe ist einzeln an-/abwählbar, der Fragetyp pro Stufe per
  Dropdown wählbar – auch **"Interaktiv"** (html, nur auf Android/iOS
  interaktiv, sonst Karteikarte) – oder auf **"KI entscheidet"** (Standard)
  – dann wählt die KI das Format passend zur Stufe (leicht eher Auswahl,
  schwer eher freies Erinnern, siehe `_variantTypeRule`/Schwierigkeits-
  Eskalation); "Interaktiv", "Bild beschriften" und "Bild markieren" wählt
  sie dabei nie von selbst. Bei den beiden Bildfragen setzt die KI die
  Stellen bzw. den Bereich selbst (relativ zum markierten Ausschnitt oder
  zur ganzen Seite); in der Vorschau lassen sie sich mit "Bild & Stellen
  bearbeiten" korrigieren. Unter **"Bildfrage selbst erstellen"** geht es
  ohne KI: Ausschnitt bzw. Seite im Bild-Editor öffnen, Stellen setzen oder
  Bereich ziehen, Beschriftungen abdecken, Frage eingeben – die Frage
  landet wie die KI-Fragen in der Vorschau ("Selbst erstellt") und bleibt
  bei einer Neu-Generierung erhalten.
  **Fokus**, alles optional und kombinierbar: per **"Bereich markieren"**
  einen Rahmen um einen Teil der Seite ziehen (`PageRegionPicker` – ideal für
  Diagramme/Formeln, die sich nicht als Text auswählen lassen; der
  Ausschnitt geht als zweites Bild an die KI, `cropImageRelative`), eine
  Textstelle bzw. eigene Anweisung vorgeben (vorbelegt aus der Textauswahl
  im PDF oder einer roten Markierung) und optional die erwartete Antwort.
  Bleibt alles leer, wählt die KI selbst das Wichtigste der Seite.
  **KI-Modell wechseln:** Über dem Knopf "Frage erstellen" steht das
  Modell, das gerade gilt (Standard: das Vision-Modell aus den
  Einstellungen); ein Tipp darauf öffnet die durchsuchbare Modellliste
  (nur Modelle mit Bildverständnis, mit Preis), "Standard" setzt zurück. Die
  Wahl gilt nur für dieses Fenster – die Einstellungen bleiben. Bei
  Tabellen, interaktiven Seiten, Bildfragen und sehr inhaltsreichen Seiten
  steht ein Hinweis, dass sich ein stärkeres Modell lohnt. In der Vorschau
  gibt es dasselbe Feld samt **"Neu"**: alle KI-Fragen mit dem gewählten
  Modell komplett neu erstellen (selbst erstellte Bildfragen bleiben) –
  "Überarbeiten" nutzt es ebenfalls. Dasselbe Feld gibt es in Nachbereiten
  ("KI erstellt" und "Fragen importieren", beim Import mit PDF nur Modelle
  mit Bildverständnis); die Zweitmeinung (Crosscheck) behält ihr Modell.
  Bewusst IMMER multimodal (Seiten-Screenshot ans Vision-Modell) statt
  optional umschaltbar – einfacher UND robuster, da Folienseiten oft
  Diagramme/Formeln enthalten, die reiner Text nicht wiedergibt. Die
  generierten Karten lassen sich vor dem Speichern eins zu eins wie im
  echten Quiz durchklicken (`QuestionAnswerView`, dieselbe Ansicht wie
  Daily Quiz/Üben statt einer reinen Textvorschau), per freier Anweisung
  ("einfacher formulieren", "anderer Fokus") überarbeiten und bei mehreren
  Fragen einzeln abwählen (Fragen-Chips oben in der Vorschau). Beim Speichern werden die Stufen einer Frage NICHT
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
  Datenbank nicht unnötig aufzublähen. Im Zweifel hängt die KI lieber ein
  Bild an – ein unnötiges lässt sich mit **"Bild entfernen"** wieder
  löschen: in der Vorschau, in der Kartenliste und direkt beim Lernen
  (Knopf oben rechts am Bild; nicht bei Bildfragen, die ihr Bild brauchen).
  Solche direkt beim Betrachten selbst erstellten Fragen tragen zusätzlich
  `Flashcard.priorityIntroduction = true`: sie umgehen damit das Einheiten-
  "behandelt"-Gate im DailyScheduler (eine bewusst JETZT gestellte Frage ist
  per Definition schon relevant, unabhängig davon, ob die zugehörige
  Vorlesungseinheit separat als "behandelt" markiert wurde) und werden beim
  Auffüllen des Tages-Budgets vor der reinen createdAt-Reihenfolge
  einsortiert – ohne das würde eine frisch gestellte Frage sonst hinter
  einem großen Altbestand noch nicht eingeführter Bulk-generierter Karten
  verschwinden und tagelang nicht im Daily Quiz auftauchen.

### 5e. "Im Skript" schon während der Aufgabe, nicht erst danach

Beim Lernen (Daily Quiz, Üben, Sprint, html-Fragen, Probeklausur-Durchsicht)
lässt sich das Original-Arbeitsblatt/Skript jetzt schon SEHEN, WÄHREND man an
der Aufgabe sitzt – nicht erst nach dem Antworten. Gerade bei aus einem
Übungsblatt importierten Fragen transkribiert die KI die Aufgabenstellung
nicht immer perfekt; der Button "Im Skript" (`SourceLinkButton` in
`lib/ui/study/study_aids.dart`) springt über `SourceLocator`/`openMaterialAt`
zur passenden Seite (exakt über `Flashcard.sourceMaterialId`/`sourcePage`,
sonst über eine Textsuche als Vermutung) und ist jetzt zusätzlich schon VOR
dem Beantworten sichtbar, sowie in der Durchsicht nach einer Probeklausur.
Bewusst ausgenommen bleibt die laufende Probeklausur selbst (`examMode`) –
wie in einer echten Klausur gibt es dort keine Hilfen während der Bearbeitung.

### 5f. Unsichere Fragen beim Import: Fragetyp-Fallback sichtbar statt stumm

Beim Import aus einer PDF (Altklausur/Übungsblatt, "Fragen aus PDF
importieren" und der Import-Modus in Vorbereiten/Nachbereiten) prüft die KI
je Frage der Reihe nach, ob sie sich sinngemäß in einen der bestehenden
Fragetypen (Auswahl, Lückentext, Zuordnen, Freitext) übernehmen lässt, sonst
ob sie sich als eigenständige interaktive **html**-Aufgabe nachbauen lässt,
und wählt erst als letzten Ausweg eine schlichte Karteikarte
(`_scanPdfQuestionsSystemPrompt`/`_importQuestionsSystemPrompt` in
`lib/services/ai_service.dart`). Ist die Antwort der KI für den gewählten
Typ unvollständig (z.B. eine Auswahlfrage ohne Optionen), wird das nicht mehr
still auf eine Karteikarte heruntergestuft: `QuestionParsing.
normalizeGeneratedFlashcard` markiert solche Einträge (`typeDowngraded` +
`requestedType`), die Vorschau zeigt sie mit einem Warnhinweis ("Unsicher:
sollte … sein"), und vor dem Speichern wird gefragt, wie damit verfahren
werden soll: trotzdem als Karteikarte speichern oder weglassen.

### 5g. Gewichtung: wichtige Aufgaben und Fächer öfter üben

Jede Karte und jedes Fach hat eine **Gewichtung** (Standard 1×). Sie bestimmt,
wie oft eine Frage drankommt: der Abstand bis zur nächsten Wiederholung wird
durch das Gewicht geteilt – eine 2×-Karte kommt also etwa doppelt so oft
wie eine 1×-Karte mit demselben Wissensstand. Der Wissensstand (Ampel) selbst
bleibt davon unberührt.

- **Standard beim Erstellen**: Fragen aus Vorlesungsfolien 1×, Aufgaben aus
  Übungsblättern 1,5× (PDF-Fragen-Import, Import-Modus in Nachbereiten,
  "Frage erstellen" und Zwischen-Check auf einem Übungsblatt).
- **Je Karte ändern**: Kartenliste → Karte aufklappen → "Gewichtung"
  (0× bis 3×; für mehrere Karten auf einmal: Auswählen → "Gewichtung
  setzen"). Abweichende Gewichte stehen in der Statuszeile ("1,5×
  gewichtet").
- **Ganz auf 0 = stummgeschaltet**: Zieht man den Regler einer Karte ganz
  nach links ("Aus"), kommt die Frage **nie mehr dran** – nicht im Daily Quiz
  (weder als neue noch als fällige Karte, auch nicht bei "Freiwillig
  weiterlernen"), nicht beim Üben, im Sprint, in der Probeklausur und bei den
  Schwachstellen. Sie zählt auch **nicht in Ampel und Statistik** (eine
  stumme rote Karte zieht die Ampel nicht runter) und hält die Stufen ihrer
  Gruppe (Leicht → Mittel → Schwer, siehe 5h) nicht auf: die nächste Stufe
  ist dann dran. Eine stumme Lernaufgabe steht nicht im Aufgaben-Ordner (5k).
  Die Karte bleibt in der Kartenliste ("Stummgeschaltet – kommt nie dran")
  und lässt sich dort jederzeit wieder einschalten; im Fach steht, wie viele
  stumm sind. Für das **Fach** geht der Regler weiterhin nur bis 0,5×.
- **Je Fach**: Fach bearbeiten → "Gewichtung". Ein höher gewichtetes Fach
  (z.B. Technik 2×) wirkt auf ALLE seine Karten (Karten- × Fach-Gewicht) und
  bringt im Daily Quiz zusätzlich mehr neue Karten pro Tag (höchstens 15, in
  den letzten 3 Tagen vor der Klausur weiterhin keine neuen).

Die Gewichtung gilt überall, wo Antworten verbucht werden (Daily Quiz, Üben,
Sprint, Probeklausur), und bleibt bei Export/Import und "Lernstand
zurücksetzen" erhalten.

### 5h. Leicht → Mittel → Schwer: erst die leichte Stufe, dann die nächste

Fragen zum selben Sachverhalt kommen nicht mehr alle gleichzeitig dran:

- **Nur die aktuelle Stufe wird gelernt.** Solange eine leichte Frage noch
  nicht grün ist (an 4 verschiedenen Tagen richtig), warten Mittel und Schwer.
  Sitzt Leicht, ruht sie und Mittel kommt dran, danach Schwer. Ist auch Schwer
  grün, bleibt nur sie in der Wiederholung (Spaced Repetition), die leichteren
  zählen in der Ampel als grün.
- **Fehlt eine Stufe**, rückt die nächste nach (z.B. direkt Schwer, wenn es
  kein Leicht gibt); gibt es kein Schwer, bleibt Mittel dauerhaft in der
  Wiederholung. Eine Frage ohne andere Stufen läuft ganz normal.
- **Welche Fragen zusammengehören – als Ordner sichtbar**: In der
  Kartenliste liegen zusammengehörige Fragen in einem zugeklappten Ordner.
  Darauf stehen der Name (was die Fragen abfragen), die schwerste Frage und
  der Stufenstand (✓ geschafft, ▶ gerade dran, 🔒 wartet). Aufgeklappt
  stehen die Fragen nach Leicht / Mittel / Schwer sortiert darunter. Über ⋮
  lässt sich ein Ordner umbenennen oder auflösen.
- **Woher die Ordner kommen**: neue Fragen aus Nachbereiten bekommen Ordner
  und Stufe direkt von der KI; "Frage erstellen" mit Leicht/Mittel/Schwer
  ist eine einzige Karte mit Stufen (aufgeklappt unter "Stufen dieser
  Frage" zu sehen). Für bereits vorhandene Karten gilt zunächst: gleiches
  Konzept = ein Ordner, Stufe aus dem Fragetyp (Auswahl leicht,
  Lückentext/Zuordnen mittel, Freitext/interaktiv/Tabelle schwer) – die
  Liste weist darauf hin, dass das ungeprüft ist. **"Per KI in Ordner
  sortieren"** (Menü der Kartenliste) geht alle Fragen des Fachs durch: in
  einen Ordner kommen nur Fragen, die wirklich dasselbe Wissen verschieden
  schwer abfragen – sonst würde eine leichte Frage zu früh aus dem Plan
  genommen. Die KI arbeitet in Portionen zu 80 Fragen und bekommt die
  Ordnernamen der vorigen Portionen mit, damit Zusammengehöriges auch
  portionsübergreifend in einem Ordner landet.
- Von Hand: "Stufe" an einer Karte; mehrere auswählen → "In Ordner legen"
  (vorhandener oder neuer Ordner) bzw. "Aus Ordner nehmen".
- Gilt im Daily Quiz, in Üben, Sprint und im Fehlertagebuch – nicht in der
  Probeklausur (die fragt je Ordner die schwerste Stufe, wie in der echten
  Klausur).

**Fehler-Leiter**: Geht eine Frage 2× in Folge schief, erscheint vor dem
Antworten automatisch eine KI-Hilfestellung; nach dem 3. Fehler eine zweite,
deutlichere. Beim 4. Fehler in Folge kommt die leichtere Stufe zurück in den
Plan (bei einer Stufenkette die vorige Stufe, sonst die leichteren Fragen
desselben Sachverhalts), bis sie wieder sitzt. Die Hilfestellungen werden an
der Karte gespeichert (auch offline wieder da). Richtig mit Hilfestellung
zählt, lässt die Ampel aber nicht steigen.

### 5i. Ampel je Fach und mehrere Karten auf einmal bearbeiten

- Auf der Startseite zeigt jedes Fach einen Balken mit den Anteilen gut
  (grün), mittel (gelb) und schwach (rot) seiner gelernten Karten, darunter
  die Prozente und wie viele noch neu sind.
- Kartenliste → Knopf "Mehrere auswählen" (oder lange auf eine Karte
  drücken): Karten ankreuzen (das Häkchen an einem Ordner wählt alle seine
  Fragen), dann über das Bearbeiten-Menü Gewichtung, Stufe, Ordner oder
  Einheit für alle setzen, den Lernstand zurücksetzen oder alle löschen.

### 5j. Fragetyp Tabelle: Tabellen direkt in der App ausfüllen

- Enthält ein Übungsblatt oder eine Folie eine auszufüllende Tabelle, legt
  die KI beim Import/Nachbereiten/"Frage erstellen" eine **Tabellen-Frage**
  an: vorgegebene Zellen werden angezeigt, die auszufüllenden sind
  Eingabefelder (die Lösung – mit Varianten, per `;` getrennt – ist
  hinterlegt). Breite Tabellen lassen sich seitlich scrollen.
- Prüfen je Zelle mit Tippfehler-Toleranz; lehnt der Abgleich eine Zelle ab,
  prüft die KI (mit API-Key) nach, ob sie trotzdem stimmt. Danach
  **Teilpunkte**: alle Zellen richtig = richtig, ab 80 % = "fast richtig"
  (zählt als *Schwer*, die Ampel steigt nicht), darunter = falsch. Falsche
  Zellen zeigen ihre Lösung.
- Tabellen zählen zur Stufe *Schwer*. In der Probeklausur zählt nur die
  komplett richtige Tabelle.
- Bearbeiten in der Kartenliste: jede Zelle ist ein Textfeld, das Schloss
  schaltet zwischen *vorgegeben* und *auszufüllen*; Zeilen/Spalten lassen
  sich anhängen und entfernen.
- KI-Format (auch für "JSON einfügen"): `"type": "table", "table": [["Kopf",
  "Kopf"], ["gegeben", {"answer": "Lösung; Variante"}]]` – statt des Objekts
  geht auch `"[[Lösung]]"`.

### 5k. Fragetyp "Lernen" und der Aufgaben-Ordner

Manche Aufgaben lassen sich in einer Quiz-App schlicht nicht prüfen:
zeichnen, entwerfen (Gantt-Diagramm, Netzplan …), programmieren, beweisen,
lange Rechen- und Herleitungswege. Dafür gibt es den Typ **"Lernen"**:

- Die KI übernimmt die Aufgabe **1:1 wie im Dokument** (alle Teilaufgaben und
  Zahlenwerte, nicht aufgeteilt; bei einem PDF-Import samt Ausschnitt der
  Seite) und schreibt dazu eine **Erklärung / den Lösungsweg** Schritt für
  Schritt (steht eine Musterlösung im Dokument, erklärt sie diese). Sie wählt
  den Typ nur, wenn keiner der prüfbaren Typen passt – auch nicht "Interaktiv".
  Beim "Frage erstellen" lässt er sich außerdem fest als Typ wählen.
- Im Lernen (Daily Quiz, Üben) steht die Aufgabe, ein Tipp deckt die
  Erklärung auf, dann bewertest du selbst, **wie gut du sie verstanden hast**:
  Unklar / Teilweise / Verstanden / Sicher (wirkt wie Nochmal / Schwer / Gut /
  Leicht auf den Lernplan). Lernaufgaben stehen für sich (keine
  Leicht/Mittel/Schwer-Ordner), kommen nicht in die Probeklausur und nicht in
  den Sprint (zu lang).
- **Aufgaben-Ordner:** Im Fach gibt es (sobald es solche Aufgaben gibt) den
  Knopf "Aufgaben-Ordner": alle Lernaufgaben des Fachs, dauerhaft
  einsehbar – geordnet nach Datei und Seite, mit Aufgabe, Erklärung, "Im
  Skript" (springt zur Stelle im Original) und Bearbeiten/Löschen, unabhängig
  vom Lernplan.
- **Rot vor der Klausur:** Ab **20 Tage** vor der Klausur (auch am
  Klausurtag, danach nicht mehr) wird der Ordner rot – der Knopf im Fach
  ("Klausur in 12 Tagen"), ein Hinweis auf der Fachkarte der Startseite und
  ein roter Kasten oben im Ordner: jetzt außerhalb der App durcharbeiten,
  z.B. auf Papier. Dafür braucht das Fach ein Klausurdatum.

### 5l. Frage erstellen: Typ-Vorgaben je Stufe

Statt bei jeder Stufe (Leicht/Mittel/Schwer) neu zu wählen, lässt sich der
Fragetyp je Stufe vorgeben – z.B. **Schwer = Freitext**:

- **Einstellungen → "Frage erstellen"**: je Stufe ein Typ oder "KI
  entscheidet" (wirkt sofort).
- Im Fenster "Frage erstellen" sind die Stufen damit vorausgewählt. **Von Hand
  ändern** geht vor dem Erstellen weiterhin – das gilt dann nur für dieses
  Mal. Mit **"Typ-Auswahl als Standard merken"** wird die aktuelle Wahl zur
  neuen Vorgabe. Welche Stufen eingeschaltet sind, bleibt wie bisher (Leicht
  an).
- Die Vorgaben reisen mit dem Sync auf andere Geräte.

### 5m. Skript-Abgleich: Erklärung im Skript statt nur im Übungsblatt

Fragen, die aus einem **Übungsblatt** erstellt wurden, verwiesen bei "Im
Skript" bisher nur auf das Blatt selbst – die Erklärung steht aber in den
Vorlesungsfolien. Jetzt gleicht die App die Fragen mit dem Skript ab:

- **Automatisch nach dem Erstellen** (Nachbereiten – Erstellen und Import,
  "Frage erstellen" im PDF-Viewer, PDF-Fragen-Import): Für Fragen aus einem
  Übungsblatt oder einer Altklausur sucht die KI im Skript des Fachs die Seite,
  auf der die Erklärung bzw. Lösung steht. Ein Hinweis unten zeigt Start und
  Ergebnis ("3 von 4 Fragen im Skript verortet"). Fragen direkt aus Folien
  brauchen das nicht.
- **Von Hand**: Kartenliste → Menü **"Erklärungen im Skript suchen"** für
  alle Karten des Fachs (auch ältere ohne bekannte Quelle). Mit dem Häkchen
  "Auch die schon gesuchten erneut prüfen" lässt sich eine frühere Suche
  wiederholen. In der Kartenliste steht an gefundenen Karten "Erklärung im
  Skript, S. N".
- **Wie gesucht wird**: lokal die fünf wahrscheinlichsten Folien (seltene
  Begriffe zählen mehr, Folien derselben Vorlesungseinheit werden bevorzugt),
  dann wählt die KI daraus die Seite – oder "keine passt". Das Ergebnis wird
  an der Karte gespeichert (`scriptMaterialId`/`scriptPage`); die Quelle
  (das Übungsblatt) bleibt erhalten.
- **Zwei Knöpfe**: Bei Fragen aus Übungsblättern heißt der Knopf vor dem
  Antworten **"Aufgabenblatt"** (die Aufgabe im Original), danach zusätzlich
  **"Im Skript"** (die Erklärung). Ist keine Erklärung bekannt, vermutet "Im
  Skript" die Stelle per Textabgleich; passt nichts, kommt der Hinweis "Im
  Skript keine passende Erklärung gefunden – hier ist das Übungsblatt."
- **Voraussetzungen**: OpenRouter-API-Key und Vorlesungsfolien als **PDF auf
  diesem Gerät** (nur die werden durchsucht). Ohne beides passiert beim
  Erstellen nichts, die Kartenliste erklärt, was fehlt.
- Fundstellen reisen mit dem Fach-Export/-Import und Sync mit.

### 5n. KI-Modell-Favoriten

Im Modellwähler (Einstellungen und "Frage erstellen") hat jedes Modell einen
**Stern**: markierte Modelle stehen im Wähler ganz oben unter "Favoriten"
(auch beim Suchen). Beim **Frage erstellen** erscheinen die Favoriten
zusätzlich als **Schnellwahl** unter dem Modell-Feld – ein Tipp wechselt das
Modell für diese Aktion, das Standard-Modell als Favorit setzt zurück auf
"Standard". Favoriten reisen mit dem Sync auf andere Geräte.

### 5o. Import: zweite KI prüft die Vollständigkeit, Schwierigkeitsstufen

Beim **Fragen-Import aus einem Dokument** – Nachbereiten → "Fragen
importieren" und "Fragen aus PDF importieren" (Fach → PDF) – gibt es vor dem
Start die Karte **"Genauigkeit und Schwierigkeit"** mit zwei Schaltern:

- **Zweite KI prüft die Vollständigkeit**: Nach dem Import liest eine zweite
  KI (das **Zweitmeinungs-Modell** aus den Einstellungen) den Text der
  PDF-Seiten selbst, zählt die dort stehenden Fragen/Aufgaben (Teilaufgaben
  einzeln) und gleicht sie mit den übernommenen ab. Sieht sie etwas anderes
  als die erste KI, **begründet sie jede Abweichung** (mit Zitat aus dem
  Dokument), und **du entscheidest**:
  - *Fehlt im Import* → **Ergänzen** (die erste KI liest diese eine Aufgabe
    gezielt nach) oder **Ignorieren**.
  - *Steht nicht im Dokument / doppelt / weicht ab* → **Entfernen** (im
    PDF-Import abgewählt, in Nachbereiten aus der Vorschau gelöscht) oder
    **Behalten**.
  Oben steht die Zählung ("Zweite KI zählt 12 Fragen im Dokument ·
  übernommen: 11"). Es wird nichts von allein geändert. Auch nachträglich
  möglich: in der Vorschau **"Jetzt prüfen"/"Erneut prüfen"**.
  Grenzen: nur PDFs mit Textebene bzw. OCR-Text (Seiten ohne lesbaren Text
  meldet die Prüfung als "nicht geprüft"); Word/PowerPoint-Dateien werden
  nicht geprüft; Bilder sieht die zweite KI nicht.
- **Verschiedene Schwierigkeitsstufen**: Zu jeder übernommenen Frage ergänzt
  die KI dasselbe Wissen in den gewählten Stufen (Leicht/Mittel/Schwer, per
  Chip abwählbar). Die **Original-Frage bleibt unverändert** und bekommt ihre
  Stufe; die ergänzten Fragen sind in der Vorschau gekennzeichnet ("Stufe
  Leicht · von der KI ergänzt") und einzeln abwählbar/löschbar. Original und
  Stufen teilen sich einen Ordner (siehe 5h): beim Lernen kommt erst die
  leichte Stufe, dann die nächste. Der Typ je Stufe folgt den Vorgaben aus
  Einstellungen → "Frage erstellen" (5l), sonst Auswahl → Lücke → Freitext.

In der Nachbereiten-Vorschau hat jede Karte jetzt außerdem einen
**Löschen-Knopf** (nimmt ergänzte Stufen mit).

### 6. Ausführen

**Am einfachsten zum Ausprobieren: im Browser**, kein Visual Studio/Android
SDK/Xcode nötig – nur Flutter + ein Chrome/Edge:

```bash
flutter run -d chrome
```

Web läuft mit derselben Codebasis (lokale Daten liegen dann im
IndexedDB des Browsers statt in einer Datei; die PDF-Anzeige nutzt dort
PdfJs, eingebunden in `web/index.html`). Für die Ziel-Plattformen:

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
(`flutter build windows`) und veröffentlicht sie unter Release
**"Windows-App (aktueller Stand)"** (Tag `windows-latest`) auf zwei Arten:

- **`Lernen-Setup.exe`** (empfohlen) – eine einzige Datei. Sie installiert
  die App nur für den eigenen Benutzer (keine Admin-Rechte) nach
  `%LOCALAPPDATA%\Programs\Lernen`, legt eine Startmenü- und auf Wunsch
  eine Desktop-Verknüpfung an und lässt sich unter "Apps" wieder
  deinstallieren. Gebaut mit Inno Setup aus `windows/installer/lernen.iss`.
  Beim ersten Start einer ungesignierten Datei zeigt Windows SmartScreen
  eine Warnung ("Weitere Informationen" → "Trotzdem ausführen").
- **`lernen-windows.zip`** – dieselbe App zum Entpacken (portable), die
  `lernen.exe` muss dann im Ordner neben ihren DLLs und dem `data`-Ordner
  bleiben.

Eine einzelne `.exe` ganz ohne Begleitdateien gibt es bei Flutter nicht –
die Engine (`flutter_windows.dll`), die Plugin-DLLs und `data/` werden zur
Laufzeit gebraucht. Das Setup versteckt diesen Ordner nur. Die Lerndaten
liegen ohnehin getrennt davon in `%APPDATA%` und bleiben bei Updates,
Neuinstallation oder dem Wechsel vom ZIP zum Setup erhalten.

### 5zk. Zustandsdiagramme (Zweistoffsysteme)

Neuer Aufgabentyp **„Zustandsdiagramm“** für Werkstoffkunde (z.B. Blei-Zinn,
Kupfer-Silber oder die Stahlecke des Eisen-Kohlenstoff-Diagramms):

- Die KI liest nur die **Eckdaten** ab: Schmelzpunkte, eutektischer
  (eutektoider) Punkt, maximale Löslichkeiten, bei Bedarf Zwischenpunkte
  gekrümmter Linien. Das Diagramm zeichnet und **rechnet die App selbst**.
- Teilaufgaben: **Phasen** an einem Punkt wählen, **Hebelgesetz** (die beiden
  Enden im Diagramm antippen, Anteile eintragen – Folgefehler aus falsch
  abgelesenen Werten werden erkannt), **Gefügeanteile** unter der eutektischen
  Temperatur, **Abkühlkurven** zeichnen (eine Kurve je Legierung, geprüft an
  Knicken und Haltepunkten), **Zusammensetzung** zu einer Liquidustemperatur,
  **maximale Löslichkeit**, **eutektische Linie**, **Gebiete benennen** und
  **Gebiet im Diagramm zeigen**.
- Ablesetoleranz 3 % der Achse, bei Anteilen 5 Prozentpunkte. Tipps in zwei
  Stufen, „Lösung zeigen“, Probeklausur ohne Rückmeldung.
- Übernehmen per Foto/Text („Aufgabe übernehmen“ → „Zustandsdiagramm“), aus dem
  ganzen Dokument oder per JSON-Import einer externen KI. Im Editor lassen sich
  alle Eckdaten und Teilaufgaben ändern; die Vorschau zeigt Diagramm und
  Musterlösung.
- Sync-Datenversion 3: Ein Gerät mit älterer App zeigt diese Aufgaben nur als
  Karteikarte (mit Musterlösung) und meldet, dass ein Update nötig ist.

### 5zj. Skizzen mit mehreren Kurven, Haltepunkten und Knicken

Der Typ „Diagramm skizzieren“ kann jetzt mehr:

- **Mehrere Kurven im selben Diagramm**, jede mit Namen und eigener Farbe
  (Abkühlkurven für 10/20/61,9/100 % Sn, Hall-Petch-Geraden für T₁/T₂ bzw.
  ε₁/ε₂, Härteverläufe für T₁ < T₂ < T₃, Streckgrenze und Bruchdehnung über der
  Glühtemperatur). Beim Lernen wählt man oben die Kurve und zeichnet sie.
- **Haltepunkt** (waagerechtes Stück bei einer Temperatur, z.B. 183 °C) und
  **Knick** (deutlicher Steigungswechsel, z.B. an der Liquidus) als Merkmale.
- **Vergleiche zwischen Kurven**: liegt über/unter, parallel verschoben,
  steiler als, Maximum früher bzw. höher als.
- Im Editor: „Weitere Kurve im selben Diagramm“, Name und Musterkurve je
  Kurve, bei jedem Merkmal die Kurve (und bei Vergleichen die zweite Kurve).
  Umbenennen nimmt die Merkmale mit.
- Eine einzelne Kurve wird wie bisher gespeichert – ältere App-Versionen
  zeigen auch Skizzen mit mehreren Kurven (dann nur mit der ersten).

### 5zi. Aufgaben von einer externen KI importieren (JSON)

Wer lieber ChatGPT, Gemini oder Claude.ai das Übungsblatt lesen lässt, kann
deren Ergebnis direkt importieren:

- **Import-Knopf** (⬆ „Aufgaben importieren“): in „Aufgabe übernehmen“ oben
  rechts und unter der Eingabe, im Aufgaben-Ordner und in „Fragen aus PDF
  importieren“ („JSON importieren“).
- **Prompt kopieren** → in die externe KI einfügen, Blatt anhängen. Der Prompt
  beschreibt dasselbe Format wie die App-KI (Rechenweg, Terminierung,
  Kristallgitter, Stückliste, Skizze, Zustandsdiagramm) und liefert für alles andere gleich die
  **fertige Quizfrage** mit (Auswahl, Lücken, Freitext, Tabelle, Zuordnen).
- **JSON-Datei hochladen** oder die Antwort einfügen. Auch eine Liste
  fertiger Fragen (Format aus „JSON einfügen“ im Nachbereiten) geht.
- Danach wie gewohnt: die App rechnet alles selbst nach. Fertige Fragen werden
  zusammen mit den Aufgaben gespeichert, „Ausprobieren“ zeigt sie wie im Quiz.
- **Auf Richtigkeit prüfen**: eine zweite KI (Modell „Gegenprüfung“) rechnet
  jede Aufgabe und Frage nach, meldet Fehler mit Erklärung und schlägt eine
  Korrektur vor („Korrektur übernehmen“ – die App prüft sie wieder selbst).
- **Vorlesung zuordnen**: wählt man eine Vorlesung (Folien-PDF des Fachs),
  bekommen die Aufgaben deren Einheit, und nach dem Speichern sucht die KI in
  genau dieser Vorlesung, wo die Lösung erklärt wird („Im Skript“). Ohne Wahl
  werden Aufgaben aus Übungsblättern wie bisher mit dem Skript abgeglichen.

### 5zh. Interaktive Aufgaben aus einem ganzen Dokument

Statt jede Aufgabe einzeln zu fotografieren, liest die KI ein ganzes
Übungsblatt (oder eine Altklausur) und macht daraus interaktive Aufgaben –
Rechenweg, Terminierung, Kristallgitter, Stückliste oder Diagramm-Skizze.
Man kann ihr sagen, welche: z.B. **„alle Mathe-Aufgaben als Rechenweg“**.

- **Wo**: im Fach unter „Fragen aus PDF importieren“ oben auf „Interaktive
  Aufgaben“ umschalten; im Menü (⋮) einer PDF „Interaktive Aufgaben daraus
  erstellen“; direkt nach dem Hochladen über „Interaktive Aufgaben“ in der
  Meldung; im Nachbereiten im Modus „Fragen importieren“ mit dem Schalter
  „Als interaktive Aufgaben“.
- **Wunsch und Art**: ein freies Feld „Welche Aufgaben?“ (leer = jede, die
  sich interaktiv machen lässt) und optional eine feste Art. Aufgaben, die
  nicht zum Wunsch passen, lässt die KI ganz weg.
- **Fortlaufend gelesen**: je zwei neue Seiten plus die Seite davor als
  Kontext – eine Aufgabe über den Seitenumbruch bleibt ganz, und keine wird
  doppelt übernommen. Ein fehlgeschlagener Abschnitt bricht den Rest nicht ab
  und steht als Hinweis oben.
- **Prüfen und speichern**: die Funde öffnen sich in „Aufgabe übernehmen“ –
  jede mit ihrer Seite („S. 3 · …“), ihrem Blatt (für „Im Aufgabenblatt
  ansehen“) und dem Seitenbild. Wie gewohnt: bearbeiten, abwählen, als normale
  Frage erstellen oder auf die Sammelliste „Noch nicht interaktiv“ setzen.
  Hochgeladene PDFs werden dafür als Übung im Fach abgelegt.

### 5zg. Zwei Geräte mit unterschiedlicher App-Version

Läuft auf einem Gerät noch eine ältere Version, kennt sie neue Aufgabentypen
(Stückliste, Skizze …) nicht: sie zeigt sie als Karteikarte und speichert sie
beim Lernen auch so. Jetzt:

- **Der Abgleich meldet es**: „Ein anderes Gerät hat zuletzt mit einer älteren
  App-Version abgeglichen – bitte dort aktualisieren“ (bzw. umgekehrt). Dafür
  trägt jeder Sync-Stand das Datenformat (`dataVersion`) mit.
- **Solche Karten werden repariert**: eine „Karteikarte“, die noch die Daten
  einer interaktiven Aufgabe enthält, ist beim nächsten Laden wieder die
  interaktive Aufgabe.
- **Nichts wird mehr gelöscht, nur weil die andere Version etwas nicht kennt**:
  fehlt im Cloud-Stand eine ganze Liste (z.B. „Noch nicht interaktiv“), weil
  die ältere Version sie nicht hochlädt, bleibt sie auf diesem Gerät erhalten.
- Kennt **diese** Version eine Aufgabe nicht (von einer neueren erstellt),
  steht im Quiz ein Hinweis „bitte aktualisieren“ statt einer stillen
  Karteikarte.

### 5zf. Diagramm skizzieren

Neuer Aufgabentyp **Diagramm skizzieren** für Aufgaben wie „Skizzieren Sie die
Längenänderung über der Temperatur (Sprung bei 911 °C)“, „Zeichnen Sie die
Spannungs-Dehnungs-Kurve mit R_p0,2, R_m und A“ oder „Skizzieren Sie die
Potentialkurve“. Die KI liefert beim „Aufgabe übernehmen“ die **Achsen**, eine
**Musterkurve** und die **Merkmale**, auf die es fachlich ankommt – geprüft wird
in der App, **grob statt pixelgenau**:

- **Zeichnen** mit Finger oder Maus direkt in die vorgegebenen Achsen (ein
  Sprung darf ein neuer Strich sein), **Rückgängig** / **Alles löschen**.
- **Markieren**: Kennwert wählen (z.B. R_m, A, r₀) und die Stelle antippen.
- **Prüfen** hakt jedes Merkmal ab: steigt/fällt/verläuft gerade in einem
  Bereich, Sprung nach unten/oben an einer Stelle („Der Sprung liegt bei ≈ 846
  statt bei 911“), Maximum/Minimum (auch „unter 0“), Anfang/Ende (Bruch),
  Annäherung an einen Wert (Asymptote), Asymmetrie („links steiler als
  rechts“) und Markierungen am richtigen Ort (am Maximum, am Ende, auf der
  Kurve vor dem Maximum …). Jede Rückmeldung nennt die Bedeutung („krz → kfz,
  dichter gepackt“).
- Danach erscheint die **Musterkurve grün gestrichelt** zum Vergleich.
  **Tipps** nennen die Merkmale nach und nach, „Lösung zeigen“ listet sie auf.
- Verlangt die Aufgabe zusätzlich „Erläutern Sie …“, legt die KI dafür einen
  **eigenen Freitext-Entwurf** an („Passt als normale Frage“).
- **Bearbeiten**: Achsen (von/bis, Beschriftung, Zahlen an/aus), Musterkurve als
  Punkte („x; y“, Leerzeile = neuer Strich), Merkmale mit Stelle, Toleranz und
  Rückmeldung. Die Vorschau zeichnet die Musterkurve und warnt, wenn sie ein
  eigenes Merkmal nicht erfüllt (dann stimmt Merkmal oder Kurve nicht).

### 5ze. Stücklisten aus dem Erzeugnisbaum

Neuer Aufgabentyp **Stückliste** (Produktionsmanagement): aus einem
Erzeugnisbaum die **Mengenübersichts-**, **Struktur-** oder
**Baukastenstückliste** (auch „Baustellen-“/„Baustückliste“) aufstellen. Die KI
liest beim „Aufgabe übernehmen“ **nur den Baum** ab (Sach-Nr., Bezeichnung,
Menge an jeder Verbindungslinie, Einheiten wie g/kg) – **die Listen rechnet die
App selbst**, auch wenn eine Baugruppe mehrfach vorkommt.

- **Üben**: die App zeichnet den Baum mit Stufen und Mengen. Breite Bäume
  erscheinen erst verkleinert ganz; „Vergrößern“ zeigt sie in voller Größe mit
  Scrollleiste (seitlich wischen oder mit der Maus ziehen). Beim Übernehmen von
  einem Foto/einer Seite hängt das Original an – der Baum vom Aufgabenblatt
  steht dann über dem gezeichneten (antippen = groß). Ein Teil im Baum
  **antippen** trägt es als neue Zeile ein (oder „Zeile hinzufügen“), dann Stufe,
  Menge und – bei der Baukastenstückliste – das **AK** (1 = eigene Stückliste,
  2 = keine) eintragen. Bei der Baukastenstückliste legt man die nötigen Listen
  selbst an („Liste anlegen“); sind im Blatt Formulare vorgegeben, sind sie schon da.
- **Prüfen** markiert jede Zeile grün oder rot, mit konkreter Rückmeldung:
  „Menge nicht multipliziert – entlang des Pfads alle Mengen malnehmen“,
  „kommt 3-mal im Baum vor – alle Vorkommen zusammenzählen“, „In der
  Strukturstückliste steht die Menge je übergeordnete Baugruppe, nicht die
  Gesamtmenge“, „kein direkter Bestandteil – nur eine Stufe tief“, „AK: hat
  eine eigene Stückliste → AK 1“, „steht an der falschen Stelle“ (eine
  vergessene Zeile macht nicht alle folgenden falsch), dazu was noch fehlt
  („Es fehlt noch 1 Liste“).
- **Tipps** (gestuft, der letzte nennt die Zeilenzahl bzw. die nötigen Listen),
  **Lösung zeigen** als fertige Tabelle; Bewertung wie bei den anderen Aufgaben.
- **Bearbeiten**: der Baum als Text, eine Zeile je Teil wie in der
  Strukturstückliste (`Stufe; Sach-Nr.; Bezeichnung; Menge; Einheit`), dazu,
  welche Listen gefragt sind (Mengenübersicht mit/ohne Baugruppen,
  Strukturstückliste mit Gesamtmengen, vorgegebene Baukasten-Formulare) – mit
  gezeichnetem Baum und Musterlösung als Vorschau. Unsicher gelesene Zahlen sind
  gelb und werden vor dem Speichern bestätigt.

### 5zd. Meldungen beim Rechenweg verstehen: KI fragen und korrigieren lassen

Findet die App beim Nachrechnen eines Rechenwegs etwas (z.B. „„8,63·10⁻⁹“ ist
als typischer Fehler hinterlegt, ist aber in Wahrheit richtig“), steht in der
Prüf-Box der Knopf **„Was heißt das? KI erklären & prüfen lassen“**. Die KI
erklärt jede Meldung in einfachen Worten – *ist die Aufgabe bzw. Musterlösung
falsch, nur eine hinterlegte Fehler-Rückmeldung, oder ist es harmlos?* –,
rechnet selbst nach und schlägt bei Bedarf eine **Korrektur** vor. Die App
rechnet die Korrektur wieder selbst nach („keine Unstimmigkeiten mehr“) und
übernimmt sie erst auf Knopfdruck. Unten im Fenster kann man **nachfragen**
(„Ist meine Aufgabe jetzt falsch?“); das Gespräch bleibt dabei erhalten. Zur
Einordnung: „typische Fehler“ sind absichtlich falsche Antworten, die Lernende
oft geben, mit eigener Rückmeldung – sie gehören nicht zum Lösungsweg.

### 5zc. Übersichtlicher: erstellte Aufgaben markiert, Bilder zuschneiden und groß ansehen

- **Schon erstellte Aufgaben im PDF markiert**: nach „Frage erstellen“ (bzw.
  „Interaktiv üben“) markiert der PDF-Viewer die Stelle blau – die ausgewählte
  Textstelle oder, wenn nur „Aufgabe 1a“ eingetippt wurde, die passende Zeile
  der Seite (Überschrift „Aufgabe 1“ → Teilaufgabe „a)“) – und speichert das
  gleich mit. Über dem PDF steht „✓ N Fragen aus dieser Seite erstellt“
  (antippen zeigt sie), und „Frage erstellen“ zeigt oben, was es aus der Seite
  schon gibt, und warnt, wenn man dieselbe Aufgabe noch einmal eintippt. Die
  Markierung erscheint in „Meine Markierungen“ als „Frage erstellt“ und lässt
  sich dort entfernen; für die KI zählt sie nicht als inhaltliche Markierung.
- **Fach-Seite aufgeräumt**: „Aufgabe interaktiv übernehmen“ ist jetzt Teil von
  „Frage erstellen“ im PDF (Knopf „Interaktiv üben“, für alle Materialarten),
  die Liste „Noch nicht interaktiv“ steht in den Einstellungen (alle Fächer,
  nach Fach filterbar), der **Speedrun** liegt im Nachbereiten (oben rechts).
- **Bild zuschneiden**: im Bild-Editor neben Abdecken und Text das Werkzeug
  „Zuschneiden“ – Rahmen um den Teil ziehen, der bleiben soll (verschieben,
  Größe ändern, „Zuschnitt aufheben“); Stellen/Bereiche von Bildfragen wandern
  mit, was außerhalb liegt, fällt weg.
- **Bild groß ansehen**: Bilder in Fragen und Aufgaben (Quiz, Rechenweg,
  Kristallgitter) antippen öffnet sie bildschirmfüllend zum Zoomen; bei
  Bildfragen (beschriften/markieren) über „Bild groß ansehen“.

### 5zb. Kristallgitter im Würfel und die Sammelliste „Noch nicht interaktiv“

Neuer Aufgabentyp **Kristallgitter**: Richtungen und Ebenen im kubischen
Einheitswürfel (kubisch primitiv, krz, kfz). Wie bei Rechenweg und Terminierung
liefert die KI nur die Indizes – **gezeichnet und geprüft wird in der App**:

- **Richtung einzeichnen** `[u v w]`: Startpunkt antippen, dann Zielpunkt. Die
  Rückmeldung erkennt „genau andersherum“, ein falsches Vorzeichen auf einer
  Achse und einen verschobenen Ursprung (bei negativen Indizes nötig).
- **Richtungsfamilie** `⟨u v w⟩`: alle Richtungen der Familie als eigene Pfeile
  (z.B. 6 bei ⟨1 0 0⟩) – doppelte und nicht dazugehörige werden gemeldet.
- **Ebene einzeichnen** `(h k l)`: drei Punkte antippen **oder**
  Achsenabschnitte wählen (1, ½, ∞). Eine parallele Ebene an anderer Stelle
  wird als solche erkannt („ergeben (2 2 0)“).
- **Richtung / Ebene ablesen**: die App zeichnet, man tippt die Indizes ein
  (Minus = Strich über der Zahl); ungekürzte Antworten zählen mit Hinweis.
- **Atome in der Ebene markieren** (z.B. kfz (1 1 1): 3 Ecken, 3 Flächenmitten).

Die **Live-Anzeige** ist standardmäßig an: beim Zeichnen steht sofort darunter,
was die eigene Eingabe ergibt („Ziel − Start = (1, 1, 1) → [1 1 1]“ bzw.
Achsenabschnitte → Miller-Indizes). Sie lässt sich je Aufgabe ausschalten; in
der Probeklausur ist sie aus. Der Würfel lässt sich drehen (Ziehen oder ◀ ▶),
ein Schalter blendet das ½-Raster ein. Gestufte **Tipps** nennen konkrete Punkte
bzw. Achsenabschnitte; „Lösung zeigen“ zeichnet die Musterlösung grün
gestrichelt ein. Bewertung wie bei den anderen Aufgaben: ohne Fehler und Tipps
gewusst, sonst „Schwer“, mit Lösung bzw. „Auflösen“ nicht gewusst. Am breiten
Bildschirm steht die Aufgabe links, der Würfel rechts. Bearbeiten in der
Kartenliste: Gitter, Art und Indizes je Teilaufgabe, mit gezeichneter Vorschau
und Hinweis, wenn sich etwas nicht zeichnen lässt (dann „ablesen“ statt
„einzeichnen“).

**Mehrere Teilaufgaben von einem Foto**: der Import interaktiver Aufgaben macht
aus einem Übungsblatt-Foto jetzt **jede Teilaufgabe zu einem eigenen Entwurf**
(z.B. 1b Rechenweg, 2a Kristall-Richtungen, 3a Ebenen …). Jeder Entwurf hat
seinen Editor, eine Häkchen-Box zum Mitspeichern und „Ausprobieren“;
„N Aufgaben speichern“ speichert alle angehakten auf einmal. Die Art lässt sich
vorgeben (Automatisch / Rechenweg / Terminierung / Kristall / Stückliste / Skizze) oder je Teilaufgabe
neu versuchen („Als Kristallgitter“ …).

**Passt als normale Frage**: Ist eine Teilaufgabe eigentlich eine ganz normale
Quizfrage (kurze Erklärung, Zuordnung in eine Tabelle, Auswahl, Bild markieren …),
erkennt die KI das und schlägt den passenden Fragetyp vor („Passt als normale Frage
(Freitext)“) – ein Tipp auf **„Als normale Frage erstellen“** legt sie an, statt sie
auf die Sammelliste zu setzen. Mit Foto sieht die KI dabei das Bild der Aufgabe (oft
stehen Tabellen oder Kriterien nur dort), sonst nur den Text. Klappt es trotzdem
nicht, setzt **„Auf die Liste setzen“** die Aufgabe selbst auf die Sammelliste –
auf Wunsch mit der fehlenden Bedienart als Gruppe (z.B. „Kriterien-Tabelle
ankreuzen“). Den Knopf gibt es auch bei unvollständig erkannten Aufgaben. Fehlende Tabellenwerte (z. B. eine Streckgrenze zum
Nachschlagen) nimmt die KI sinnvoll an und schreibt „angenommen: …“ dazu.

**Sammelliste „Noch nicht interaktiv“**: Teilaufgaben, die die App (noch) nicht
selbst prüfen kann, landen **automatisch** auf einer Liste – mit der Begründung
der KI und der **fehlenden Bedienart** in wenigen Wörtern („Kurve in Diagramm
zeichnen“, „Netzplan zeichnen“ …). Die Liste steht **in den Einstellungen**
(„Noch nicht interaktiv“ → „Liste öffnen“, alle Fächer zusammen, oben nach Fach
filterbar; auch im „Aufgabe übernehmen“-Bildschirm oben rechts erreichbar): die
Aufgaben sind nach fehlender Bedienart
gruppiert (häufigste zuerst), **„Liste kopieren“** legt alles als Text in die
Zwischenablage – zum Einfügen und Weiterschicken, damit man sieht, welcher
Aufgabentyp als Nächstes am meisten bringt. Einträge lassen sich einzeln
löschen, alle auf einmal leeren oder „Interaktiv versuchen“. **„Fragen dazu
erstellen“** (je Aufgabe oder alle auf einmal) legt sie trotzdem als Karten an –
wie beim Fragen-Import meist als Lernaufgabe mit ausführlichem Lösungsweg, ohne
Prüfung durch die App; die Aufgabe bleibt mit „✓ Frage erstellt“ auf der Liste,
weil die Bedienart ja weiter fehlt. Wird eine gesammelte
Aufgabe doch noch interaktiv gespeichert, verschwindet sie von der Liste. Die
Liste wird mit synchronisiert und beim Löschen des Fachs mit gelöscht.

### 5za. Rechenwege und Terminierung interaktiv üben

*Zahlen werden relativ geprüft*: auch sehr kleine Ergebnisse (z.B.
Diffusionskoeffizient 5,8·10⁻⁹ cm²/s) werden genau verglichen – „0“ oder ein
falscher Exponent zählt nicht als richtig, gerundete Werte in
Zehnerpotenz-Schreibweise („5,8*10^-9“, mindestens zwei gültige Ziffern) schon.

Zwei neue Aufgabentypen, bei denen **die App selbst nachrechnet** – die KI
liefert nur die Struktur und die erwarteten Antworten:

- **Rechenweg** (z.B. Differentialgleichungen, Integrale, Werkstoff- oder
  BWL-Rechnungen): **Schritt für Schritt** – je Schritt eine Auswahl oder ein
  Formelfeld (`-1/u`, `x - sqrt(12 - 2*x)`, `pi*sqrt(3)/8` …, mit Hilfstasten
  und „So lese ich es“-Vorschau). Jede gleichwertige Schreibweise zählt, bei
  Integrationskonstanten jede Form derselben Lösungsschar. Typische Fehler
  bekommen eine eigene Rückmeldung („Prüf den Vorfaktor“, „Die Konstante C
  fehlt“), dazu gestufte **Tipps** und „Schritt zeigen“. Oder **Nur Ergebnis**:
  auf Papier rechnen, Ergebnis eintippen – die **Probe** (DGL und Anfangswert
  an mehreren Stellen eingesetzt) zeigt, wo es nicht passt. Wer auf Papier
  gerechnet hat, kann den Rechenweg **fotografieren und prüfen lassen**: die KI
  liest Zeile für Zeile und markiert Fehler und Folgefehler, das Endergebnis
  rechnet die App selbst nach; ab dem ersten Fehler geht es in der App Schritt
  für Schritt weiter.
- **Terminierung** (Vorwärts-/Rückwärtsterminierung): Balken im
  **Gantt-Diagramm** setzen (Tag antippen, mit ◀ ▶ / Ziehen / Pfeiltasten
  verschieben), Start, Ende, Liegezeiten bzw. Puffer eintragen („Start/Ende aus
  Diagramm“ übernimmt die eigenen Balken). Rückmeldung **sofort** oder **erst am
  Ende**; **Folgefehler** werden erkannt (passt zum eigenen Diagramm, obwohl
  davor etwas falsch war). Tipp, Lösung zeigen mit „So rechnet man“, und
  „Mit anderen Zahlen üben“. Zählweise wie im Skript (Tage einschließlich oder
  Zeitpunkte). Am breiten Bildschirm: Aufgabe links, Diagramm rechts.

**Aufgabe übernehmen**: im PDF-Viewer unter „Frage erstellen“ der Knopf
„Interaktiv üben (Rechenweg, Terminierung, Kristall)“ (aktuelle Seite als Bild,
Fokus-Text bzw. markierter Text wie „Aufgabe 1a“) oder im Aufgaben-Ordner
„Interaktiv üben“ an jeder Aufgabe (Text, Erklärung, Bild und Quelle vorbelegt). Aufgabentext und/oder Fotos eingeben (bei
einem Seitenfoto reicht „Aufgabe 2b“), optional die vorhandene Lösung. Die KI
schlägt die Aufgabe vor, die App prüft die Musterlösung sofort („Musterlösung
von der App nachgerechnet“ oder die gefundenen Unstimmigkeiten) bzw. rechnet
die Terminierung selbst aus. Alles ist bearbeitbar (Schritte, erwartete
Antworten, Teile, Dauern, Termine, Zählweise, was gefragt ist), „Ausprobieren“
zeigt die Aufgabe wie im Quiz. Passt eine Aufgabe nicht (z.B. Zeichnen), sagt
die KI warum – man kann es trotzdem als Rechenweg, Terminierung oder
Kristallgitter versuchen (mehrere Teilaufgaben und Sammelliste: Abschnitt 5zb).
Gespeicherte Aufgaben kommen bald im Lernplan dran, zählen in der Probeklausur
(dort nur das Ergebnis, ohne Hilfen) und lassen sich in der Kartenliste
bearbeiten.

### 5z. Vorlesung kürzen (anhand von Übungsaufgaben)

Aus einer **schon hochgeladenen Vorlesung** wird eine gekürzte Fassung, die nur
noch enthält, was man für bestimmte Übungsaufgaben braucht – mit allen
Erklärungen dazu, ohne den Rest. Einstieg: im Fach **„Vorlesung kürzen“** (unter
„Material hochladen“), im Menü einer Folie **„Kürzen …“** oder beim Vorbereiten
die Karte **„Vorlesung kürzen“**.

1. **Vorlesung wählen**, **Übungsaufgaben** hochladen oder aus dem Fach wählen
   (optional – ohne Aufgaben richtet sich die KI nur nach dem Auftrag) und den
   **Auftrag** eingeben, z.B. „Alles, was man braucht, um diese Übungsaufgaben
   zu lösen“. Die **Strenge** (Knapp / Ausgewogen / Großzügig) steuert, wie
   viel Zusammenhang mitkommt.
2. Die KI wertet zuerst die Aufgaben aus („was muss man können?“) und geht dann
   die Vorlesung **abschnittsweise durch** (Rolling-Kontext: spätere Abschnitte
   wissen, was schon erklärt ist, was noch fehlt und welche Überschriften schon
   behalten wurden). Sie **schreibt nichts um**: die Vorlesung ist in Blöcke
   zerlegt, die KI nennt nur die Kennungen der Blöcke, die bleiben – das
   gekürzte Dokument besteht also immer aus dem Originaltext, es kann nichts
   erfunden werden.
3. **Vorschau**: wie viele Seiten bleiben („3 von 40 Seiten, 8 %“), die
   behaltenen Abschnitte mit Begründung (einzeln abwählbar), was weggelassen
   wurde, und was **die Vorlesung nicht erklärt** („für Aufgabe 3 fehlt die
   Laplace-Transformation“). Zwei Schalter wirken sofort, ohne neue
   KI-Anfrage: **Beispielaufgaben der Vorlesung mitnehmen** (die Erklärungen
   bleiben in jedem Fall) und **Markierungen setzen**.
4. **Speichern** legt im Fach ein Material „<Name> – gekürzt.pdf“ ab: eine PDF
   mit nur den behaltenen Seiten – auf Wunsch mit einem **gelben Streifen dort,
   wo der relevante Teil auf der Seite beginnt** (und klein in der Ecke „Original:
   S. 12“, damit man mit dem Skript abgleichen kann) – plus die **Textfassung**
   (Menü „Text ansehen und kopieren“). Bei einer Vorlesung ohne PDF auf diesem
   Gerät (oder PowerPoint/Word) entsteht nur die Textfassung.

Gescannte Seiten ohne Textebene liest die App vorher per KI (Texterkennung), die
Markierungen entfallen dort mangels Text. Das gekürzte Dokument zählt nicht als
Skript (keine Doppelung im Frage-Chat und bei der „Im Skript“-Suche).

### 5y. Zweite Code-Analyse (Oktober 2026)

Neue Durchsicht der Erweiterungen seit der ersten Analyse (Rechnen mit der KI,
Berichtsentwurf, Laborfach und Fotos, Überspringen/Auflösen, Formelsammlung,
Sync mit Zusammenführen). **Kein hoher oder blockierender Befund**; fünf kleine
Befunde sind behoben und haben Regressionstests (Nr. 52–56 in `CODE_ANALYSE.md`):

- Fehlermeldungen des Rechners zeigen einen sehr langen Ausdruck nur gekürzt.
- Ein Fragetyp ohne KI-Namen wirft nicht mehr, wenn eine Karte befördert wird.
- Fotos auslesen: Liefert die KI die Zellen in falscher Form, kommt der Rest
  des Fotos (Beschreibung, Notizen, Zuordnung) trotzdem an.
- **Fotos zu gelöschten Versuchen** (auf einem anderen Gerät gelöscht oder durch
  eine Wiederherstellung entfernt) werden nach dem Abgleich aufgeräumt statt als
  unsichtbarer Speicher liegen zu bleiben.
- Rechnen und Berichtsentwurf melden auch unerwartete Fehler.

Neu ist außerdem ein Wächter-Test, der prüft, dass keine Kopier-Methode einer
Karte ein Feld verliert. Die offenen Hinweise (Zusammenführen je Eintrag statt
je Feld, Fotos nur lokal, Dezimalkomma im Ausdruck) stehen am Ende von
`CODE_ANALYSE.md`.

### 5x. Formelsammlung aus Vorlesungen (Grob / Mittel / Fein)

Im **Vorbereiten-Modus** gibt es neben "Kurz" und "Ausführlich" den dritten Weg
**Formelsammlung erstellen**: Folien hochladen (oder "Vorhandenes Material
verwenden"), **Genauigkeit wählen**, die KI sammelt die Formeln und Regeln. Das
Ergebnis liegt im Fach unter **Zusammenfassungen** (Funktions-Symbol,
"Formelsammlung · Mittel · 14 Formeln").

Die KI ordnet jeden Eintrag einer Stufe zu – die Genauigkeit entscheidet dann,
welche sichtbar sind (am Beispiel Integralrechnung):
- **Fein** – alles, was man braucht: der Stoff selbst (Stammfunktionen,
  Integrationsregeln, partielle Integration, Substitution) **plus** die Regeln aus
  früheren Themen (Produkt-, Ketten-, Quotientenregel) **plus** die elementaren
  Rechenregeln (Bruch-, Potenz-, Wurzel-, Logarithmusgesetze, binomische Formeln).
- **Mittel** – die Rechenregeln fallen weg, der Rest bleibt (also auch die
  Ableitungsregeln, weil man sie für partielle Integration und Substitution braucht).
- **Grob** – auch die Ableitungsregeln fallen weg, **solange sie nichts Neues
  sind**: führen die Folien eine Regel selbst neu ein, bleibt sie auch bei Grob.

**Alles wird gespeichert, die Genauigkeit ist nur die Ansicht:** über dem Inhalt
steht der Umschalter Grob/Mittel/Fein ("3 von 5 Formeln"), du kannst jederzeit –
auch Wochen später – umstellen, ohne die KI noch einmal zu fragen (die Wahl wird
gespeichert). Die Formeln werden als LaTeX gesetzt.
- **Ergänztes ist markiert:** Was nicht in den Folien steht, sondern von der KI als
  Standardregel ergänzt wurde (vor allem Hilfs- und Rechenregeln), trägt die Marke
  "ergänzt – bitte prüfen". Die KI soll nur allgemein bekannte, sichere Regeln
  ergänzen und nichts erfinden – prüfen solltest du trotzdem.
- **Bearbeiten:** Stift-Symbol → jeden Eintrag ändern (Name, LaTeX mit Vorschau,
  Hinweis, "gehört zu" Kernstoff/Hilfsregel/Rechenregel), löschen oder je Abschnitt
  "Formel hinzufügen". Änderungen werden sofort gespeichert; der Titel lässt sich
  ändern ("Fertig").
- **Kopieren:** Knopf oben rechts legt die Sammlung bei der gewählten Genauigkeit
  als Markdown mit `$$…$$` in die Zwischenablage (zum Einfügen in ein Dokument).
- Lange Foliensätze werden abschnittsweise verarbeitet und zusammengeführt (gleiche
  Formeln nur einmal); es gilt das Fragen-Modell aus den Einstellungen. Die
  Sammlung reist mit dem Cloud-Sync und dem Fach-Export.

### 5w. Fragen überspringen und auflösen

Im **Daily Quiz**, in **Üben** (auch beim Üben aus dem Fehlertagebuch) und im
**Sprint** gibt es unter jeder Frage zwei Knöpfe (nicht in der Probeklausur – die
hat ihr eigenes "Überspringen", das sofort als falsch zählt):
- **Überspringen** – die Frage wird weggelegt, **nichts wird verbucht** (kein
  Lernstand, keine Ampel). Sie kommt am **Ende** der Runde noch einmal dran: im
  Daily Quiz nach der Hauptrunde und vor der Wiederholungsrunde ("⏭ Übersprungen ·
  noch N"), in Üben und Sprint ganz hinten in der Runde. Wieder überspringen legt
  sie erneut nach hinten; bei der letzten übrigen Frage gibt es den Knopf nicht
  mehr (sie käme sofort wieder).
- **Auflösen** – wer eine Frage gar nicht beantworten will: die richtige Lösung
  erscheint sofort (Optionen, Lücken, Tabellenzellen, Stellen im Bild, Zuordnung,
  Rückseite der Karteikarte), die Frage **zählt als falsch** (wie eine falsche
  Antwort: Ampel, Wiederholungsrunde, Fehler-Leiter). Es gibt keine KI-Prüfung und
  kein "Als richtig werten"; die Erklärung der KI steht danach wie sonst bereit.

### 5v. Laborfach-Schalter und Fotos zu Versuchen

**Laborfach.** Beim Anlegen (und später unter "Fach bearbeiten") gibt es den
Schalter **Laborfach**. Nur dann zeigt das Fach den Abschnitt **Laborversuche**
(Versuche, Fotos, "Rechnen mit KI"); ohne den Schalter bleibt das Fach schlank,
und Kalender sowie Startseiten-Hinweise für Versuche tauchen dort nicht auf.
Ältere Fächer zählen als normales Fach – hat eines schon Versuche, bleibt der
Abschnitt sichtbar. Der Schalter reist mit Sync und Fach-Export (ein importiertes
Fach mit Versuchen wird zum Laborfach).

**Fotos zuordnen & auslesen** (`lib/ui/lab/lab_photos_screen.dart`) – im Fach
unter Laborversuche ("Fotos zuordnen & auslesen", sobald es einen Versuch gibt)
und im Reiter *Durchführung* eines Versuchs ("Fotos auslesen"; dann geht es nur
um diesen Versuch). Bis zu 10 Fotos auf einmal (Messprotokoll, Geräteanzeige,
Notizen, Tafel). Je Foto fragt die App das **Bild-Modell**: es erkennt, was zu
sehen ist, ordnet es einem **Versuch und Versuchsteil** zu (Titel, Größen,
Einheiten, Spalten der Tabellen; unsicher → keine Zuordnung, die du dann selbst
wählst) und liest die Werte in die **leeren Messwertfelder** ab. Weitere Werte
(Einstellungen, Skalen) kommen als Notiz in den Teil, Unleserliches wird nur
gemeldet, nichts wird erfunden.
- **Du entscheidest:** Versuch und Teil sind per Auswahl änderbar, jeder
  erkannte Wert hat ein Häkchen; ersetzt ein Wert etwas, das du schon eingetragen
  hast, steht das dabei. Erst "Übernehmen" (oder "Alle übernehmen") schreibt in den
  Versuch. Ändert man das Ziel gegenüber der KI, gehen die Werte als Notiz in den
  Teil (die Nummerierung der KI passt dann nicht zu den Tabellen).
- **Fotos bleiben beim Versuch:** abgelegt als Streifen im Reiter *Durchführung*
  (Antippen = groß mit Zoom, Löschen). Die Bilder liegen **nur auf diesem Gerät**
  (eigener Speicher, nicht im Cloud-Sync und nicht im Fach-Export); die
  ausgelesenen Werte stehen im Versuch und reisen mit. Wird ein Versuch oder das
  Fach gelöscht, verschwinden auch seine Fotos.
- Gelesene Werte lassen sich danach mit "Rechnen mit KI" weiterverwenden.

### 5u. Rechenaufgaben an/aus, Modell für Erklärungen, Formeln überall

**Schalter "Rechenaufgaben"** – oben im Daily Quiz, in "Üben" (vor dem Start)
und im Sprint: **an** am Schreibtisch, **aus**, wenn gerade kein
Taschenrechner zur Hand ist (Handy im Bett). Der Schalter gilt nur auf diesem
Gerät (am PC an, auf dem Handy aus – wird nicht synchronisiert).
- **Was als Rechenaufgabe zählt:** beim Erstellen und Importieren markiert die
  KI jede Frage (`"calc": true/false` – echtes Rechnen mit Taschenrechner, nicht
  2·3 oder eine Formel nennen). Für ältere Karten ohne Markierung erkennt die App
  es am Text (`lib/services/calc_task_detector.dart`): eine Rechenaufforderung
  ("Berechne", "Wie groß ist …") oder eine Zahl mit Einheit als Lösung, dazu
  mehrere echte Größen in der Aufgabe (Zahlen mit Einheit, Kommazahlen,
  Zehnerpotenzen). In der Kartenliste steht "Rechenaufgabe" dabei; in
  "Bearbeiten" lässt es sich je Karte festlegen (Automatisch / Ja / Nein).
- **Aus:** Rechenaufgaben kommen im Daily Quiz nicht dran (auch nicht in der
  Wiederholungsrunde und bei "freiwillig weiterlernen"); die App merkt sich, welche
  heute dran gewesen wären ("3 Rechenaufgaben heute aufgehoben").
- **Wieder an:** aufgehobene Rechenaufgaben kommen **zuerst und zusätzlich** zum
  normalen Tagesbudget dran (höchstens 10 extra je Fach und Tag), überfällige
  Wiederholungen ohnehin. In "Üben" stehen sie vorne. Beim Beantworten verschwindet
  die Markierung "aufgehoben". Die Probeklausur nimmt bewusst immer alles.

**Modell für Erklärungen & Hilfe** – Einstellungen → KI-Modelle: eigener Eintrag
"Erklärungen & Hilfe". Ohne Wahl gilt das Fragen-Modell; wählst du dort dasselbe,
folgt es ihm wieder (Rückgängig-Knopf). Gilt für "Erklär mir das", Tipps, Rückfragen
im Quiz, Lerneinheit, Sokrates-Dialog, Frage-Chat, Fehlertagebuch und das
Gegenlesen im Laborversuch; Antwortprüfung (Freitext, Lücken) und Fragenerstellung
bleiben beim Fragen-Modell, Bild-Fragen beim Vision-Modell. Reist mit dem Sync.

**Formeln (LaTeX) überall:** auch in Zuordnen-Begriffen, Kategorien, Optionen und
Lösungen der Kartenliste, Konzepten, Zusammenfassungen, Vorschauen beim Erstellen,
Probeklausur- und Fehlertagebuch-Listen, Seitennotizen, Rückfragen und im
Laborversuch. Außerdem erkennt die App Formeln, bei denen die KI die Dollarzeichen
vergessen hat ("Es gilt U = R \cdot I"), Formeln in Backticks und `$ … $` mit
Leerzeichen; `\frac`, `\beta`, `\theta` u.ä. ohne Dollarzeichen werden beim Einlesen
nicht mehr zu Steuerzeichen.

### 5t. Rechnen mit KI und Berichtsentwurf (Laborversuch)

**Rechnen mit KI** (`lib/ui/calc/calc_screen.dart`) – erreichbar im
Laborversuch (Durchführung: Knopf **"Rechnen mit KI"** je Versuchsteil und
**"Rechnen"** je Auswertungsaufgabe; die Messwerte des Teils stehen dann schon
im Werte-Feld) und im Fach (Abschnitt Laborversuche: **"Rechnen mit KI (Werte
oder Bilder)"**). Du gibst eine Aufgabe, Werte als Text oder Tabelle und/oder
**Fotos** (Aufgabenblatt, Messprotokoll, Tabelle, Messgerät, Oszilloskop; bis zu
6, werden auf 1600 px verkleinert) ein und drückst **"Berechnen"**.

- **Die KI rechnet nicht, die App schon.** Das Modell liest die Werte und stellt
  einen *Rechenplan* auf (gegebene Größen mit Einheit, Schritte mit Formel,
  Annahmen); ausgewertet wird er lokal (`lib/services/calc_engine.dart`, ein
  sicherer Formel-Auswerter ohne `eval`). Sprachmodelle verrechnen sich, ein
  Auswerter nicht. Erlaubt: Zahlen, Größen, `+ - * / ^`, Klammern und Funktionen
  wie `sqrt`, `sin`, `ln`, `lg`, `exp`, `hypot`, `pow`, `rad`; über **Messreihen**
  `mean`, `median`, `stdev`, `min`, `max`, `rms`, `sum` sowie `slope`,
  `intercept`, `r2` (Ausgleichsgerade). Eine Größe mit mehreren Werten rechnet
  Zeile für Zeile (Ergebnis als Tabelle).
- **Rechenweg** je Schritt: Name, Formel (LaTeX), Erklärung, **eingesetzte
  Werte** (`R = 12,3 V / 0,45 A`) und Ergebnis mit Einheit (deutsches Komma, vier
  gültige Ziffern, Zehnerpotenz bei sehr großen/kleinen Werten). Ganz oben steht
  das Ergebnis. Fehler (Division durch 0, unbekannte Größe) stehen am Schritt,
  unabhängige Schritte rechnen trotzdem.
- **Gelesene Werte prüfen und korrigieren:** unter "Gegeben – bitte prüfen"
  steht jeder Wert samt dem, was im Bild stand; unsicher Gelesenes ist markiert.
  Tippst du einen anderen Wert ein, rechnet die App **sofort neu** – ohne weitere
  KI-Anfrage. Reihen mit Semikolon.
- **Anpassen lassen:** "Rechne zusätzlich die Leistung" / "Nimm für R_2 den Wert
  220 Ω" überarbeitet den Plan (die KI sieht den bisherigen Plan; Bilder nur auf
  Wunsch erneut). Fehlende Angaben nennt die KI unter "Es fehlt noch" statt zu
  raten; Annahmen und Plausibilitätshinweise stehen darunter.
- **Rechenweg kopieren** oder **"In Notizen speichern"** (an die Notizen des
  Versuchsteils angehängt) – von dort nutzt ihn der Berichtsentwurf.
- Modell: mit Bildern das **Vision-Modell**, sonst das Fragen-Modell (Einstellungen).

**Berichtsentwurf zur Inspiration** (`lib/ui/lab/lab_draft_screen.dart`) – im
Reiter Bericht der Knopf **"Entwurf zur Inspiration"** (alle Abschnitte) bzw. je
Abschnitt (nur dieser). Die KI schreibt aus den Daten des Versuchs (Messwerte,
Notizen samt Rechenwegen, Antworten, Auszüge aus Skript und Anleitung) einen
groben Entwurf; **nichts wird erfunden** – Fehlendes steht als
`[ergänzen: …]` darin, Abbildungen als `[Abbildung: …]`, und eine Liste nennt,
was noch fehlt.

- **Vorlage und Vorgaben:** eine Berichtsvorlage hochladen (Word, PDF,
  PowerPoint – wird wie andere Unterlagen im Fach abgelegt und beim Versuch
  gemerkt), aus dem Fach wählen oder als **Foto** mitgeben, dazu eigene Vorgaben
  (Umfang, Gliederung, Passiv, Formalia). Die KI folgt Gliederung und Formalia der
  Vorlage; "Gliederung der Vorlage übernehmen" legt Abschnitte, die nur die
  Vorlage kennt (z. B. Anhang), als neue Berichtsabschnitte an.
- **Ausformuliert oder nur Gerüst** (Stichpunkte); die bisherigen eigenen Texte
  können berücksichtigt werden.
- **Getrennt vom eigenen Text:** der Entwurf steht in einem eigenen Feld unter
  dem Abschnitt (markier- und kopierbar), **"In meinen Text übernehmen"** hängt
  ihn an deinen Text an (und räumt ihn weg), **"Neu erzeugen"** und **Verwerfen**
  ebenso. Dein Text und das Gegenlesen bleiben unberührt; Entwürfe kommen nicht
  in den Export.
- Grenzen: der Entwurf ist keine Abgabe – Zahlen, Aussagen und Quellen prüfst du
  selbst; ohne Daten (keine Messwerte, keine Notizen) bleibt er dünn und voller
  Lücken-Hinweise.

### 5s. Sync: Geräte abgleichen, frühere Cloud-Stände

**Warum:** vorher gewann bei einem Konflikt immer EIN ganzer Stand – hatte das
Handy zuletzt hochgeladen, war die Arbeit vom PC weg. Jetzt gilt: nichts
überschreiben, sondern zusammenführen.

**Wie der Abgleich arbeitet** (`lib/services/sync_merge.dart`,
`sync_merge_apply.dart`, `SyncService.merge`): drei Stände werden verglichen –
der lokale, der der Cloud und der **Basisstand** (was beide beim letzten
Abgleich gemeinsam hatten; je Eintrag ein Hash, nur auf diesem Gerät
gespeichert, `sync_base_store.dart`).
- *Nur auf einer Seite vorhanden:* neu → wird übernommen. War es im Basisstand
  und ist dort unverändert, wurde es auf der anderen Seite gelöscht → fällt
  auch hier weg. Wurde es hier weiterbearbeitet und dort gelöscht, bleibt es.
- *Auf einer Seite seit dem Basisstand geändert:* diese Fassung gilt.
- *Auf beiden Seiten geändert:* Karten – der **spätere Lernstand** (letzte
  Wiederholung, dann Anzahl Wiederholungen); Laborversuche – der mit mehr
  eigenem Text; Materialien – Markierungen, Seitennotizen und Notizen beider
  Seiten bleiben; alles andere – die lokale Fassung. Was dabei nicht gewinnt,
  steht in der Sicherung.
- Lerntage werden vereinigt, Probeklausuren und Chats ergänzt, der heutige
  Daily-Stand zusammengeführt. Einträge, deren Fach wegfällt, gehen mit.
- **Erster Abgleich** eines Geräts (noch kein Basisstand, oder nach dem
  Wiederherstellen einer Sicherung): es wird nur ergänzt, nie gelöscht.
- Ändert sich dabei etwas auf diesem Gerät, entsteht vorher eine **Sicherung**
  ("Vor dem Zusammenführen", die letzten 5). Das Ergebnis geht anschließend in
  die Cloud; hat währenddessen ein weiteres Gerät hochgeladen, wird nichts
  überschrieben, sondern neu abgeglichen.

**Automatisch:** mit Auto-Sync gleicht die App bei einem Konflikt selbst ab,
kurz nach dem Start und beim Zurückkehren in die App nach, ob ein anderes Gerät
weitergelernt hat (Status unter dem Schalter: z.B. "In der Cloud neu oder
geändert: 3 Karten."). Läuft das mehrmals hintereinander in einen Konflikt (ein
anderes Gerät lädt gerade ständig hoch), bleibt es beim Knopf "Abgleichen".

**Frühere Cloud-Stände** (`sync_cloud_history.dart`): beim Hochladen bleibt der
ersetzte Stand in der Cloud liegen (Teil-Dokumente `sync_parts/{pushId}_n`, Liste
`history` im Hauptdokument) – wenn er von einem ANDEREN Gerät stammt (genau dann
geht fremder Fortschritt verloren), wenn der Verlauf leer ist oder wenn er einen
Tag älter als der letzte Eintrag ist; es bleiben höchstens fünf. Der Dialog zeigt
Datum, Umfang und Gerät; "Wiederherstellen" sichert lokal, übernimmt den Stand
und lädt ihn hoch – der ersetzte Stand landet selbst wieder im Verlauf. Mehr
Speicher in der Cloud: bis zu fünf zusätzliche komprimierte Stände.

**Grenzen:** zwei Geräte, die dieselbe Karte gleichzeitig ändern, werden nach
obiger Regel entschieden, nicht Feld für Feld. Ein gelöschter Eintrag wird nur
erkannt, wenn dieses Gerät schon einmal abgeglichen hat (Basisstand). PDF-Dateien
selbst laufen weiter über den eigenen PDF-Speicher.

### 5q. PDF-Viewer: KI-Frage-Panel neben der Seite, Notizen zu Seiten

**"Frage zur Seite"** (Sprechblasen-Symbol oben im Viewer, `lib/ui/widgets/
page_qa_panel.dart`): auf **breiten Bildschirmen** (ab ca. 900 px, z.B. Windows)
dockt das Fenster **neben dem PDF** an statt es zu verdecken – bei 50 % Zoom
passt die Seite daneben, und das Panel kann dauerhaft offen bleiben, während
man blättert. Jede Frage sieht die Seite, die im Moment des Fragens angezeigt
wird (plus den Dokumenttext); die Kopfzeile zeigt die aktuelle Seite.
**Pfeil-Symbol** im Panel: auf die andere Seite (links/rechts) schieben, **X**:
schließen (das Gespräch bleibt erhalten). Auf schmalen Bildschirmen (Handy)
kommt es wie bisher als Bottom-Sheet.

- **Antworten speichern:** unter jeder KI-Antwort **"Auf Seite N speichern"**
  heftet sie als **Seitennotiz** an ihre Seite (`MaterialItem.pageNotes`,
  sofort gespeichert, reist mit Sync und Fach-Export, fließt als Notiz in
  spätere KI-Kontexte ein). Der Reiter **"Notizen"** listet sie – die der
  aktuellen Seite zuerst –, **Seite N** springt dorthin, das Papierkorb-Symbol
  löscht.
- **Markieren und kopieren:** alle KI-Texte im Panel (und im Frage-Chat des
  Fachs) lassen sich mit der Maus/dem Finger markieren; "Antwort kopieren"
  kopiert eine ganze Antwort.

### 5r. Quiz: mit der KI über die Antwort sprechen

Unter der KI-Erklärung im Quiz (auch im Üben, Sprint usw.) gibt es **"Mit der
KI besprechen"** (`lib/ui/study/explain_chat.dart`, `AiService.followUpAnswer`):
ein kleiner Chat, der Frage, richtige Lösung, deine Antwort und die Erklärung
kennt. Damit kannst du
- **Rückfragen** stellen ("Das habe ich nicht verstanden: …", "Anderes
  Beispiel"),
- **in eigenen Worten erklären** und prüfen lassen ("Ich erkläre es mal in
  meinen Worten: …") – die KI sagt zuerst, ob es stimmt (Ja / Fast / Nicht
  ganz), was richtig ist und was fehlt,
- die KI bitten, **auf einen Punkt genauer einzugehen**.
Die Chips füllen den Satzanfang vor, gesendet wird mit dem Knopf oder
**Strg+Enter**. Die KI-Antworten sind markierbar. Das Gespräch gilt für die
eine Karte; mit "Weiter" ist es weg (die Frage-Chats des Fachs bleiben
gespeichert).

### 5p. Laborversuch: Vorbereitung, Durchführung, Bericht

Für Praktika, bei denen du dich **vor dem Versuch vorbereiten**, ihn im Labor
**durchführen** und danach einen **Bericht** schreiben musst (und am
Semesterende darüber geprüft wirst): im Fach unter **Laborversuche** →
"Laborversuch anlegen" (`lib/ui/lab/`).

**Anlegen.** Name (optional), **Labortermin** und **Berichtsabgabe**, dazu die
Unterlagen: **Versuchsanleitung/Durchführung** und – falls vorhanden – das
**Theorie-Skript** (neu hochladen oder "Aus dem Fach"; hochgeladene Dateien
liegen danach auch unter Materialien). "Versuch einlesen": die KI liest
daraus die **Vorbereitungsaufgaben** (Wortlaut und Nummerierung wie im
Skript), die **Versuchsteile** mit Schritten, **Messwerttabellen** (Vorgaben
fest, leere Felder zum Ausfüllen) und **Auswertungsfragen** sowie die
Hinweise (z.B. "USB-Stick mitbringen"). Alles lässt sich danach von Hand
ändern, ergänzen und löschen. Ohne KI-Key geht "Leer anlegen".

**Vier Reiter** (der Versuch öffnet je nach Termin auf dem passenden):
- **Vorbereitung**: Aufgaben mit **eigener Antwort** (wird nach einer kurzen
  Pause von selbst gespeichert). **"Gegenlesen lassen"**: die KI sagt
  *Passt / Teilweise / Noch nicht getroffen*, was **fehlt** und **wo du
  nachschauen** kannst – **keine Musterlösung**. Sie stützt sich dabei auf die
  passenden Skript-Seiten (lokaler Stichwortabgleich, dazu Chips zum direkten
  Öffnen der Seite). Ändert man den Text danach, steht die Einschätzung als
  veraltet da. **"Im Skript nachschlagen"** geht auch ohne KI.
  **Exportieren/Drucken**: PDF, Text oder in die Zwischenablage (nur Aufgaben
  und *deine* Antworten – die KI-Einschätzung steht nicht darin).
- **Durchführung** (auch am Handy am Platz): Schritte abhaken, **Messwerte in
  die Tabellen** eintragen, Notizen je Versuchsteil, Auswertungsfragen mit
  demselben Gegenlesen (die KI sieht dabei deine Messwerte).
- **Bericht**: ein Abschnitt je Versuchsteil plus Einleitung und Fazit – du
  schreibst, die KI liest jeden Abschnitt **gegen**: stimmen Werte mit der
  Tabelle, fehlen Einheiten/Messabweichungen, sind die Fragen beantwortet,
  trägt der Schluss? Beim Gegenlesen schreibt sie den Text nicht um und liefert
  keine Formulierungen. Auf Wunsch gibt es zusätzlich einen **groben Entwurf
  zur Inspiration** (Abschnitt 5t) – getrennt von deinem Text. Export als
  PDF/Text (mit den Messwerten im Anhang; Entwürfe sind nicht dabei);
  "Abgegeben" abhaken.
- **Rechnen mit KI**: je Versuchsteil und je Auswertungsaufgabe der Knopf
  **"Rechnen"** – aus Werten oder Fotos zum Ergebnis mit Rechenweg (Abschnitt 5t).
- **Lernen**: **"Karten aus dem Skript erstellen"** öffnet Nachbereiten mit
  Theorie-Skript und Anleitung schon eingetragen; **"Meine Antworten als
  Karten"** macht aus deinen Antworten, die beim Gegenlesen *Passt* bekamen,
  Karteikarten (schon vorhandene Fragen werden übersprungen); dazu der
  Frage-Chat und die Unterlagen.

**Kalender und Startseite.** Labortermin und Berichtsabgabe stehen im
Kalender (Tippen öffnet den Versuch); auf der Startseite erscheint am Fach ein
Hinweis, wenn die Vorbereitung eines Versuchs in den nächsten 14 Tagen noch
nicht beantwortet ist oder ein Bericht in den nächsten 7 Tagen fällig und
unfertig ist.

**Sync/Export.** Laborversuche reisen mit dem Cloud-Sync und dem Fach-Export;
ein weitergegebenes Fach enthält die Aufgaben, aber keine Antworten, Messwerte,
Berichtstexte oder Termine.

Grenzen: Die KI liest nur Text (Oszillogramme/Abbildungen der Anleitung und
Messkurven werden nicht ausgewertet), es gibt keine Diagramme oder
Messdaten-Auswertung, und sehr lange Unterlagen werden auf etwa 45 000
Zeichen je Gruppe gekürzt (die App weist darauf hin). In PDFs werden nur die
Standard-Schriften genutzt – Ω, µ (griechisch) und Pfeile erscheinen daher als
"Ohm", "µ" und "->"; der Text-Export bleibt unverändert.

### In-App-Update-Hinweis

Damit man nicht von Hand auf GitHub nachschauen muss, ob es einen neueren
Build gibt: beide Workflows setzen `--build-number=${{ github.run_number }}`
(eine garantiert fortlaufende Zahl über alle Pushes hinweg) und
veröffentlichen zusätzlich ein `version.json`
(`{"buildNumber": ..., "sha": "...", "tag": "..."}`) unter derselben
Release-URL wie die APK/das ZIP. `UpdateCheckerService` vergleicht das beim
App-Start (und über "Nach Updates suchen" in den Einstellungen) mit der
Build-Nummer der laufenden App (`package_info_plus`) – findet es eine
neuere, gibt es eine SnackBar bzw. einen Button **"Jetzt installieren"**
(`lib/services/update_installer_io.dart`, `lib/ui/widgets/update_actions.dart`):

- **Windows** lädt `Lernen-Setup.exe` ins Temp-Verzeichnis, prüft, dass
  wirklich ein Programm ankam, startet es still (`/SILENT`) und beendet
  sich; das Setup ersetzt die Dateien und startet die App danach neu.
- **Android** lädt die APK in den Cache und übergibt sie über einen
  FileProvider an den System-Installer (`MainActivity.installApk`, Kanal
  `lernen/update`, Berechtigung `REQUEST_INSTALL_PACKAGES`). Man bestätigt
  nur noch "Aktualisieren" – ganz still geht das bei Apps außerhalb des
  Play Stores nicht. Beim allerersten Mal fragt Android, ob Lernen Apps
  installieren darf. Weil jede APK mit demselben Schlüssel signiert ist
  (`android/app/debug.keystore`), installiert sie über die alte App; Daten
  bleiben erhalten, nichts muss vorher gelöscht werden.

Klappt das nicht, öffnet sich der Download im Browser.

## Tests

```bash
flutter analyze   # statische Analyse
flutter test       # FSRS-Algorithmus, Exam-Scheduler, KI-JSON-Parsing, App-Smoke-Test
TZ=Europe/Berlin flutter test   # zusätzlich über die Zeitumstellung (so läuft es auch in CI)
```

Alle Datumsrechnungen laufen über Kalendertage (`DateTime(j, m, t ± n)`,
`calendarDaysBetween`) statt über `Duration(days: …)`/`difference().inDays`:
an der Sommer-/Winterzeit-Umstellung hat ein Tag 23 bzw. 25 Stunden, sonst
verschieben sich Vorlesungszeiten, Fälligkeiten, Streak und Countdown
(`test/services/dst_test.dart`, aussagekräftig nur mit einer Zeitzone mit
Umstellung). Der ausführliche Analysebericht mit allen gefundenen und
behobenen Fehlern steht in `CODE_ANALYSE.md`.

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
