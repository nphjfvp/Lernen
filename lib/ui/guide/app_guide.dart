import 'package:flutter/material.dart';

/// Ein Punkt der Einführung: was es ist und wo man es findet.
class GuideItem {
  const GuideItem(this.title, this.text, {this.where = ''});

  final String title;
  final String text;

  /// Weg in der App, z.B. „Fächer → Fach → Vorbereiten“.
  final String where;
}

/// Ein Kapitel der Einführung (siehe AppGuideScreen).
class GuideChapter {
  const GuideChapter({required this.icon, required this.title, required this.intro, required this.items});

  final IconData icon;
  final String title;
  final String intro;
  final List<GuideItem> items;
}

/// Inhalt der Einführung (Einstellungen → Einführung). Bei neuen Funktionen
/// hier mitpflegen – die Wege müssen zu den Beschriftungen in der App passen.
const appGuideChapters = <GuideChapter>[
  GuideChapter(
    icon: Icons.route_rounded,
    title: 'Der Lernkreislauf',
    intro:
        'Die App ist um einen einfachen Ablauf gebaut: Unterlagen rein, vor und nach der Vorlesung damit '
        'arbeiten, dann jeden Tag kurz wiederholen – dosiert bis zur Klausur.',
    items: [
      GuideItem('1. Fach anlegen', 'Name, Klausurdatum und auf Wunsch die Vorlesungstermine.', where: 'Fächer → +'),
      GuideItem(
        '2. Material hochladen',
        'Folien und Übungsblätter als PDF, Word oder PowerPoint.',
        where: 'Fächer → Fach → Material → Material hochladen',
      ),
      GuideItem(
        '3. Vorbereiten',
        'Vor der Vorlesung: die KI fasst die Folien zusammen, damit du weißt, was kommt.',
        where: 'Fächer → Fach → Verstehen → Vorbereiten',
      ),
      GuideItem(
        '4. Nachbereiten',
        'Nach der Vorlesung: Konzepte und Karteikarten aus Folien und Übungen – von der KI oder selbst.',
        where: 'Fächer → Fach → Verstehen → Nachbereiten',
      ),
      GuideItem(
        '5. Daily Quiz',
        'Jeden Tag die fälligen Karten, über alle Fächer, so verteilt, dass bis zur Klausur alles sitzt.',
        where: 'Leiste unten → Daily Quiz',
      ),
      GuideItem(
        'Weiter lernen',
        'Die Karte ganz oben auf der Startseite weiß, wo du zuletzt warst: Sie setzt die angefangene Reihe an '
            'der nächsten offenen Aufgabe fort – sonst schlägt sie Üben in dem Fach vor, dessen Klausur am '
            'nächsten liegt. Darunter: Daily Quiz und Schwachstellen mit einem Tipp.',
        where: 'Leiste unten → Fächer (ganz oben)',
      ),
      GuideItem(
        'Ohne KI geht es auch',
        'Alles läuft offline. Die KI-Funktionen brauchen einen eigenen OpenRouter-Key (Kapitel „KI einrichten“).',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.folder_rounded,
    title: 'Fächer und Material',
    intro: 'Jedes Fach sammelt seine Unterlagen, Einheiten und Karten an einem Ort.',
    items: [
      GuideItem(
        'Drei Reiter je Fach',
        '„Lernen“: Üben (auch der Reihe nach), Probeklausur, markierte Fragen und dein Lernstand. „Verstehen“: '
            'Vorbereiten, Nachbereiten, Visuell lernen, Aufgaben visuell lösen, Fragen stellen. „Material“: '
            'Dateien, Import, Zusammenfassungen, Konzepte, Karten und Einheiten. Der zuletzt gewählte Reiter '
            'bleibt je Fach.',
        where: 'Fächer → Fach',
      ),
      GuideItem(
        'Fach einstellen',
        'Klausurdatum (steuert, wie viel das Daily Quiz täglich bringt), Farbe, Vorlesungstermine und der '
            'Schalter „Laborfach“ für Fächer mit Versuchen.',
        where: 'Fächer → Fach → Stift oben',
      ),
      GuideItem(
        'PDF ansehen und markieren',
        'Folien öffnen, Stellen rot/gelb/grün markieren, Notizen zu Seiten, Fragen zur aktuellen Seite stellen.',
        where: 'Fach → Material → PDF antippen',
      ),
      GuideItem(
        'Gescannte PDFs',
        'Ohne Textebene liest die Texterkennung die Seiten – automatisch oder über das Menü am Material.',
        where: 'Fach → Material → ⋮ → Texterkennung',
      ),
      GuideItem(
        'Einheiten',
        'Vorlesungen als Einheiten ordnen – selbst anlegen, von der KI vorschlagen lassen oder aus den '
            'Terminen im Stundenplan erzeugen.',
        where: 'Fach → Material → Einheiten',
      ),
      GuideItem(
        'Vorlesung kürzen',
        'Nur behalten, was für die Übungsaufgaben wirklich gebraucht wird – Grob, Mittel oder Fein.',
        where: 'Fach → Material → Vorlesung kürzen',
      ),
      GuideItem(
        'Fach teilen oder sichern',
        'Ein Fach als Datei exportieren und auf einem anderen Gerät oder bei Freunden importieren.',
        where: 'Fach → Teilen-Symbol oben · Fächer → Import-Symbol oben',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.menu_book_rounded,
    title: 'Vorbereiten und Nachbereiten',
    intro: 'Hier entstehen aus deinen Unterlagen Überblick, Lernkonzepte und Karten.',
    items: [
      GuideItem(
        'Zusammenfassung und Formelsammlung',
        'Ein KI-Überblick der Folien; auf Wunsch eine Formelsammlung in Grob, Mittel oder Fein.',
        where: 'Fach → Verstehen → Vorbereiten',
      ),
      GuideItem(
        'Lernmodus in der PDF',
        'Folien Seite für Seite durchgehen: alle paar Seiten ein kurzer Zwischen-Check (Abstand unter '
            'Einstellungen → Lernmodus), zu jeder Seite eine Frage stellen oder eine Karte daraus machen.',
        where: 'Fach → Material → PDF öffnen',
      ),
      GuideItem(
        'Karten erstellen',
        'Die KI erzeugt Konzepte und Karten, je Fakt in den Stufen Leicht, Mittel und Schwer. Den Fragetyp '
            'je Stufe kannst du vorgeben oder der KI überlassen.',
        where: 'Fach → Verstehen → Nachbereiten',
      ),
      GuideItem(
        'Fragen aus PDF importieren',
        'Die KI liest ganze Übungsblätter oder Altklausuren und übernimmt jede vorhandene Frage und Aufgabe.',
        where: 'Fach → Material → Fragen aus PDF importieren',
      ),
      GuideItem(
        'Aufgaben interaktiv machen',
        'Rechenaufgaben, Terminierungen, Stücklisten usw. werden zu Aufgaben, die die App Schritt für Schritt '
            'prüft. Vor dem Speichern kann eine zweite KI die Lösung kontrollieren.',
        where: 'Fach → Material → ⋮ → Interaktive Aufgaben daraus erstellen',
      ),
      GuideItem(
        'Andere KI nutzen',
        '„Prompt kopieren“, in ChatGPT, Gemini oder Claude.ai einfügen, Blatt anhängen und die Antwort '
            'zurück importieren.',
        where: 'Aufgaben-Ordner bzw. Aufgabe übernehmen → Aufgaben importieren',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.style_rounded,
    title: 'Daily Quiz und Lernstand',
    intro:
        'Das Daily Quiz plant mit Spaced Repetition (FSRS): Was du gut kannst, kommt seltener, was hakt, bald '
        'wieder – und alles abgestimmt auf dein Klausurdatum.',
    items: [
      GuideItem(
        'Beim Beantworten',
        'Falsch Beantwortetes kommt in derselben Runde noch einmal. Überspringen legt eine Karte nach hinten, '
            'Auflösen zeigt die Lösung. Vorher ein KI-Tipp, danach eine Erklärung oder „Im Skript“ nachsehen.',
        where: 'Daily Quiz',
      ),
      GuideItem(
        'Ampel',
        'Jede Karte ist rot, gelb oder grün. Grün gibt es erst, wenn etwas über mehrere Tage sicher sitzt.',
        where: 'Fach → Lernen (Lernstand) · Fortschritt',
      ),
      GuideItem(
        'Stufen',
        'Erst die leichte Stufe eines Fakts, dann die mittlere und die schwere – die nächste wird frei, wenn '
            'die vorige grün ist.',
      ),
      GuideItem(
        'Fragen markieren',
        'Unsichere Fragen markieren und später gesammelt ansehen oder visuell erklären lassen.',
        where: 'Beim Lernen: Lesezeichen-Symbol · Fach → Lernen → Markierte Fragen',
      ),
      GuideItem(
        'Üben und Probeklausur',
        'Frei üben unabhängig vom Plan, oder eine Probeklausur mit Zeitlimit und Note.',
        where: 'Fach → Lernen → Üben · Probeklausur',
      ),
      GuideItem(
        'Der Reihe nach',
        'Aufgaben einer Einheit oder einer PDF von vorne nach hinten lösen – für Stoff, der aufeinander aufbaut. '
            'Der Stand bleibt gespeichert: Was du nicht geschafft hast, kommt in der nächsten Runde wieder, Gelöstes '
            'wird übersprungen. „Kann ich schon“ überspringt eine Aufgabe; tippe in der Übersicht eine Aufgabe an, '
            'um dort neu zu starten, oder starte ganz von vorn. Die Reihenfolge lässt sich umschalten: wie im '
            'Dokument oder von leicht nach schwer. Zufällig üben geht weiterhin.',
        where: 'Fach → Lernen → Üben → Der Reihe nach · bei einer PDF „… Aufgaben der Reihe nach“ · im PDF oben',
      ),
      GuideItem(
        'Schwachstellen',
        'Das Fehlertagebuch zeigt, was oft schiefgeht; „Die 20 schwächsten üben“ und eine KI-Musteranalyse.',
        where: 'Fortschritt → Schwachstellen',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.extension_rounded,
    title: 'Fragetypen und Aufgaben',
    intro: 'Neben Karteikarten kann die App viele Aufgabenarten selbst abfragen und prüfen.',
    items: [
      GuideItem(
        'Fragen',
        'Karteikarte, Einfach- und Mehrfachauswahl, Lückentext, Zuordnen, Tabelle ausfüllen, Freitext mit '
            'KI-Prüfung, Bild beschriften, Bild markieren und interaktive Seiten.',
      ),
      GuideItem(
        'Interaktive Aufgaben',
        'Rechenwege, Terminierung (Gantt), Stücklisten, Kristallgitter im Würfel, Zustandsdiagramme, '
            'Diagramm skizzieren und Freihand-Skizzen mit KI-Bewertung.',
      ),
      GuideItem(
        'Rechenweg: drei Arten zu lösen',
        '„Schritt für Schritt“ führt dich mit Tipps durch die Musterlösung. „Selbst rechnen“: du schreibst deinen '
            'eigenen Rechenweg – eine Zeile je Schritt, so viele du willst – und prüfst mit ✓ hinter der Zeile jeden '
            'Schritt einzeln (die App rechnet nach, sonst die KI, ohne Weiteres zu verraten); unten stehen die '
            'Zeichen, die zur Aufgabe passen (z.B. dy/dx, y′, ∫, dx, lim, sin). Daneben (am Handy darüber) steht '
            'dein Rechenweg live in Handschrift mit echten Brüchen und Hochzahlen – wie ein Lösungsblatt; mit der '
            'Sprechblase besprichst du jeden Schritt mit der KI, vor oder nach dem Prüfen. „Abgeben“ prüft das '
            'Ergebnis. '
            '„Nur Ergebnis“: auf Papier rechnen, Ergebnis eintippen. Rückmeldung gibt es immer erst beim Prüfen bzw. '
            'Abgeben. Steht im Aufgabenbild doch eine Lösung: Stift-Symbol am Bild → abdecken oder wegschneiden.',
      ),
      GuideItem(
        'Aufgaben-Ordner',
        'Aufgaben zum Verstehen, die sich nicht als Quiz abfragen lassen. 20 Tage vor der Klausur wird der '
            'Ordner rot.',
        where: 'Fach → Material → Aufgaben-Ordner',
      ),
      GuideItem(
        'Noch nicht interaktiv',
        'Aufgaben, für die eine Bedienart fehlt, landen in einer Sammelliste – zum Kopieren und Schicken, damit '
            'der passende Typ dazukommt.',
        where: 'Einstellungen → Noch nicht interaktiv',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.animation_rounded,
    title: 'Visuell lernen',
    intro: 'Die KI erklärt Themen Schritt für Schritt mit Animationen und Simulationen – danach löst du selbst.',
    items: [
      GuideItem(
        'Lektion aus Thema oder PDF',
        'Eine Seite, einen Bereich oder die ganze PDF wählen, ausführlich oder kurz, erklärend oder sokratisch '
            '(die KI fragt, du denkst mit).',
        where: 'Fach → Verstehen → Visuell lernen',
      ),
      GuideItem(
        'Erst der Text, dann die Bilder',
        'Eine Lektion öffnet sich, sobald Texte und Formeln stehen. Die Darstellungen werden danach einzeln '
            'gezeichnet und erscheinen nach und nach – die des Schritts, den du gerade siehst, zuerst. Klappt eine '
            'nicht, holt „Jetzt zeichnen“ nur sie nach. Lieber alles in einem Stück wie früher? Das lässt sich '
            'umstellen.',
        where: 'Einstellungen → Lektionen in zwei Stufen erzeugen',
      ),
      GuideItem(
        'Aufgaben visuell lösen',
        'Die KI ordnet die Aufgaben deines Fachs in Typen. Typ antippen, Leicht, Mittel oder Schwer wählen – sie '
            'stellt eine neue Aufgabe und löst sie Schritt für Schritt; gleiche Größen haben überall dieselbe Farbe. '
            'Fragen und Wünsche gehen in die KI-Leiste unten (siehe „Die KI-Leiste“): z.B. „Markier alles mit dem '
            'Weg grün und alles mit der Zeit rot“ oder „Lass uns das an einem Beispiel durchgehen“.',
        where: 'Fach → Verstehen → Aufgaben visuell lösen',
      ),
      GuideItem(
        'Lernen – erst verstehen, dann lösen',
        'Kennst du einen Begriff aus der Aufgabe noch gar nicht, wähle in der KI-Leiste „Erst verstehen“ (oder '
            'tippe oben auf die Glühbirne). Im Lern-Chat fragst du alles, lässt es dir zeigen und an eigenen Beispielen erklären – '
            'die KI verrät die Lösung nicht und drängt nicht. Wenn du bereit bist: „Jetzt lösen“. Das Gespräch '
            'bleibt für später erhalten.',
        where: 'Aufgabe → KI-Leiste → Erst verstehen',
      ),
      GuideItem(
        'Animationen und 3D',
        'Bewegte Szenen mit Regler und Beschriftung; räumliche Szenen lassen sich drehen – Kristallgitter '
            'ebenso wie Bauteile (Wellen und Achsen mit Absätzen). Funktionen zweier Veränderlicher erscheinen als '
            'Fläche z = f(x, y) mit Tangentialebene, Gradient und Extrempunkten; Fläche und Welle rechnet die App '
            'selbst aus der Formel bzw. den Maßen. „In 3D ansehen“ öffnet echtes 3D mit Licht, Schatten und Zoom.',
      ),
      GuideItem(
        'Die KI-Leiste',
        'Unten in jeder Lektion sitzt eine Leiste mit drei Arten. „Fragen“: stell eine Frage zum Schritt – die '
            'Antwort kannst du als eigenen Schritt behalten. „Ändern“: sag, wie es aussehen soll – „zeig das als '
            'Graph“, „noch ein Zwischenschritt beim Integrieren“, „markier die Zeit rot“; der Schritt wird sofort '
            'umgebaut, auch in mehrere Schritte, „Rückgängig“ holt den alten zurück. „Als 3D-Modell“ baut ihn als '
            'drehbares Modell; ist dafür ein eigenes (teureres) Modell gewählt, fragt die App vor jeder Nutzung '
            'nach. „Ausführlich …“ ändert auch die ganze Lektion. „Erst verstehen“: Begriffe von Grund auf, ohne '
            'dass die Lösung verraten wird. Der Pfeil klappt die Leiste ein. Oben stehen „Schritt x von n“ und '
            'ein Fortschrittsbalken. Lädt eine Darstellung nicht: „Neu erzeugen“.',
        where: 'Lektion → Leiste unten',
      ),
      GuideItem(
        'Lernpfad',
        'Mehrere Vorlesungen oder ein ganzes Semester als Folge von Lektionen mit Rückblick und Kurzfassung.',
        where: 'Visuell lernen → Lernpfad erstellen',
      ),
      GuideItem(
        'Frei fragen',
        'Ohne PDF einfach fragen – die KI erklärt mit Bildern im Chat. „Als Lektion speichern“ übernimmt genau '
            'die Antworten und Darstellungen, die du siehst – ohne neue Anfrage.',
        where: 'Visuell lernen → Frag einfach',
      ),
      GuideItem(
        'Antworten behalten',
        'Eine Antwort auf deine Frage zum Schritt ist mit dem Schließen weg. „Als Schritt behalten“ legt sie '
            'samt Darstellung als eigenen Schritt in die Lektion – dann musst du sie nicht noch einmal (bezahlt) '
            'erfragen.',
        where: 'Lektion → KI-Leiste → Fragen',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.sports_esports_rounded,
    title: 'Spiele',
    intro: 'Zur Auflockerung, immer aus deinen eigenen Karten. Keine Münzen, nur dein eigener Stand.',
    items: [
      GuideItem(
        'Boss-Kampf',
        'Die schwächsten Karten eines Fachs als Endgegner: richtig trifft, falsch kostet ein Herz und die Karte '
            'kommt wieder, bis alles sitzt. Zählt wie das Daily Quiz.',
        where: 'Fortschritt → Spiele',
      ),
      GuideItem(
        'Fehlerjagd',
        'Stimmt’s oder nicht? Die KI versteckt typische Denkfehler in Aussagen zu deinem Stoff. Am Ende die '
            'gehakten Karten gezielt üben.',
        where: 'Fortschritt → Spiele',
      ),
      GuideItem(
        'Sprint',
        '60 Sekunden gegen deine schwächsten Karten, mit persönlicher Bestleistung.',
        where: 'Fortschritt → Spiele',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.insights_rounded,
    title: 'Kalender, Fortschritt, Erinnerung',
    intro: 'Überblick über Termine und darüber, wie es um deinen Stoff steht.',
    items: [
      GuideItem('Kalender', 'Vorlesungstermine und Klausuren im Monat.', where: 'Leiste unten → Kalender'),
      GuideItem(
        'Fortschritt',
        'Lernserie, Ampel-Trend über die Zeit und der Stand je Fach.',
        where: 'Leiste unten → Fortschritt',
      ),
      GuideItem(
        'Lernerinnerung',
        'Eine tägliche Benachrichtigung zur gewählten Uhrzeit (Android; im Browser nicht möglich).',
        where: 'Einstellungen → Lernerinnerung',
      ),
      GuideItem(
        'Widget (Android)',
        'Auf dem Startbildschirm: nächste Vorlesung, fällige Karten und Countdown zur Klausur.',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.science_rounded,
    title: 'Labor',
    intro: 'Für Fächer mit Laborversuchen (Schalter „Laborfach“ im Fach).',
    items: [
      GuideItem(
        'Versuch anlegen',
        'Aus der Versuchsanleitung: Vorbereitungsfragen, Ablauf und Messungen.',
        where: 'Fach → Lernen → Laborversuche',
      ),
      GuideItem('Durchführung', 'Messwerte eintragen, Fotos aufnehmen, mit KI rechnen lassen.'),
      GuideItem('Bericht', 'Ein Berichtsentwurf aus deinen Daten, den du anpasst; die KI gibt Rückmeldung.'),
    ],
  ),
  GuideChapter(
    icon: Icons.smart_toy_rounded,
    title: 'KI einrichten',
    intro:
        'Die KI läuft über OpenRouter mit deinem eigenen Key – ohne eigenen Server, du zahlst nur, was du '
        'nutzt (viele Modelle sind kostenlos).',
    items: [
      GuideItem(
        'Key eintragen',
        'Unter openrouter.ai einen Key erstellen und hier speichern. Mit Konto reist er per Sync mit.',
        where: 'Einstellungen → KI (BYOK)',
      ),
      GuideItem(
        'Modelle',
        'Getrennt wählbar für Fragenerstellen, Erklärungen, Vision (gescannte Folien), Crosscheck und '
            '3D-Modelle. Für 3D wählt die App ohne deine Angabe selbst ein günstiges Modell, das Räumliches gut '
            'kann. Favoriten markieren; Claude, GPT, Gemini usw. sind alle über OpenRouter verfügbar.',
        where: 'Einstellungen → Modelle',
      ),
      GuideItem(
        'Modelle testen',
        'Neben jeder Modellauswahl steht „Test“: Schick dieselbe Eingabe an bis zu vier Modelle und vergleiche '
            'die Ergebnisse – mit Dauer und Kosten. Fragen erstellen und visuelle Lektion aus einer kleinen PDF, '
            'einer Seite deines Materials oder eigenem Text; Erklärung zu einer Frage; Seite abschreiben (Vision); '
            'Fragen gegenprüfen; 3D-Modell aus deiner Beschreibung. Die Ergebnisse dienen nur dem Vergleich: sie '
            'bleiben 30 Minuten, mit „Behalten“ dauerhaft – im Lernstoff landet nichts. „Dieses Modell nehmen“ '
            'stellt es ein. Jeder Test kostet wie eine normale Anfrage.',
        where: 'Einstellungen → Modelle → Test',
      ),
      GuideItem(
        'Was es kostet',
        'Die App zählt mit, was OpenRouter für jede Antwort meldet: heute, in diesem Monat und insgesamt, je '
            'Modell und für die letzten Anfragen einzeln. Gezählt wird auf diesem Gerät, in US-Dollar; '
            'verbindlich ist die Abrechnung bei OpenRouter.',
        where: 'Einstellungen → KI-Kosten',
      ),
      GuideItem(
        'Wenn es hakt',
        'Bei Überlastung (häufig bei kostenlosen Modellen) versucht die App es selbst noch einmal. Dauert es '
            'lange, fragt sie, ob du weiter warten willst. Klare Fehlermeldungen sagen, was zu tun ist.',
      ),
      GuideItem(
        'Im Hintergrund',
        'Auf Android läuft eine KI-Anfrage weiter, wenn du die App kurz verlässt. Im Browser bleibt dafür der '
            'Bildschirm an.',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.devices_rounded,
    title: 'Geräte und Sync',
    intro: 'Handy, PC und iPad mit demselben Stand.',
    items: [
      GuideItem(
        'Konto und Abgleich',
        'Mit Google oder E-Mail anmelden und „Abgleichen“ – beide Seiten behalten, was neu ist. Auf Wunsch '
            'automatisch.',
        where: 'Einstellungen → Account · Cloud-Sync',
      ),
      GuideItem(
        'Ohne Konto',
        'Ein Sync-Code verbindet Geräte. Nimm „Sicheren Code erzeugen“ – kurze Codes lassen sich erraten.',
        where: 'Einstellungen → Cloud-Sync',
      ),
      GuideItem(
        'Sicherungen',
        'Die App sichert täglich auf dem Gerät; frühere Cloud-Stände lassen sich zurückholen.',
        where: 'Einstellungen → Cloud-Sync → Sicherungen · Frühere Cloud-Stände',
      ),
      GuideItem(
        'PDFs auf allen Geräten',
        'Mit einem eigenen Speicher (z.B. Cloudflare R2) reisen auch die PDF-Dateien mit.',
        where: 'Einstellungen → PDF-Speicher',
      ),
      GuideItem(
        'Updates und Web-App',
        'Android und Windows holen Updates aus der App. Im Browser (auch iPad): nphjfvp.github.io/Lernen – in '
            'Safari „Teilen → Zum Home-Bildschirm“.',
        where: 'Einstellungen → App-Version',
      ),
    ],
  ),
  GuideChapter(
    icon: Icons.inbox_rounded,
    title: 'Claude-Postfach',
    intro: 'Claude baut in einer Claude-Code-Sitzung Aufgaben aus deinen Unterlagen und legt sie dir in die App.',
    items: [
      GuideItem(
        'Einrichten',
        'Einen Postfach-Code erzeugen und Claude geben – er ist wie ein Passwort.',
        where: 'Einstellungen → Claude-Postfach',
      ),
      GuideItem(
        'Übernehmen',
        'Neue Lieferungen meldet die App beim Start. „Ansehen & übernehmen“, Fach wählen, im Import prüfen und '
            'speichern.',
        where: 'Einstellungen → Claude-Postfach → Postfach öffnen',
      ),
    ],
  ),
];
