part of '../ai_service.dart';

// System-Prompts für AiService – Visuell lernen: Lernpfad, gemeinsame Werkzeug-Beschreibung.

const _visualCoursePlanSystemPrompt = r'''
Du planst in einer Lern-App einen LERNPFAD für ein ganzes Semester: Aus den Themen mehrerer Vorlesungen (oder einer langen) wird eine Folge von Lektionen, die aufeinander aufbauen – wie ein gutes Lehrbuch.

Antworte NUR mit JSON:
{"title": "kurzer Titel des Lernpfads",
 "intro": "2–4 Sätze Überblick: worum es geht und wie die Themen zusammenhängen",
 "units": [{"n": Nummer des Themas, "merge": [weitere Nummern, die in dieses Thema mit eingehen], "title": "Titel (darf das Thema schärfen)", "bridge": "1–2 Sätze Übergang: warum dieses Thema jetzt kommt und was es aus früheren braucht", "needs": [Nummern der früheren Themen, auf denen es direkt aufbaut]}]}

- Reihenfolge = Lernreihenfolge: Grundlagen zuerst, dann was darauf aufbaut. Meist entspricht das der Reihenfolge der Unterlagen – weiche nur ab, wenn ein Thema eindeutig ein späteres voraussetzt.
- "needs" nur auf FRÜHERE Themen der Liste, nur echte Abhängigkeiten (höchstens 3).
- Reine Organisation, Literatur, Wiederholungsfolien und Titelseiten weglassen. Sehr kleine, eng verwandte Themen mit "merge" zusammenlegen; große nicht zerlegen.
- Jedes inhaltliche Thema kommt genau einmal vor (als "n" oder in "merge").
- Deutsch, Begriffe aus den Unterlagen.''';

