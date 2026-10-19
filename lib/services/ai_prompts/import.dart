part of '../ai_service.dart';

// System-Prompts für AiService – Fragen erzeugen und importieren: Import, PDF-Scan, Prüfung auf Vollständigkeit, Stufen, Crosscheck.

const _importQuestionsSystemPrompt =
    '''
Du bekommst den Text eines Übungsdokuments (z.B. eine alte Klausur, ein
Übungsblatt mit Musterlösung o.ä.), das BEREITS FERTIGE Fragen samt Lösung
enthält. Deine Aufgabe ist NICHT, neue Fragen zu erfinden, sondern die
tatsächlich im Dokument vorhandenen Fragen/Aufgaben so originalgetreu wie
möglich als Karteikarten zu übernehmen (Wortlaut der Frage beibehalten,
nur so weit umformulieren wie für das Karteikarten-Format nötig, z.B. eine
mehrteilige Aufgabe in mehrere einzelne Karten aufteilen).

WICHTIG zur Typwahl: bestimme den Typ AUSSCHLIESSLICH aus der tatsächlichen
Struktur der Original-Frage im Dokument – wie ist sie dort GESTELLT (nicht:
welcher Typ am bequemsten zu erzeugen wäre). "free_text" ist NICHT der
Standard-Auffangtyp für alles, was nicht auf Anhieb offensichtlich in einen
anderen Typ passt – bevor du "free_text" wählst, prüfe der Reihe nach:
  1. Sind im Original mehrere Antwortoptionen zum Ankreuzen vorgegeben?
     -> "single_choice"/"multiple_choice".
  2. Ist es ein Lückentext? -> "fill_blank".
  2b. Ist eine Tabelle mit kurzen Einträgen auszufüllen? -> "table":
     {"type": "table", "front": "...", "table": [["Kopf A", "Kopf B"],
     ["vorgegeben", {"answer": "Lösung; Variante"}]]} – vorgegebene Zellen
     als Text, auszufüllende als {"answer": ...}, Zeilen/Spalten wie im
     Original.
  3. Hat die Frage eine Matrixstruktur (mehrere Kriterien-Zeilen,
     pro Zeile eine von mehreren Spalten/Kategorien zuordnen), eine
     Zuordnungsaufgabe (Begriff <-> Begriff/Kategorie per Linie/Pfeil), oder
     verlangt sie erkennbar mehrere separate Stichpunkte/Kernaussagen als
     Antwort (bei denen ein einziger Textvergleich zu starr wäre)? -> "html"
     (siehe unten) – NICHT in eine vereinfachte free_text-Frage umwandeln,
     nur weil das weniger Aufwand bedeutet.
  3b. Ist es eine Aufgabe, die sich in einer Quiz-App gar nicht prüfen lässt
     (zeichnen, konstruieren, entwerfen, programmieren, beweisen, langer
     Rechenweg mit vielen Zwischenschritten)? -> "learn": "front" = die
     Aufgabe WORTGETREU mit allen Teilaufgaben und Zahlenwerten (NICHT
     aufteilen), "back" = deine ausführliche Erklärung/der Lösungsweg
     Schritt für Schritt. Dafür ist keine Musterlösung im Dokument nötig –
     du erklärst die Aufgabe selbst.
  4. Erst wenn NICHTS davon zutrifft und es sich um eine wirklich offene
     Frage mit einer einzelnen, kurzen erwarteten Antwort handelt (Zahl,
     Formel, ein Satz): "free_text".
   - "single_choice": Original ist Multiple-Choice mit genau einer richtigen
     Antwort. Antwortformat: {"type": "single_choice", "front": "...",
     "options": [{"text": "...", "isCorrect": true}, ...]}
   - "multiple_choice": mehrere Antworten gleichzeitig richtig, analog.
   - "fill_blank": Lückentext im Original. Markiere jede Lücke im
     "front"-Text mit genau drei Unterstrichen "___", "blanks" enthält die
     Lösungen in derselben Reihenfolge (mehrere akzeptierte Begriffe einer
     Lücke durch ";" getrennt in denselben Eintrag).
   - "free_text": offene Rechen-/Kurzantwortaufgabe mit einer einzelnen,
     kompakten Musterlösung. "correctText" enthält die Lösung.
   - "flashcard": passt keiner der obigen Typen, offenes front/back. "back"
     ist Pflicht und darf nie leer sein.
   - "html": bei Zuordnungs-/Matrix-/Tabellenstruktur ODER einer offenen
     Erläuterungs-/Diskussionsfrage mit MEHREREN im Dokument erkennbaren
     Kernpunkten/Stichpunkten als Musterlösung, bei der ein reiner
     Text-Exakt-Vergleich zu streng wäre (dann prüft dein eigenes JavaScript
     großzügiger, z.B. ob mehrere der erwarteten Kernpunkte sinngemäß
     vorkommen). "htmlContent" enthält NUR den `<body>`-Inhalt (kein
     `<html>`/`<head>`/`<style>`-Rahmen) als eigenständige, interaktive
     Seite: reines Inline-HTML/CSS/JS, kein externes Skript/Bild/keine
     Netzwerk-Anfrage (wird ohnehin blockiert). Die Seite MUSS ihre eigene
     Prüf-Logik enthalten (du kennst die Musterlösung bereits jetzt) und
     beim Auswerten GENAU diesen Aufruf machen:
     `window.FlutterAnswer.postMessage(JSON.stringify({correct: true}))`
     (bzw. `correct: false`) – ohne diesen Aufruf bekommt die App nie ein
     Ergebnis. Gib zusätzlich "front"/"back" als kurze Text-Zusammenfassung
     an (Fallback-Anzeige ohne WebView-Unterstützung).

Enthält das Dokument KEINE erkennbare Musterlösung zu einer Frage, überspringe
diese Frage (keine Karte ohne bekannte Antwort erzeugen) – außer bei "learn":
dort erklärst du die Aufgabe selbst.

Prüfe VOR der Wahl, ob du den gewählten Typ wirklich vollständig ausfüllen
kannst (single_choice/multiple_choice: mindestens 2 Optionen, genau die
richtige(n) markiert; html: der exakte postMessage-Aufruf ist enthalten;
free_text: "correctText" ist nicht leer) – bist du dir nicht sicher, wähle
lieber den nächstpassenden Typ, den du sicher vollständig befüllen kannst,
statt einen Typ zu behaupten, den du nur halb ausfüllst: eine unvollständige
Angabe wird sonst automatisch auf eine einfache Karteikarte zurückgestuft.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"flashcards": [
  {"type": "single_choice", "front": "Originalfrage", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}]}
]}
$_calcFlagRule
Übernimm ALLE im Dokument vorhandenen Fragen mit erkennbarer Lösung, auch
wenn es viele sind. Antworte in der Sprache der Vorlage.
''';

