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

struct RootView: View {
    @State private var pane: Pane? = .calendar
    @State private var selectedProject: String?
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section("Śledzenie") {
                    row(.calendar, "Kalendarz", "calendar", "#2f8cf0")
                    row(.projects, "Projekty", "folder.fill", "#e0457b")
                    row(.reports, "Raporty", "chart.bar.fill", "#c64fd6")
                }
                Section("Ustawienia") {
                    row(.general, "Ogólne", "gearshape.fill", "#8e8e96")
                    row(.ai, "AI", "sparkles", "#8e5cf0")
                    row(.system, "System", "lock.shield.fill", "#e8a321")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Circle().fill(tracker.isPaused ? Color.orange : Color.green).frame(width: 7, height: 7)
                    Text(tracker.isPaused ? "Wstrzymane" : "Śledzenie · \(fmtDuration(tracker.activeTodaySeconds / 60))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
            }
        } detail: {
            switch pane ?? .calendar {
            case .calendar: CalendarView()
            case .projects: ProjectsView(selected: $selectedProject)
            case .reports: ReportsView()
            case .general: GeneralSettingsView()
            case .ai: AISettingsView()
            case .system: SystemSettingsView()
            }
        }
        .onChange(of: pane) { _ in selectedProject = nil }
    }

    private func row(_ p: Pane, _ title: String, _ symbol: String, _ hex: String) -> some View {
        Label { Text(title) } icon: { IconTile(symbol: symbol, color: Color(hex: hex)) }
            .tag(p)
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
