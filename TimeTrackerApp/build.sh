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
# Podpis: stały certyfikat „TimeTracker Local” (jeśli istnieje) sprawia, że macOS pamięta
# Dostępność między kompilacjami. Podpis ad-hoc zmienia się przy każdym buildzie,
# więc stary wpis w Ustawieniach przestaje pasować — wtedy czyścimy go, żeby nie mylił.
SIGN_ID="TimeTracker Local"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  codesign --force --sign "$SIGN_ID" --identifier studio.mk.timetracker "$APP"
  STABLE=1
else
  codesign --force --sign - --identifier studio.mk.timetracker "$APP" >/dev/null 2>&1 || true
  tccutil reset Accessibility studio.mk.timetracker >/dev/null 2>&1 || true
  STABLE=0
fi

echo "✅ Gotowe: $APP"
open "$APP"
if [ "$STABLE" = 0 ]; then
  echo
  echo "Dostępność: stary wpis został usunięty — gdy macOS zapyta, włącz TimeTracker w"
  echo "Ustawieniach systemowych → Prywatność i ochrona → Dostępność, a potem uruchom aplikację ponownie."
  echo
  echo "Żeby nie robić tego po każdej kompilacji, utwórz raz certyfikat do podpisu:"
  echo "  Dostęp do pęku kluczy → menu Dostęp do pęku kluczy → Asystent certyfikatów → Utwórz certyfikat…"
  echo "  Nazwa: TimeTracker Local · Typ tożsamości: Główny z podpisem własnym · Typ certyfikatu: Podpisywanie kodu"
  echo "Następne kompilacje podpiszą się nim automatycznie i macOS zapamięta uprawnienia."
fi
echo "W aplikacji: Ustawienia → System → włącz „Uruchamiaj przy logowaniu”."