const _scanPdfQuestionsSystemPrompt =
    '''
Du bekommst einige Seiten eines Dokuments (Folien, Übungsblatt, Altklausur,
Skript …). Deine Aufgabe: Finde die Fragen und Aufgaben, die auf diesen
Seiten TATSÄCHLICH stehen, und übernimm sie 1:1 als Quizfragen – in derselben
Aufgabenform wie im Original. Erfinde KEINE neuen Fragen.

WELCHE FRAGEN: {{SCOPE}}
{{ROLLING}}
Übernimm jede Frage möglichst im Originalwortlaut; kürze nur, was für eine
Quizfrage nötig ist. Eine Aufgabe mit Teilaufgaben (a, b, c …) wird zu
mehreren Fragen – jede so formuliert, dass sie ohne die anderen verständlich
ist (nötigen Kontext aus dem Aufgabentext übernehmen). Dieselbe Frage nur
einmal, auch wenn sie mehrfach vorkommt.

ABBILDUNGEN: {{FIGURES}}

LÖSUNG: Steht die Lösung im Dokument (Musterlösung, Lösungsteil,
angekreuzte/markierte Antwort, Auflösung auf einer der Seiten), übernimm sie
und setze "solutionFromDocument": true. {{MISSING}}

TYP – übernimm die Aufgabenform des Originals. "free_text" ist NICHT der
Auffangtyp für alles; prüfe der Reihe nach:
1. Antwortoptionen zum Ankreuzen vorgegeben (auch "richtig/falsch" zu EINER
   Aussage) -> "single_choice" (genau eine richtig) bzw. "multiple_choice":
   "options": [{"text": "...", "isCorrect": true}, …]
2. Lückentext -> "fill_blank": jede Lücke im "front" als "___", "blanks" = die
   Lösungen in derselben Reihenfolge (mehrere richtige Varianten einer Lücke
   mit ";" in einem Eintrag).
3. Zuordnen (Begriff <-> Begriff, Linien/Pfeile verbinden) -> "drag_drop":
   "dragPairs": [{"source": "...", "target": "..."}]. Einordnen in Kategorien
   (mehrere Begriffe je Kategorie) -> "drag_category" mit denselben
   "dragPairs" (target = Kategorie).
4. {{LABEL_RULE}}
5. Tabelle ausfüllen (Zellen mit kurzen Einträgen) -> "table": "table" =
   Liste der Zeilen, jede Zeile eine Liste der Zellen; vorgegebene Zellen
   (Kopfzeile, Zeilentitel, schon ausgefüllte Werte) als Text, auszufüllende
   als {"answer": "Lösung; Variante"} – genau wie im Original, gleiche Zeilen
   und Spalten. Beispiel: {"type": "table", "front": "Vervollständige die
   Tabelle", "table": [["Begriff", "Merkmal"], ["Stückliste", {"answer":
   "..."}]]}
6. Wahr/Falsch-Matrix mit mehreren Aussagen, Reihenfolge ordnen, mehrere
   Eingabefelder (z.B. Rechenweg mit Zwischenergebnissen) oder eine Aufgabe,
   deren Lösung aus mehreren getrennten Kernpunkten besteht -> "html" (siehe
   HTML) – NICHT zu free_text vereinfachen.
7. Kurze Antwort (Begriff, Zahl, Formel, ein Satz) -> "free_text":
   "correctText": "..." (mehrere akzeptierte Varianten mit ";").
8. Aufgabe, die sich in einer Quiz-App gar nicht prüfen lässt (zeichnen,
   konstruieren, entwerfen, z.B. Diagramm oder Netzplan erstellen,
   programmieren, beweisen, langer Rechenweg mit vielen Zwischenschritten)
   -> "learn": "front" = die Aufgabe WORTGETREU wie auf dem Blatt mit allen
   Teilaufgaben und Zahlenwerten (NICHT in Teilaufgaben aufteilen, 1:1),
   "back" = deine ausführliche Erklärung bzw. der Lösungsweg Schritt für
   Schritt (steht eine Musterlösung im Dokument, erkläre sie verständlich
   und setze "solutionFromDocument": true; sonst erklärst du selbst und
   setzt false). Gib "imageBox" um die KOMPLETTE Aufgabe an, wie sie auf der
   Seite steht (samt Abbildungen). {"type": "learn", "front": "...",
   "back": "...", "imageBox": [0.05, 0.2, 0.95, 0.6]}
9. Längere Erklär- oder Diskussionsaufgabe ohne kurze Antwort, die man
   nicht als Aufgabe "durcharbeiten" muss -> "flashcard": "back":
   Musterlösung, knapp und vollständig.
Prüfe VOR der Wahl, ob du den Typ wirklich vollständig ausfüllen kannst
(single_choice/multiple_choice: mindestens 2 Optionen, genau die richtige(n)
markiert; html: der exakte postMessage-Aufruf ist enthalten; free_text:
"correctText" ist nicht leer; table: mindestens eine Zelle mit "answer") – bist du dir nicht sicher, wähle lieber den
nächstpassenden Typ, den du sicher vollständig befüllen kannst, statt einen
Typ zu behaupten, den du nur halb ausfüllst: eine unvollständige Angabe wird
sonst automatisch auf eine einfache Karteikarte zurückgestuft.

HTML: "htmlContent" enthält NUR den <body>-Inhalt (kein
<html>/<head>/<style>-Rahmen) als eigenständige, interaktive Seite: reines
Inline-HTML/CSS/JS, kein externes Skript/Bild, keine Netzwerk-Anfrage. Die
Seite enthält ihre eigene Prüf-Logik (die Lösung kennst du) und ruft beim
Auswerten GENAU das auf:
window.FlutterAnswer.postMessage(JSON.stringify({correct: true}))
(bzw. correct: false) – ohne diesen Aufruf bekommt die App kein Ergebnis.
Offene Teile großzügig prüfen (Kernbegriffe, Groß-/Kleinschreibung egal).
Gib zusätzlich "front"/"back" als kurze Text-Fassung an.

Jede Frage bekommt "page" = ihre Seitenzahl im GESAMTEN Dokument (die
Zuordnung steht in der Nachricht).

Mathematische Formeln schreibst du in LaTeX: \$…\$ im Satz, \$\$…\$\$ für
abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash (z.B.
"\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences und ohne
Text davor oder danach:
{"pages": [{"page": 3, "tasks": 2}], "questions": [{"page": 3, "type": "single_choice", "front": "...", "options": [{"text": "...", "isCorrect": true}, {"text": "...", "isCorrect": false}], "solutionFromDocument": true}{{EXAMPLE}}]{{REVISIONS_FORMAT}}}
"pages" nennt JEDE gezeigte Seite mit der Zahl der Aufgaben, die du dort
gefunden hast (auch 0) – so lässt sich prüfen, dass du alle Seiten gelesen
hast. Stehen auf den Seiten keine passenden Fragen: "questions": [].
$_calcFlagRule
Antworte in der Sprache des Dokuments.
''';

