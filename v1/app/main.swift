// TimeTracker.app — lekki tracker aktywności dla MK Design Studio.
// Co 5 s zapisuje aktywną aplikację, tytuł okna, adres strony w przeglądarce oraz
// bezczynność do ~/Documents/TimeTracker/exports/RRRR-MM-DD.json (format zgodny z summarize.py).
// Podejście (Accessibility API dla tytułów, AppleScript/AX dla adresów, CGEventSource
// dla bezczynności) wzorowane na ActivityWatch (aw-watcher-window, aw-watcher-afk, MPL-2.0);
// kod napisany od nowa.

import Cocoa
import ApplicationServices

let PANEL_URL = "https://claude.ai/artifact/Q9xCMNf12pyoBrdy4xC5vk"
let POLL: TimeInterval = 5
let AFK_AFTER: TimeInterval = 180        // jak domyślnie w ActivityWatch
let FLUSH_EVERY: TimeInterval = 60
let MAX_JOIN_GAP: TimeInterval = 20      // dłuższa przerwa między próbkami = uśpienie, nie łączymy
let BASE = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/TimeTracker")
let EXPORTS = BASE.appendingPathComponent("exports")
let LOGS = BASE.appendingPathComponent("logs")

let PRIVATE_APPS: Set<String> = ["1Password", "1Password 7", "Bitwarden", "Keychain Access", "Dostęp do pęku kluczy", "Passwords", "Hasła", "Dashlane"]
let CHROMIUM = ["Google Chrome", "Google Chrome Canary", "Chromium", "Brave Browser", "Microsoft Edge", "Arc", "Vivaldi", "Opera", "Dia"]
let GECKO = ["Firefox", "Firefox Developer Edition", "Firefox Nightly", "Zen", "Zen Browser", "LibreWolf", "Waterfox", "Floorp"]

// MARK: - log

let logFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
func log(_ msg: String) {
    let line = "\(logFmt.string(from: Date())) \(msg)\n"
    let url = LOGS.appendingPathComponent("tracker.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.data(using: .utf8)!.write(to: url) }
}

// MARK: - format pliku

struct Ev: Codable {
    var timestamp: String
    var duration: Double
    var data: [String: String]
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

let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC"); return f }()
let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
let tzFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "xx"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

/// Ciąg zdarzeń jednego rodzaju; kolejne próbki z tymi samymi danymi wydłużają ostatnie zdarzenie.
final class Track {
    var events: [Ev] = []
    var lastStart: Date?
    var lastSeen: Date?

    func sample(_ data: [String: String], at now: Date, startAt: Date? = nil) {
        if let s = lastStart, let seen = lastSeen, now.timeIntervalSince(seen) <= MAX_JOIN_GAP {
            let i = events.count - 1
            if events[i].data == data {
                events[i].duration = now.timeIntervalSince(s)
                lastSeen = now
                return
            }
            // zamknij poprzednie zdarzenie na początku nowego
            let end = max(s, startAt ?? now)
            events[i].duration = end.timeIntervalSince(s)
        }
        let start = startAt ?? now
        events.append(Ev(timestamp: iso.string(from: start), duration: max(0, now.timeIntervalSince(start)), data: data))
        lastStart = start
        lastSeen = now
    }
    /// zakończ ciągłość (pauza, uśpienie, koniec dnia)
    func cut() { lastStart = nil; lastSeen = nil }
}

// MARK: - odczyt aktywnego okna

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
/// Firefox i pochodne: adres strony z węzła AXWebArea (jak w ActivityWatch)
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

/// Chrome, Arc, Edge, Brave, Safari: adres aktywnej karty przez AppleScript.
/// Okna incognito / prywatne są pomijane.
final class BrowserURL {
    private var scripts: [String: NSAppleScript] = [:]
    private var blockedUntil: [String: Date] = [:]

    private func source(for app: String) -> String? {
        if CHROMIUM.contains(app) {
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
            // -1743: brak zgody na sterowanie przeglądarką; nie pytaj ponownie przez 10 min
            blockedUntil[app] = Date().addingTimeInterval(code == -1743 ? 600 : 60)
            log("URL z \(app) niedostępny (błąd \(code))")
            return nil
        }
        let s = res.stringValue ?? ""
        return s.isEmpty ? nil : s
    }
}

// MARK: - bezczynność

func secondsSinceInput() -> TimeInterval {
    CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
}
func screenLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

// MARK: - tracker

final class Tracker {
    var day: String
    let window = Track()
    let afk = Track()
    let browser = BrowserURL()
    var pausedUntil: Date?
    var dirty = false
    let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    init() {
        day = dayFmt.string(from: Date())
        load()
    }

    var fileURL: URL { EXPORTS.appendingPathComponent("\(day).json") }

    /// po restarcie dopisujemy do dzisiejszego pliku zamiast go nadpisywać
    func load() {
        window.events = []; afk.events = []; window.cut(); afk.cut()
        guard let d = try? Data(contentsOf: fileURL), let f = try? JSONDecoder().decode(DayFile.self, from: d), f.source == "timetracker-app" else { return }
        window.events = f.window
        afk.events = f.afk
    }

    func flush() {
        guard dirty else { return }
        let f = DayFile(date: day, exportedAt: iso.string(from: Date()), host: host, tz: tzFmt.string(from: Date()),
                        source: "timetracker-app", window: window.events, afk: afk.events, web: [])
        do {
            let data = try JSONEncoder().encode(f)
            try data.write(to: fileURL, options: .atomic)
            dirty = false
        } catch { log("Błąd zapisu: \(error.localizedDescription)") }
    }

    var paused: Bool {
        if let p = pausedUntil, p > Date() { return true }
        pausedUntil = nil
        return false
    }

    func tick() {
        let now = Date()
        let today = dayFmt.string(from: now)
        if today != day { flush(); day = today; load(); dirty = true }
        if paused { window.cut(); afk.cut(); return }

        // bezczynność: początek przerwy cofamy do ostatniego ruchu myszy/klawiatury
        let idle = secondsSinceInput()
        let locked = screenLocked()
        if locked || idle >= AFK_AFTER {
            let start = locked ? now : now.addingTimeInterval(-idle)
            afk.sample(["status": "afk"], at: now, startAt: afk.events.last?.data["status"] == "afk" ? nil : start)
        } else {
            afk.sample(["status": "not-afk"], at: now)
        }
        dirty = true
        if locked { window.cut(); return }

        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else { return }
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
        var data = ["app": name, "title": ""]
        if !PRIVATE_APPS.contains(name), AXIsProcessTrusted(), let w = focusedWindow(pid: app.processIdentifier) {
            data["title"] = windowTitle(w) ?? ""
            if GECKO.contains(name), let u = geckoURL(w) { data["url"] = u }
        }
        if data["url"] == nil, !PRIVATE_APPS.contains(name), let u = browser.url(for: name) { data["url"] = u }
        window.sample(data, at: now)
    }

    /// łączny czas aktywny dziś (do menu)
    func activeToday() -> TimeInterval {
        afk.events.filter { $0.data["status"] == "not-afk" }.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - pasek menu

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    let tracker = Tracker()
    var ticker: Timer?, flusher: Timer?
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let permLine = NSMenuItem(title: "", action: #selector(openAccessibility), keyEquivalent: "")
    let pause30 = NSMenuItem(title: "Wstrzymaj na 30 minut", action: #selector(pauseShort), keyEquivalent: "")
    let pauseDay = NSMenuItem(title: "Wstrzymaj do jutra", action: #selector(pauseToday), keyEquivalent: "")
    let resume = NSMenuItem(title: "Wznów śledzenie", action: #selector(resumeTracking), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        try? FileManager.default.createDirectory(at: EXPORTS, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: LOGS, withIntermediateDirectories: true)
        log("Start TimeTracker")

        // poproś o dostęp do Dostępności (tytuły okien); bez niego zapisujemy same nazwy aplikacji
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) { log("Brak uprawnień Dostępności — zapisuję tylko nazwy aplikacji") }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        statusLine.isEnabled = false
        for i in [statusLine, permLine, NSMenuItem.separator(), pause30, pauseDay, resume, NSMenuItem.separator()] { menu.addItem(i) }
        for (t, s) in [("Otwórz panel", #selector(openPanel)), ("Pokaż folder z danymi", #selector(openFolder))] {
            let i = NSMenuItem(title: t, action: s, keyEquivalent: ""); i.target = self; menu.addItem(i)
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Zakończ TimeTracker", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self
        menu.addItem(quitItem)
        for i in [permLine, pause30, pauseDay, resume] { i.target = self }
        item.menu = menu
        refreshIcon()

        tracker.tick()
        ticker = Timer.scheduledTimer(withTimeInterval: POLL, repeats: true) { [weak self] _ in self?.tracker.tick(); self?.refreshIcon() }
        flusher = Timer.scheduledTimer(withTimeInterval: FLUSH_EVERY, repeats: true) { [weak self] _ in self?.tracker.flush() }
        ticker?.tolerance = 1; flusher?.tolerance = 5

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tracker.window.cut(); self?.tracker.afk.cut(); self?.tracker.flush() }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tracker.tick() }
    }

    func applicationWillTerminate(_ n: Notification) { tracker.dirty = true; tracker.flush(); log("Stop TimeTracker") }

    func refreshIcon() {
        let name = tracker.paused ? "pause.circle" : "clock"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "TimeTracker")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = tracker.paused ? "TimeTracker: wstrzymany" : "TimeTracker: śledzenie aktywne"
    }

    func menuWillOpen(_ menu: NSMenu) {
        let m = Int(tracker.activeToday() / 60)
        let t = m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60)) min" : "\(m) min"
        if tracker.paused, let p = tracker.pausedUntil {
            let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(p) ? "HH:mm" : "EEEE HH:mm"; f.locale = Locale(identifier: "pl_PL")
            statusLine.title = "Wstrzymane do \(f.string(from: p)) · dziś \(t)"
        } else {
            statusLine.title = "Śledzenie aktywne · dziś \(t)"
        }
        let trusted = AXIsProcessTrusted()
        permLine.title = trusted ? "Tytuły okien: włączone" : "Tytuły okien: brak dostępu — kliknij, aby nadać"
        permLine.isEnabled = !trusted
        pause30.isHidden = tracker.paused; pauseDay.isHidden = tracker.paused; resume.isHidden = !tracker.paused
    }

    @objc func pauseShort() { tracker.pausedUntil = Date().addingTimeInterval(1800); tracker.flush(); refreshIcon(); log("Pauza 30 min") }
    @objc func pauseToday() {
        tracker.pausedUntil = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)); tracker.flush(); refreshIcon(); log("Pauza do jutra")
    }
    @objc func resumeTracking() { tracker.pausedUntil = nil; tracker.tick(); refreshIcon(); log("Wznowiono") }
    @objc func openPanel() { if let u = URL(string: PANEL_URL) { NSWorkspace.shared.open(u) } }
    @objc func openFolder() { NSWorkspace.shared.open(BASE) }
    @objc func openAccessibility() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
    }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
