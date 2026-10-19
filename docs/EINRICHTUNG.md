# Lernen – Einrichtung und Entwicklung

API-Key, Cloud-Sync, Account, PDF-Speicher, Builds, Updates, Backups und Tests.
Kurzüberblick: [README](../README.md).

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
Codes möglich) samt deren Unterdokumenten `sync_parts/*` und sperren alles
andere per Default. **Nach dem Update auf den aufgeteilten Sync einmal neu
veröffentlichen** – ohne die `sync_parts`-Regel klappt der Upload nur,
solange der komprimierte Bestand in ein Dokument passt (die App meldet es
dann verständlich).

Für ein komplett eigenes Firebase-Projekt (z.B. eigener Fork): Projekt unter
<https://console.firebase.google.com> anlegen, eine Web-App registrieren,
die angezeigte `firebaseConfig` in `lib/firebase_options.dart` eintragen,
Firestore Database aktivieren, obige Rules einfügen.

### 3a. Fach exportieren/importieren (JSON-Datei)

Unabhängig vom Cloud-Sync (der immer den GESAMTEN lokalen Datenbestand
spiegelt): ein einzelnes Fach lässt sich als eigenständige JSON-Datei
sichern oder weitergeben – z.B. um es an ein anderes Gerät ohne Account zu
übertragen, mit jemand anderem zu teilen, oder einfach als Backup vor dem
Löschen (`ModuleExportService`).

- **Exportieren**: Im Modul-Detail oben rechts (Teilen-Symbol) – schreibt
  Modul, Einheiten, Materialien (inkl. Original-PDF-Bytes, plattform-
  unabhängig als Base64 eingebettet, siehe `ModuleExportService.embedBytes`),
  Zusammenfassungen (Vorbereiten), Konzepte und Karteikarten in eine
  `.json`-Datei (Speichern-Dialog über
  `file_picker`, funktioniert auch im Web als Download). Bewusst NICHT
  enthalten: Chat-Verlauf und Ampel-Trend-Snapshots – geräte-/sitzungs-
  bezogene Verlaufsdaten ohne Bezug zum eigentlichen Fach-Inhalt.
- **Importieren**: Auf dem Start-Bildschirm ("Meine Fächer") über das
  Symbol neben dem Titel – legt aus einer solchen Datei ein NEUES Fach an.
  Alle IDs (Modul, Einheiten, Materialien, Konzepte, Karteikarten) werden
  dabei frisch vergeben, alle Querverweise dazwischen konsistent
  mitübersetzt (`ModuleExportService.parse`) – dieselbe Datei lässt sich
  daher beliebig oft importieren, auch mehrfach auf demselben Gerät, ohne
  mit vorhandenen Daten zu kollidieren. Enthält die Datei einen Lernstand,
  fragt der Import "Übernehmen" oder "Neu beginnen" (bei weitergegebenen
  Fächern: alle Karten neu, Stufen-Ketten wieder auf der leichtesten Stufe);
  gespeichert wird in einer einzigen Transaktion (kein halbes Fach beim
  Abbruch).

### 3b. Eigener PDF-Speicher (optional)

Der Firestore-Sync überträgt nur Text und Lernstand – Firebase Storage für die
Dateien bräuchte den kostenpflichtigen Blaze-Tarif. Stattdessen bringt man
(wie beim API-Key) seinen eigenen Speicher mit: **Einstellungen →
PDF-Speicher**. Ohne Eintrag passiert nichts.

- **Cloudflare R2** (10 GB kostenlos, kein Traffic-Entgelt): Bucket anlegen,
  unter "R2 → API-Token verwalten" ein Token mit "Objekt lesen & schreiben"
  für diesen Bucket erstellen. In der App: S3-kompatibel, Endpunkt
  `https://<konto-id>.r2.cloudflarestorage.com`, Bucket-Name, Region `auto`,
  Access Key ID + Secret Access Key, Pfad-Adressierung an.
- **Backblaze B2** (10 GB kostenlos): Bucket (privat) + Application Key
  anlegen. Endpunkt `https://s3.<region>.backblazeb2.com`, Region z.B.
  `eu-central-003`, keyID als Access Key, applicationKey als Secret.
- **AWS S3 / MinIO**: wie oben; neue AWS-Buckets brauchen Pfad-Adressierung
  aus.
- **WebDAV** (Nextcloud, Uni-Cloud, ownCloud): Ordner-URL wie
  `https://cloud.example.de/remote.php/dav/files/NAME/Lernen`, Benutzername,
  **App-Passwort** (in Nextcloud unter Einstellungen → Sicherheit erzeugen).

"Speichern & testen" prüft Adresse und Zugangsdaten. Danach lädt jeder Sync
(automatisch oder "Hochladen") noch nicht hochgeladene PDFs vorab hoch
(`lernen-pdfs/<material-id>.pdf`); öffnet man auf einem anderen Gerät ein
Material ohne lokale Datei, wird sie dort bei Bedarf geholt. Gelöschte
Materialien werden auch im Speicher entfernt. Die Zugangsdaten reisen wie der
API-Key nur über den Konto-Sync, nie über einen Sync-Code – einmal eintragen
reicht, die anderen Geräte bekommen sie beim nächsten "Abgleichen" (mit
Auto-Sync wird die Änderung sofort hochgeladen und beim Öffnen der App geholt).