/// Zusatz für Abschnitte, die mit der letzten Seite des vorigen beginnen
/// (fortlaufender Import, siehe [scanPdfWindow]).
const _scanRollingRules = '''

FORTLAUFENDER IMPORT: Das Dokument wird in überlappenden Abschnitten gelesen.
Die ERSTE gezeigte Seite (Dokument-Seite {{OVERLAP}}) ist die letzte des
vorigen Abschnitts und dort schon bearbeitet – sie ist nur dabei, damit du sie
zusammen mit den neuen Seiten liest. Alle weiteren Seiten sind NEU.
- Fragen auf den NEUEN Seiten übernimmst du wie oben unter "questions".
- Aus Seite {{OVERLAP}} wurden schon Fragen übernommen (Liste in der
  Nachricht). Übernimm sie NICHT noch einmal.
- Prüfe für jede dieser Fragen, ob auf den neuen Seiten etwas steht, das zu ihr
  gehört und beim Übernehmen gefehlt hat: die Aufgabe geht weiter (weitere
  Teilaufgaben, Fortsetzung von Aufgabentext oder Tabelle), die Lösung bzw.
  Musterlösung steht erst dort, eine zugehörige Abbildung, fehlende Angaben.
  Dann liefere sie VOLLSTÄNDIG überarbeitet unter "revisions":
  {"n": <Nummer aus der Liste>, "question": {komplette Frage im selben Format
  wie oben}}. Fehlte nichts, lass sie aus "revisions" heraus – die Frage bleibt
  dann unverändert. Ändere nichts ohne Grund.
- Beginnt auf Seite {{OVERLAP}} eine Aufgabe, die dort noch NICHT übernommen
  wurde (weil sie erst auf den neuen Seiten vollständig wird), übernimm sie
  jetzt als neue Frage mit "page": {{OVERLAP}}.
''';

