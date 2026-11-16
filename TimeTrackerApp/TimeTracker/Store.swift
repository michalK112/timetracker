import Foundation
import Security
import Combine

enum Paths {
    static let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/TimeTracker")
    static let exports = base.appendingPathComponent("exports")
    static let data = base.appendingPathComponent("data")
    static let days = data.appendingPathComponent("days")
    static let reports = base.appendingPathComponent("reports")
}

enum Keychain {
    static let service = "studio.mk.timetracker"
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value = value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Projekty, ustawienia i dni zapisane lokalnie jako JSON w ~/Documents/TimeTracker/data.
@MainActor
final class Store: ObservableObject {
    @Published var projects: [Project] = [] { didSet { if loaded { save(projects, "projects.json") } } }
    @Published var settings = AppSettings() { didSet { if loaded && settings != oldValue { save(settings, "settings.json") } } }
    private var days: [String: DayRecord] = [:]   // pamięć podręczna; zmiany ogłasza setDay()
    @Published var hasAPIKey = Keychain.get("anthropic-api-key") != nil

    private var loaded = false
    private let enc: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }()
    private let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init() {
        let fm = FileManager.default
        for dir in [Paths.data, Paths.days, Paths.reports, Paths.exports] { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        if let d = try? Data(contentsOf: Paths.data.appendingPathComponent("projects.json")), let p = try? dec.decode([Project].self, from: d) {
            projects = p
        } else {
            projects = [Project(id: "shape-factor", name: "Shape Factor", colorHex: "#ff375f", order: 0,
                                tools: [ToolRule(type: .slack, keywords: ["shape factor", "shape-factor"]),
                                        ToolRule(type: .figma, keywords: ["Shape Factor"]),
                                        ToolRule(type: .invoices, keywords: ["Shape Factor"])],
                                keywords: ["Shape Factor", "shapefactor"])]
            save(projects, "projects.json")
        }
        if let d = try? Data(contentsOf: Paths.data.appendingPathComponent("settings.json")), let s = try? dec.decode(AppSettings.self, from: d) {
            settings = s
        }
        loaded = true
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard let d = try? enc.encode(value) else { return }
        try? d.write(to: Paths.data.appendingPathComponent(name), options: .atomic)
    }

    // MARK: projekty

    func project(_ id: String?) -> Project? { id.flatMap { pid in projects.first { $0.id == pid } } }

    func addProject() -> Project {
        let used = Set(projects.map { $0.colorHex })
        let color = projectPalette.first { !used.contains($0) } ?? projectPalette[projects.count % projectPalette.count]
        let p = Project(id: "p" + UUID().uuidString.prefix(8).lowercased(), name: "Nowy projekt", colorHex: color, order: projects.count)
        projects.append(p)
        return p
    }
    func update(_ p: Project) { if let i = projects.firstIndex(where: { $0.id == p.id }) { projects[i] = p } }
    func deleteProject(_ id: String) { projects.removeAll { $0.id == id } }

    // MARK: dni

    func day(_ key: String) -> DayRecord {
        if let d = days[key] { return d }
        let url = Paths.days.appendingPathComponent("\(key).json")
        let rec = (try? Data(contentsOf: url)).flatMap { try? dec.decode(DayRecord.self, from: $0) } ?? DayRecord(date: key)
        days[key] = rec
        return rec
    }

    func setDay(_ rec: DayRecord) {
        objectWillChange.send()
        days[rec.date] = rec
        if let d = try? enc.encode(rec) { try? d.write(to: Paths.days.appendingPathComponent("\(rec.date).json"), options: .atomic) }
    }

    func mutateDay(_ key: String, _ change: (inout DayRecord) -> Void) {
        var rec = day(key)
        change(&rec)
        setDay(rec)
    }

    func mutateEntry(_ key: String, _ id: String, _ change: (inout Entry) -> Void) {
        mutateDay(key) { rec in
            if let i = rec.entries.firstIndex(where: { $0.id == id }) {
                change(&rec.entries[i])
                rec.entries[i].locked = true
            }
        }
    }

    func approvalMode(_ key: String) -> ApprovalMode { day(key).approvalMode ?? settings.approvalDefault }

    /// dni, z których są zapisane wpisy (najnowsze pierwsze)
    func savedDayKeys() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.days.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted(by: >)
    }

    // MARK: klucz API

    func setAPIKey(_ key: String?) {
        Keychain.set(key?.trimmed, for: "anthropic-api-key")
        hasAPIKey = Keychain.get("anthropic-api-key") != nil
    }
}
