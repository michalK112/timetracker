import SwiftUI
import ServiceManagement
import AppKit

struct GeneralSettingsView: View {
    @EnvironmentObject var store: Store

    private var reportTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: store.settings.reportHour, minute: store.settings.reportMinute, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            store.settings.reportHour = c.hour ?? 18
            store.settings.reportMinute = c.minute ?? 0
        })
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Utwórz raport o", selection: reportTime, displayedComponents: .hourAndMinute)
                LabeledContent("Dni robocze") {
                    HStack(spacing: 5) {
                        ForEach([(2, "Pn"), (3, "Wt"), (4, "Śr"), (5, "Cz"), (6, "Pt"), (7, "So"), (1, "Nd")], id: \.0) { d in
                            let on = store.settings.workdays.contains(d.0)
                            Button {
                                if on { store.settings.workdays.remove(d.0) } else { store.settings.workdays.insert(d.0) }
                            } label: {
                                Text(d.1).font(.system(size: 12, weight: .medium)).frame(width: 30, height: 24)
                                    .foregroundStyle(on ? Color.white : Color.secondary)
                                    .background(on ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Toggle("Powiadomienie z podsumowaniem", isOn: $store.settings.notifyReport)
                    .onChange(of: store.settings.notifyReport) { v in if v { Notifier.requestAuthorization() } }
                Toggle("Zapisuj raport jako plik Markdown", isOn: $store.settings.saveMarkdown)
            } header: { Text("Raport dzienny") } footer: {
                Text("Pliki trafiają do Dokumenty/TimeTracker/reports.").foregroundStyle(.secondary)
            }

            Section("Liczenie czasu") {
                Picker("Bezczynność po", selection: $store.settings.idleMinutes) {
                    ForEach([3, 5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Pomijaj na liście krótsze niż", selection: $store.settings.minBlockMinutes) {
                    ForEach([1, 2, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Przeliczaj wpisy co", selection: $store.settings.refreshMinutes) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
                Toggle("Pokazuj kategorię „Inne” w raporcie", isOn: $store.settings.includeOther)
                LabeledContent("Godziny na pasku kalendarza") {
                    HStack {
                        Picker("", selection: $store.settings.workStart) { ForEach(5...12, id: \.self) { Text("\($0):00").tag($0) } }.labelsHidden().fixedSize()
                        Text("–")
                        Picker("", selection: $store.settings.workEnd) { ForEach(14...23, id: \.self) { Text("\($0):00").tag($0) } }.labelsHidden().fixedSize()
                    }
                }
            }

            Section {
                Picker("Domyślnie dla nowego dnia", selection: $store.settings.approvalDefault) {
                    Text("Ręczne").tag(ApprovalMode.manual)
                    Text("Automatyczne").tag(ApprovalMode.auto)
                }
            } header: { Text("Zatwierdzanie wpisów") } footer: {
                Text("Automatyczne: wpisy przypisane do projektu są od razu zatwierdzone. Każdy dzień przełączysz w kalendarzu.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ogólne")
    }
}

struct AISettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @State private var keyDraft = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Toggle("Podsumowania AI", isOn: $store.settings.aiEnabled)
                if store.hasAPIKey {
                    LabeledContent("Klucz API") {
                        HStack {
                            Label("Zapisany w Pęku kluczy", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                            Button("Usuń") { store.setAPIKey(nil); testResult = nil }
                        }
                    }
                } else {
                    LabeledContent("Klucz API") {
                        HStack {
                            SecureField("sk-ant-…", text: $keyDraft).frame(minWidth: 240)
                            Button("Zapisz") { store.setAPIKey(keyDraft); keyDraft = "" }.disabled(keyDraft.trimmed.isEmpty)
                        }
                    }
                }
                TextField("Model", text: $store.settings.aiModel)
                HStack {
                    Button(testing ? "Sprawdzam…" : "Sprawdź połączenie") {
                        testing = true
                        Task { testResult = await engine.testAPI(); testing = false }
                    }
                    .disabled(!store.hasAPIKey || testing)
                    if let r = testResult { Text(r).font(.callout).foregroundStyle(.secondary) }
                }
                if let err = engine.lastError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
            } header: { Text("Claude") } footer: {
                Text("Klucz utworzysz na console.anthropic.com → API Keys. Płacisz za użycie — przy krótkich podsumowaniach to zwykle grosze dziennie. Szybki i tani model w zupełności wystarczy.")
                    .foregroundStyle(.secondary)
            }
            Section("Co jest wysyłane") {
                Text("Przy podsumowaniu do Claude trafiają: nazwy aplikacji, tytuły okien, domeny stron, godziny i czas wpisów oraz Twoja notatka dnia. Zapis aktywności co 5 s nie opuszcza Maca.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI")
    }
}

struct SystemSettingsView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Dostępność (tytuły okien)") {
                    if tracker.accessibilityGranted {
                        Label("Włączona", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Nadaj dostęp") {
                            tracker.requestAccessibility()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Toggle("Uruchamiaj przy logowaniu", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in
                        do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = error.localizedDescription }
                    }
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.orange) }
            } header: { Text("Uprawnienia i start") } footer: {
                Text("Adresy stron z Chrome, Arc i Safari wymagają zgody na sterowanie przeglądarką — macOS zapyta przy pierwszym użyciu. Okna incognito i menedżery haseł są pomijane.")
                    .foregroundStyle(.secondary)
            }
            Section("Śledzenie") {
                LabeledContent("Stan") {
                    if tracker.isPaused, let p = tracker.pausedUntil {
                        Text("Wstrzymane do \(hmFormatter.string(from: p))").foregroundStyle(.orange)
                    } else {
                        Text("Aktywne · dziś \(fmtDuration(tracker.activeTodaySeconds / 60))").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if tracker.isPaused {
                        Button("Wznów śledzenie") { tracker.pause(until: nil) }
                    } else {
                        Button("Wstrzymaj na 30 minut") { tracker.pause(until: Date().addingTimeInterval(1800)) }
                        Button("Wstrzymaj do jutra") { tracker.pause(until: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))) }
                    }
                }
            }
            Section("Dane") {
                LabeledContent("Folder") { Text("Dokumenty/TimeTracker").foregroundStyle(.secondary) }
                Button("Pokaż w Finderze") { NSWorkspace.shared.open(Paths.base) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("System")
    }
}