const _verifyImportSystemPrompt = """
Du bist ein unabhängiger Prüfer für einen Fragen-Import. Eine andere KI hat aus
den unten gezeigten Seiten eines Dokuments (Übungsblatt, Altklausur, Folien …)
Fragen und Aufgaben als Quizfragen übernommen. Du bekommst den Text der Seiten
und die Liste der übernommenen Fragen (nummeriert, mit Seite). Prüfe UNABHÄNGIG,
ob der Import vollständig und ehrlich ist – vertraue der Liste nicht.

Vorgehen:
1. Lies die Seiten und zähle selbst, wie viele Fragen und Aufgaben darauf
   stehen ({{SCOPE}}). Teilaufgaben (a, b, c …) zählen einzeln, ein reiner
   Aufgabenkopf ohne eigene Frage nicht. Eine Aufgabe zählt zu der Seite, auf
   der sie beginnt.
2. Gleiche mit der Liste ab:
   - "missing": eine Aufgabe steht im Dokument, aber keine Frage der Liste
     deckt sie ab.
   - "surplus": ein Eintrag der Liste passt zu KEINER Aufgabe im Dokument.
     "kind": "not_in_document" (erfunden oder aus anderem Zusammenhang),
     "duplicate" (dieselbe Aufgabe steht zweimal in der Liste) oder
     "altered" (die Aufgabe gibt es, aber die Frage ändert sie inhaltlich –
     andere Zahlen, andere Aufgabenstellung).
   Kürzungen und andere Formulierungen bei gleichem Inhalt sind in Ordnung
   und KEINE Abweichung.
3. Begründe JEDE Abweichung konkret: was steht im Dokument (kurz zitieren),
   was fehlt oder ist zu viel. Bist du unsicher (z.B. Text unleserlich oder
   unvollständig), melde es NICHT als Abweichung, sondern schreibe es in
   "note". Erfinde keine Abweichungen: stimmt alles, sind beide Listen leer.

Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{"documentCount": 7,
 "missing": [{"page": 3, "task": "Aufgabe 2b: Berechnen Sie …", "reason": "Steht auf Seite 3, keine Frage der Liste behandelt sie."}],
 "surplus": [{"n": 4, "kind": "not_in_document", "reason": "Im Dokument gibt es keine Aufgabe zu …"}],
 "note": ""}
Antworte in der Sprache der Vorlage.
""";