**Web-Version:** der Browser lässt die Anfragen nur zu, wenn der Speicher
CORS für die Adresse der App erlaubt. Bei R2/B2 in den Bucket-Einstellungen
eine CORS-Regel anlegen, z.B.:

```json
[{"AllowedOrigins": ["https://<deine-app-adresse>"],
  "AllowedMethods": ["GET", "PUT", "DELETE", "HEAD"],
  "AllowedHeaders": ["*"], "MaxAgeSeconds": 3600}]
```

(B2 nutzt im Web-UI ein eigenes Format mit denselben Angaben.) Nextcloud
erlaubt fremde Web-Origins meist nicht – dort funktioniert der PDF-Speicher
in den nativen Apps (Android/Windows/iOS), die kein CORS brauchen.

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

### 5. PDF-Textextraktion + -Ansicht (Syncfusion)

`syncfusion_flutter_pdf` wird für die reine Textextraktion genutzt (kein
UI-Widget), `syncfusion_flutter_pdfviewer` zusätzlich für die visuelle
Folien-Ansicht + Markier-Funktion (`MaterialViewerScreen`, siehe unten). Für
Privatpersonen/kleine Unternehmen ist die kostenlose
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
IndexedDB des Browsers statt in einer Datei; die PDF-Anzeige nutzt dort
PdfJs, eingebunden in `web/index.html`). Für die Ziel-Plattformen:

```bash
flutter run -d windows   # Windows-Desktop (braucht Visual Studio C++-Workload)
flutter run -d ios       # iOS (benötigt Xcode + Mac)
flutter run -d android   # Android (Emulator oder Gerät mit USB-Debugging)
```

`flutter devices` zeigt an, was auf dem jeweiligen Rechner tatsächlich
verfügbar ist.

### Android-APK ohne eigenen Rechner (GitHub Actions)

Bei jedem Push baut `.github/workflows/android-apk.yml` automatisch eine
installierbare APK – auch komplett vom Handy aus nutzbar, ohne PC. **Als
Update veröffentlicht** (Release `android-latest`/`windows-latest`) wird nur
vom App-Branch `claude/neue-lern-app-fokus-ej3k48`; andere Branches liefern
nur das Artifact am Actions-Lauf. Vor dem
Build laufen `flutter analyze` und `flutter test`; schlägt eins davon fehl,
wird keine neue APK veröffentlicht (gilt ebenso für die Windows-App):

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

`.github/workflows/windows-app.yml` baut analog eine native Windows-App
(`flutter build windows`) und veröffentlicht sie unter Release
**"Windows-App (aktueller Stand)"** (Tag `windows-latest`) auf zwei Arten:

- **`Lernen-Setup.exe`** (empfohlen) – eine einzige Datei. Sie installiert
  die App nur für den eigenen Benutzer (keine Admin-Rechte) nach
  `%LOCALAPPDATA%\Programs\Lernen`, legt eine Startmenü- und auf Wunsch
  eine Desktop-Verknüpfung an und lässt sich unter "Apps" wieder
  deinstallieren. Gebaut mit Inno Setup aus `windows/installer/lernen.iss`.
  Beim ersten Start einer ungesignierten Datei zeigt Windows SmartScreen
  eine Warnung ("Weitere Informationen" → "Trotzdem ausführen").
- **`lernen-windows.zip`** – dieselbe App zum Entpacken (portable), die
  `lernen.exe` muss dann im Ordner neben ihren DLLs und dem `data`-Ordner
  bleiben.

Eine einzelne `.exe` ganz ohne Begleitdateien gibt es bei Flutter nicht –
die Engine (`flutter_windows.dll`), die Plugin-DLLs und `data/` werden zur
Laufzeit gebraucht. Das Setup versteckt diesen Ordner nur. Die Lerndaten
liegen ohnehin getrennt davon in `%APPDATA%` und bleiben bei Updates,
Neuinstallation oder dem Wechsel vom ZIP zum Setup erhalten.

### Web-App (iPad, iPhone, jeder Browser)

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

### Eigener Signierschlüssel

Ohne Secrets signiert die CI mit dem eingecheckten Debug-Schlüssel
(`android/app/debug.keystore`). Für einen eigenen Schlüssel:

1. Schlüssel erzeugen (einmal, auf dem PC; `keytool` gehört zu jedem Java/
   Android Studio):
   `keytool -genkeypair -v -keystore lernen-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias lernen`
   – Datei und Passwort gut aufheben (ohne sie keine Updates mehr).
