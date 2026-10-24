# Lernen

Eine schlanke Klausur-Lern-App für Windows, Android und den Browser (auch
iPad/iPhone) – der Nachfolger von [Quiz-app](https://github.com/nphjfvp/quiz-app),
diesmal mit engerem Fokus statt Feature-Fülle: **Vorbereiten → Nachbereiten →
Daily Quiz**, mit KI über den eigenen OpenRouter-Key und komplett offline nutzbar.

## Installieren

| Gerät | So geht's |
|---|---|
| **Android** | [app-release.apk](https://github.com/nphjfvp/Lernen/releases/download/android-latest/app-release.apk) laden und installieren. Updates kommen danach aus der App. |
| **Windows** | [Lernen-Setup.exe](https://github.com/nphjfvp/Lernen/releases/download/windows-latest/Lernen-Setup.exe) ausführen (ohne Admin-Rechte). Updates kommen aus der App. |
| **iPad, iPhone, jeder Browser** | <https://nphjfvp.github.io/Lernen/> öffnen; in Safari **Teilen → Zum Home-Bildschirm**, dann startet sie wie eine App. |

Alle drei werden bei jedem Push auf den App-Branch automatisch neu gebaut –
erst nach grünem `flutter analyze` und `flutter test`.

## Erste Schritte

1. **KI-Key**: unter <https://openrouter.ai> einen Key erstellen und in der App
   unter **Einstellungen** eintragen (BYOK, kein eigener Server).
2. **Fach anlegen** mit Klausurdatum, Folien und Übungen hochladen (PDF, Word,
   PowerPoint).
3. **Vorbereiten** (vor der Vorlesung: Zusammenfassung) und **Nachbereiten**
   (danach: Konzepte und Karteikarten, auch aus Übungsblättern importiert).
4. Jeden Tag das **Daily Quiz** – dosiert nach Klausurdatum (FSRS).
5. Optional: **anmelden** und synchronisieren, dann ist alles auf allen Geräten.

## Was die App kann

Eine Führung durch alles gibt es in der App unter **Einstellungen → Einführung**.


- **Lernen**: Daily Quiz mit Spaced Repetition (FSRS), Wissensstand-Ampel,
  Stufen Leicht → Mittel → Schwer, Probeklausur mit Note, Fehlertagebuch,
  Kalender, Fortschritt, Lernerinnerung (Android) und Widget.
- **Spiele** (zur Pause, aus deinen Karten): Boss-Kampf, Fehlerjagd und Sprint.
- **Material**: PDFs ansehen und markieren, Texterkennung für Scans, Fragen zu
  einer Seite, Vorlesung kürzen, Formelsammlung, Frage-Chat zum Stoff.
- **Fragetypen**: Auswahl, Lückentext, Zuordnen, Tabellen, Bilder beschriften
  und markieren, freie Antworten mit KI-Prüfung, interaktive Seiten – dazu
  Rechenwege, Kristallgitter, Zustandsdiagramme, Terminierung (Gantt),
  Stücklisten und Skizzen.
- **Visuell lernen**: Lektionen mit Animationen (2D und 3D, wo nötig – auch als
  echtes 3D zum Drehen und Zoomen),
  erklärend oder sokratisch, aus PDFs, Fragen oder frei im Chat; Lernpfad für
  ein ganzes Semester.
- **Labor**: Vorbereitung, Durchführung mit Fotos, Berichtsentwurf.
- **Geräte**: Cloud-Sync (Konto), eigener PDF-Speicher, Sicherungen, Export.
- **Claude-Postfach**: Claude baut in einer Claude-Code-Sitzung Aufgaben aus
  deinen Unterlagen und legt sie dir in die App – du prüfst und übernimmst sie.

Ausführlich: [docs/FUNKTIONEN.md](docs/FUNKTIONEN.md).

## Dokumentation

| Datei | Inhalt |
|---|---|
| [docs/FUNKTIONEN.md](docs/FUNKTIONEN.md) | Alle Funktionen im Detail, bewusst Weggelassenes, Architektur, Design |
| [docs/EINRICHTUNG.md](docs/EINRICHTUNG.md) | Flutter, API-Key, Cloud-Sync, Account, PDF-Speicher, Builds, Web-App, Signierschlüssel, Backups, Updates, Tests |
| [CHANGELOG.md](CHANGELOG.md) | Was sich wann geändert hat (das Neueste oben) |
| [AI_CONTEXT.md](AI_CONTEXT.md) | Arbeitsgrundlage für KI-Sitzungen: Regeln, Datenmodell, Stolperfallen, Stand |
| [AUDIT.md](AUDIT.md), [CODE_ANALYSE.md](CODE_ANALYSE.md) | Code-Prüfungen und ihr Stand |
| [DESIGN_IDEEN.md](DESIGN_IDEEN.md) | Ideen-Liste mit Bewertung |

## Entwickeln

```bash
git pull && flutter pub get   # oder ./update.sh
flutter run -d chrome          # schnellster Weg zum Ausprobieren
flutter analyze
flutter test                   # auch mit TZ=Europe/Berlin (so läuft es in CI)
```

Flutter 3.47 (stable). Details, Plattformen und CI:
[docs/EINRICHTUNG.md](docs/EINRICHTUNG.md).
