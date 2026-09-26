# Code-Analyse – Lernen (September 2026)

Gründliche Durchsicht der gesamten App (~24.000 Zeilen Dart) nach dem
gemeldeten Zuordnen-Fehler („ein Begriff belegt direkt beide Felder, ich kann
die Frage gar nicht fertig machen“) – mit dem Ziel, **ähnliche Fehler** zu
finden: Daten, die die KI oder ein anderes Gerät liefert und die die App
nicht erwartet, Zustände, die sich gegenseitig überschreiben, und Rechnungen,
die nur „meistens“ stimmen.

**Ergebnis:** 51 Befunde (Nr. 51 als Nachtrag nach dem ersten Test auf dem Handy). Behoben sind 1 Blocker, 11 schwere, 26 mittlere
und 8 leichte Befunde sowie 3 Wünsche. Zwei Befunde sind nur Hinweise und
bewusst nicht umgesetzt (Nr. 20 und 27); sie stehen mit weiteren
Empfehlungen unten. Die Logik-Fehler haben Regressionstests. Einige reine
Oberflächen-Abläufe (Nr. 34, 40–43, 45, 48, 50) sind durch Code-Lesen,
Analyzer und Build geprüft, aber ohne eigenen Test. 432 → 495 Tests, alle
grün, auch mit
`TZ=Europe/Berlin` (Zeitumstellung). `flutter analyze` ist sauber, der
Web-Build ist erfolgreich.

## Vorgehen

1. **Fragetypen und Antwortprüfung**: `AnswerChecker`, `QuestionAnswerView`,
   `QuestionParsing`, alle KI-Prompts mit ihren Formatregeln.
2. **Lernabläufe**: Daily Quiz, Üben, Sprint, Probeklausur, Zwischen-Check,
   `ReviewService`/`CardReviewMixin`, FSRS, Ampel, Stufen-Eskalation.
3. **Daten**: Modelle (`fromMap`), Repositories, Sync, Export/Import,
   Auto-Sync.
4. **Screens und KI-Dienst**: PDF-Viewer, Vorbereiten, Nachbereiten, Chat,
   Statistik, Fehlertagebuch, Einstellungen, Fach anlegen, Einheiten.
5. **Muster-Suche** über den ganzen Code, zum Beispiel:
   - harte Casts (`as String`, `DateTime.parse`) auf fremden Daten,
   - `firstWhere` ohne Rückfallwert,
   - `Duration(days:)`/`difference().inDays` auf Ortszeit,
   - Speichern ohne Sperre gegen doppeltes Tippen,
   - Context-Zugriffe nach `await`.
6. **Beweis per Test**: Logik-Fehler wurden zuerst mit einem Test
   nachgestellt. Für die Zeitumstellung wurde der alte Code gegengeprüft: Die
   Tests schlugen dort fehl, mit dem Fix laufen sie durch.

## So funktioniert das Daily Quiz (nach der Prüfung)

1. **Welche Karten überhaupt:**
   - nur Karten bestehender Fächer,
   - Karten einer Einheit nur, wenn sie behandelt ist (abgehakt oder Termin
     erreicht),
   - selbst beim Lesen erstellte Fragen immer.
2. **Fällige Wiederholungen:**
   - alle Karten, deren Fälligkeit heute oder früher liegt, älteste zuerst,
     ohne Obergrenze;
   - die Fälligkeit setzt FSRS nach jeder Antwort auf Mitternacht in ganzen
     Kalendertagen (mindestens morgen).
3. **Neue Karten pro Fach:**
   - Das Budget verteilt den Rückstand auf die Tage bis zur Klausur, abzüglich
     3 Tage reiner Wiederholung (ohne Klausur: 14 Tage).
   - Ein schwacher Wissensstand bremst auf 50–100 %.
   - Mindestens 10 pro Tag, solange Rückstand da ist, höchstens 15.
   - In den letzten 3 Tagen vor der Klausur kommen keine neuen Karten; dann
     nur über „Freiwillig weiterlernen“.
   - Heute schon eingeführte Karten werden abgezogen, auch nach Neustart oder
     „Aktualisieren“.
   - Selbst erstellte Fragen kommen immer und zuerst.
