#!/bin/bash
# TimeTracker — wyłączenie aplikacji (dane w ~/Documents/TimeTracker zostają)
for L in studio.mk.timetracker studio.mk.timetracker.export; do
  launchctl bootout "gui/$(id -u)/$L" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$L.plist"
done
pkill -x TimeTracker 2>/dev/null || true
rm -rf "$HOME/Applications/TimeTracker.app"
echo "TimeTracker wyłączony. Dane w ~/Documents/TimeTracker zostały bez zmian."