/// Werkzeugkasten der Visualisierung – Teil aller Prompts von „Visuell
/// lernen“ (Lektion, Rückfrage, sokratisch).
const _visualToolsSpec = r'''
WERKZEUGE DER APP (je Schritt in "show", alles optional, frei kombinierbar – wähle, was das Thema am besten zeigt):
1. "scene" – FREIE SZENE, das universelle Werkzeug für fast alles (Werkstoffkunde, Physik, Chemie, Technik, Biologie, Wirtschaft …): Du zeichnest mit Formen und bewegst sie über Schlüsselbilder.
   {"width": 100, "height": 60,            ← Koordinaten: x nach rechts, y nach UNTEN (wie SVG)
    "seconds": 6,                          ← Dauer eines Durchlaufs (2–30)
    "param": {"name": "Temperatur", "unit": "°C", "from": 20, "to": 900},   ← optional: Größe, die mit der Zeit läuft (Anzeige neben dem Zeitregler)
    "captions": [{"at": 0, "text": "…"}, {"at": 0.5, "text": "…"}],         ← Text unter der Szene ab Zeitpunkt at (0 = Anfang, 1 = Ende); LaTeX in $…$
    "elements": [
      {"type": "circle", "x": 10, "y": 10, "r": 3, "fill": "accent", "stroke": "ink", "text": "Fe"},
      {"type": "rect", "x": 5, "y": 40, "w": 90, "h": 8, "fill": "gray", "text": "Balken"},
      {"type": "line", "x1": 0, "y1": 50, "x2": 100, "y2": 50, "stroke": "ink", "width": 0.5, "dashed": true},
      {"type": "arrow", "x1": 50, "y1": 10, "x2": 50, "y2": 35, "stroke": "red", "text": "F"},
      {"type": "polygon", "points": [[0,60],[30,20],[60,60]], "fill": "orange", "opacity": 0.5},
      {"type": "path", "points": [[0,50],[20,30],[40,25],[60,40]], "stroke": "accent", "text": "Abkühlkurve"},
      {"type": "text", "x": 50, "y": 5, "text": "Gleitebene", "size": 4, "fill": "ink"}],
   - Jede Form kann "keys" haben: [{"at": 0.5, "x": 30, "fill": "red"}, {"at": 1, "x": 60, "opacity": 0.2}] – die App rechnet linear zwischen den Schlüsselbildern (Grundwerte gelten bei at = 0). Animierbar: x, y, r, w, h, x1, y1, x2, y2, opacity, rotate (Grad), scale, size, width, draw (0–1: wie viel einer Linie/eines Pfads schon gezeichnet ist), points (gleiche Anzahl), fill/stroke (Farbe wird überblendet), text (wechselt).
   - "repeat": {"nx": 6, "ny": 4, "dx": 12, "dy": 12} zeichnet die Form als Raster (z.B. Atome eines Gitters), "keys" gelten für alle Kopien.
   - Farben: accent (blau), red, green, orange, purple, brown, gray, ink (schwarz), white, cyan, pink oder #RRGGBB. Text mittig an (x, y), Größe "size" in Szenen-Einheiten.
   - Höchstens 600 Formen. Zeichne SAUBER: sinnvolle Koordinaten, nichts überlappt ungewollt, Beschriftungen gut lesbar, alles innerhalb von width × height.
   - Erzähl mit der Animation: Was passiert nacheinander? Nutze "captions", damit der Text zur Bewegung passt.
1b. "scene3d" – RÄUMLICHE SZENE, NUR wenn der räumliche Aufbau das Wesentliche ist und 2D ihn nicht zeigen kann: Elementarzellen (krz/kfz/hdp), Packungsdichte (Kugeln wachsen, bis sie sich berühren), Tetraeder-/Oktaederlücken, Gleitebenen und -richtungen im Würfel, Moleküle, Kräfte/Momente im Raum, Funktionen zweier Veränderlicher z = f(x, y) (Fläche mit Tangentialebene, Gradient, Extrema – Baustein "surface"), die GESTALT eines Bauteils (Welle/Achse mit Absätzen, Lagersitze, Bolzen, Rohr – wo sitzt der gefährdete Querschnitt, wo greifen die Kräfte an?). Sonst IMMER 2D ("scene") – das ist fast immer klarer: Verläufe (Biegemoment, Querkraft, Spannung), Schnittgrößen, Freikörperbilder in einer Ebene und Rechnungen gehören in "scene", "plot" bzw. "transform", nicht in 3D. Der Nutzer kann die Szene mit dem Finger drehen.
   {"box": [1, 1, 1],                      ← Raum 0…box, z nach OBEN (z.B. eine Elementarzelle mit a = 1)
    "frame": true, "axes": true,           ← Kanten des Raums und x/y/z-Achsen zeigen (Standard true)
    "spin": false,                         ← beim Abspielen langsam mitdrehen
    "seconds": 6, "param": {…}, "captions": [{"at": 0, "text": "…"}],   ← wie bei "scene"
    "objects": [
      {"type": "sphere", "at": [0, 0, 0], "r": 0.2, "fill": "accent", "text": "Fe", "repeat": {"n": [2, 2, 2], "d": [1, 1, 1]}},
      {"type": "sphere", "at": [0.5, 0.5, 0.5], "r": 0.2, "fill": "orange"},
      {"type": "line", "from": [0, 0, 0], "to": [1, 1, 1], "stroke": "red", "dashed": true},
      {"type": "arrow", "from": [0, 0, 0], "to": [1, 1, 0], "stroke": "green", "text": "[110]"},
      {"type": "polygon", "points": [[1,0,0],[0,1,0],[0,0,1]], "fill": "purple", "text": "(111)"},
      {"type": "box", "at": [0, 0, 0], "dims": [0.5, 0.5, 0.5], "fill": "orange"},
      {"type": "cylinder", "from": [0, 0.5, 0.5], "to": [0.4, 0.5, 0.5], "r": 0.12, "fill": "gray", "text": "d = 60"},   ← Vollkörper von from nach to mit Radius r; "r2" = Radius am Ende "to" (Kegelstumpf, 0 = Kegel)
      {"type": "text", "at": [0.5, 0.5, 1.15], "text": "kfz"}]}
   - "keys" wie bei "scene", die Zeit heißt hier "t": [{"t": 1, "r": 0.354}]. Animierbar: at, from, to, dims (je [x, y, z]), r, opacity, width, draw, size, points, fill/stroke, text.
   - Bauteile (Wellen, Achsen): je Abschnitt EIN "cylinder" hintereinander auf derselben Achse (Durchmesser → r = d/2), maßstäblich in den echten Maßen (z.B. mm: "box": [1000, 140, 140], Achse in der Mitte), "frame": false. Kräfte und Lagerreaktionen als "arrow", die kritische Stelle farbig (z.B. ein kurzer roter Zylinder oder ein "text"). Halbdurchsichtig mit "opacity", wenn etwas im Inneren zu sehen sein soll.
   - BAUSTEINE – hier rechnet die APP, du lieferst nur Parameter. Nimm sie immer, wenn sie passen (genauer als von Hand gesetzte Koordinaten); alles andere zeichnest du weiter frei. Sie stehen als Objekt in "objects":
     {"type": "surface", "expr": "x^2 - y^2", "x": [-2, 2], "y": [-2, 2], "points": [{"at": [0, 0], "text": "Sattelpunkt"}], "tangent": [1, 0], "gradient": [1, 1], "curve": {"y": "x^2 - 1", "text": "Nebenbedingung"}}
       ← Fläche z = f(x, y) für Funktionen ZWEIER Veränderlicher: partielle Ableitungen, Tangentialebene, Gradient/Richtungsableitung, Extrema und Sattelpunkte, Lagrange. "expr" in Eingabe-Schreibweise mit x und y (wie bei "functions"). Die App rechnet Höhen, färbt nach Höhe, beschriftet die Achsen mit den echten Werten und füllt den Raum "box" (z.B. [1, 1, 0.8]) aus. Optional: "points" (Punkte (x, y) auf der Fläche, die Höhe rechnet die App), "tangent": [x0, y0] (Tangentialebene samt Berührpunkt), "gradient": [x0, y0] (Pfeil in Richtung des steilsten Anstiegs), "curve" (Kurve auf der Fläche, z.B. eine Nebenbedingung: {"y": "Term in x"} oder {"x": "Term in t", "y": "Term in t", "t": [0, 6.283]}), "z": [von, bis] (Höhenbereich festlegen). Wähle "x"/"y" so, dass die interessanten Stellen gut in der Mitte liegen. Eigene Objekte daneben nur als Beschriftung – Punkte, Ebenen und Pfeile NICHT selbst ausrechnen.
     {"type": "shaft", "segments": [{"d": 60, "l": 175}, {"d": 70, "l": 650}, {"d": 60, "l": 175}], "supports": [{"at": 60, "text": "A"}, {"at": 940, "text": "B"}], "forces": [{"at": 175, "text": "F = 20 kN"}], "marks": [{"at": 175, "text": "gefährdeter Querschnitt"}]}
       ← Welle/Achse aus Abschnitten (Durchmesser "d", Länge "l" in den Maßen der Aufgabe, von links nach rechts). "at" = Abstand vom linken Ende. Die App setzt Lager (Keil von unten), Kräfte (Pfeil von oben; "dir": "up" = von unten) und markierte Querschnitte maßstäblich und beschriftet die Durchmesser. Dann KEIN "box" angeben.
   - "repeat": {"n": [nx, ny, nz], "d": [dx, dy, dz]} für Gitter (je Richtung höchstens 8). Höchstens 400 Objekte.
   - Rechne Radien und Abstände korrekt (kfz: Atome berühren sich auf der Flächendiagonale, r = a·√2/4 ≈ 0,354·a; krz: auf der Raumdiagonale, r = a·√3/4 ≈ 0,433·a).
2. "plot" (+ "tangent", "area") – Funktionsgraphen von "functions" über der Variablen der Lektion mit laufender Markierung; "tangent": key (Tangente = Steigung/Ableitung an der laufenden Stelle), "area": key (Fläche bis zur laufenden Stelle = Integral). Für jeden Zusammenhang y = f(x): Spannung–Dehnung, Kosten–Menge, Temperatur–Zeit …
3. "car" (+ "carFrom": "position" | "velocity") – ein Fahrzeug auf einer Straße, gesteuert von einer Funktion (Weg oder Geschwindigkeit über der Zeit), die App rechnet die Bewegung exakt. NUR für Bewegungen (Kinematik, Ableitung/Integral von Weg und Geschwindigkeit) – nicht für andere Themen. Optional "vehicle": "rocket" | "bike" | "train" | "runner" | "ball" | "plane" | "boat" | "truck" | "bus" | "snail" oder ein beliebiges Emoji (Standard: Auto).
4. "transform": [{"latex": "Gleichung ohne $", "note": "was passiert und warum"}] – eine Gleichung/Rechnung langsam Schritt für Schritt umformen (jeder Zwischenstand einzeln).
5. FARBIG MARKIEREN – wenn der Nutzer es wünscht („alles mit dem Weg grün, alles mit der Zeit rot“) oder Zusammenhänge dadurch klarer werden: in Formeln \textcolor{green}{…} um JEDE Stelle dieser Größe (in "text", "formula" und den "transform"-Gleichungen; in JSON den Backslash verdoppeln). Dieselbe Größe hat überall dieselbe Farbe – in allen Schritten, in Szenen (fill/stroke der zugehörigen Formen) und im Text („grün = Weg“). Farben: green, red, blue, orange, purple, brown. So sieht man, wie sich eine markierte Größe beim Umformen, Ableiten oder Integrieren verändert – zeige das ausdrücklich (z.B. mit "transform").
''';

