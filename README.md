# Lernen

Eine schlanke Klausur-Lern-App für Windows, iPad (iOS) und Android – der
Nachfolger von [Quiz-app](https://github.com/nphjfvp/quiz-app), diesmal mit
engerem Fokus statt Feature-Fülle.

## Was die App macht

- **Modul-Verwaltung** – Fächer-Ordner mit Klausurdatum, in denen Folien und
  Übungsaufgaben gesammelt werden.
- **Vorbereiten-Modus** – Vorlesungsfolien als PDF, Word oder PowerPoint
  hochladen → die KI erstellt eine strukturierte Zusammenfassung mit
  hervorgehobenen Kernkonzepten. Zusammenfassungen lassen sich danach
  jederzeit bearbeiten (Titel/Kernkonzepte/Text) oder löschen.
- **Nachbereiten-Modus** – Folien UND Übungsaufgaben gemeinsam hochladen →
  die KI erstellt Lernkonzepte und Karteikarten mit Fokus auf tiefem
  Verständnis der Übungen (nicht nur Theorie-Wiedergabe). Einzelne Konzepte
  und Karteikarten lassen sich im Modul-Detail bzw. in der Karteikarten-
  Übersicht jederzeit bearbeiten oder löschen.
- **Daily Quiz (Exam-Scheduler)** – tägliche Lernsession über alle Fächer
  hinweg. FSRS-Spaced-Repetition für fällige Wiederholungen; die Menge neuer
  Karten wird pro Fach dynamisch an Wissensstand und Klausarnähe angepasst
  (siehe `lib/services/daily_scheduler_service.dart`).
- **Fragetypen & adaptive Schwierigkeit** – die KI erzeugt beim Nachbereiten
  neben klassischen Karteikarten auch Single-Choice, Multiple-Choice,
  Freitext, Lückentext sowie Drag&Drop-Zuordnung/-Kategorisierung (Auswahl je
  nach Inhalt, `lib/models/flashcard.dart` `QuestionType`,
  `lib/services/answer_checker.dart` prüft automatisch inkl. toleranter
  Tippfehler-Erkennung bei Freitext/Lückentext). Ausgewählte Single-Choice-
  Fragen tragen zusätzlich eine Eskalationskette (Single-Choice → Lückentext
  → Freitext): wird eine Frage im Daily Quiz wiederholt richtig beantwortet
  (Leitner-Box, Schwelle 3), erzeugt die KI im Hintergrund lazy die nächst
  schwierigere Variante zur selben Karte – ohne alle Stufen vorab zu
  generieren. Eine falsche Antwort senkt die Box wieder, ohne die Karte
  zurückzustufen. Bewusst NICHT enthalten: der Mathe-Formel-Fragetyp der
  Vorgänger-App.
- **Materialien & Vorarbeiten** – im Modul-Detail lässt sich beliebig viel
  Material (z.B. der komplette Semesterinhalt, als PDF/Word/PowerPoint)
  direkt hochladen, ohne dass dafür eine KI-Anfrage anfällt – reine
  Textextraktion (`lib/services/material_text_extractor.dart`) + Ablage,
  auch wieder löschbar. Jedes Material hat eine manuelle
  "Behandelt"-Markierung, die der Nutzer setzt, sobald das Thema in der
  Vorlesung dran war; sie blockiert nichts (man kann jederzeit weiter
  vorarbeiten), dient aber als zusätzlicher Kontext für den Frage-Chat.
- **Fortschritt** – eigener Tab mit Streak (aufeinanderfolgende Lerntage),
  Gesamtzahl Wiederholungen und geschätzter Behaltensrate (aus dem
  FSRS-Zustand der Karten), gesamt und pro Fach. Komplett aus vorhandenen
  Daten berechnet, kein separates Tracking (siehe
  `lib/services/stats_service.dart`).
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
  kein wirklich passendes Material (allgemeine Frage, kein Bezug zum
  Fach), liefert sie eine leere Auswahl statt krampfhaft irgendetwas
  Naheliegendes einzubeziehen – die Frage wird dann ganz normal ohne
  Materialbezug beantwortet. Über den "Mit Materialien"-Schalter im Chat
  kann der Nutzer den Materialbezug auch komplett abschalten, um bewusst
  allgemein zu fragen. Schlägt die Auswahl-Anfrage selbst fehl (Fehler statt
  Ergebnis), greift ein Sicherheitsnetz auf ein Zeichenbudget-basiertes
  Zusammenstellen aller Materialien zurück (Vorrang für behandelte).
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
  Fächer, Materialien, Konzepte, Karteikarten UND den BYOK-Teil der
  Einstellungen (API-Key + Modellwahl); Geräte-lokales wie die
  Lernerinnerungs-Uhrzeit bleibt bewusst lokal. Ohne Konfiguration läuft die
  App komplett offline.
- **Account (optional)** – E-Mail/Passwort oder Google-Anmeldung über
  Firebase Auth, aus den Einstellungen heraus. Nie erzwungen: die App bleibt
  auch ohne Account voll nutzbar. Der Hauptzweck ist der automatische
  Cloud-Sync oben (siehe dort) statt des manuellen Sync-Codes.

## Bewusst NICHT enthalten (verglichen mit der Vorgänger-App)

Der Vorgänger hatte 9 Fragetypen (inkl. Mathe-Formel-Fragen mit Formel-Editor
und Diagramm-Beschriftung/Bild-Markierung), 6 Mini-Games, eine
Coin-Economy/Shop, Mock-Klausuren, Formelsammlungen, Sokrates-Modus u.v.m.
Diese App übernimmt 6 der 9 Fragetypen inkl. der adaptiven
Schwierigkeits-Eskalation (siehe oben), lässt aber bewusst den
Mathe-Formel-Fragetyp sowie diagramm-/bildbasierte Fragetypen (Diagramm
beschriften, Bild markieren) weg und konzentriert sich ansonsten auf den
Kernkreislauf **Vorbereiten → Nachbereiten → Daily Quiz** ohne Mini-Games,
Economy o.ä. Die Vision-Modell-Rolle
existiert bereits in den Einstellungen (für später), eine konkrete
OCR-Fallback-Pipeline für gescannte/bildbasierte PDFs (Rasterung + Versand an
ein Vision-Modell) ist aber noch nicht umgesetzt – aktuell scheitert die
Textextraktion bei rein-bildbasierten PDFs mit einer klaren Fehlermeldung.

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
    ai_service.dart                 OpenRouter-Anbindung (BYOK), Chunking/Rolling
                                     Context, Crosscheck-Pass, Frage-Chat + JSON-Reparatur
    text_chunker.dart                Zerlegt lange Texte für ai_service.dart
    content_analyzer.dart            Kurzanalyse (Länge → Chunking-Empfehlung)
    chat_context_builder.dart        Baut den Material-Kontext für den Frage-Chat
    model_catalog_service.dart      Ruft OpenRouters Modell-Katalog live ab
    fsrs_service.dart               FSRS-4.5 Spaced-Repetition-Algorithmus
    daily_scheduler_service.dart    Exam-Scheduler (fällige + neue Karten)
    stats_service.dart              Streak/Wiederholungen/Behaltensrate aus
                                     vorhandenen Modul-/Karteikarten-Daten
    sync_service.dart               Firestore Sync-Code Push/Pull (optional)
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
Codes möglich) und sperren alles andere per Default.

