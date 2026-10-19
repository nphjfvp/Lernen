# Changelog

Was sich geändert hat – das Neueste oben. Die Nummern (5a … 6i) sind die
früheren Abschnittsnummern aus der README und bleiben als Verweis erhalten.
Ausführliche Beschreibung der Funktionen: [docs/FUNKTIONEN.md](docs/FUNKTIONEN.md).

### 6i. Sichere Sync-Codes

- **„Sicheren Code erzeugen“** unter dem Sync-Code-Feld: ein zufälliger Code
  wie `k7mq-x2vd-9hfa-tn4e`, der sich nicht erraten lässt. Selbst gewählte
  Codes müssen jetzt mindestens 16 Zeichen haben.
- **Schon einen kurzen Code?** Er funktioniert weiter, darunter steht aber ein
  Hinweis mit **„Auf sicheren Code umziehen“**: die App lädt deinen Stand
  unter einem neuen Code hoch und zeigt ihn zum Abschreiben/Kopieren. Den
  gibst du auf den anderen Geräten ein.
- **Danach** (alle Geräte umgezogen): unter „Verbindung prüfen“ die Regeln
  kopieren und in Firebase (Firestore → Regeln) neu veröffentlichen – ab
  dann lehnt Firebase kurze Codes ab. Wer nur mit Konto synchronisiert, ist
  nicht betroffen.

### 6h. KI-Prompts in eigenen Dateien

- Die 50 festen Anweisungen an die KI (System-Prompts) stehen jetzt nach Thema
  in `lib/services/ai_prompts/` (Material, Import, Prüfen und Lernhilfen,
  Aufgaben und Labor, Visuell lernen) statt mitten im KI-Code. Am Verhalten
  ändert sich nichts – die Texte sind Zeichen für Zeichen gleich.

### 6g. Doku aufgeräumt

- Die README ist jetzt ein kurzer Überblick: installieren, erste Schritte, was
  die App kann, wo welche Doku liegt.
- Die Details stehen unverändert in [docs/FUNKTIONEN.md](docs/FUNKTIONEN.md)
  (Funktionen, Architektur, Design) und [docs/EINRICHTUNG.md](docs/EINRICHTUNG.md)
  (Einrichtung, Builds, Web-App, Signierschlüssel, Backups, Tests); die
  Änderungen der Reihe nach hier im Changelog.
- CODE_ANALYSE.md zeigt oben den aktuellen Stand aller Prüfpunkte.

### 6f. Eigener Signierschlüssel (vorbereitet)