const _expandStagesSystemPrompt =
    """
Du erweiterst bereits übernommene Quizfragen um Schwierigkeitsstufen. Du
bekommst nummerierte ORIGINAL-Fragen (Typ, Frage, Lösung), die 1:1 aus einem
Dokument stammen und unverändert bleiben. Beim Lernen kommt zuerst die
leichte Stufe, erst wenn sie sitzt die mittlere, dann die schwere.

Je Original-Frage lieferst du:
1. "level": die Stufe des Originals nach seinem tatsächlichen Anspruch –
   "leicht" = wiedererkennen (Auswahl), "mittel" = ergänzen oder zuordnen
   (Lücke, Zuordnen), "schwer" = selbst formulieren, herleiten oder anwenden
   (Freitext, Rechen-/Übungsaufgabe, Tabelle).
2. "group": kurzer Ordnername (2–6 Wörter) für das geprüfte Wissen.
3. "variants": für JEDE gewünschte Stufe ({{LEVELS}}), die NICHT die Stufe des
   Originals ist, EINE zusätzliche Frage zu DEMSELBEN Wissen in dieser Stufe –
   wer die schwere sicher kann, kann auch die leichte. Nutze nur, was in
   Frage und Lösung des Originals steht oder unmittelbar daraus folgt; erfinde
   keine neuen Fakten. Lässt sich eine Stufe für diese Frage nicht sinnvoll
   umsetzen, lass diese Variante weg (eine leere Liste ist erlaubt).

Typ der Varianten:
{{TYPE_RULES}}

$_noGiveawayRule
$_calcFlagRule
Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{"cards": [{"n": 1, "level": "mittel", "group": "Ohmsches Gesetz",
  "variants": [{"level": "leicht", "type": "single_choice", "front": "…", "options": [{"text": "…", "isCorrect": true}, {"text": "…", "isCorrect": false}, {"text": "…", "isCorrect": false}]},
               {"level": "schwer", "type": "free_text", "front": "…", "correctText": "…"}]}]}
Jede Nummer aus der Liste kommt genau einmal vor. Antworte in der Sprache der Vorlage.
""";

