import SwiftUI
import AppKit

struct ReportsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @State private var selected: String?

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(store.savedDayKeys(), id: \.self) { key in
                    let rec = store.day(key)
                    let live = rec.entries.filter { $0.status != .rejected && $0.projectId != nil }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(longDay(dateFromKey(key)))
                            Spacer()
                            Text("\(fmtHours(live.reduce(0) { $0 + $1.effectiveMinutes })) h").monospacedDigit().foregroundStyle(.secondary)
                        }
                        DayBar(entries: live)
                    }
                    .padding(.vertical, 4)
                    .tag(key as String?)
                }
            }
            .frame(width: 300)
            Divider()
            if let key = selected {
                ReportDetail(key: key)
            } else {
                VStack(spacing: 6) {
                    Text("Wybierz dzień").font(.headline)
                    Text("Raport powstaje automatycznie o \(String(format: "%d:%02d", store.settings.reportHour, store.settings.reportMinute)) w dni robocze.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Raporty")
        .onAppear { if selected == nil { selected = store.savedDayKeys().first } }
    }
}

struct DayBar: View {
    let entries: [Entry]
    @EnvironmentObject var store: Store
    var body: some View {
        let totals = store.projects.map { p in (p.color, entries.filter { $0.projectId == p.id }.reduce(0) { $0 + $1.effectiveMinutes }) }.filter { $0.1 > 0 }
        let sum = max(1, totals.reduce(0) { $0 + $1.1 })
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(totals.enumerated()), id: \.offset) { _, t in
                    Rectangle().fill(t.0).frame(width: max(3, (geo.size.width - CGFloat(totals.count) * 2) * t.1 / sum))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 5)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
    }
}

struct ReportDetail: View {
    let key: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @State private var working = false
    @State private var copied = false

    var body: some View {
        let rec = store.day(key)
        let live = rec.entries.filter { $0.status != .rejected }
        let totals = store.projects.compactMap { p -> (Project, [Entry])? in
            let es = live.filter { $0.projectId == p.id }
            return es.isEmpty ? nil : (p, es)
        }.sorted { a, b in a.1.reduce(0) { $0 + $1.effectiveMinutes } > b.1.reduce(0) { $0 + $1.effectiveMinutes } }
        let other = live.filter { $0.projectId == nil }
        let projectMinutes = live.filter { $0.projectId != nil }.reduce(0) { $0 + $1.effectiveMinutes }
        let pending = live.filter { $0.status == .review }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(longDay(dateFromKey(key))).font(.title2.weight(.semibold))
                        Text("\(fmtDuration(projectMinutes)) w projektach" + (pending > 0 ? " · \(pending) do przeglądu" : ""))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(copied ? "Skopiowano" : "Kopiuj jako tekst") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(engine.markdown(key), forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                    Button("Pokaż plik") {
                        engine.writeMarkdown(key)
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.reports.appendingPathComponent("\(key).md")])
                    }
                }
                DayBar(entries: live.filter { $0.projectId != nil })

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        if let r = rec.report, !r.summary.isEmpty {
                            Text(r.summary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(store.hasAPIKey ? "Brak podsumowania dnia." : "Dodaj klucz API w Ustawieniach → AI, żeby dostawać podsumowania dnia.")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            if let r = rec.report { Text("Wygenerowano \(hmFormatter.string(from: r.generatedAt))").font(.caption).foregroundStyle(.tertiary) }
                            Spacer()
                            Button(working ? "Generuję…" : (rec.report == nil ? "Utwórz raport" : "Utwórz ponownie")) {
                                working = true
                                Task { await engine.makeReport(key, notify: false); working = false }
                            }
                            .disabled(working)
                        }
                    }
                    .padding(6)
                } label: { Text("Podsumowanie") }

                ForEach(totals, id: \.0.id) { item in
                    let p = item.0
                    let es = item.1
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle().fill(p.color).frame(width: 10, height: 10)
                            Text(p.name).font(.headline)
                            Text(fmtDuration(es.reduce(0) { $0 + $1.effectiveMinutes })).foregroundStyle(.secondary)
                        }
                        ForEach(es) { e in entryLine(e) }
                    }
                }
                if !other.isEmpty && store.settings.includeOther {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle().fill(Color.gray).frame(width: 10, height: 10)
                            Text("Inne").font(.headline)
                            Text(fmtDuration(other.reduce(0) { $0 + $1.effectiveMinutes })).foregroundStyle(.secondary)
                        }
                        ForEach(other) { e in entryLine(e) }
                    }
                }
                if !rec.note.trimmed.isEmpty {
                    GroupBox { Text(rec.note).frame(maxWidth: .infinity, alignment: .leading).padding(6) } label: { Text("Notatka dnia") }
                }
            }
            .padding(24)
        }
    }

    private func entryLine(_ e: Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(hmFormatter.string(from: e.start))–\(hmFormatter.string(from: e.end))").monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(e.summary ?? e.apps.first?.title ?? "").lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(fmtHours(e.effectiveMinutes)) h").monospacedDigit()
        }
        .font(.callout)
    }
}
