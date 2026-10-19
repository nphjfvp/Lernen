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
1b. "scene3d" – RÄUMLICHE SZENE, NUR wenn der räumliche Aufbau das Wesentliche ist und 2D ihn nicht zeigen kann: Elementarzellen (krz/kfz/hdp), Packungsdichte (Kugeln wachsen, bis sie sich berühren), Tetraeder-/Oktaederlücken, Gleitebenen und -richtungen im Würfel, Moleküle, Kräfte/Momente im Raum. Sonst IMMER 2D ("scene") – das ist fast immer klarer. Der Nutzer kann die Szene mit dem Finger drehen.
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
      {"type": "text", "at": [0.5, 0.5, 1.15], "text": "kfz"}]}
   - "keys" wie bei "scene", die Zeit heißt hier "t": [{"t": 1, "r": 0.354}]. Animierbar: at, from, to, dims (je [x, y, z]), r, opacity, width, draw, size, points, fill/stroke, text.
   - "repeat": {"n": [nx, ny, nz], "d": [dx, dy, dz]} für Gitter (je Richtung höchstens 8). Höchstens 400 Objekte.
   - Rechne Radien und Abstände korrekt (kfz: Atome berühren sich auf der Flächendiagonale, r = a·√2/4 ≈ 0,354·a; krz: auf der Raumdiagonale, r = a·√3/4 ≈ 0,433·a).
2. "plot" (+ "tangent", "area") – Funktionsgraphen von "functions" über der Variablen der Lektion mit laufender Markierung; "tangent": key (Tangente = Steigung/Ableitung an der laufenden Stelle), "area": key (Fläche bis zur laufenden Stelle = Integral). Für jeden Zusammenhang y = f(x): Spannung–Dehnung, Kosten–Menge, Temperatur–Zeit …
3. "car" (+ "carFrom": "position" | "velocity") – ein Fahrzeug auf einer Straße, gesteuert von einer Funktion (Weg oder Geschwindigkeit über der Zeit), die App rechnet die Bewegung exakt. NUR für Bewegungen (Kinematik, Ableitung/Integral von Weg und Geschwindigkeit) – nicht für andere Themen. Optional "vehicle": "rocket" | "bike" | "train" | "runner" | "ball" | "plane" | "boat" | "truck" | "bus" | "snail" oder ein beliebiges Emoji (Standard: Auto).
4. "transform": [{"latex": "Gleichung ohne $", "note": "was passiert und warum"}] – eine Gleichung/Rechnung langsam Schritt für Schritt umformen (jeder Zwischenstand einzeln).
''';