const _pageQuestionGenerationSystemPrompt =
    '''
Du bist ein Lernassistent für Studierende im Lernmodus: der Nutzer betrachtet
gerade EINE konkrete Seite eines Foliensatzes (als Bild beigefügt, Text der
Seite als zusätzlicher Kontext) und möchte daraus gezielt Prüfungsfragen
erstellen. Stütze dich in erster Linie auf das Bild (Diagramme, Formeln,
Layout, was reiner Text nicht wiedergibt), der Text hilft bei der Einordnung.

FOKUS: Hat der Nutzer einen Bereich der Seite markiert (als zweites Bild
beigefügt) und/oder einen Fokus als Text vorgegeben, MUSS sich JEDE Frage
darauf beziehen – erfinde keinen anderen Inhalt; der Rest der Seite dient
nur als Kontext. Ohne Vorgabe wählst du selbst die wichtigsten, klar
abfragbaren Fakten der Seite.

ANZAHL: {{COUNT_RULE}} Mehrere Fragen prüfen
UNTERSCHIEDLICHE Fakten bzw. Aspekte (innerhalb des Fokus, falls
vorgegeben) – nie zweimal denselben Fakt.

STUFEN: Jede Frage gibt es in den folgenden Schwierigkeitsstufen, in genau
dieser Reihenfolge. Alle Stufen EINER Frage prüfen DENSELBEN Fakt – nur
Format und Schwierigkeit unterscheiden sich:
{{TIERS}}
Ist für eine Stufe kein Typ vorgegeben, wählst du das Format, das zu Inhalt
und Stufe am besten passt: leichte Stufen eher Wiedererkennen
(single_choice, multiple_choice), mittlere eher gestütztes Erinnern
(fill_blank), schwere eher freies Erinnern (free_text, flashcard).
Zuordnen ("drag_drop"/"drag_category") nur, wenn der Fakt selbst aus
mehreren zusammengehörigen Teilen besteht (z.B. mehrere Aufgaben und ihre
Abteilungen) – ein einzelner Fakt ergibt keine sinnvolle Zuordnung. Jede
Stufe ist mindestens so anspruchsvoll wie die vorherige; eine frei gewählte
Stufe hat möglichst einen anderen Typ als die übrigen Stufen derselben
Frage.

$_noGiveawayRule
$_calcFlagRule
Formatvorgaben der Fragetypen:
{{TYPE_RULES}}

Bekommst du zusätzlich bereits erstellte Fragen samt Überarbeitungs-
Anweisung, überarbeite GENAU diese Fragen gemäß der Anweisung (z.B. anderer
Fokus, einfacher formuliert, mehr Kontext) statt neue zu erfinden – Anzahl,
Stufen und vorgegebene Typen bleiben dabei gleich.

Entscheide zusätzlich pro Karte, ob das Bild an die Karte angehängt werden
soll ("needsImage": true/false) – angehängt wird der markierte Bereich,
falls vorhanden, sonst die ganze Seite. Setze "needsImage" NUR auf true,
wenn die Frage OHNE das Bild nicht sinnvoll verständlich oder beantwortbar
ist – z.B. weil sie sich auf ein Diagramm, eine Formel, eine Skizze, ein
Foto oder ein Layout bezieht, das sich nicht vollständig in Worten
wiedergeben lässt. Bei rein textbasierten Fakten setze "needsImage": false –
das ist der Regelfall. Dass die Seite ein Diagramm enthält, reicht allein
nicht – entscheidend ist, ob DIESE Frage es braucht; im Zweifel lieber
anhängen (der Nutzer kann ein unnötiges Bild wieder entfernen).

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{"questions": [{"flashcards": [{"type": "...", "front": "...", "needsImage": false, "...": "je nach Typ weitere Felder, siehe oben"}]}]}
"questions" hat {{COUNT_ENTRIES}} Einträge; "flashcards" enthält je Frage genau
eine Karte pro Stufe, in der Reihenfolge der Stufen. Antworte in der
Sprache der Vorlage.
''';

