import Foundation

/// Dzieli zapis aktywności na wpisy i przypisuje je do projektów według reguł.
/// (Odpowiednik bin/summarize.py — ta sama logika, przeniesiona do aplikacji.)
enum Classifier {
    struct Piece {
        var start: Date
        var end: Date
        var app: String
        var title: String
        var url: String
        var projectId: String?
        var seconds: TimeInterval { end.timeIntervalSince(start) }
        var tool: ToolType { ToolType.detect(app: app, url: url, title: title) }
        var domain: String {
            guard !url.isEmpty, let host = URL(string: url)?.host else { return "" }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    private static let cleanPatterns = [#"^\(\d+\)\s*"#, #"^[•●]\s*"#,
        #"\s+[-–—]\s+(Google Chrome|Safari|Arc|Microsoft Edge|Mozilla Firefox|Brave)$"#, #"\s*[-–—]\s*Audio playing$"#, #"\s+\(\d+\)$"#]

    static func cleanTitle(_ t: String) -> String {
        var s = t.trimmed
        for p in cleanPatterns { s = s.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return String(s.prefix(140))
    }

    // MARK: czas aktywny

    /// okresy aktywności; krótkie przerwy (poniżej progu bezczynności) liczą się jako praca
    static func activeSpans(_ afk: [Ev], idleMinutes: Int) -> [(Date, Date)]? {
        if afk.isEmpty { return nil }
        let act = afk.filter { $0.data["status"] == "not-afk" }.map { ($0.start, $0.end) }.sorted { $0.0 < $1.0 }
        var out: [(Date, Date)] = []
        let gap = TimeInterval(idleMinutes * 60)
        for (a, b) in act {
            if let last = out.last, a.timeIntervalSince(last.1) <= gap {
                out[out.count - 1].1 = max(last.1, b)
            } else {
                out.append((a, b))
            }
        }
        return out
    }

    static func clip(_ a: Date, _ b: Date, _ spans: [(Date, Date)]?) -> [(Date, Date)] {
        guard let spans = spans else { return b > a ? [(a, b)] : [] }
        var out: [(Date, Date)] = []
        for (s, e) in spans {
            if e <= a { continue }
            if s >= b { break }
            let x = max(a, s), y = min(b, e)
            if y > x { out.append((x, y)) }
        }
        return out
    }

    // MARK: dopasowanie

    static func score(_ p: Project, app: String, text: String, url: String) -> Int {
        var best = 0
        let lurl = url.lowercased()
        for t in p.tools {
            let kws = t.keywords.map { $0.lowercased().trimmed }.filter { !$0.isEmpty }
            let inTool: Bool
            if t.type == .custom {
                inTool = !t.app.trimmed.isEmpty && app.lowercased().contains(t.app.lowercased().trimmed)
            } else {
                inTool = t.type.matchesApp(app) ||
                    (ToolType.browser.matchesApp(app) && t.type.webDomains.contains { lurl.contains($0) || text.contains($0) })
            }
            guard inTool else { continue }
            if kws.isEmpty {
                if t.type != .browser { best = max(best, 2) }   // cała przeglądarka bez słów = zbyt szeroko
            } else if kws.contains(where: { text.contains($0) }) {
                best = max(best, 4)
            }
        }
        for k in p.keywords {
            let k = k.lowercased().trimmed
            if !k.isEmpty && text.contains(k) { best = max(best, 3) }
        }
        return best
    }

    static func pieces(window: [Ev], afk: [Ev], projects: [Project], settings: AppSettings) -> [Piece] {
        let active = projects.filter { $0.enabled }.sorted { $0.order < $1.order }
        let spans = activeSpans(afk, idleMinutes: settings.idleMinutes)
        var out: [Piece] = []
        for ev in window.sorted(by: { $0.start < $1.start }) {
            let app = ev.data["app"] ?? "?"
            let title = ev.data["title"] ?? ""
            let url = ev.data["url"] ?? ""
            let text = [app, title, url].joined(separator: " ").lowercased()
            var bestScore = 0
            var pid: String?
            for p in active {
                let s = score(p, app: app, text: text, url: url)
                if s > bestScore { bestScore = s; pid = p.id }
            }
            for (x, y) in clip(ev.start, ev.end, spans) {
                out.append(Piece(start: x, end: y, app: app, title: cleanTitle(title), url: url, projectId: pid))
            }
        }
        // przytnij ewentualne nakładki
        var fixed: [Piece] = []
        var lastEnd: Date?
        for var p in out {
            if let le = lastEnd, p.start < le { p.start = le }
            if p.end > p.start { fixed.append(p); lastEnd = p.end }
        }
        return fixed
    }

    // MARK: wpisy

    private struct Block { var key: String; var start: Date; var end: Date; var pieces: [Piece]
        var seconds: TimeInterval { pieces.reduce(0) { $0 + $1.seconds } } }

    static func entries(from pieces: [Piece]) -> [Entry] {
        // 1. ciągłe bloki jednego projektu (przerwy < 5 min)
        var raw: [Block] = []
        for pc in pieces {
            let k = pc.projectId ?? "_other"
            if var last = raw.last, last.key == k, pc.start.timeIntervalSince(last.end) < 300 {
                last.end = pc.end; last.pieces.append(pc); raw[raw.count - 1] = last
            } else {
                raw.append(Block(key: k, start: pc.start, end: pc.end, pieces: [pc]))
            }
        }
        // 2. wtrącenia < 3 min nie przerywają bloku; ten sam projekt rozdzielony nimi (≤ 10 min) łączymy
        var merged: [Block] = []
        for b in raw {
            if b.seconds < 180 { continue }
            if var last = merged.last, last.key == b.key, b.start.timeIntervalSince(last.end) <= 600 {
                last.end = b.end; last.pieces += b.pieces; merged[merged.count - 1] = last
            } else {
                merged.append(b)
            }
        }
        // 3. podział wg narzędzia, gdy fragment trwa ≥ 8 min
        var split: [Block] = []
        for b in merged {
            var runs: [(tool: ToolType?, pieces: [Piece])] = []
            for pc in b.pieces {
                if let last = runs.last, last.tool == pc.tool { runs[runs.count - 1].pieces.append(pc) }
                else { runs.append((pc.tool, [pc])) }
            }
            var out: [(tool: ToolType?, pieces: [Piece])] = []
            for r in runs {
                let sec = r.pieces.reduce(0) { $0 + $1.seconds }
                if let last = out.last, last.tool != nil, sec < 480 || last.tool == r.tool {
                    out[out.count - 1].pieces += r.pieces
                } else if out.isEmpty && sec < 480 && runs.count > 1 {
                    out.append((nil, r.pieces))           // krótki początek dołączy do następnego fragmentu
                } else if let last = out.last, last.tool == nil {
                    out[out.count - 1].pieces += r.pieces
                    out[out.count - 1].tool = r.tool
                } else {
                    out.append(r)
                }
            }
            for r in out {
                let ps = r.pieces.sorted { $0.start < $1.start }
                guard let f = ps.first, let l = ps.last else { continue }
                split.append(Block(key: b.key, start: f.start, end: l.end, pieces: ps))
            }
        }
        // 4. wpisy
        let idFmt = DateFormatter(); idFmt.dateFormat = "HHmm"
        var result: [Entry] = []
        for b in split {
            if b.key == "_other" && b.seconds < 300 { continue }
            var acts: [String: AppUse] = [:]
            var order: [String] = []
            var toolSec: [ToolType: TimeInterval] = [:]
            for pc in b.pieces {
                let title = pc.title.isEmpty ? (pc.domain.isEmpty ? pc.app : pc.domain) : pc.title
                let k = pc.app + "|" + title
                if acts[k] == nil { acts[k] = AppUse(app: pc.app, title: title, domain: pc.domain, minutes: 0, tool: pc.tool); order.append(k) }
                acts[k]!.minutes += pc.seconds / 60
                toolSec[pc.tool, default: 0] += pc.seconds
            }
            let apps = order.compactMap { acts[$0] }.sorted { $0.minutes > $1.minutes }
            let tool = toolSec.max { $0.value < $1.value }?.key ?? .custom
            result.append(Entry(id: "\(b.key)-\(idFmt.string(from: b.start))",
                                projectId: b.key == "_other" ? nil : b.key,
                                start: b.start, end: b.end, minutes: (b.seconds / 6).rounded() / 10,
                                tool: tool, apps: Array(apps.prefix(6)), summary: nil, summaryKey: nil,
                                status: .review))
        }
        return result
    }

    /// Łączy świeżo policzone wpisy z zapisanymi; ręcznie zmienione (locked) zostają bez zmian.
    static func merge(fresh: [Entry], into existing: [Entry], mode: ApprovalMode) -> [Entry] {
        var byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [Entry] = existing.filter { $0.locked }
        let lockedIds = Set(result.map { $0.id })
        for var e in fresh where !lockedIds.contains(e.id) {
            if let old = byId.removeValue(forKey: e.id) {
                e.summary = old.summary
                e.summaryKey = old.summaryKey
                e.status = old.projectId == e.projectId ? old.status : defaultStatus(e, mode)
                e.adjustMinutes = old.adjustMinutes
            } else {
                e.status = defaultStatus(e, mode)
            }
            result.append(e)
        }
        return result.sorted { $0.start < $1.start }
    }

    static func defaultStatus(_ e: Entry, _ mode: ApprovalMode) -> EntryStatus {
        e.projectId == nil ? .unassigned : (mode == .auto ? .approved : .review)
    }
}