2. Base64 davon: PowerShell
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("lernen-release.jks")) | Set-Clipboard`
3. GitHub → Settings → Secrets and variables → Actions → vier Secrets:
   `ANDROID_KEYSTORE_BASE64` (Base64 von oben), `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS` (`lernen`), `ANDROID_KEY_PASSWORD`.
4. Beim nächsten Update erkennt die App den neuen Schlüssel (`signer` in
   `version.json`) und zeigt statt „Jetzt installieren“ die Anleitung zur
   **einmaligen Neuinstallation**: erst mit dem Konto synchronisieren, APK
   laden, Lernen deinstallieren, neu installieren, anmelden. Nicht im Sync:
   Laborfotos und – ohne PDF-Speicher – die PDF-Dateien selbst.

Ohne Secrets bleibt alles wie bisher (Debug-Schlüssel).

### Backup und Wiederherstellen

Vor großen Umbauten wird der Stand als Backup festgehalten – als Commit in der
Historie des App-Zweigs (bleibt dauerhaft erhalten):

| Backup | Commit |
| --- | --- |
| vor dem Modus „Visuell lernen“ | `8043a211bb436cd880851f7a52a517d0a46ad5ab` |

- **Wiederherstellen** (ohne Hilfe): GitHub → *Actions* → *Backup
  wiederherstellen* → *Run workflow* (das letzte Backup ist vorausgefüllt). Der
  Code-Stand des Backups kommt als neuer Commit auf den App-Zweig, die Builds
  starten automatisch, und die App bietet das Update wie gewohnt an. Die
  Lerndaten auf dem Gerät bleiben erhalten; nichts geht verloren – auch das
  Wiederherstellen lässt sich wieder rückgängig machen (Workflow mit dem Commit
  davor erneut starten).
- Daten, die eine neuere Version angelegt hat (z.B. neue Aufgabentypen), zeigt
  die ältere Version als Karteikarte; sie gehen nicht verloren.

### In-App-Update-Hinweis

Damit man nicht von Hand auf GitHub nachschauen muss, ob es einen neueren
Build gibt: beide Workflows setzen `--build-number=${{ github.run_number }}`
(eine garantiert fortlaufende Zahl über alle Pushes hinweg) und
veröffentlichen zusätzlich ein `version.json`
(`{"buildNumber": ..., "sha": "...", "tag": "..."}`) unter derselben
Release-URL wie die APK/das ZIP. `UpdateCheckerService` vergleicht das beim
App-Start (und über "Nach Updates suchen" in den Einstellungen) mit der
Build-Nummer der laufenden App (`package_info_plus`) – findet es eine
neuere, gibt es eine SnackBar bzw. einen Button **"Jetzt installieren"**
(`lib/services/update_installer_io.dart`, `lib/ui/widgets/update_actions.dart`):

- **Windows** lädt `Lernen-Setup.exe` ins Temp-Verzeichnis, prüft, dass
  wirklich ein Programm ankam, startet es still (`/SILENT`) und beendet
  sich; das Setup ersetzt die Dateien und startet die App danach neu.
- **Android** lädt die APK in den Cache und übergibt sie über einen
  FileProvider an den System-Installer (`MainActivity.installApk`, Kanal
  `lernen/update`, Berechtigung `REQUEST_INSTALL_PACKAGES`). Man bestätigt
  nur noch "Aktualisieren" – ganz still geht das bei Apps außerhalb des
  Play Stores nicht. Beim allerersten Mal fragt Android, ob Lernen Apps
  installieren darf. Weil jede APK mit demselben Schlüssel signiert ist
  (`android/app/debug.keystore`), installiert sie über die alte App; Daten
  bleiben erhalten, nichts muss vorher gelöscht werden.

Klappt das nicht, öffnet sich der Download im Browser.

## Tests

```bash
flutter analyze   # statische Analyse
flutter test       # FSRS-Algorithmus, Exam-Scheduler, KI-JSON-Parsing, App-Smoke-Test
TZ=Europe/Berlin flutter test   # zusätzlich über die Zeitumstellung (so läuft es auch in CI)
```

Alle Datumsrechnungen laufen über Kalendertage (`DateTime(j, m, t ± n)`,
`calendarDaysBetween`) statt über `Duration(days: …)`/`difference().inDays`:
an der Sommer-/Winterzeit-Umstellung hat ein Tag 23 bzw. 25 Stunden, sonst
verschieben sich Vorlesungszeiten, Fälligkeiten, Streak und Countdown
(`test/services/dst_test.dart`, aussagekräftig nur mit einer Zeitzone mit
Umstellung). Der ausführliche Analysebericht mit allen gefundenen und
behobenen Fehlern steht in `CODE_ANALYSE.md`.

Die Kernlogik (FSRS-Scheduling, Exam-Scheduler-Dosierung, robuste
JSON-Extraktion aus KI-Antworten, Sync-Codec, LaTeX-Reparatur, CSV, S3-
Signatur gegen die offiziellen AWS-Beispielwerte) ist mit `flutter test` ohne
Gerät abgedeckt; dieselben Tests laufen in CI vor jedem Build. Texterkennung
und PDF-Speicher sind nur gegen nachgebaute HTTP-Antworten getestet – echte
OpenRouter-/R2-/Nextcloud-Aufrufe einmal von Hand ausprobieren. Zusätzlich wurde der komplette Kernablauf – Fach anlegen,
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