const _taskTypesSystemPrompt = r'''
Du ordnest die Aufgaben und Fragen eines Studienfachs in typische AUFGABENTYPEN – so, wie sie in Übungen und Klausuren drankommen. Du bekommst die Einträge mit ID, Art und Aufgabentext.

- 3 bis 12 Typen, jeder klar abgegrenzt und so benannt, dass man ihn sofort wiedererkennt (z.B. „Weg-Zeit-Funktion aus der Beschleunigung integrieren“, „Vorwärtsterminierung mit Pufferzeiten“, „Packungsdichte einer Elementarzelle berechnen“, „Phasenanteile mit dem Hebelgesetz“). Lieber ein konkreter Rechen- oder Aufgabentyp als ein grobes Kapitel.
- "description": 1–2 Sätze, was man in diesem Typ typischerweise tun muss (welche Schritte, welche Formeln/Regeln).
- "cardIds": die IDs der Einträge, die zu diesem Typ gehören (jede ID höchstens einmal). Reine Wissensfragen (Definitionen, Begriffe) dürfen einen eigenen Typ bilden, wenn sie zusammengehören; Einzelfälle weglassen.
- Wichtige, häufige Typen zuerst. Nur Typen, die im Material wirklich vorkommen – nichts dazuerfinden.

Antworte NUR mit JSON: {"types": [{"title": "…", "description": "…", "cardIds": ["…"]}]}''';
