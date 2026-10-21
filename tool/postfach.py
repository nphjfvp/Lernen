#!/usr/bin/env python3
"""Claude-Postfach: Lieferungen für die Lern-App ablegen, ansehen, löschen.

Für Claude-Code-Sitzungen (siehe .claude/skills/postfach/SKILL.md). Die App
holt Lieferungen unter `inbox/{code}/items` ab (lib/services/claude_inbox.dart);
Zugriff hat, wer den Postfach-Code kennt (firestore.rules) – kein Konto,
kein Schlüssel nötig. Nur Standardbibliothek.

  python3 tool/postfach.py send   --code CODE --title "Blatt 3" [--subject Fach] [--note Text] aufgaben.json
  python3 tool/postfach.py list   --code CODE
  python3 tool/postfach.py delete --code CODE --id ID

Den Code NIE ins Repo schreiben (öffentlich) – nur auf der Kommandozeile.
"""
import argparse
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_CODE = 16  # wie SyncCodes.minLength und firestore.rules


def firebase_web_config():
    """projectId und apiKey aus lib/firebase_options.dart (Web-Konfiguration)."""
    with open(os.path.join(ROOT, 'lib', 'firebase_options.dart'), encoding='utf-8') as f:
        src = f.read()
    web = src[src.index('static const FirebaseOptions web'):]
    project = re.search(r"projectId: '([^']+)'", web).group(1)
    key = re.search(r"apiKey: '([^']+)'", web).group(1)
    return project, key


def items_url(code, item_id=None):
    project, key = firebase_web_config()
    path = f'projects/{project}/databases/(default)/documents/inbox/{urllib.parse.quote(code, safe="")}/items'
    if item_id:
        path += '/' + urllib.parse.quote(item_id, safe='')
    return f'https://firestore.googleapis.com/v1/{path}?key={key}'


def request(method, url, body=None):
    data = None if body is None else json.dumps(body).encode('utf-8')
    req = urllib.request.Request(url, data=data, method=method, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode('utf-8')
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode('utf-8', 'replace')
        try:
            detail = json.loads(detail)['error']['message']
        except Exception:
            pass
        hint = ''
        if e.code == 403:
            hint = ('\nHinweis: Firestore lehnt ab – sind die Regeln mit dem Postfach in Firebase veröffentlicht '
                    '(App: Einstellungen → Cloud-Sync → „Verbindung prüfen“ → Regeln kopieren)?')
        sys.exit(f'Fehler {e.code}: {detail}{hint}')


def check_code(code):
    if len(code.strip()) < MIN_CODE:
        sys.exit(f'Der Postfach-Code ist zu kurz (mindestens {MIN_CODE} Zeichen) – in der App unter '
                 'Einstellungen → Claude-Postfach erzeugen.')
    return code.strip()


def cmd_send(args):
    code = check_code(args.code)
    with open(args.file, encoding='utf-8') as f:
        payload = f.read()
    try:
        parsed = json.loads(payload)
    except json.JSONDecodeError as e:
        sys.exit(f'{args.file} ist kein gültiges JSON: {e}')
    if len(payload.encode('utf-8')) > 900_000:
        sys.exit('Die Lieferung ist zu groß (über 900 KB) – bitte auf mehrere aufteilen.')
    count = len(parsed.get('tasks', [])) + len(parsed.get('flashcards', [])) if isinstance(parsed, dict) else len(parsed)
    now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
    fields = {
        'title': {'stringValue': args.title},
        'subject': {'stringValue': args.subject or ''},
        'note': {'stringValue': args.note or ''},
        'payload': {'stringValue': payload},
        'createdAt': {'timestampValue': now},
    }
    doc = request('POST', items_url(code), {'fields': fields})
    print(f'Abgelegt: „{args.title}“ ({count} Einträge) – ID {doc.get("name", "").rsplit("/", 1)[-1]}')


def cmd_list(args):
    code = check_code(args.code)
    docs = request('GET', items_url(code)).get('documents', [])
    if not docs:
        print('Postfach leer.')
    for d in docs:
        f = d.get('fields', {})
        title = f.get('title', {}).get('stringValue', '')
        subject = f.get('subject', {}).get('stringValue', '')
        size = len(f.get('payload', {}).get('stringValue', ''))
        print(f'{d["name"].rsplit("/", 1)[-1]}  {f.get("createdAt", {}).get("timestampValue", "")}  „{title}“'
              f'{" für " + subject if subject else ""}  ({size} Zeichen)')


def cmd_delete(args):
    code = check_code(args.code)
    request('DELETE', items_url(code, args.id))
    print(f'Gelöscht: {args.id}')


def main():
    p = argparse.ArgumentParser(description='Claude-Postfach der Lern-App')
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('send')
    s.add_argument('--code', required=True)
    s.add_argument('--title', required=True)
    s.add_argument('--subject', default='')
    s.add_argument('--note', default='')
    s.add_argument('file')
    s.set_defaults(func=cmd_send)
    lst = sub.add_parser('list')
    lst.add_argument('--code', required=True)
    lst.set_defaults(func=cmd_list)
    d = sub.add_parser('delete')
    d.add_argument('--code', required=True)
    d.add_argument('--id', required=True)
    d.set_defaults(func=cmd_delete)
    args = p.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()
