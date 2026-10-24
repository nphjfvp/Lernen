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
        where: 'Fächer → Fach → Material hochladen',
      ),
      GuideItem(
        '3. Vorbereiten',
        'Vor der Vorlesung: die KI fasst die Folien zusammen, damit du weißt, was kommt.',
        where: 'Fächer → Fach → Vorbereiten',
      ),
      GuideItem(
        '4. Nachbereiten',
        'Nach der Vorlesung: Konzepte und Karteikarten aus Folien und Übungen – von der KI oder selbst.',
        where: 'Fächer → Fach → Nachbereiten',
      ),
      GuideItem(
        '5. Daily Quiz',
        'Jeden Tag die fälligen Karten, über alle Fächer, so verteilt, dass bis zur Klausur alles sitzt.',
        where: 'Leiste unten → Daily Quiz',
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
        'Fach einstellen',
        'Klausurdatum (steuert, wie viel das Daily Quiz täglich bringt), Farbe, Vorlesungstermine und der '
            'Schalter „Laborfach“ für Fächer mit Versuchen.',
        where: 'Fächer → Fach → Stift oben',
      ),
      GuideItem(
        'PDF ansehen und markieren',
        'Folien öffnen, Stellen rot/gelb/grün markieren, Notizen zu Seiten, Fragen zur aktuellen Seite stellen.',
        where: 'Fach → Materialien → PDF antippen',
      ),
      GuideItem(
        'Gescannte PDFs',
        'Ohne Textebene liest die Texterkennung die Seiten – automatisch oder über das Menü am Material.',
        where: 'Fach → Materialien → ⋮ → Texterkennung',
      ),
      GuideItem(
        'Einheiten',
        'Vorlesungen als Einheiten ordnen – selbst anlegen, von der KI vorschlagen lassen oder aus den '
            'Terminen im Stundenplan erzeugen.',
        where: 'Fach → Einheiten',
      ),
      GuideItem(
        'Vorlesung kürzen',
        'Nur behalten, was für die Übungsaufgaben wirklich gebraucht wird – Grob, Mittel oder Fein.',
        where: 'Fach → Materialien → Vorlesung kürzen',
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
        where: 'Fach → Vorbereiten',
      ),
      GuideItem(
        'Lernmodus in der PDF',
        'Folien Seite für Seite durchgehen: alle paar Seiten ein kurzer Zwischen-Check (Abstand unter '
            'Einstellungen → Lernmodus), zu jeder Seite eine Frage stellen oder eine Karte daraus machen.',
        where: 'Fach → Materialien → PDF öffnen',
      ),
      GuideItem(
        'Karten erstellen',
        'Die KI erzeugt Konzepte und Karten, je Fakt in den Stufen Leicht, Mittel und Schwer. Den Fragetyp '
            'je Stufe kannst du vorgeben oder der KI überlassen.',
        where: 'Fach → Nachbereiten',
      ),
      GuideItem(
        'Fragen aus PDF importieren',
        'Die KI liest ganze Übungsblätter oder Altklausuren und übernimmt jede vorhandene Frage und Aufgabe.',
        where: 'Fach → Fragen aus PDF importieren',
      ),
      GuideItem(
        'Aufgaben interaktiv machen',
        'Rechenaufgaben, Terminierungen, Stücklisten usw. werden zu Aufgaben, die die App Schritt für Schritt '
            'prüft. Vor dem Speichern kann eine zweite KI die Lösung kontrollieren.',
        where: 'Fach → Materialien → ⋮ → Interaktive Aufgaben daraus erstellen',
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
        where: 'Fach · Fortschritt',
      ),
      GuideItem(
        'Stufen',
        'Erst die leichte Stufe eines Fakts, dann die mittlere und die schwere – die nächste wird frei, wenn '
            'die vorige grün ist.',
      ),
      GuideItem(
        'Fragen markieren',
        'Unsichere Fragen markieren und später gesammelt ansehen oder visuell erklären lassen.',
        where: 'Beim Lernen: Lesezeichen-Symbol · Fach → Markierte Fragen',
      ),
      GuideItem(
        'Üben und Probeklausur',
        'Frei üben unabhängig vom Plan, oder eine Probeklausur mit Zeitlimit und Note.',
        where: 'Fach → Üben (Lernmodus) · Probeklausur',
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
        'Aufgaben-Ordner',
        'Aufgaben zum Verstehen, die sich nicht als Quiz abfragen lassen. 20 Tage vor der Klausur wird der '
            'Ordner rot.',
        where: 'Fach → Aufgaben-Ordner',
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
        where: 'Fach → Visuell lernen',
      ),
      GuideItem(
        'Animationen und 3D',
        'Bewegte Szenen mit Regler und Beschriftung; räumliche Szenen lassen sich drehen. „In 3D ansehen“ '
            'öffnet echtes 3D mit Licht, Schatten und Zoom.',
      ),
      GuideItem(
        'Darstellung ändern',
        'Passt eine Darstellung nicht, sag der KI, was anders sein soll; lädt eine nicht, „Neu erzeugen“.',
      ),
      GuideItem(
        'Lernpfad',
        'Mehrere Vorlesungen oder ein ganzes Semester als Folge von Lektionen mit Rückblick und Kurzfassung.',
        where: 'Visuell lernen → Lernpfad erstellen',
      ),
      GuideItem(
        'Frei fragen',
        'Ohne PDF einfach fragen – die KI erklärt mit Bildern im Chat.',
        where: 'Visuell lernen → Frag einfach',
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
        where: 'Fach → Laborversuche',
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
        'Getrennt wählbar für Fragenerstellen, Erklärungen, Vision (gescannte Folien) und Crosscheck. Favoriten '
            'markieren; Claude, GPT, Gemini usw. sind alle über OpenRouter verfügbar.',
        where: 'Einstellungen → Modelle',
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