Für ein komplett eigenes Firebase-Projekt (z.B. eigener Fork): Projekt unter
<https://console.firebase.google.com> anlegen, eine Web-App registrieren,
die angezeigte `firebaseConfig` in `lib/firebase_options.dart` eintragen,
Firestore Database aktivieren, obige Rules einfügen.

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

### 5. PDF-Textextraktion (Syncfusion)

`syncfusion_flutter_pdf` wird für die reine Textextraktion genutzt (kein
UI-Widget). Für Privatpersonen/kleine Unternehmen ist die kostenlose
[Syncfusion Community License](https://www.syncfusion.com/sales/communitylicense)
ausreichend; für größere Organisationen ggf. Lizenz prüfen und
`SyncfusionLicense.registerLicense(...)` beim App-Start ergänzen.

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
installierbare APK – auch komplett vom Handy aus nutzbar, ohne PC:

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

## Tests

```bash
flutter analyze   # statische Analyse
flutter test       # FSRS-Algorithmus, Exam-Scheduler, KI-JSON-Parsing, App-Smoke-Test
```

Die Kernlogik (FSRS-Scheduling, Exam-Scheduler-Dosierung, robuste
JSON-Extraktion aus KI-Antworten) ist mit `flutter test` ohne Gerät
abgedeckt. Zusätzlich wurde der komplette Kernablauf – Fach anlegen,
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