4. **Runde:**
   - Fällige und neue Karten, fachübergreifend gemischt.
   - Über 60 Karten werden neue Karten reihum je Fach gekürzt.
5. **Wiederholungsrunde:**
   - Falsch Beantwortetes kommt am Ende der Runde erneut, bis zu 3-mal.
   - Ein erneuter Fehler am selben Tag zählt nicht noch einmal gegen die
     Karte (neu, siehe Befund 36).
6. **Bewertung jeder Antwort:**
   - richtig → „Gut“, falsch → „Nochmal“;
   - offene Karteikarten bewertest du selbst.
   - Die Ampel steigt höchstens einmal pro Tag und sinkt höchstens einmal pro
     Tag.
   - Grün braucht richtige Antworten an 4 verschiedenen Tagen.
   - Bei Grün wird eine Stufen-Frage befördert (Auswahl → Lückentext →
     Freitext).
   - Zwei Fehltage in Folge stufen zurück (auf der schwersten Stufe: 5).
7. **Speichern:**
   - Jede Antwort wird auf den gespeicherten Stand der Karte angewendet.
   - Der Tagesfortschritt übersteht einen Neustart.
   - Eine inzwischen gelöschte Karte wird nicht wieder angelegt.

## Befunde und Fixes

Schwere: **B** Blocker · **H** hoch · **M** mittel · **N** niedrig ·
**W** Wunsch.

### Fragetypen und Antwortprüfung

| Nr | | Problem | Fix |
|---|---|---|---|
| 1 | B | **Zuordnen mit doppeltem Ziel** (z.B. zweimal „Metall“): Die Zuordnung lief über den Ziel-Text, ein Begriff belegte beide Felder, der Pool wurde nie leer und „Prüfen“ blieb gesperrt. | Zuordnung über Positionen statt Texte. Doppelte Ziele werden als Kategorien-Frage angezeigt und geprüft. Der Prompt verlangt jedes Ziel genau einmal, das Parsing wandelt solche Fragen in `drag_category` um. |
| 2 | H | Gleich lautende Begriffe: Beim Ablegen verschwanden fremde Zuordnungen, die Kategorien-Prüfung lief über Texte. | Index-basiert, Kategorien per Multiset geprüft. |
| 3 | H | Lückentext mit leerer Lösung war unlösbar. Passte die Zahl der Lücken nicht zu den Lösungen, gab es Felder ohne Lücke. | Leere Lücken fallen weg. Bei unpassender Anzahl wird die Frage zur Karteikarte, ohne Markierung mit einer Lösung zur Freitextfrage. Die Lücken sind im Text nummeriert. |
| 5 | M | Kaputte Karten (keine richtige Option, leere Lösung, keine Paare) waren immer falsch. | `AnswerChecker.isAnswerable`: Solche Karten werden als Karteikarte zum Selbstbewerten gezeigt. |
| 6 | M | Multiple Choice ließ sich ohne Auswahl prüfen (versehentlich falsch). | „Prüfen“ erst nach einer Auswahl. |
| 7 | M | Single Choice mit nur einer Option. | Mindestens 2 Optionen, sonst Karteikarte. |
| 8 | N | Die Lösung „ ; “ ergab die Rückseite „;“. | Nur echte Alternativen zählen. |
| 11 | W | Zuordnen auch per Antippen. | Begriff antippen, dann Feld antippen. Abgelegte Begriffe lassen sich verschieben, der Pool dient als Ablage. |
| 12 | H | Auswahl-Optionen wurden nie gemischt, die KI setzt die richtige meist zuerst. Man lernte so die Position statt der Antwort. | Anzeige gemischt; „Alle/Keine der genannten“ bleiben am Ende. |
| 13 | M | Interaktive Fragen gingen nach „Prüfen“ in der Seite sofort weiter, ihr Feedback war nie zu sehen. | Die App zeigt das Ergebnis, eine Erklärung und „Weiter“ unter der Seite. In der Probeklausur geht es weiterhin sofort weiter. |
| 35 | W | **Lückentext per KI prüfen** (mehrere Lösungen je Lücke, Rechtschreibung). | Lokal zählen die Lösung, jede per „;“ hinterlegte Variante und Tippfehler. Lehnt das eine Lücke ab, bewertet die KI jede Lücke nach; sie kann nur hochwerten. Danach zeigt jede Lücke ✓/✗ und die richtige Schreibweise. Gilt in allen Lernmodi. |
| 51 | H | **Nachtrag nach dem Test auf dem Handy:** Die KI-Prüfung für Lückentexte war zu streng. Sie bewertete jede Lücke einzeln gegen ihre Musterlösung, damit waren vertauschte Lücken („Produktion und Entwicklung“) immer falsch. „Anderer Begriff/zu allgemein“ ließ „Werkstätten“ und „Produkte“ durchfallen, „debinrten“ galt nicht als eindeutiger Tippfehler. Ein Fehlschlag der KI-Anfrage war zudem unsichtbar. | Neuer Prompt: ganzer Satz, Wissen statt Rechtschreibung, Reihenfolge egal bei gleichrangigen Lücken, im Zweifel für den Lernenden, Temperatur 0, kurze Begründung je Lücke. Ob die KI geprüft hat oder scheiterte, steht unter dem Ergebnis. „Als richtig werten“ als Ausweg bei Freitext und Lückentext. Freitext-Prompt: Rechtschreibung zählt nicht. |

