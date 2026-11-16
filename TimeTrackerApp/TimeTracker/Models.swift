import SwiftUI

// MARK: - Narzędzia

enum ToolType: String, Codable, CaseIterable, Identifiable {
    case slack, figma, browser, ai, invoices, mail, meet, code, framer, notion, terminal, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .slack: return "Slack"
        case .figma: return "Figma"
        case .browser: return "Przeglądarka"
        case .ai: return "Asystenci AI"
        case .invoices: return "Faktury"
        case .mail: return "Poczta"
        case .meet: return "Spotkania"
        case .code: return "Edytor kodu"
        case .framer: return "Framer"
        case .notion: return "Notion"
        case .terminal: return "Terminal"
        case .custom: return "Inna aplikacja"
        }
    }
    var symbol: String {
        switch self {
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .figma: return "pencil.tip"
        case .browser: return "globe"
        case .ai: return "sparkles"
        case .invoices: return "doc.text.fill"
        case .mail: return "envelope.fill"
        case .meet: return "video.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .framer: return "square.grid.3x3.fill"
        case .notion: return "doc.richtext.fill"
        case .terminal: return "terminal.fill"
        case .custom: return "app.fill"
        }
    }
    var color: Color {
        switch self {
        case .slack: return Color(hex: "#c2457e")
        case .figma: return Color(hex: "#f0663a")
        case .browser: return Color(hex: "#2f8cf0")
        case .ai: return Color(hex: "#d97757")
        case .invoices: return Color(hex: "#32b45a")
        case .mail: return Color(hex: "#3a7bf0")
        case .meet: return Color(hex: "#18a999")
        case .code: return Color(hex: "#5b5ce6")
        case .framer: return Color(hex: "#3d3f48")
        case .notion: return Color(hex: "#6b6b73")
        case .terminal: return Color(hex: "#4a4b52")
        case .custom: return Color(hex: "#8e8e96")
        }
    }
    /// nazwy aplikacji (małymi literami), jak raportuje je macOS
    var appNames: [String] {
        switch self {
        case .slack: return ["slack"]
        case .figma: return ["figma"]
        case .browser: return ToolType.browsers
        case .ai: return ["claude", "chatgpt", "cursor", "windsurf", "perplexity", "copilot", "gemini", "lm studio", "ollama"]
        case .mail: return ["mail", "poczta", "microsoft outlook", "outlook", "spark", "airmail", "mimestream"]
        case .meet: return ["zoom.us", "zoom", "microsoft teams", "teams", "facetime", "webex"]
        case .code: return ["code", "visual studio code", "zed", "webstorm", "xcode", "sublime text", "nova"]
        case .framer: return ["framer"]
        case .notion: return ["notion"]
        case .terminal: return ["terminal", "iterm2", "warp", "ghostty", "alacritty", "kitty"]
        case .invoices, .custom: return []
        }
    }
    /// fragmenty adresów, po których narzędzie działające w przeglądarce jest rozpoznawane
    var webDomains: [String] {
        switch self {
        case .ai: return ["claude.ai", "chatgpt.com", "chat.openai.com", "gemini.google.com", "perplexity.ai", "v0.dev", "v0.app",
                          "lovable.dev", "bolt.new", "copilot.microsoft.com", "aistudio.google.com", "console.anthropic.com"]
        case .invoices: return ["fakturownia", "infakt", "wfirma", "ifirma", "saldeo", "faktura"]
        case .mail: return ["mail.google.com", "outlook.live.com", "outlook.office"]
        case .meet: return ["meet.google.com", "zoom.us/", "teams.microsoft.com"]
        case .figma: return ["figma.com"]
        case .slack: return ["app.slack.com"]
        case .notion: return ["notion.so", "notion.site"]
        case .framer: return ["framer.com"]
        default: return []
        }
    }
    var apps: String {
        switch self {
        case .browser: return "Chrome, Safari, Arc, Edge"
        case .ai: return "Claude, ChatGPT, Cursor, Perplexity, Gemini, v0, Lovable"
        case .invoices: return "Fakturownia, inFakt, wFirma, iFirma"
        case .mail: return "Mail, Gmail, Outlook"
        case .meet: return "Zoom, Meet, Teams"
        case .code: return "VS Code, Zed, Xcode"
        case .terminal: return "Terminal, iTerm, Warp"
        default: return ""
        }
    }
    var hint: String {
        switch self {
        case .slack: return "Kanał lub rozmowa, np. shape-factor"
        case .figma: return "Nazwa pliku lub zespołu"
        case .browser: return "Domena lub fragment tytułu strony"
        case .ai: return "Nazwa rozmowy, projektu lub repozytorium, np. Fliko"
        case .invoices: return "Nazwa kontrahenta na fakturze"
        case .mail: return "Nadawca, domena lub temat"
        case .meet: return "Nazwa spotkania"
        case .code: return "Repozytorium lub folder"
        case .framer, .notion: return "Nazwa projektu lub strony"
        case .terminal: return "Folder lub nazwa sesji"
        case .custom: return "Fragment tytułu okna"
        }
    }

    static let browsers = ["google chrome", "chrome", "safari", "arc", "microsoft edge", "firefox", "brave browser",
                           "opera", "vivaldi", "zen", "orion", "chromium", "dia"]

    func matchesApp(_ app: String) -> Bool {
        let a = app.lowercased()
        return appNames.contains { a == $0 || a.hasPrefix($0 + " ") }
    }

    /// narzędzie, którego dotyczy fragment pracy
    static func detect(app: String, url: String, title: String) -> ToolType {
        let t = (title + " " + url).lowercased()
        if ToolType.browser.matchesApp(app) {
            for type in [ToolType.ai, .invoices, .mail, .meet, .figma, .slack, .notion, .framer] where type.webDomains.contains(where: { t.contains($0) }) {
                return type
            }
        }
        for type in ToolType.allCases where type != .custom && type.matchesApp(app) { return type }
        return .custom
    }
}

