// Zapis aktywności: aktywna aplikacja, tytuł okna, adres strony i bezczynność, co 5 s.
// Podejście (Accessibility API dla tytułów, AppleScript/AX dla adresów, CGEventSource dla
// bezczynności) wzorowane na ActivityWatch (aw-watcher-window, aw-watcher-afk, MPL-2.0);
// kod napisany od nowa.

import Cocoa
import ApplicationServices
import Combine

let POLL_INTERVAL: TimeInterval = 5
let AFK_AFTER: TimeInterval = 180
let MAX_JOIN_GAP: TimeInterval = 20

let PRIVATE_APPS: Set<String> = ["1Password", "1Password 7", "Bitwarden", "Keychain Access", "Dostęp do pęku kluczy", "Passwords", "Hasła", "Dashlane"]
let CHROMIUM_APPS = ["Google Chrome", "Google Chrome Canary", "Chromium", "Brave Browser", "Microsoft Edge", "Arc", "Vivaldi", "Opera", "Dia"]
let GECKO_APPS = ["Firefox", "Firefox Developer Edition", "Firefox Nightly", "Zen", "Zen Browser", "LibreWolf", "Waterfox", "Floorp"]

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC"); return f
}()

// MARK: - format pliku dnia (zgodny z wcześniejszymi eksportami)

struct Ev: Codable {
    var timestamp: String
    var duration: Double
    var data: [String: String]
    var start: Date { isoFormatter.date(from: timestamp) ?? .distantPast }
    var end: Date { start.addingTimeInterval(duration) }
}

struct DayFile: Codable {
    var date: String
    var exportedAt: String
    var host: String
    var tz: String
    var source: String
    var window: [Ev]
    var afk: [Ev]
    var web: [Ev]
}

/// Ciąg zdarzeń; kolejne próbki z tymi samymi danymi wydłużają ostatnie zdarzenie.
final class Track {
    var events: [Ev] = []
    private var lastStart: Date?
    private var lastSeen: Date?

    func sample(_ data: [String: String], at now: Date, startAt: Date? = nil) {
        if let s = lastStart, let seen = lastSeen, now.timeIntervalSince(seen) <= MAX_JOIN_GAP, !events.isEmpty {
            let i = events.count - 1
            if events[i].data == data {
                events[i].duration = now.timeIntervalSince(s)
                lastSeen = now
                return
            }
            let end = max(s, startAt ?? now)
            events[i].duration = end.timeIntervalSince(s)
        }
        let start = startAt ?? now
        events.append(Ev(timestamp: isoFormatter.string(from: start), duration: max(0, now.timeIntervalSince(start)), data: data))
        lastStart = start
        lastSeen = now
    }
    func cut() { lastStart = nil; lastSeen = nil }
}

// MARK: - odczyt okna

func axString(_ value: AnyObject?) -> String? {
    guard let value = value else { return nil }
    let cf = value as CFTypeRef
    if CFGetTypeID(cf) == CFStringGetTypeID() { return (cf as! CFString) as String }
    if CFGetTypeID(cf) == CFAttributedStringGetTypeID() { return (value as! NSAttributedString).string }
    return nil
}
func axElement(_ value: AnyObject?) -> AXUIElement? {
    guard let value = value, CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func focusedWindow(pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    var w: AnyObject?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success else { return nil }
    return axElement(w)
}
func windowTitle(_ w: AXUIElement) -> String? {
    var t: AnyObject?
    guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success else { return nil }
    return axString(t)
}
func geckoURL(_ window: AXUIElement) -> String? {
    var queue = [window]; var i = 0
    while i < queue.count && i < 384 {
        let el = queue[i]; i += 1
        var role: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        if axString(role) == "AXWebArea" {
            var u: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &u)
            if let url = u as? NSURL { return url.absoluteString }
            return axString(u)
        }
        var ch: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ch)
        if let c = ch as? [AXUIElement] { queue.append(contentsOf: c) }
    }
    return nil
}

/// Adres aktywnej karty (Chrome, Arc, Edge, Brave, Safari); okna incognito są pomijane.
final class BrowserURL {
    private var scripts: [String: NSAppleScript] = [:]
    private var blockedUntil: [String: Date] = [:]

    private func source(for app: String) -> String? {
        if CHROMIUM_APPS.contains(app) {
            return """
            tell application "\(app)"
              if (count of windows) is 0 then return ""
              try
                if mode of front window is "incognito" then return ""
              end try
              return URL of active tab of front window
            end tell
            """
        }
        if app == "Safari" || app == "Safari Technology Preview" {
            return """
            tell application "\(app)"
              if (count of windows) is 0 then return ""
              return URL of current tab of front window
            end tell
            """
        }
        return nil
    }