### Lernabläufe und Lernstand

| Nr | | Problem | Fix |
|---|---|---|---|
| 4 | H | Eine per KI erzeugte nächste Stufe wurde ungeprüft gespeichert. Eine unvollständige Stufe überlebte dann jede Rück- und Wiederbeförderung. | Die Stufe läuft durch dieselbe Prüfung wie neue Karten, sonst bleibt die Karte auf ihrer Stufe. Das Bild der Karte wird übernommen. |
| 9 | M | Ohne API-Key erschien „nächstes Mal: Lückentext“, obwohl die Beförderung nie passieren kann. | Meldung unterdrückt. |
| 15 | H | Eine während einer Lernrunde gelöschte Karte (oder ihr Fach) entstand beim Beantworten neu, als „Zombie“ ohne Fach, der mitsynchronisiert wurde. | `FlashcardRepository.update` schreibt nur bestehende Karten. |
| 16 | H | **Verlorene Updates**: Lernmodi beantworteten den Kartenstand vom Rundenstart. Zum Beispiel ließ „falsche üben“ nach der Probeklausur deren Fehler verschwinden, die Ampel wurde zu schnell grün. | Die Antwort wird auf den gespeicherten Stand angewendet. Ein Stufenwechsel passiert nur, wenn die Stufe noch dieselbe ist. |
| 17 | H | FSRS rechnete in 24-Stunden-Blöcken: abends lernen und am Morgen wiederholen zählte als 0 Tage, die Abstände wuchsen nicht. | Kalendertage. |
| 18 | M | Das erste Nichtwissen einer neuen Karte zählte als „1× vergessen“. | Nur gelernte Karten zählen, neue Karten haben den Zustand `learning`. |
| 19 | N | Sprint: Eine Antwort nach Zeitablauf erhöhte noch die Punkte. | Zählt nur fürs Lernen. |
| 36 | M | **Wiederholungsrunde bestrafte mehrfach**: Jeder weitere Fehler am selben Tag senkte die Ampel erneut (Grün → Rot in einer Runde) und zählte als weiteres „vergessen“. Zwei Fehler binnen Minuten stuften zurück, während der Aufstieg 4 Tage braucht. | Ein erneuter Fehlversuch am selben Tag zählt nicht noch einmal (FSRS, Ampel, Fehlertagebuch, Rückstufung). |
| 37 | M | Verwaiste Karten ohne Fach (z.B. Zombies aus Nr. 15) kamen täglich im Daily Quiz, ließen sich aber nirgends löschen. | Der Scheduler plant nur Karten bestehender Fächer. |
| 38 | N | Eine gelöschte, falsch beantwortete Karte kam trotzdem in die Wiederholungsrunde. | `ReviewOutcome.cardDeleted`. |
| 39 | N | Über 60 Karten wurden neue Karten am Listenende gekappt, also spätere Fächer komplett, auch selbst erstellte Fragen. | Selbst erstellte Fragen zuerst, der Rest reihum je Fach. |
| 49 | M | Verwaiste Karten zählten auch in Statistik, Trend, Fehlertagebuch und Sprint. | `loadAll` liefert nur Karten bestehender Fächer. |