Die Android-App war mit dem öffentlichen Debug-Schlüssel aus dem Repo signiert
– damit könnte jeder eine APK bauen, die Android als Update von Lernen annimmt.
Ein eigener Schlüssel ist vorbereitet (aktiv, sobald er in den GitHub-Secrets
liegt); wechselt er, erklärt die App die einmalige Neuinstallation statt eines
Updates, das Android ablehnen würde. Einrichtung:
[docs/EINRICHTUNG.md → Eigener Signierschlüssel](docs/EINRICHTUNG.md#eigener-signierschlüssel).

### 6e. KI-Anfragen: automatisch erneut versuchen, klare Fehler

- **Überlastet oder kurz weg** (429 „zu viele Anfragen“ – bei kostenlosen
  Modellen häufig –, 502/503 Anbieter nicht erreichbar, 408/504
  Zeitüberschreitung, abgerissene Verbindung): die App versucht es nach 3 und
  nach 8 Sekunden noch einmal selbst (nennt der Server eine Wartezeit, gilt
  die, höchstens 30 s). Auch Fehler, die OpenRouter mitten in einer sonst
  normalen Antwort meldet, zählen dazu.
- **Klare Meldung statt Roh-Text**: z.B. „OpenRouter lehnt den API-Key ab
  (401) – bitte in den Einstellungen prüfen“, „Kein Guthaben mehr (402)“ oder
  „Zu viele Anfragen (429) – auch nach 3 Versuchen …“. Die vollständige
  Antwort bleibt dort, wo die App Details zeigt (z.B. beim Fragen-Import).

### 6d. Updates nur vom App-Branch

- **Android- und Windows-Builds** laufen weiter auf jedem Branch (mit Tests,
  Download am Actions-Lauf), aber **als Update veröffentlicht** (Releases
  `android-latest`/`windows-latest`, aus denen die App ihre Updates holt) wird
  nur noch vom App-Branch `claude/neue-lern-app-fokus-ej3k48`. Vorher landete
  jeder Experimentier-Branch als Update auf den Geräten.
- Läufe desselben Branches warten aufeinander – ein älterer Build kann den
  Release eines neueren nicht mehr überschreiben.

### 6c. Web-App fürs iPad (und jeden Browser)

Adresse: **<https://nphjfvp.github.io/Lernen/>** – bei jedem Push automatisch
auf dem neuesten Stand (Workflow „Web-App“, `.github/workflows/web-app.yml`,
mit denselben Tests wie Android/Windows davor).

- **Auf dem iPad/iPhone**: in Safari öffnen → **Teilen → Zum Home-Bildschirm**.
  Dann startet sie im Vollbild wie eine App, und Safari behält die Daten
  dauerhaft (normale Websites löscht Safari nach 7 Tagen ohne Besuch).
- **Daten**: liegen im Browser des Geräts; mit Konto-Anmeldung laufen sie per
  Sync wie gewohnt zwischen Pixel, PC und iPad.
- **Einmalig einrichten**: GitHub → Settings → Pages → Source „GitHub Actions“.
  Für die Google-Anmeldung in Firebase → Authentication → Settings →
  Autorisierte Domains `nphjfvp.github.io` eintragen.
- **Fürs iPad angepasst**: eigenes App-Icon, Ladeanzeige beim ersten Start,
  Farben passend zur App (hell/dunkel), Bitte um dauerhaften Speicher. Auf
  breiten Bildschirmen (iPad quer, großes Fenster – auch unter Windows) stehen
  die Hauptbereiche mittig statt über die ganze Breite gezogen.
- **PDFs im Browser**: liegen in einem eigenen Speicher und werden erst
  geladen, wenn man sie öffnet – vorher steckten sie in der App-Datenbank,
  die der Browser beim Start komplett in den Arbeitsspeicher lädt (bei vielen
  Vorlesungen wurde die App auf dem iPad langsam oder von Safari beendet).
  Schon gespeicherte PDFs ziehen beim ersten Start einmalig um.
- **Interaktive Fragen („Interaktiv“, html) im Browser**: laufen jetzt auch
  dort – in einem abgeschotteten Fenster ohne Zugriff auf die App oder das
  Internet (vorher kam im Browser nur die Karteikarte zum Umdrehen).
- **Geht im Browser nicht**: Lernerinnerungen und das Startbildschirm-Widget
  (nur Android). KI-Anfragen laufen nicht weiter, wenn man die App verlässt –
  solange eine läuft, hält die App deshalb den Bildschirm an (kein
  automatisches Sperren; Safari ab iOS 16.4, Chrome, Edge).

### 6b. Animationen laden zuverlässiger

- **Toleranter beim Einlesen**: Schreibt die KI Szenen leicht anders als
  verlangt (z.B. `pos`/`size`/`from`–`to`, „square“, „triangle“, Gruppen,
  `objects` statt `elements`, Darstellung direkt am Schritt statt unter
  `show`), wird das jetzt verstanden. Ungültige Zahlen (NaN) werden ignoriert.
- **Ein kaputtes Teil reißt nicht die ganze Szene mit**: Jedes Element (2D und
  3D) wird einzeln gezeichnet – scheitert eines, fehlt nur dieses.
- **Kein stilles Verschwinden mehr**: Lässt sich eine Darstellung nicht laden,
  steht am Schritt „Die Darstellung ließ sich nicht laden: …“ (mit Grund) und
  **Neu erzeugen** schickt die KI mit vorausgefülltem Wunsch noch einmal los.
  Im Chat gibt es dafür **Nochmal zeigen**.

### 6a. Absturz beim Lernpfad (Android) behoben, Fehler mit Code

- **Ursache**: Die Hintergrund-Übertragung der KI-Anfragen (WorkManager) darf
  einem Job höchstens 10 KB mitgeben – der Lernpfad (und andere große
  Anfragen) schickt viel mehr. Die Bibliothek hat das nicht abgefangen, die
  App wurde beendet.
- **Jetzt**: Kleine Anfragen gehen wie bisher direkt mit, große als Datei
  (im Job steht nur der Pfad) – sie laufen weiter im Hintergrund, ohne Grenze.
- **Wird die App doch mitten in einer KI-Anfrage oder beim Einlesen der PDFs
  beendet**, meldet der nächste Start das mit **Fehlercode KI-HG-01**,
  Aufgabe, Größe und Zeitpunkt (Details kopierbar) – und KI-Anfragen laufen in
  dieser Sitzung ohne Hintergrund-Dienst.
- **Sonstige Fehler der App** erscheinen als Hinweis „Fehler APP-XXXX: …“ mit
  „Details“ (kopierbar) statt still zu verschwinden.

### 5zz. Visueller Chat – frei fragen, ohne PDF

Ganz oben in **„Visuell lernen“: „Frag einfach – die KI erklärt mit Bildern“**:

- Eine Frage eintippen (oder einen Vorschlag antippen) – ohne PDF, ohne
  Thema vorher festzulegen. Je Nachricht wählst du **Visuell**,
  **Schriftlich** oder **Beides**.
- Die Antworten kommen im Chat und können alles zeigen, was die Lektionen
  können: 2D-Szenen, 3D-Modelle, Graphen mit Tangente/Fläche, Fahrzeug (Auto,
  Rakete …), Umformungen in Zeitlupe – Formeln echt gesetzt.
- **Rückfragen** beziehen sich auf das Gespräch („und wenn die Masse doppelt so
  groß ist?“).
- **„Als Lektion speichern“** (Hut oben): Aus dem Gespräch wird eine richtige
  Lektion mit Schritten und Übung.
- Gespräche werden gespeichert und synchronisiert (Sync-Version 8); die
  letzten stehen zum Fortsetzen unter dem Knopf.

### 5zy. Visuell lernen: Darstellung in der App ändern, Formeln in Szenen

- **„Darstellung ändern“** unter jedem Schritt (und beim Ergebnis bzw. in der
  Kurzfassung „Ändern“): Wunsch eintippen oder einen Vorschlag antippen
  („Formeln richtig setzen“, „Übersichtlicher“, „Anderes Beispiel“, „Rakete
  statt Auto“, „Mehr Zwischenschritte“, „Als 3D-Modell“) und wählen: **nur
  dieser Schritt** oder **ganze Lektion**. Die KI baut um – auch groß (anderes
  Beispiel inkl. Übung) – alles andere bleibt. Gespeichert, mit
  **„Rückgängig“**.
- **Formeln in Szenen**: Texte mit `$…$` in 2D- und 3D-Szenen werden jetzt
  als echte Formeln gesetzt (vorher erschienen sie als Klartext mit `$`).
- **Fahrzeug wählbar**: Statt des Autos kann eine Rakete, ein Fahrrad, Zug,
  Läufer, Ball, Flugzeug, Boot, Lkw, Bus, eine Schnecke oder ein beliebiges
  Emoji fahren – die Bewegung rechnet die App weiter exakt aus der Funktion.

### 5zx. Kaputtes JSON der KI wird automatisch repariert

„Antwort der KI konnte nicht als JSON gelesen werden“ kommt jetzt kaum noch:

- **Erst repariert die App selbst** (ohne neue Anfrage): Text oder Codefences
  um das JSON, einfache Backslashes in LaTeX, echte Zeilenumbrüche/Tabs und
  Anführungszeichen in Texten, überzählige Kommas und **abgeschnittene
  Antworten** (offener Text/Klammern werden geschlossen, ein halber letzter
  Eintrag fällt weg).
- **Klappt das nicht, geht die Antwort samt Fehlermeldung einmal automatisch an
  die KI zurück** („gib genau das als gültiges JSON zurück“) – du musst nichts
  neu eingeben. Erst wenn auch das scheitert, kommt eine Fehlermeldung.
- Gilt für alle KI-Funktionen und auch für **eingefügtes JSON einer externen
  KI** (Fragen „JSON einfügen“, interaktive Aufgaben per JSON) – dort mit
  hinterlegtem Key.

### 5zw. Lernpfad: ein ganzes Semester visuell lernen

Unter **„Visuell lernen“ → „Lernpfad erstellen“**:

- **Mehrere Vorlesungen** (PDFs des Fachs ankreuzen und/oder hochladen) oder
  eine lange – optional mit Schwerpunkt, Detailgrad und Erklären/Sokratisch.
- Die KI liest alles in Abschnitten, sammelt die Themen und **ordnet sie zu
  einem Lernpfad**: Grundlagen zuerst, was baut worauf auf, je Thema ein
  **Übergang** („warum jetzt, was brauchen wir von vorher“). Reine
  Organisation fällt weg, zu kleine Themen werden zusammengelegt. In der
  Vorschau kannst du Themen weglassen, dann speichern.
- **Lektionen entstehen nacheinander** – beim Öffnen eines Themas (oder „Alle
  vorbereiten“). Jede beginnt mit einem **Rückblick**: was aus den früheren
  Themen gebraucht wird (die KI bekommt deren Kurzfassungen) und warum es jetzt
  darauf aufbaut.
- **Ausführlich oder Kurzfassung**: Jede Lektion hat eine Kurzfassung
  (Kernpunkte, wichtigste Formel, eine Darstellung) zum schnellen
  Wiedereinsteigen – oben umschaltbar oder im Pfad direkt mit „Kurz“.
- **Fortschritt**: „Abschließen – weiter mit …“ am Ende jeder Lektion hakt das
  Thema ab; „Weiter mit …“ führt zum nächsten. Erledigt-Haken lassen sich auch
  von Hand setzen. Lernpfade werden synchronisiert (Sync-Version 7); Fortschritt
  von zwei Geräten wird zusammengeführt.

### 5zv. KI läuft im Hintergrund weiter (Android) und mehr Themen je PDF

- **App kurz verlassen bricht nichts mehr ab (Android)**: Android friert Apps
  im Hintergrund ein – dabei riss die Verbindung zu OpenRouter ab. Jetzt laufen
  alle KI-Anfragen als Hintergrund-Job des Systems (WorkManager) weiter; die
  Antwort ist da, wenn du zurückkommst. Gilt für alles mit KI (Lektionen,
  Themenliste, Importe, Erklärungen …). Klappt der Hintergrund-Weg einmal nicht,
  geht die Anfrage automatisch auf dem normalen Weg raus.
- Grenze: Wird die App ganz geschlossen (weggewischt), läuft die gerade
  laufende Anfrage zwar noch zu Ende, die App kann das Ergebnis danach aber
  nicht mehr übernehmen.
- **Themenliste ohne feste 8er-Grenze**: Lange PDFs werden in Abschnitten
  gelesen (je etwa 30.000 Zeichen bzw. 40 Seiten), damit auch der hintere Teil
  vorkommt; je Abschnitt bis zu etwa ein Thema pro 2 Seiten (4–15). Gleiche
  Themen aus mehreren Abschnitten werden zusammengelegt.

### 5zu. Visuell lernen: räumliche Szenen (3D), wo es nötig ist

Ergänzung zu den 2D-Szenen – **2D bleibt die erste Wahl**, 3D nimmt die KI nur,
wenn der räumliche Aufbau das Wesentliche ist:

- **Elementarzellen** (krz, kfz, hdp), **Packungsdichte** (Atome wachsen, bis
  sie sich berühren – die Packungsdichte läuft als Wert mit), **Lücken** im
  Gitter, **Gleitebenen und -richtungen**, Moleküle, Kräfte im Raum.
- Bausteine: Kugeln, Linien, Pfeile, Quader, ebene Flächen und Text im Raum,
  mit Schlüsselbildern (Position, Radius, Deckkraft, Farbe, „wird gezeichnet“)
  und Raster für ganze Gitter; Beschriftungen im Zeitverlauf.
- Bedienung wie beim Würfel der Kristallgitter-Aufgaben: **ziehen zum
  Drehen**, ◀ ▶ in 15°-Schritten, „Ansicht“ setzt zurück; optional dreht sich
  die Szene beim Abspielen langsam mit.
- Funktioniert in Lektionen, Rückfragen und im sokratischen Modus.

### 5zt. Fragen markieren und aus Fragen visuell lernen

- **Markieren im Daily Quiz**: Oben neben dem Fach sitzt ein Lesezeichen. Damit
  markierst du die aktuelle Frage als **„Fehler in der Frage“** (z.B. falsche
  Musterlösung, unklare Option) oder **„Merken“** – jeweils mit optionaler
  Notiz. Das Symbol zeigt den Stand (rot = Fehler, gefüllt = gemerkt);
  nochmal tippen ändert oder entfernt die Markierung.
- **„Markierte Fragen“** im Fach: alle Markierungen, filterbar nach Fehler
  oder Gemerkt, mit **Bearbeiten** (Frage korrigieren, danach Markierung
  entfernen), **Visuell erklären**, **Ändern** und **Entfernen**. Die
  Markierungen werden mit synchronisiert.
- **„Visuell erklären“ aus einer Frage** (nach dem Beantworten bei den
  Lernhilfen und in „Markierte Fragen“): Die KI baut aus Frage, Lösung,
  Erklärung und der Stelle im Skript eine Lektion wie in „Visuell lernen“ –
  wahlweise erklärt oder sokratisch, mit Animation und Übung. Sie wird im Fach
  gespeichert und gehört zur Frage: beim nächsten Mal **„Öffnen“** ohne neue
  KI-Anfrage (oder neu erstellen).
- Sync-Datenformat jetzt Version 6 – alle Geräte aktualisieren.

### 5zs. Visuell lernen: Themenliste bei mehreren PDF-Seiten

Wie bei den interaktiven Aufgaben schaut die KI bei einem **Seitenbereich oder
der ganzen PDF** erst, was drinsteckt:

- **„Themen finden“** listet die Themen der Auswahl mit Seiten, einem Satz
  Inhalt und einer **Idee, wie die App es zeigt** („So: Atome im Gitter
  schwingen stärker …“).
- Was sich **kaum sinnvoll animieren** lässt (reine Aufzählungen, Literatur,
  Organisatorisches), ist markiert – mit Grund – und nicht vorausgewählt.
- Du hakst an, was du willst → **je Thema eine eigene Lektion** mit genau
  dessen Seiten und der Darstellungs-Idee. Mehrere kleinere Anfragen statt
  einer riesigen: bessere Lektionen und seltener „KI braucht länger“.
- Eine Lektion öffnet sich gleich; bei mehreren stehen sie unten in der Liste.
  Scheitert ein Thema, bleiben die anderen erhalten (mit Hinweis).
- Eine einzelne Seite oder ein Thema ohne PDF geht wie bisher direkt.

### 5zr. Visuell lernen für jedes Fach: freie Animationen

Bisher konnte „Visuell lernen“ nur Auto, Funktionsgraph und Umformung – darum
landete die KI oft beim Auto-Beispiel, auch wenn es gar nicht um Mathe ging.
Jetzt wählt sie die Darstellung **frei nach dem Thema**:

- **Freie Szenen**: Die KI zeichnet mit Kreisen (z.B. Atome), Rechtecken
  (Körner, Bauteile), Linien, Pfeilen (Kräfte), Flächen, Kurvenzügen und Text –
  und bewegt sie über Schlüsselbilder (Position, Größe, Farbe, Drehung,
  Durchsichtigkeit, eine Kurve, die nach und nach gezeichnet wird).
  - **Raster** für Gitter (z.B. 6 × 4 Atome mit einer Angabe).
  - **Beschriftungen**, die zur Bewegung wechseln.
  - Eine **mitlaufende Größe** neben dem Zeitregler (z.B. „Temperatur =
    460 °C“).
- Beispiele: Atome, die beim Erwärmen stärker schwingen (Wärmeausdehnung), eine
  wandernde Versetzung, wachsende Körner, Diffusion, Kräfte an einem Balken,
  eine Abkühlkurve, die entsteht.
- Das **Auto nur noch bei Bewegungen**; Graphen und Umformungen weiterhin, wo
  sie passen. Mit PDF hält sich die KI an deren Inhalt und Beispiele.
- Die Übung sucht auch bei eher qualitativen Themen eine prüfbare Frage (Anzahl,
  Anteil, Abschätzung). Szenen gibt es auch in Rückfragen und im sokratischen
  Modus.

### 5zq. Visuell lernen: Erklären oder sokratisch

Beim Erstellen einer Lektion (und jederzeit oben in der Lektion umschaltbar)
wählst du, **wie** du lernst:

- **Erklären** – wie bisher: jeder Schritt wird erklärt, gezeigt und simuliert.
- **Sokratisch** – du erarbeitest dir jeden Schritt **selbst**:
  - Der Schritt bleibt zunächst verdeckt. Du siehst das Auto bzw. den Graphen
    vom Stand davor und eine **Leitfrage** (z.B. „Wie könntest du aus dem Weg
    ablesen, wie schnell das Auto gerade ist?“).
  - Du antwortest in eigenen Worten. Die KI prüft, würdigt, was stimmt, zeigt
    Widersprüche auf und stellt eine kleinere Frage – **ohne die Lösung zu
    verraten**. Dabei kann sie dir in der Simulation etwas zum Beobachten zeigen
    (z.B. die Tangente).
  - **„Tipp“** gibt einen konkreteren Hinweis, **„Auflösen“** deckt den Schritt
    auf.
  - Hast du es selbst herausgefunden: **„Selbst herausgefunden!“** – dann
    erscheinen Erklärung, Formel, Umformung und Simulation des Schritts als
    Bestätigung.
- Die Wahl wird an der Lektion gemerkt.

### 5zp. KI braucht länger: „Weiter warten“ statt Abbruch

- Antwortet OpenRouter 3 Minuten lang nicht, bricht die App nicht mehr einfach
  ab, sondern fragt: **„Weiter warten“** oder **„Abbrechen“**. Die Anfrage
  läuft dabei weiter – nichts wird neu gestartet oder doppelt bezahlt.
- Kommt die Antwort, während der Dialog offen ist, schließt er sich von selbst.
- Nach weiteren 3 Minuten fragt die App erneut. Laufen mehrere Anfragen
  gleichzeitig, gibt es nur einen Dialog.
- Typische Gründe für lange Wartezeiten: viele Seiten oder Bilder auf einmal,
  sehr lange Antworten (viele Karten), „denkende“ Modelle oder ein
  ausgelastetes Modell bei OpenRouter.

### 5zo. Visuell lernen

Im Fach unter **„Visuell lernen“** erklärt die App Mathe, Physik & Co. mit
bewegten Bildern statt nur Text:

- **Thema oder PDF**: Ein eigenes Beispiel bzw. Thema eintippen (z. B.
  „Ableitung mit einem Auto erklären“) oder leer lassen – dann sucht die KI
  selbst ein passendes Beispiel. Optional eine PDF aus dem Fach wählen oder neu
  hochladen und festlegen: **eine Seite, ein Bereich oder die ganze PDF**.
- **Detailgrad**: Kurz, Normal oder Ausführlich.
- **Lektion Schritt für Schritt**: Jeder Schritt erklärt, *warum* man ihn macht,
  *welche Formel* benutzt wird und *was das für das Beispiel bedeutet*. Dazu:
  - ein **simuliertes Auto** (Weg aus s(t) oder aufsummiert aus v(t)), mit
    Geschwindigkeitspfeil und Anzeige von Weg und Tempo,
  - **Funktionsgraphen** mit wanderndem Punkt, **Tangente** (Steigung =
    Ableitung) und **Fläche** (Integral),
  - **Umformungen langsam nacheinander** (z. B. von Δy/Δx zu dy/dx), vor- und
    zurückspulbar.
  Die KI liefert nur die Terme – alle Werte, Ableitungen und Flächen rechnet
  die App selbst nach.
- **Rückfrage zu jedem Schritt**: „Frage zu diesem Schritt“ – und wählen, ob
  die Antwort **visuell, schriftlich oder beides** sein soll (z. B. „Warum ist
  y′ = dy/dx?“ → die Umformung wird gezeigt und erklärt).
- **Danach selbst rechnen** wie bei den Rechenweg-Aufgaben. Bei einem Fehler:
  **„Simulieren“** zeigt, was deine Antwort in echt bedeuten würde (zweites,
  halb durchsichtiges Auto bzw. zweite Kurve neben der richtigen), **„Warum
  falsch?“** erklärt den Fehler visuell und schriftlich.
- Lektionen werden im Fach gespeichert und synchronisiert (Sync-Version 5 –
  alle Geräte aktualisieren).

### 5zn. Lerneinheiten zu den falschen Fragen nach dem Daily Quiz

- Ist das Daily Quiz geschafft und war heute etwas falsch (auch wenn es in der
  Wiederholung danach klappte), bietet die App **Lerneinheiten** dazu an –
  oder „Nein danke“.
- **Nach Fächern sortiert**, nicht durcheinander: erst alle Fragen eines
  Fachs, dann das nächste (Fach-Leiste oben). Je Frage: die Frage, die richtige
  Antwort und die kurze Lerneinheit (von der KI, an der Karte gespeichert, mit
  Fundstelle im Skript).
- Jede Lerneinheit lässt sich **überspringen**, ebenso der Rest eines Fachs;
  „Beenden“ bricht ganz ab.
- Nach den Lerneinheiten eines Fachs: **die Fragen nochmal versuchen** – danach
  „x von y richtig“ und die falschen erneut. Das zählt nicht für die Planung
  (die Karten wurden heute schon bewertet).
- Erledigt oder abgelehnt, erscheint das Angebot an dem Tag nicht wieder.

### 5zm. Zustandsdiagramm-Aufgaben 1:1 wie auf dem Blatt

Beispiel Blatt 6, Aufgabe 1 (Pb-Sn mit gemessener Abkühlkurve):

- **Alle Teilaufgaben in einer Karte**, in der Reihenfolge des Blatts – auch
  Wissens- und Erklärfragen („Um welchen Typ von Zweistoffsystem handelt es
  sich?“, „Schlagen Sie ein Verfahren vor …“) als Teil „Frage“: mit Auswahl
  (geprüft) oder Freitext mit Musterantwort zum Selbstbewerten.
- **Gegebene Abkühlkurve**: Ist statt einer Temperatur eine gemessene Kurve
  abgebildet, zeigt die App diese Kurve (Knick, Haltepunkt); man liest selbst
  ab, die Temperatur steht nicht mehr im Text.
- **Werte vom Blatt statt aus dem Lehrbuch**: Die KI soll alle Eckdaten aus dem
  abgebildeten Diagramm ablesen, auch wenn es vom Lehrbuch abweicht.
- **Beschriftung wie im Skript**: unter der eutektischen Linie wahlweise nach
  Gefüge („Eutektikum + α-MK“ / „Eutektikum + β-MK“, gestrichelt getrennt).
  Abkühlkurven tragen die Namen vom Blatt („100 % Pb, 0 % Sn“, „Eutektische
  Legierung“).
- Die Abbildung des Blatts wird an die Karte gehängt.

### 5zl. Gefüge skizzieren (Freihand mit KI-Bewertung) und Bilder als Antworten

- **Neuer Aufgabentyp „Freihand-Skizze“**: frei zeichnen – z.B. das Korngefüge
  vor und nach dem Walzen, nach primärer und sekundärer Rekristallisation,
  Perlit, eine Versetzung. Mehrere Zeichenflächen nebeneinander (Chips oben),
  Rückgängig/Leeren, oder **Foto der Papier-Skizze** statt Zeichnung.
- **„Von der KI prüfen lassen“**: Die Zeichnung geht als Bild an das
  Bild-Modell (Einstellungen) und wird an den hinterlegten **Kriterien**
  bewertet (je Kriterium ✓/✗/? mit Kommentar und kurzer Rückmeldung). Die
  Kriterien bleiben bis dahin verborgen. Nicht bestanden → ergänzen und
  nochmal prüfen (zählt dann als „Schwer“).
- **„Selbst prüfen“** (auch ohne KI-Key): Kriterien und Musterlösung abhaken;
  nicht alles getroffen zählt als „Nochmal“. Probeklausur: „Antwort abgeben“
  lässt die KI werten.
- Übernehmen per „Aufgabe übernehmen“ („Freihand“), aus dem ganzen Dokument
  oder per JSON-Import; im Editor Flächen, Kriterien (Pflicht/optional, je
  Fläche) und Beschreibung der Musterskizze.
- **Bilder als Antwortoptionen** bei Single-/Multiple-Choice (z.B.
  „Welches Gefügebild zeigt …?“): Beim PDF-Import mit Seitenbildern schneidet
  die App das Bild jeder Option aus der Seite aus; im Karten-Editor lässt sich
  je Option ein Bild hinzufügen oder entfernen. Beim Lernen werden die Bilder
  groß angezeigt (Lupe zum Vergrößern).
- Sync-Datenversion 4: ältere App-Versionen zeigen Freihand-Aufgaben als
  Karteikarte und Bild-Optionen nur mit ihrer Beschriftung.

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
  Kristallgitter, Stückliste, Skizze, Zustandsdiagramm, Freihand-Skizze) und liefert für alles andere gleich die
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