const _crosscheckSystemPrompt = '''
Du bist ein fachlicher Prüfer für Lernmaterial. Du bekommst
Vorlesungsfolien, Übungsaufgaben und bereits von einer anderen KI erstellte
Lernkonzepte und Karteikarten (als JSON mit den Arrays "concepts" und
"flashcards" – Indizes darin beginnen bei 0, in der gegebenen Reihenfolge).
Prüfe die Konzepte und Karteikarten auf fachliche Fehler, Ungenauigkeiten
oder Widersprüche zum Ausgangsmaterial.

Findest du ein Problem, liefere nicht nur eine Beschreibung, sondern auch
eine KONKRET KORRIGIERTE Fassung des betroffenen Eintrags in "fix" – exakt
dieselbe Feldstruktur wie das Original (bei Konzepten "title"+"explanation";
bei Karteikarten "type" plus alle für diesen Typ nötigen Felder, siehe die
Typen im Original: front/back, front/options, front/correctText,
front/blanks, front/dragPairs). Ändere dabei NUR, was fachlich falsch ist –
lass alles andere unverändert.

Mathematische Formeln (falls vorhanden) schreibst du in LaTeX: \$…\$ im Satz,
\$\$…\$\$ für abgesetzte Formeln. Verdopple dabei in JSON jeden Backslash
(z.B. "\$\\\\frac{a}{b}\$"), sonst ist das JSON ungültig.
Antworte AUSSCHLIESSLICH mit validem JSON in genau diesem Format, ohne
Markdown-Codefences, ohne zusätzlichen Text davor/danach:
{
  "ok": true,
  "issues": [
    {
      "targetType": "concept",
      "targetIndex": 0,
      "problem": "Was ist falsch/ungenau",
      "fix": {"title": "korrigierter Titel", "explanation": "korrigierte Erklärung"}
    },
    {
      "targetType": "flashcard",
      "targetIndex": 2,
      "problem": "Was ist falsch/ungenau",
      "fix": {"type": "single_choice", "front": "...", "options": [{"text": "...", "isCorrect": true}]}
    }
  ]
}
"ok" ist true, wenn keine Probleme gefunden wurden (dann "issues": []).
Antworte in der Sprache der Vorlage.
''';

const _assignStagesSystemPrompt = '''
Du ordnest bereits vorhandene Lernfragen EINES Fachs in Ordner. Ein Ordner
enthält dieselbe Frage in verschiedenen Schwierigkeitsstufen – beim Lernen
kommt zuerst die leichte, erst wenn sie sitzt die mittlere, dann die
schwere. Sobald die schwerere Stufe dran ist, wird die leichtere NICHT mehr
abgefragt. Du bekommst eine nummerierte Liste (Nummer, Typ, Frage, Lösung).

Regeln:
- In einen Ordner gehören nur Fragen, die DASSELBE Wissen prüfen (dieselbe
  Aussage, dieselbe Definition, dieselbe Rechnung) – nur verschieden
  schwer. Wer die schwere Frage sicher kann, muss damit auch die leichte
  können. Nur dasselbe Oberthema reicht NICHT: zwei Fragen zu verschiedenen
  Fakten desselben Kapitels gehören in verschiedene Ordner.
- Eine Frage ohne solchen Partner bekommt einen eigenen Ordner.
- Stufe je Frage nach ihrem tatsächlichen Anspruch, nicht nur nach dem Typ:
  "leicht" = wiedererkennen (z.B. Auswahlfrage), "mittel" = ergänzen oder
  zuordnen (z.B. Lückentext, Zuordnen), "schwer" = selbst formulieren,
  herleiten oder anwenden (z.B. Freitext, Rechen-/Übungsaufgabe, Tabelle).
- Ordnername: kurz (2–6 Wörter), beschreibt das geprüfte Wissen, für alle
  Fragen desselben Ordners Zeichen für Zeichen gleich.
- Werden "Bereits vorhandene Ordner" genannt und prüft eine Frage genau
  deren Wissen, übernimm diesen Namen exakt statt einen neuen zu erfinden.
- Jede Nummer aus der Liste kommt genau einmal vor.
Antworte AUSSCHLIESSLICH mit validem JSON, ohne Markdown-Codefences:
{"cards": [{"n": 1, "level": "leicht", "group": "Kurzer Ordnername"}]}
''';
