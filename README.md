# TimeTracker

Automatyczne śledzenie czasu pracy nad projektami klientów na macOS — MK Design Studio.

Aplikacja co 5 sekund zapisuje aktywną aplikację, tytuł okna i adres strony, dzieli dzień na wpisy,
przypisuje je do projektów według reguł (narzędzia + słowa kluczowe) i na koniec dnia tworzy raport
z czasem na projekt i listą zadań. Podsumowania wpisów pisze Claude.

## Struktura

| Folder | Co to jest |
|---|---|
| `TimeTrackerApp/` | **Wersja 2 (aktualna)** — samodzielna aplikacja SwiftUI: okno z kalendarzem, projektami, raportami i ustawieniami + pasek menu. Podsumowania przez Claude API. |
| `v1/app/` | Wersja 1 — tracker w pasku menu (Swift, jeden plik), zapisuje aktywność do `~/Documents/TimeTracker/exports`. |
| `v1/bin/` | Wersja 1 — instalator, deinstalator i `summarize.py` (podział dnia na wpisy). |
| `v1/panel/` | Wersja 1 — panel HTML (artifact na claude.ai) z kalendarzem, projektami i raportami. |

## Uruchomienie wersji 2

Xcode: otwórz `TimeTrackerApp/TimeTracker.xcodeproj` → Run.
Bez Xcode: `bash TimeTrackerApp/build.sh` (wystarczą Narzędzia wiersza poleceń).

Szczegóły w [TimeTrackerApp/README.md](TimeTrackerApp/README.md).

## Dane

Wszystkie dane zostają lokalnie w `~/Documents/TimeTracker` (poza repozytorium):
`exports/` — zapis aktywności, `data/` — projekty, ustawienia i wpisy, `reports/` — raporty Markdown.
Klucz API Claude jest przechowywany w Pęku kluczy macOS.

## Inspiracja

Sposób odczytu okien, adresów stron i bezczynności wzorowany na
[ActivityWatch](https://github.com/ActivityWatch) (MPL-2.0); kod napisany od nowa.
