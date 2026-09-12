#!/usr/bin/env bash
# Holt den neuesten Stand und startet die App im Browser - immer in einem
# Rutsch, damit nie versehentlich ein veralteter Stand getestet wird.
set -e

echo "==> git pull"
git pull

echo "==> flutter pub get"
flutter pub get

echo "==> flutter run -d chrome"
flutter run -d chrome
