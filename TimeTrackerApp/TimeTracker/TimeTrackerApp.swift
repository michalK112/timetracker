import SwiftUI
import AppKit

@main
struct TimeTrackerApp: App {
    @StateObject private var store: Store
    @StateObject private var tracker: Tracker
    @StateObject private var engine: Engine

    init() {
        let s = Store()
        let t = Tracker()
        let e = Engine(store: s, tracker: t)
        _store = StateObject(wrappedValue: s)
        _tracker = StateObject(wrappedValue: t)
        _engine = StateObject(wrappedValue: e)
        t.start()
        e.start()
        if !t.accessibilityGranted { t.requestAccessibility() }
        if s.settings.notifyReport { Notifier.requestAuthorization() }
    }

    var body: some Scene {
        Window("TimeTracker", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(tracker)
                .environmentObject(engine)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 800)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
                .environmentObject(tracker)
                .environmentObject(engine)
        } label: {
            Image(systemName: tracker.isPaused ? "pause.circle" : "clock")
        }
    }
}

enum Pane: String, Hashable {
    case calendar, projects, reports, general, ai, system
}

/// Numer wersji pokazywany w panelu bocznym — pozwala sprawdzić, czy działa najnowsza kompilacja.
let APP_BUILD = "2.0 · build 4"

/// Główne okno: własny panel boczny (przyciski) + widok sekcji.
/// Bez NavigationSplitView i zaznaczania List — w poprzednich wersjach kliknięcia nie przełączały widoku.
struct RootView: View {
    @State private var pane: Pane = .calendar
    @State private var selectedProject: String?
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .background(.regularMaterial)
            Divider()
            NavigationStack {
                detail
            }
            .id(pane)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .calendar: CalendarView()
        case .projects: ProjectsView(selected: $selectedProject)
        case .reports: ReportsView()
        case .general: GeneralSettingsView()
        case .ai: AISettingsView()
        case .system: SystemSettingsView()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                IconTile(symbol: "clock.fill", color: Color(hex: "#e0457b"), size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TimeTracker").font(.system(size: 14, weight: .semibold))
                    Text("MK Design Studio").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 14)

            sectionLabel("Śledzenie")
            row(.calendar, "Kalendarz", "calendar", "#2f8cf0")
            row(.projects, "Projekty", "folder.fill", "#e0457b")
            row(.reports, "Raporty", "chart.bar.fill", "#c64fd6")
            sectionLabel("Ustawienia").padding(.top, 14)
            row(.general, "Ogólne", "gearshape.fill", "#8e8e96")
            row(.ai, "AI", "sparkles", "#8e5cf0")
            row(.system, "System", "lock.shield.fill", "#e8a321")

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(tracker.isPaused ? Color.orange : Color.green).frame(width: 7, height: 7)
                    Text(tracker.isPaused ? "Wstrzymane" : "Śledzenie · \(fmtDuration(tracker.activeTodaySeconds / 60))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(APP_BUILD).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func row(_ p: Pane, _ title: String, _ symbol: String, _ hex: String) -> some View {
        SidebarRow(title: title, symbol: symbol, color: Color(hex: hex), selected: pane == p) {
            pane = p
            selectedProject = nil
        }
    }
}

/// Pozycja panelu bocznego ze stanami: zwykły, hover, wybrany.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconTile(symbol: symbol, color: color)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.85))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var background: Color {
        if selected { return Color.accentColor.opacity(hovering ? 0.24 : 0.18) }
        if hovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var engine: Engine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if tracker.isPaused, let p = tracker.pausedUntil {
            Text("Wstrzymane do \(hmFormatter.string(from: p))")
        } else {
            Text("Dziś \(fmtDuration(tracker.activeTodaySeconds / 60))")
        }
        if !tracker.accessibilityGranted {
            Button("Nadaj dostęp do Dostępności…") { tracker.requestAccessibility() }
        }
        Divider()
        Button("Otwórz TimeTracker") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Przelicz wpisy teraz") { engine.refresh(dayKey(Date())) }
        Divider()
        if tracker.isPaused {
            Button("Wznów śledzenie") { tracker.pause(until: nil) }
        } else {
            Button("Wstrzymaj na 30 minut") { tracker.pause(until: Date().addingTimeInterval(1800)) }
            Button("Wstrzymaj do jutra") { tracker.pause(until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))) }
        }
        Divider()
        Button("Zakończ TimeTracker") { tracker.flush(); NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
