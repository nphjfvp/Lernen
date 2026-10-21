---
name: postfach
description: Aufgaben für die Lern-App bauen und ins Claude-Postfach des Nutzers legen. Verwenden, wenn der Nutzer ein Übungsblatt, eine Altklausur, Folien oder Themen schickt und die Aufgaben in seiner App landen sollen – oder wenn er „Postfach“, „in die App bauen“, „schick mir Aufgaben“ o.ä. sagt.
---

# Claude-Postfach

Die App holt Lieferungen unter `inbox/{Postfach-Code}/items` in Firestore ab
(`lib/services/claude_inbox.dart`), zeigt sie unter Einstellungen →
Claude-Postfach bzw. beim Start als Hinweis, und der Nutzer übernimmt sie im
gewohnten Import (Prüfen, Fach wählen, Speichern). Format = dasselbe wie für
externe KIs (`AiService.parseImportedTasks`).

## Ablauf

1. **Postfach-Code** vom Nutzer erfragen, falls er ihn nicht genannt hat
   (App: Einstellungen → Claude-Postfach → „Postfach-Code erzeugen“, dann
   kopieren). Den Code **nie** ins Repo schreiben, committen oder in einer
   Datei im Repo ablegen – das Repo ist öffentlich. Freunde haben eigene Codes.
2. **Format-Regeln holen** (immer, sie ändern sich mit der App):
   `POSTFACH_PROMPT=<scratchpad>/prompt.txt flutter test tool/postfach_check_test.dart`
   und `prompt.txt` vollständig lesen. Das sind genau die Regeln, nach denen
   die App liest (interaktive Arten wie Rechenweg, Terminierung, Kristallgitter,
   Stückliste, Skizze, Zustandsdiagramm, Freihand-Skizze; sonst fertige
   Quizfragen unter `card`/`flashcards`).
3. **Material lesen**: jede Aufgabe wortgetreu übernehmen, Lösungen selbst
   rechnen und prüfen, passende interaktive Art wählen, sonst eine fertige
   Quizfrage mit sinnvollem Fragetyp. Nichts erfinden, was nicht im Material
   steht (außer Lösungen, die sich zwingend ergeben).
4. **JSON in den Scratchpad schreiben – nicht ins Repo** (öffentlich,
   Urheberrecht der Unterlagen).
5. **Prüfen**: `POSTFACH_FILE=<datei> flutter test tool/postfach_check_test.dart`.
   Alle Einträge müssen gelesen werden (0 verworfen). „UNVOLLSTÄNDIG“ oder
   „NICHT INTERAKTIV → Sammelliste“ beheben. Passt eine Aufgabe in keine
   vorhandene Art und der Nutzer will sie interaktiv, die Art im Code ergänzen
   – das ist ein normales Feature (vorher mit dem Nutzer abstimmen; Tests, Doku,
   Commit wie sonst) und dauert länger als die Lieferung.
6. **Senden**:
   `python3 tool/postfach.py send --code <CODE> --title "<kurz, z.B. Übungsblatt 3>" --subject "<Fach>" --note "<1–2 Sätze, was drin ist>" <datei>`
   `--subject` ist nur ein Vorschlag fürs Fach (Name wie in der App).
   `list`/`delete` zeigen bzw. löschen Lieferungen. Über 900 KB aufteilen.
   Fehler 403: Der Nutzer muss die Firestore-Regeln neu veröffentlichen
   (App: Einstellungen → Cloud-Sync → „Verbindung prüfen“ → Regeln kopieren →
   Firebase-Konsole → Firestore → Regeln).
7. **Dem Nutzer berichten**: wie viele Aufgaben welcher Art geliefert wurden,
   was ausgelassen wurde und warum, und dass sie beim nächsten Öffnen der App
   (oder unter Einstellungen → Claude-Postfach → „Postfach öffnen“) zum Prüfen
   bereitliegen.

## Grenzen

- Bilder/Abbildungen reisen nicht mit – Aufgaben, die ohne Abbildung nicht
  gehen, als Text beschreiben oder weglassen und das sagen.
- Die Lieferung landet erst nach dem Prüfen und Speichern in den Karten;
  danach löscht die App sie aus dem Postfach.
