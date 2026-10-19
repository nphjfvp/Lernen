# Lernen – Funktionen im Detail

Ausführliche Beschreibung aller Bereiche, der bewussten Auslassungen und der
Architektur. Kurzüberblick: [README](../README.md); Änderungen der Reihe nach:
[CHANGELOG](../CHANGELOG.md).

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
  API-Anfrage beim Beantworten. Auf Android/iOS und im Browser (dort in einem
  abgeschotteten iframe) tatsächlich interaktiv;
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
