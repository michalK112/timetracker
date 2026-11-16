# TimeTracker 2 — samodzielna aplikacja na macOS

Jedno okno: kalendarz wpisów, projekty, raporty, ustawienia + ikona w pasku menu.
Wszystko działa lokalnie; Claude (przez klucz API) pisze tylko podsumowania.

## Uruchomienie

**Xcode:** otwórz `TimeTracker.xcodeproj` → Run (⌘R). Gotową aplikację znajdziesz w Product → Show Build Folder.

**Bez Xcode:** `bash ~/Documents/TimeTracker/TimeTrackerApp/build.sh`
— kompiluje do ~/Applications/TimeTracker.app i uruchamia.

Obie drogi zatrzymują poprzednią wersję (pasek menu + eksport w tle).

## Pierwsze uruchomienie
1. Zezwól na dostęp do Dokumentów i Dostępności.
2. Ustawienia → AI → wklej klucz API z console.anthropic.com.
3. Ustawienia → System → „Uruchamiaj przy logowaniu”.

## Dane (Dokumenty/TimeTracker)
- `exports/` — zapis aktywności co 5 s (ten sam format co wersja 1)
- `data/projects.json`, `data/settings.json`, `data/days/RRRR-MM-DD.json` — projekty, ustawienia, wpisy
- `reports/` — raporty Markdown