// MARK: - Projekty

struct ToolRule: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var type: ToolType
    var app: String = ""
    var keywords: [String] = []
}

struct Project: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var colorHex: String
    var enabled: Bool = true
    var order: Int = 0
    var tools: [ToolRule] = []
    var keywords: [String] = []

    var color: Color { Color(hex: colorHex) }

    var summary: String {
        let t = tools.map { $0.type == .custom && !$0.app.isEmpty ? $0.app : $0.type.label }
        let n = keywords.count + tools.reduce(0) { $0 + $1.keywords.count }
        return (t.isEmpty ? "Brak narzędzi" : t.joined(separator: ", ")) + " · \(n) " + plural(n, "słowo kluczowe", "słowa kluczowe", "słów kluczowych")
    }
}

let projectPalette = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#63e6e2", "#40c8e0",
                      "#0a84ff", "#5e5ce6", "#bf5af2", "#ff375f", "#ac8e68", "#98989d"]

// MARK: - Ustawienia

enum ApprovalMode: String, Codable, CaseIterable { case manual, auto }

struct AppSettings: Codable, Equatable {
    var reportHour = 18
    var reportMinute = 0
    var workdays: Set<Int> = [2, 3, 4, 5, 6]     // Calendar.weekday: 1 = niedziela … 7 = sobota
    var workStart = 8
    var workEnd = 18
    var idleMinutes = 5
    var minBlockMinutes = 2
    var includeOther = true
    var approvalDefault: ApprovalMode = .manual
    var refreshMinutes = 15
    var aiEnabled = true
    var aiModel = "claude-haiku-4-5"
    var notifyReport = true
    var saveMarkdown = true

