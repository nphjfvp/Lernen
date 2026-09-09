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
  ui/              home, modules, prepare, review, daily, settings
```

Lokale Persistenz läuft über [Sembast](https://pub.dev/packages/sembast)
(reines Dart, keine nativen Bindings nötig – funktioniert identisch auf
Windows/iOS/Android). State-Management ist bewusst einfach gehalten:
`ChangeNotifier`-Repositories + `provider`, keine zusätzliche Abstraktion.

## Setup

### 1. Flutter

Dieses Projekt wurde mit Flutter 3.47 (stable) angelegt. `flutter pub get`
im Projektverzeichnis installiert alle Abhängigkeiten.

### 2. OpenRouter-API-Key (BYOK)

Key unter <https://openrouter.ai> erstellen und in der App unter
**Einstellungen** eintragen. Es ist kein Backend nötig.

### 3. Cloud-Sync (optional)

Ohne weitere Konfiguration läuft die App vollständig offline – die
Einstellungen zeigen dann "Cloud-Sync nicht konfiguriert". Um Sync zwischen
Windows/iPad/Android zu aktivieren:

1. Eigenes Firebase-Projekt anlegen (<https://console.firebase.google.com>).
2. Firestore Database aktivieren (Testmodus reicht für den Sync-Code-Ansatz;
   für den Produktivbetrieb Security Rules ergänzen, die Lese-/Schreibzugriff
   auf `sync_codes/{code}` nicht komplett offenlassen).
3. `flutterfire configure` im Projektverzeichnis ausführen (installiert
   `firebase_options.dart` und die nötigen nativen Konfigurationsdateien für
   Android/iOS/Windows).
4. `Firebase.initializeApp()` in `lib/main.dart` nutzt danach automatisch die
   generierte Konfiguration.

### 4. PDF-Textextraktion (Syncfusion)

`syncfusion_flutter_pdf` wird für die reine Textextraktion genutzt (kein
UI-Widget). Für Privatpersonen/kleine Unternehmen ist die kostenlose
[Syncfusion Community License](https://www.syncfusion.com/sales/communitylicense)
ausreichend; für größere Organisationen ggf. Lizenz prüfen und
`SyncfusionLicense.registerLicense(...)` beim App-Start ergänzen.

### 5. Ausführen

```bash
flutter run -d windows   # Windows-Desktop
flutter run -d ios       # iOS (benötigt Xcode + Mac)
flutter run -d android   # Android
```

## Tests

```bash
flutter analyze   # statische Analyse
flutter test       # FSRS-Algorithmus, Exam-Scheduler, KI-JSON-Parsing, App-Smoke-Test
```

Die Kernlogik (FSRS-Scheduling, Exam-Scheduler-Dosierung, robuste
JSON-Extraktion aus KI-Antworten) ist mit `flutter test` ohne Gerät
abgedeckt. UI-Screens (PDF-Upload-Flows, Klausur-Countdown, Daily-Quiz-
Session) wurden in diesem Sandbox-Environment nicht auf einem echten
Windows/iOS/Android-Gerät durchgeklickt – das lohnt sich vor dem ersten
echten Einsatz nachzuholen (`flutter run -d <platform>`).
