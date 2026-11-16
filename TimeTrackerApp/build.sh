#!/bin/bash
# TimeTracker 2 — kompilacja bez Xcode (wystarczą Narzędzia wiersza poleceń).
# Użycie: bash ~/Documents/TimeTracker/TimeTrackerApp/build.sh
# Alternatywa: otwórz TimeTracker.xcodeproj w Xcode i kliknij Run.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/TimeTracker.app"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Brak kompilatora Swift. Otwieram instalator Narzędzi wiersza poleceń — po instalacji uruchom ponownie."
  xcode-select --install 2>/dev/null || true; exit 1
fi

echo "▸ Zatrzymuję poprzednią wersję…"
for L in studio.mk.timetracker studio.mk.timetracker.export; do
  launchctl bootout "gui/$(id -u)/$L" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$L.plist"
done
pkill -x TimeTracker 2>/dev/null || true
sleep 1

echo "▸ Kompilacja…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  -o "$APP/Contents/MacOS/TimeTracker" "$DIR"/TimeTracker/*.swift \
  -framework SwiftUI -framework AppKit -framework ApplicationServices -framework ServiceManagement -framework UserNotifications
sed -e 's/$(EXECUTABLE_NAME)/TimeTracker/' -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/studio.mk.timetracker/' \
  "$DIR/TimeTracker/Info.plist" > "$APP/Contents/Info.plist"
codesign --force --sign - --identifier studio.mk.timetracker "$APP" >/dev/null 2>&1 || true

echo "✅ Gotowe: $APP"
open "$APP"
echo "W aplikacji: Ustawienia → System → włącz „Uruchamiaj przy logowaniu” i sprawdź dostęp do Dostępności."
echo "Po przebudowaniu macOS może ponownie poprosić o Dostępność i dostęp do Dokumentów."
