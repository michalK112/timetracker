import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @State private var date = Date()
    @State private var sortLongest = false
    @State private var filterProject = ""          // "" = wszystkie, "_other" = Inne
    @State private var filterStatus = ""           // "" = każdy
    @State private var expanded: Set<String> = []
    @State private var showRejected = false

    private var key: String { dayKey(date) }

    var body: some View {
        let rec = store.day(key)
        let all = rec.entries
        let live = all.filter { $0.status != .rejected }
        let filtered = all.filter { e in
            (filterProject.isEmpty || (filterProject == "_other" ? e.projectId == nil : e.projectId == filterProject)) &&
            (filterStatus.isEmpty || e.status.rawValue == filterStatus)
        }.sorted { sortLongest ? $0.effectiveMinutes > $1.effectiveMinutes : $0.start < $1.start }

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(rec: rec, live: live)
                    legend(live)
                    HourStrip(entries: all, date: date, settings: store.settings) { hour in
                        if let e = all.filter({ Calendar.current.component(.hour, from: $0.start) == hour && ($0.status != .rejected || showRejected) })
                            .min(by: { $0.start < $1.start }) {
                            withAnimation { proxy.scrollTo(e.id, anchor: .top) }
                        }
                    }
                    toolbar
                    Divider()
                    if all.isEmpty {
                        emptyState
                    }
                    ForEach([EntryStatus.review, .approved, .unassigned], id: \.self) { st in
                        let group = filtered.filter { $0.status == st }
                        if !group.isEmpty {
                            groupHeader(st, group)
                            ForEach(group) { e in
                                EntryRow(entry: e, day: key, expanded: expandedBinding(e.id)).id(e.id)
                                Divider()
                            }
                        }
                    }
                    let rejected = filtered.filter { $0.status == .rejected }
                    if !rejected.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Odrzucone").font(.title3.weight(.semibold))
                            Text("\(rejected.count) · nie wliczają się do raportu").foregroundStyle(.secondary)
                            Button(showRejected ? "Ukryj" : "Pokaż") { showRejected.toggle() }.buttonStyle(.link)
                        }
                        if showRejected {
                            ForEach(rejected) { e in
                                EntryRow(entry: e, day: key, expanded: expandedBinding(e.id)).id(e.id)
                                Divider()
                            }
                        }
                    }
                    noteEditor
                }
                .padding(24)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Kalendarz")
    }

    // MARK: części

    private func header(rec: DayRecord, live: [Entry]) -> some View {
        let inProjects = live.filter { $0.projectId != nil }.reduce(0) { $0 + $1.effectiveMinutes }
        let approved = live.filter { $0.status == .approved }.count
        return HStack(spacing: 18) {
            HStack(spacing: 0) {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
                    .help("Poprzedni dzień")
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .frame(width: 110)
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }
                    .help("Następny dzień")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(shortDay(date)).font(.headline)
                HStack(spacing: 8) {
                    Text("**\(live.count)** \(plural(live.count, "wpis", "wpisy", "wpisów"))")
                    Text("·").foregroundStyle(.tertiary)
                    Text("**\(approved)** \(plural(approved, "zatwierdzony", "zatwierdzone", "zatwierdzonych"))")
                    Text("·").foregroundStyle(.tertiary)
                    Text("**\(fmtHours(inProjects)) h** w projektach")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let last = rec.lastUpdated {
                Text("Zaktualizowano \(hmFormatter.string(from: last))").font(.caption).foregroundStyle(.tertiary)
            }
            Button {
                engine.refresh(key)
            } label: {
                if engine.busy { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .help("Przelicz wpisy teraz")
        }
    }

    @ViewBuilder private func legend(_ live: [Entry]) -> some View {
        let totals = store.projects.compactMap { p -> (Project, Double)? in
            let m = live.filter { $0.projectId == p.id }.reduce(0) { $0 + $1.effectiveMinutes }
            return m > 0 ? (p, m) : nil
        }.sorted { $0.1 > $1.1 }
        if !totals.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(totals, id: \.0.id) { p, m in
                    HStack(spacing: 6) {
                        Circle().fill(p.color).frame(width: 8, height: 8)
                        Text("\(p.name) · \(fmtHours(m)) h").monospacedDigit()
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(p.color.opacity(0.14), in: Capsule())
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { sortLongest.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                .help(sortLongest ? "Sortowanie: najdłuższe — kliknij, by sortować chronologicznie" : "Sortowanie: chronologicznie — kliknij, by pokazać najdłuższe")
            Picker("Projekt", selection: $filterProject) {
                Text("Wszystkie projekty").tag("")
                ForEach(store.projects) { p in Text(p.name).tag(p.id) }
                Text("Inne").tag("_other")
            }
            .labelsHidden().fixedSize()
            Picker("Status", selection: $filterStatus) {
                Text("Każdy status").tag("")
                ForEach(EntryStatus.allCases, id: \.self) { s in Text(s.label).tag(s.rawValue) }
            }
            .labelsHidden().fixedSize()
            Spacer()
            Toggle("Automatyczne zatwierdzanie", isOn: Binding(
                get: { store.approvalMode(key) == .auto },
                set: { setMode($0 ? .auto : .manual) }))
                .toggleStyle(.switch)
                .help("Automatycznie: wpisy przypisane do projektu są od razu zatwierdzone. Ręcznie: czekają na Ciebie.")
        }
    }

    private func groupHeader(_ st: EntryStatus, _ group: [Entry]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(st.label).font(.title3.weight(.semibold))
            Text("\(group.count) \(plural(group.count, "wpis", "wpisy", "wpisów")) · \(fmtHours(group.reduce(0) { $0 + $1.effectiveMinutes })) h")
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if st == .review && group.contains(where: { $0.projectId != nil }) {
                Button("Zatwierdź wszystkie") {
                    for e in group where e.projectId != nil { store.mutateEntry(key, e.id) { $0.status = .approved } }
                }
            }
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(Calendar.current.isDateInToday(date) ? "Dziś nie ma jeszcze wpisów" : "Brak wpisów z tego dnia").font(.headline)
            Text(Calendar.current.isDateInToday(date)
                 ? "Wpisy powstają co \(store.settings.refreshMinutes) min z zapisanej aktywności. Blok pracy musi trwać co najmniej 3 minuty."
                 : "W tym dniu nie było zapisanej aktywności.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notatka dnia").font(.headline).padding(.top, 10)
            TextEditor(text: Binding(get: { store.day(key).note }, set: { v in store.mutateDay(key) { $0.note = v } }))
                .font(.body)
                .frame(minHeight: 70)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            Text("Uzupełnia to, czego nie widać w tytułach okien, np. „wysłany landing v3 do akceptacji”. Trafia do podsumowań AI i raportu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: akcje

    private func shift(_ days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        expanded.removeAll()
    }

    private func setMode(_ mode: ApprovalMode) {
        store.mutateDay(key) { rec in
            rec.approvalMode = mode
            if mode == .auto {
                for i in rec.entries.indices where rec.entries[i].status == .review && rec.entries[i].projectId != nil {
                    rec.entries[i].status = .approved
                }
            }
        }
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) }, set: { v in if v { expanded.insert(id) } else { expanded.remove(id) } })
    }
}

// MARK: - Pasek godzin

struct HourStrip: View {
    let entries: [Entry]
    let date: Date
    let settings: AppSettings
    var onTap: (Int) -> Void
    @EnvironmentObject var store: Store

    var body: some View {
        let cal = Calendar.current
        let live = entries.filter { $0.status != .rejected }
        var h0 = settings.workStart, h1 = settings.workEnd
        for e in live { h0 = min(h0, cal.component(.hour, from: e.start)); h1 = max(h1, cal.component(.hour, from: e.end)) }
        let dayStart = cal.startOfDay(for: date)
        let nowHour = cal.isDateInToday(date) ? cal.component(.hour, from: Date()) : -1

        return HStack(spacing: 6) {
            ForEach(h0...max(h0, h1), id: \.self) { h in
                let hs = dayStart.addingTimeInterval(TimeInterval(h * 3600))
                let he = hs.addingTimeInterval(3600)
                let segs = segments(live, hs, he)
                let total = segs.reduce(0) { $0 + $1.1 }
                let count = live.filter { $0.start >= hs && $0.start < he }.count
                Button { onTap(h) } label: {
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            if total < 1 {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])).foregroundStyle(.quaternary)
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    ForEach(Array(segs.enumerated()), id: \.offset) { _, s in
                                        Rectangle().fill(s.0.opacity(0.7)).frame(height: 44 * min(1, s.1 / 60))
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                if count > 0 { Text("\(count)").font(.system(size: 12, weight: .semibold)).frame(maxHeight: .infinity) }
                            }
                        }
                        .frame(height: 44)
                        Text("\(h):00").font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(h == nowHour ? Color.accentColor : Color.secondary)
                            .fontWeight(h == nowHour ? .semibold : .regular)
                    }
                    .frame(minWidth: 40, maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(h):00 — \(Int(total)) min")
            }
        }
    }

    /// minuty projektów w danej godzinie (kolor, minuty)
    private func segments(_ live: [Entry], _ hs: Date, _ he: Date) -> [(Color, Double)] {
        var acc: [String: (Color, Double)] = [:]
        for e in live {
            let span = max(60, e.end.timeIntervalSince(e.start))
            let ov = max(0, min(e.end, he).timeIntervalSince(max(e.start, hs)))
            guard ov > 0 else { continue }
            let color = store.project(e.projectId)?.color ?? Color.gray
            let k = e.projectId ?? "_other"
            let m = e.effectiveMinutes * ov / span
            acc[k] = (color, (acc[k]?.1 ?? 0) + m)
        }
        return acc.values.sorted { $0.1 > $1.1 }
    }
}

// MARK: - Wpis

struct EntryRow: View {
    let entry: Entry
    let day: String
    @Binding var expanded: Bool
    @EnvironmentObject var store: Store

    var body: some View {
        let project = store.project(entry.projectId)
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    StatusTag(status: entry.status)
                    projectMenu(project)
                    Tag { Text("\(hmFormatter.string(from: entry.start))–\(hmFormatter.string(from: entry.end))").monospacedDigit() }
                    Tag { Image(systemName: entry.tool.symbol).foregroundStyle(.secondary); Text(entry.tool.label) }
                    Spacer()
                    actions
                }
                HStack(alignment: .top, spacing: 14) {
                    timeColumn
                    Text(entry.summary ?? "Podsumowanie pojawi się po zakończeniu bloku pracy.")
                        .foregroundStyle(entry.summary == nil ? .secondary : .primary)
                        .italic(entry.summary == nil)
                        .lineLimit(expanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { expanded.toggle() }
                        .help(expanded ? "Zwiń" : "Rozwiń")
                }
            }
            activities.frame(width: 230, alignment: .leading)
        }
        .padding(.vertical, 6)
        .opacity(entry.status == .rejected ? 0.55 : 1)
    }

    private func projectMenu(_ project: Project?) -> some View {
        let color = project?.color ?? .gray
        return Menu {
            ForEach(store.projects) { p in
                Button(p.name) { setProject(p.id) }
            }
            Divider()
            Button("Inne") { setProject(nil) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(project?.name ?? "Inne").font(.system(size: 12, weight: .medium))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.35)))
        .help("Zmień projekt wpisu")
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if entry.status == .rejected {
                iconButton("arrow.uturn.backward", "Przywróć") { restore() }
            } else {
                if entry.projectId != nil {
                    iconButton("checkmark", entry.status == .approved ? "Cofnij zatwierdzenie" : "Zatwierdź",
                               tint: entry.status == .approved ? .green : nil) {
                        store.mutateEntry(day, entry.id) { $0.status = $0.status == .approved ? .review : .approved }
                    }
                }
                iconButton("xmark", "Odrzuć — nie wliczy się do raportu") {
                    store.mutateEntry(day, entry.id) { $0.status = .rejected }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26)
                .foregroundStyle(tint ?? Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var timeColumn: some View {
        HStack(spacing: 4) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(fmtHours(entry.effectiveMinutes)).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                if entry.adjustMinutes != 0 {
                    Text("\(entry.adjustMinutes > 0 ? "+" : "−")\(fmtHours(abs(entry.adjustMinutes))) h")
                        .font(.system(size: 10.5)).foregroundStyle(Color.accentColor).monospacedDigit()
                } else {
                    Text("h").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 48, alignment: .trailing)
            VStack(spacing: 0) {
                stepButton("chevron.up", 6, "Dodaj 6 minut")
                stepButton("chevron.down", -6, "Odejmij 6 minut")
            }
        }
        .frame(width: 92, alignment: .leading)
    }

    private func stepButton(_ symbol: String, _ delta: Double, _ help: String) -> some View {
        Button {
            guard entry.minutes + entry.adjustMinutes + delta >= 0 else { return }
            store.mutateEntry(day, entry.id) { $0.adjustMinutes += delta }
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Aktywności").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ForEach(Array(entry.apps.prefix(3).enumerated()), id: \.offset) { _, a in
                HStack(spacing: 8) {
                    IconTile(symbol: a.tool.symbol, color: a.tool.color, size: 20)
                    Text(a.title).lineLimit(1).truncationMode(.tail).help("\(a.app) · \(a.title)")
                    Spacer(minLength: 4)
                    Text("\(Int(a.minutes.rounded())) min").font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                }
                .font(.system(size: 12.5))
            }
        }
    }

    private func setProject(_ id: String?) {
        let mode = store.approvalMode(day)
        store.mutateEntry(day, entry.id) { e in
            e.projectId = id
            e.status = id == nil ? .unassigned : (mode == .auto ? .approved : .review)
        }
    }

    private func restore() {
        let mode = store.approvalMode(day)
        store.mutateEntry(day, entry.id) { e in
            e.status = e.projectId == nil ? .unassigned : (mode == .auto ? .approved : .review)
        }
    }
}