### Datum und Zeitumstellung

Nachgewiesen mit `TZ=Europe/Berlin`; die CI testet jetzt ebenfalls so.

| Nr | | Problem | Fix |
|---|---|---|---|
| 32 | H | Überall wurde mit `± Duration(days)` auf Ortszeit gerechnet. Folgen:<br>• Wöchentliche Vorlesungen lagen nach der Umstellung 1 h daneben (9:15 statt 10:15).<br>• Der Kalender im März/Oktober zeigte Tage auf 23/1 Uhr ohne Termine, im Oktober ein Datum doppelt.<br>• Der Streak riss ab (5 statt 11 Tage).<br>• Karten wurden um 23 Uhr am Vortag fällig.<br>• Die Erinnerung war dauerhaft 1 h verschoben.<br>• Betroffen waren außerdem die Tagesplan-Grenze und der Trend-Zeitraum. | Kalenderarithmetik `DateTime(j, m, t ± n)` überall. |
| 33 | M | Klausur-Countdown und Tagesplan-Tempo rechneten über den Sommerzeit-Beginn einen Tag zu wenig („in 20 Tagen“ statt 21). | Gemeinsamer Helfer `calendarDaysBetween`. |

### Daten: Sync, Export, Modelle

| Nr | | Problem | Fix |
|---|---|---|---|
| 10, 26, 28 | M | Harte Casts in Modellen: Eine unbekannte Material-Art oder ein fehlendes Feld (neuere App-Version, Import) ließ den ganzen Download oder Import scheitern. | Tolerantes Lesen, IDs bleiben Pflicht. |
| 21 | H | **Sync-Download** vom Stand einer neueren App-Version (oder ohne Fächerliste) fand „keine Daten“ und löschte lokal trotzdem alles. | Vorher prüfen, sonst Abbruch mit Meldung. |
| 22 | M | Nach dem Download blieb die Fächerliste bis zum Neustart alt. | Wird neu geladen. |
| 23 | H | Der Fach-Export ließ die Zusammenfassungen weg; sie gingen beim Weitergeben oder Sichern verloren. | Werden exportiert und importiert, alte Dateien bleiben lesbar. |
| 24 | M | Der Import speicherte Stück für Stück, ein Abbruch hinterließ ein halbes Fach. | Eine Transaktion. |
| 25 | M | Der Import übernahm immer den fremden Lernstand. | Nachfrage „Übernehmen / Neu beginnen“. |
| 47 | N | Einstellungen, Chat-Verlauf, Ampel-Verlauf und Modellkatalog wurden hart gelesen; ein falscher Wert in den Einstellungen hätte den App-Start verhindert. | Tolerant. |

### Screens