    func url(for app: String) -> String? {
        if let until = blockedUntil[app], until > Date() { return nil }
        if scripts[app] == nil, let src = source(for: app) { scripts[app] = NSAppleScript(source: src) }
        guard let script = scripts[app] else { return nil }
        var err: NSDictionary?
        let res = script.executeAndReturnError(&err)
        if let err = err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            blockedUntil[app] = Date().addingTimeInterval(code == -1743 ? 600 : 60)
            return nil
        }
        let s = res.stringValue ?? ""
        return s.isEmpty ? nil : s
    }
}

func secondsSinceInput() -> TimeInterval {
    CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
}
func screenLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

// MARK: - Tracker

@MainActor
final class Tracker: ObservableObject {
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var activeTodaySeconds: TimeInterval = 0
    @Published private(set) var currentApp: String = ""
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()

    private(set) var day: String
    let window = Track()
    let afk = Track()
    private let browser = BrowserURL()
    private var dirty = false
    private var ticker: Timer?
    private var flusher: Timer?
    private let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    init() {
        day = dayKey(Date())
        load()
    }

    var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    func start() {
        try? FileManager.default.createDirectory(at: Paths.exports, withIntermediateDirectories: true)
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: POLL_INTERVAL, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        ticker?.tolerance = 1
        flusher = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.window.cut(); self?.afk.cut(); self?.flush() }
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause(until date: Date?) {
        pausedUntil = date
        window.cut(); afk.cut()
        dirty = true
        flush()
        if date == nil { tick() }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(opts)
    }

    private var fileURL: URL { Paths.exports.appendingPathComponent("\(day).json") }

    private func load() {
        window.events = []; afk.events = []; window.cut(); afk.cut()
        guard let d = try? Data(contentsOf: fileURL), let f = try? JSONDecoder().decode(DayFile.self, from: d), f.source == "timetracker-app" else { return }
        window.events = f.window
        afk.events = f.afk
        recomputeActive()
    }

    func flush() {
        guard dirty else { return }
        let f = DayFile(date: day, exportedAt: isoFormatter.string(from: Date()), host: host, tz: tzString(),
                        source: "timetracker-app", window: window.events, afk: afk.events, web: [])
        if let data = try? JSONEncoder().encode(f) {
            try? data.write(to: fileURL, options: .atomic)
            dirty = false
        }
    }

    private func tzString() -> String {
        let f = DateFormatter(); f.dateFormat = "xx"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: Date())
    }

    private func recomputeActive() {
        activeTodaySeconds = afk.events.filter { $0.data["status"] == "not-afk" }.reduce(0) { $0 + $1.duration }
    }

    private func tick() {
        let now = Date()
        let today = dayKey(now)
        if today != day { flush(); day = today; load(); dirty = true }
        accessibilityGranted = AXIsProcessTrusted()
        if isPaused { window.cut(); afk.cut(); return }
        if pausedUntil != nil { pausedUntil = nil }

        let idle = secondsSinceInput()
        let locked = screenLocked()
        if locked || idle >= AFK_AFTER {
            let start = locked ? now : now.addingTimeInterval(-idle)
            afk.sample(["status": "afk"], at: now, startAt: afk.events.last?.data["status"] == "afk" ? nil : start)
        } else {
            afk.sample(["status": "not-afk"], at: now)
        }
        dirty = true
        recomputeActive()
        if locked { window.cut(); return }

        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else { return }
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { window.cut(); currentApp = name; return }
        var data = ["app": name, "title": ""]
        if !PRIVATE_APPS.contains(name), accessibilityGranted, let w = focusedWindow(pid: app.processIdentifier) {
            data["title"] = windowTitle(w) ?? ""
            if GECKO_APPS.contains(name), let u = geckoURL(w) { data["url"] = u }
        }
        if data["url"] == nil, !PRIVATE_APPS.contains(name), let u = browser.url(for: name) { data["url"] = u }
        window.sample(data, at: now)
        currentApp = name
    }

    /// zdarzenia z danego dnia: dzisiejsze z pamięci, starsze z pliku
    func events(for key: String) -> (window: [Ev], afk: [Ev]) {
        if key == day { return (window.events, afk.events) }
        let url = Paths.exports.appendingPathComponent("\(key).json")
        guard let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(DayFile.self, from: d) else { return ([], []) }
        return (f.window, f.afk)
    }
}
