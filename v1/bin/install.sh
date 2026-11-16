#!/bin/bash
# TimeTracker — kompilacja i uruchomienie TimeTracker.app (pasek menu, start przy logowaniu)
# Użycie: bash ~/Documents/TimeTracker/bin/install.sh
# Aplikacja trafia do ~/Applications (launchd nie uruchamia programów z Dokumentów),
# dane zapisuje w ~/Documents/TimeTracker.
set -e
BASE="$HOME/Documents/TimeTracker"
APP="$HOME/Applications/TimeTracker.app"
LABEL="studio.mk.timetracker"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$BASE/app/main.swift"

echo "▸ TimeTracker — instalacja"
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "  Potrzebne są Narzędzia wiersza poleceń Xcode (kompilator Swift)."
  echo "  Otwieram instalator Apple — po zakończeniu uruchom tę komendę ponownie."
  xcode-select --install 2>/dev/null || true
  exit 1
fi
[ -f "$SRC" ] || { echo "  Brak pliku $SRC"; exit 1; }

mkdir -p "$BASE/exports" "$BASE/reports" "$BASE/logs" "$BASE/config" "$BASE/summaries" "$HOME/Library/LaunchAgents"

# zatrzymaj poprzednią wersję (i stary eksport z ActivityWatch, jeśli był)
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/studio.mk.timetracker.export" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/studio.mk.timetracker.export.plist"
pkill -x TimeTracker 2>/dev/null || true

echo "▸ Kompilacja…"
mkdir -p "$HOME/Applications" "$APP/Contents/MacOS"
xcrun swiftc -O -o "$APP/Contents/MacOS/TimeTracker" "$SRC" -framework Cocoa -framework ApplicationServices
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>TimeTracker</string>
  <key>CFBundleDisplayName</key><string>TimeTracker</string>
  <key>CFBundleExecutable</key><string>TimeTracker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>TimeTracker odczytuje adres aktywnej karty w przeglądarce, żeby przypisać czas do właściwego projektu.</string>
</dict></plist>
PL
codesign --force --sign - --identifier "$LABEL" "$APP" >/dev/null 2>&1 || echo "  (podpis ad-hoc nieudany — aplikacja i tak zadziała)"

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/TimeTracker</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PL
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✅ TimeTracker działa — ikona zegara w pasku menu."
echo
echo "Ostatnie kroki:"
echo "  1. Gdy macOS zapyta, czy TimeTracker może korzystać z folderu Dokumenty — kliknij Zezwól (tam zapisuje dane)."
echo "  2. Nadaj dostęp do Dostępności, żeby zapisywać tytuły okien:"
echo "  Ustawienia systemowe → Prywatność i ochrona → Dostępność → włącz TimeTracker."
echo "  (macOS pokaże też pytania o sterowanie Chrome/Safari — zezwól, żeby zapisywać adresy stron.)"
echo "Po każdej ponownej instalacji macOS może poprosić o ten dostęp jeszcze raz."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