| Nr | | Problem | Fix |
|---|---|---|---|
| 14 | W | Frage erstellen: 1–5 Fragen, „Interaktiv“ wählbar. | Umgesetzt (Fragen-Chips in der Vorschau). |
| 29 | N | Beim Löschen eines Materials wurde zuerst die Datei gelöscht; ein Abbruch hinterließ ein Material ohne PDF. | Reihenfolge getauscht. |
| 30 | M | Das Häkchen „behandelt“ zu entfernen löschte auch einen künftigen Termin. | Ein künftiger Termin bleibt. |
| 31 | M | Karten-Screenshots in doppelter Auflösung blähten Datenbank und Sync auf. | Auf maximal 1280 px verkleinert. |
| 34 | M | PDF-Viewer: Eine entfernte Markierung blieb nach „Speichern“ dauerhaft farbig im PDF. | Die Annotation trägt die Markierungs-ID und wird mit entfernt. |
| 40 | M | Vorbereiten/Nachbereiten: Übernommenes Material hatte auf dem Handy keine PDF-Vorschau (dort liegt die PDF als Datei). | Die PDF wird aus der Datei geladen. |
| 41 | N | Die Markierungen eines gleichnamigen alten Materials landeten fest im Text des neuen. | Rohtext und KI-Kontext werden getrennt. |
| 42 | N | „Folie ansehen“ öffnete Word/PowerPoint im PDF-Viewer. | Nur PDFs. |
| 43 | M | Ausführlich vorbereiten: Rückfragen gingen verloren, wenn nur vorhandenes Material ohne Einheit genutzt wurde. | Sie werden an dessen Notiz angehängt. |
| 44 | M | Kein Schutz beim Zurück: Eine Zurück-Geste verwarf die bezahlte KI-Vorschau oder die ganze Sitzung. | Rückfrage „Ergebnis verwerfen?“ (`DiscardGuard`). |
| 45 | M | Doppeltippen auf „Speichern“ legte Materialien, Konzepte und Karten doppelt an. Wer mitten im Speichern verließ, hatte Materialien ohne Karten. | Sperre, und das Speichern läuft vollständig durch. |
| 46 | M | Ein einzelner kaputter KI- oder JSON-Eintrag kippte den ganzen Abschnitt. Beim eingefügten JSON hing „Speichern“ ohne Meldung. | Kaputte Einträge fallen einzeln weg und werden gezählt. |
| 48 | M | Einheit mit Termin: Im Datumsdialog hieß „Abbrechen“ „Termin entfernen“, schon ein Tippen daneben löschte den Termin. | Ausdrückliche Wahl „Termin ändern / entfernen“. |
| 50 | M | Doppeltippen auf „Fach anlegen“ erzeugte zwei gleiche Fächer. | Die ID wird einmal vergeben, der Knopf ist gesperrt. |

## Offene Hinweise und Empfehlungen (bewusst nicht umgesetzt)

- **Kartenliste (Nr. 20):**
  - Nur Karteikarten sind bearbeitbar. Eine falsche Auswahl- oder
    Zuordnen-Frage lässt sich nur löschen.
  - Formeln erscheinen dort als Roh-LaTeX.
  - Empfehlung: Editor je Fragetyp.
- **Auto-Sync (Nr. 27):** Er lädt bei jeder Änderung den ganzen Bestand hoch,
  inklusive Karten-Screenshots. Empfehlung: inkrementeller Sync (nur
  geänderte Datensätze).
- **Fällige Karten ungedeckelt** (H5, Absicht): Nach einer längeren Pause kann
  eine Runde sehr lang werden. Empfehlung: optionales Tageslimit für
  Wiederholungen.
- **Klausur-Endspurt:** In den letzten 3 Tagen vor der Klausur kommen neue
  Karten nur über „Freiwillig weiterlernen“. Die Startansicht sagt dann „nichts
  fällig“, auch wenn noch neue Karten warten. Empfehlung: Hinweis mit der
  Anzahl.
- **Verwaiste Karten** werden ausgeblendet, nicht gelöscht, und reisen im
  Cloud-Sync weiter mit. Ein automatisches Löschen wäre riskant, falls die
  Fächerliste einmal nicht geladen ist. Empfehlung: eine „Aufräumen“-Funktion
  in den Einstellungen.
- **Seitenfragen mit 5 Fragen × 3 Stufen** erzeugen große KI-Antworten. Bricht
  das Modell ab, erscheint ein JSON-Fehler. Dann weniger Fragen auf einmal
  wählen.
- **Zwischen-Check:** Auf Seiten ohne Textebene (gescannt) tut „Quiz starten“
  nichts Sichtbares.
- **Leistung:** Konzept oder Frage aus einer Seite parst die PDF bis zu dreimal
  synchron. Bei sehr großen PDFs kann das kurz ruckeln.
- **Zurückgestellt:** H9 und H10 aus `AUDIT.md`.
- **Von Hand auf dem Gerät prüfen:**
  - Entfernen einer Markierung nach Speichern und Neu-Öffnen (Syncfusion),
  - interaktive Fragen,
  - Termine und Erinnerung über die Zeitumstellung.
