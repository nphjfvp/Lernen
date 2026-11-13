# Hinweise für Claude-Sitzungen

Projektkontext: [AI_CONTEXT.md](AI_CONTEXT.md) (zuerst lesen).

## Fertige Arbeit immer als Update ausliefern

Der Nutzer will Änderungen **immer sofort in der App** haben. Darum nach jeder
abgeschlossenen Änderung (analyze sauber, Tests grün, committet) zusätzlich zum
Sitzungs-Branch **auf den App-Branch `claude/neue-lern-app-fokus-ej3k48`
pushen** – das ist ausdrücklich erlaubt und gewünscht, ohne nachzufragen:

```
git fetch origin claude/neue-lern-app-fokus-ej3k48
git rebase origin/claude/neue-lern-app-fokus-ej3k48   # falls der App-Branch weiter ist
git push origin HEAD:claude/neue-lern-app-fokus-ej3k48
```

Nur vom App-Branch werden Android-APK („android-latest“, In-App-Update),
Windows-Setup und Web-App veröffentlicht; andere Branches bauen nur Artifacts.
Nie mit `--force` auf den App-Branch pushen; bei Konflikten erst rebasen und
neu testen. Kein Pull Request nötig.