### 5n. KI-Modell-Favoriten

Im Modellwähler (Einstellungen und "Frage erstellen") hat jedes Modell einen
**Stern**: markierte Modelle stehen im Wähler ganz oben unter "Favoriten"
(auch beim Suchen). Beim **Frage erstellen** erscheinen die Favoriten
zusätzlich als **Schnellwahl** unter dem Modell-Feld – ein Tipp wechselt das
Modell für diese Aktion, das Standard-Modell als Favorit setzt zurück auf
"Standard". Favoriten reisen mit dem Sync auf andere Geräte.

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

### 5i. Ampel je Fach und mehrere Karten auf einmal bearbeiten

- Auf der Startseite zeigt jedes Fach einen Balken mit den Anteilen gut
  (grün), mittel (gelb) und schwach (rot) seiner gelernten Karten, darunter
  die Prozente und wie viele noch neu sind.
- Kartenliste → Knopf "Mehrere auswählen" (oder lange auf eine Karte
  drücken): Karten ankreuzen (das Häkchen an einem Ordner wählt alle seine
  Fragen), dann über das Bearbeiten-Menü Gewichtung, Stufe, Ordner oder
  Einheit für alle setzen, den Lernstand zurücksetzen oder alle löschen.

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
  Dropdown wählbar – auch **"Interaktiv"** (html, auf Android/iOS und
  im Browser interaktiv, unter Windows Karteikarte) – oder auf **"KI entscheidet"** (Standard)
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