    init() {}
    // odporne na nowe pola w przyszłych wersjach
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        reportHour = (try? c.decode(Int.self, forKey: .reportHour)) ?? d.reportHour
        reportMinute = (try? c.decode(Int.self, forKey: .reportMinute)) ?? d.reportMinute
        workdays = (try? c.decode(Set<Int>.self, forKey: .workdays)) ?? d.workdays
        workStart = (try? c.decode(Int.self, forKey: .workStart)) ?? d.workStart
        workEnd = (try? c.decode(Int.self, forKey: .workEnd)) ?? d.workEnd
        idleMinutes = (try? c.decode(Int.self, forKey: .idleMinutes)) ?? d.idleMinutes
        minBlockMinutes = (try? c.decode(Int.self, forKey: .minBlockMinutes)) ?? d.minBlockMinutes
        includeOther = (try? c.decode(Bool.self, forKey: .includeOther)) ?? d.includeOther
        approvalDefault = (try? c.decode(ApprovalMode.self, forKey: .approvalDefault)) ?? d.approvalDefault
        refreshMinutes = (try? c.decode(Int.self, forKey: .refreshMinutes)) ?? d.refreshMinutes
        aiEnabled = (try? c.decode(Bool.self, forKey: .aiEnabled)) ?? d.aiEnabled
        aiModel = (try? c.decode(String.self, forKey: .aiModel)) ?? d.aiModel
        notifyReport = (try? c.decode(Bool.self, forKey: .notifyReport)) ?? d.notifyReport
        saveMarkdown = (try? c.decode(Bool.self, forKey: .saveMarkdown)) ?? d.saveMarkdown
    }
}

// MARK: - Wpisy

enum EntryStatus: String, Codable, CaseIterable {
    case review, approved, unassigned, rejected
    var label: String {
        switch self {
        case .review: return "Do przeglądu"
        case .approved: return "Zatwierdzone"
        case .unassigned: return "Nieprzypisane"
        case .rejected: return "Odrzucone"
        }
    }
    var tint: Color {
        switch self {
        case .review: return .orange
        case .approved: return .green
        case .unassigned: return .secondary
        case .rejected: return .red
        }
    }
}

struct AppUse: Codable, Hashable {
    var app: String
    var title: String
    var domain: String
    var minutes: Double
    var tool: ToolType
}

struct Entry: Codable, Identifiable, Hashable {
    var id: String
    var projectId: String?
    var start: Date
    var end: Date
    var minutes: Double
    var adjustMinutes: Double = 0
    var tool: ToolType
    var apps: [AppUse]
    var summary: String?
    var summaryKey: String?
    var status: EntryStatus
    var locked = false

    var effectiveMinutes: Double { max(0, minutes + adjustMinutes) }
    /// podpis aktywności — zmiana oznacza, że podsumowanie trzeba napisać od nowa
    var activityKey: String {
        let titles = apps.prefix(4).map { $0.title }.joined(separator: "|")
        return "\(Int(minutes / 10))|\(titles)"
    }
}

struct DayReport: Codable, Hashable {
    var generatedAt: Date
    var summary: String
}

struct DayRecord: Codable {
    var date: String
    var approvalMode: ApprovalMode?
    var note: String = ""
    var entries: [Entry] = []
    var report: DayReport?
    var lastUpdated: Date?
}

// MARK: - Pomocnicze

func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    if n == 1 { return one }
    let m10 = n % 10, m100 = n % 100
    return (2...4).contains(m10) && !(12...14).contains(m100) ? few : many
}

/// 1,4 (godziny z jednym miejscem po przecinku)
func fmtHours(_ minutes: Double) -> String {
    let h = (minutes / 6).rounded() / 10
    return h.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pl_PL")))
}
func fmtDuration(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
}
let hmFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
let dayKeyFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
func dayKey(_ d: Date) -> String { dayKeyFormatter.string(from: d) }
func dateFromKey(_ k: String) -> Date { dayKeyFormatter.date(from: k) ?? Date() }
func longDay(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "EEEE, d MMMM"
    let s = f.string(from: d); return s.prefix(1).uppercased() + s.dropFirst()
}
func shortDay(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "pl_PL"); f.dateFormat = "EEE, d MMM"
    return (Calendar.current.isDateInToday(d) ? "Dziś, " : "") + f.string(from: d)
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255, opacity: 1)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
