# Browser-Tests der Web-App (Playwright)

Ergänzen `flutter test` um Tests im echten Browser (Release-Build). Nicht Teil
der CI – bei Änderungen an Web-Start, Navigation oder Stift-Blatt von Hand
laufen lassen. Braucht Node mit `playwright` und Chromium.

```bash
flutter build web --base-href /Lernen/ --no-web-resources-cdn
mkdir -p /tmp/site && ln -sfn "$PWD/build/web" /tmp/site/Lernen
(cd /tmp/site && python3 -m http.server 8766 &)

node tool/web_e2e/startup.js /tmp            # Startzeit (online)
node tool/web_e2e/startup.js /tmp offline    # Startzeit ohne Netz (navigator.onLine = false)
node tool/web_e2e/smoke.js /tmp 1280 800     # alle Tabs, Konsolenfehler
node tool/web_e2e/flow.js /tmp 390 844       # Fach anlegen, Einstufen, Laut denken (Handybreite)
```

Stift-Blatt messen (eigene Messseite `tool/ink_bench/main.dart`, Stift-Events
per CDP mit `pointerType: "pen"`):

```bash
flutter build web -t tool/ink_bench/main.dart -o build/ink_bench --no-web-resources-cdn
(cd build/ink_bench && python3 -m http.server 8765 &)
node tool/web_e2e/ink_bench.js "http://localhost:8765/?fill=8"   # volles Blatt
node tool/web_e2e/ink_bench.js "http://localhost:8765/?fill=0"   # leeres Blatt
```

Hinweise: Texteingabe über `locator.focus()` + `keyboard.type` (ein Klick
landet auf der Semantik-Ebene). Ohne Grafikkarte (Container) sind alle Zeiten
ein Vielfaches langsamer als auf echten Geräten – verglichen werden die
Verhältnisse (leeres vs. volles Blatt, vorher vs. nachher).
