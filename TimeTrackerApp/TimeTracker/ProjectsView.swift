import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var store: Store
    @Binding var selected: String?

    var body: some View {
        if let id = selected, store.project(id) != nil {
            ProjectDetail(projectId: id, onBack: { selected = nil })
        } else {
            list
        }
    }

    private var list: some View {
        Form {
            Section {
                ForEach(store.projects) { p in
                    HStack(spacing: 12) {
                        IconTile(symbol: "folder.fill", color: p.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name)
                            Text(p.summary).font(.caption).foregroundStyle(.secondary)
                            let words = p.keywords + p.tools.flatMap { $0.keywords }
                            if !words.isEmpty {
                                Text(words.prefix(6).joined(separator: " · ") + (words.count > 6 ? " …" : ""))
                                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                            } else {
                                Text("Brak słów kluczowych — kliknij, żeby dodać").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { p.enabled }, set: { v in var q = p; q.enabled = v; store.update(q) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .help("Śledź ten projekt")
                        Button { selected = p.id } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = p.id }
                }
                if store.projects.isEmpty {
                    Text("Nie masz jeszcze projektów. Projekt to klient lub zlecenie, np. Shape Factor.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Obserwowane projekty")
            } footer: {
                Text("Wyłączony projekt zostaje zapisany, ale jego czas nie jest przypisywany.").foregroundStyle(.secondary)
            }

            Section("Jak działa dopasowanie") {
                LabeledContent("Narzędzie + słowo kluczowe") { Text("np. okno Slacka z „shape-factor” w tytule — najdokładniejsze").foregroundStyle(.secondary) }
                LabeledContent("Słowa kluczowe ogólne") { Text("szukane w tytułach okien i adresach stron").foregroundStyle(.secondary) }
                LabeledContent("Reszta") { Text("trafia do „Inne” — przypiszesz ją w kalendarzu").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Projekty")
        .toolbar {
            ToolbarItem {
                Button { selected = store.addProject().id } label: { Label("Dodaj projekt", systemImage: "plus") }
                    .help("Dodaj projekt")
            }
        }
    }
}

struct ProjectDetail: View {
    @EnvironmentObject var store: Store
    let projectId: String
    var onBack: () -> Void
    @State private var confirmDelete = false

    private var project: Binding<Project> {
        Binding(get: { store.project(projectId) ?? Project(id: projectId, name: "", colorHex: "#888888") },
                set: { store.update($0) })
    }

    var body: some View {
        let p = project.wrappedValue
        Form {
            Section("Ogólne") {
                TextField("Nazwa", text: project.name, prompt: Text("Np. Shape Factor"))
                LabeledContent("Kolor") {
                    HStack(spacing: 7) {
                        ForEach(projectPalette, id: \.self) { hex in
                            let owner = store.projects.first { $0.id != projectId && $0.colorHex == hex }
                            Button { project.wrappedValue.colorHex = hex } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(p.colorHex == hex ? 0.9 : 0), lineWidth: 2).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .disabled(owner != nil)
                            .opacity(owner != nil ? 0.25 : 1)
                            .help(owner.map { "Używa go projekt \($0.name)" } ?? "Wybierz kolor")
                        }
                    }
                }
                Toggle("Śledź ten projekt", isOn: project.enabled)
            }

            Section {
                KeywordEditor(words: project.keywords, placeholder: "Np. Shape Factor, shapefactor.com")
            } header: {
                Text("Słowa kluczowe")
            } footer: {
                Text("Szukane w tytułach okien i adresach stron we wszystkich aplikacjach. Wielkość liter nie ma znaczenia.").foregroundStyle(.secondary)
            }

            Section {
                ForEach(p.tools) { rule in
                    ToolRuleRow(rule: toolBinding(rule.id)) {
                        project.wrappedValue.tools.removeAll { $0.id == rule.id }
                    }
                }
                Menu {
                    let used = Set(p.tools.map { $0.type })
                    ForEach(ToolType.allCases.filter { $0 == .custom || !used.contains($0) }) { t in
                        Button { project.wrappedValue.tools.append(ToolRule(type: t)) } label: { Label(t.label, systemImage: t.symbol) }
                    }
                } label: {
                    Label("Dodaj narzędzie", systemImage: "plus.circle.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } header: {
                Text("Narzędzia")
            } footer: {
                Text("Bez słów kluczowych cały czas w danym narzędziu liczy się do projektu — dobre dla aplikacji używanych tylko dla tego klienta.").foregroundStyle(.secondary)
            }


            Section {
                HStack {
                    Text("Usunięcie projektu nie zmienia zapisanych wpisów.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Usuń projekt", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(p.name.isEmpty ? "Projekt" : p.name)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { onBack() } label: { Label("Projekty", systemImage: "chevron.left") }.help("Wróć do listy projektów")
            }
        }
        .confirmationDialog("Usunąć projekt „\(p.name)”?", isPresented: $confirmDelete) {
            Button("Usuń", role: .destructive) { onBack(); store.deleteProject(projectId) }
        } message: {
            Text("Wpisy w kalendarzu zostaną, ale nowe nie będą do niego przypisywane.")
        }
    }

    private func toolBinding(_ id: String) -> Binding<ToolRule> {
        Binding(get: { project.wrappedValue.tools.first { $0.id == id } ?? ToolRule(type: .custom) },
                set: { v in
                    var p = project.wrappedValue
                    if let i = p.tools.firstIndex(where: { $0.id == id }) { p.tools[i] = v; project.wrappedValue = p }
                })
    }
}

struct ToolRuleRow: View {
    @Binding var rule: ToolRule
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: rule.type.symbol, color: rule.type.color)
            VStack(alignment: .leading, spacing: 6) {
                if rule.type == .custom {
                    TextField("Nazwa aplikacji", text: $rule.app, prompt: Text("Nazwa aplikacji, np. Pixelmator Pro"))
                        .textFieldStyle(.plain).font(.body.weight(.medium))
                } else {
                    Text(rule.type.label).font(.body.weight(.medium))
                }
                Text((rule.type.apps.isEmpty ? "" : rule.type.apps + " · ") +
                     (rule.keywords.isEmpty ? "bez słów kluczowych liczy się cały czas w tej aplikacji" : "liczy się tylko przy pasujących słowach"))
                    .font(.caption).foregroundStyle(.secondary)
                KeywordEditor(words: $rule.keywords, placeholder: rule.type.hint)
            }
            Spacer(minLength: 0)
            Button("Usuń", role: .destructive, action: onDelete).buttonStyle(.borderless).font(.caption)
        }
        .padding(.vertical, 2)
    }
}
