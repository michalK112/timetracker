#!/bin/bash
# TimeTracker — pobiera najnowszą wersję z GitHuba, kompiluje i uruchamia.
# Użycie: curl -fsSL https://raw.githubusercontent.com/michalK112/timetracker/main/TimeTrackerApp/update.sh | bash
set -e
REPO="michalK112/timetracker"
STATE="$HOME/Documents/TimeTracker/data/installed_commit"

echo "▸ Sprawdzam najnowszą wersję…"
SHA=$(curl -fsSL -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$REPO/commits/main") || {
  echo "Nie udało się połączyć z GitHubem (repozytorium prywatne albo brak internetu)."; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
echo "▸ Pobieram wersję ${SHA:0:7}…"
curl -fsSL "https://codeload.github.com/$REPO/zip/$SHA" -o "$T/src.zip"
unzip -q "$T/src.zip" -d "$T"
SRC=$(find "$T" -mindepth 1 -maxdepth 1 -type d | head -1)

mkdir -p "$(dirname "$STATE")"
OLD=$(cat "$STATE" 2>/dev/null || true)
echo "$SHA" > "$STATE"
if ! bash "$SRC/TimeTrackerApp/build.sh"; then
  if [ -n "$OLD" ]; then echo "$OLD" > "$STATE"; else rm -f "$STATE"; fi
  echo "❌ Kompilacja nie powiodła się — skopiuj powyższe komunikaty i wyślij je Claude."
  exit 1
fi
echo "✅ Zainstalowano wersję ${SHA:0:7}."
