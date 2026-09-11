# Lernen

Eine schlanke Klausur-Lern-App für Windows, iPad (iOS) und Android – der
Nachfolger von [Quiz-app](https://github.com/nphjfvp/quiz-app), diesmal mit
engerem Fokus statt Feature-Fülle.

## Was die App macht

- **Modul-Verwaltung** – Fächer-Ordner mit Klausurdatum, in denen Folien und
  Übungsaufgaben gesammelt werden.
- **Vorbereiten-Modus** – PDF-Vorlesungsfolien hochladen → die KI erstellt
  eine strukturierte Zusammenfassung mit hervorgehobenen Kernkonzepten.
- **Nachbereiten-Modus** – Folien UND Übungsaufgaben gemeinsam hochladen →
  die KI erstellt Lernkonzepte und Karteikarten mit Fokus auf tiefem
  Verständnis der Übungen (nicht nur Theorie-Wiedergabe).
- **Daily Quiz (Exam-Scheduler)** – tägliche Lernsession über alle Fächer
  hinweg. FSRS-Spaced-Repetition für fällige Wiederholungen; die Menge neuer
  Karten wird pro Fach dynamisch an Wissensstand und Klausarnähe angepasst
  (siehe `lib/services/daily_scheduler_service.dart`).
- **BYOK** – die KI läuft über [OpenRouter](https://openrouter.ai) mit einem
  selbst mitgebrachten API-Key. Es gibt keinen App-eigenen Server; Anfragen
  gehen direkt vom Gerät an OpenRouter.
- **Cloud-Sync (optional)** – Sync-Code-basiert wie beim Vorgänger, über ein
  eigenes Firebase-Projekt. Ohne Konfiguration läuft die App komplett
  offline.
- **Account (optional)** – E-Mail/Passwort oder Google-Anmeldung über
  Firebase Auth, aus den Einstellungen heraus. Nie erzwungen: die App bleibt
  auch ohne Account voll nutzbar, Account und Sync-Code existieren
  nebeneinander.

## Bewusst NICHT enthalten (verglichen mit der Vorgänger-App)

Der Vorgänger hatte 9 Fragetypen, 6 Mini-Games, eine Coin-Economy/Shop,
Mock-Klausuren, Formelsammlungen, Sokrates-Modus u.v.m. Diese App
konzentriert sich auf den Kernkreislauf **Vorbereiten → Nachbereiten →
Daily Quiz** und verzichtet bewusst auf alles andere. Auch Vision-Pipelines
(Bild-Upload, handschriftliche Formeln) und mehrstufiges Text-Chunking für
sehr große PDFs sind (noch) nicht umgesetzt – lange Foliensätze werden aktuell
hart gekürzt (`AiService.maxInputChars`).

## Architektur

```
lib/
  models/        Module, MaterialItem, Summary, Concept, Flashcard, AppSettings
  services/
    database_service.dart          Sembast (lokale, dateibasierte NoSQL-DB)
    pdf_service.dart                PDF-Textextraktion (syncfusion_flutter_pdf)
    ai_service.dart                 OpenRouter-Anbindung (BYOK) + JSON-Reparatur
    fsrs_service.dart               FSRS-4.5 Spaced-Repetition-Algorithmus
    daily_scheduler_service.dart    Exam-Scheduler (fällige + neue Karten)
    sync_service.dart               Firestore Sync-Code Push/Pull (optional)
  repositories/    ChangeNotifier-Wrapper um die DB, für Provider/Consumer
  theme/           Design-Tokens ("Ruhig & Fokussiert") + Light-/Dark-Theme
  ui/              home, modules, prepare, review, daily, settings
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
Sie beschränken den Zugriff auf `sync_codes/{code}` (kein Auflisten/Erraten
existierender Codes möglich) und sperren alles andere per Default.

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
(`flutter run -d <platform>`).
