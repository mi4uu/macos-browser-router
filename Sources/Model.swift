import AppKit

// MARK: - Paths

enum Paths {
    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("BrowserRouter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let config = supportDir.appendingPathComponent("config.json")
    static let history = supportDir.appendingPathComponent("history.jsonl")
    static let rules = supportDir.appendingPathComponent("rules.txt")
}

// MARK: - Config

struct Config: Codable {
    /// Target id links are currently forwarded to (bundle id, optionally `#profile directory`).
    var defaultBrowser: String?
    /// Menu language: "auto" (follow macOS) or a code from `L10n.available`.
    var language = "auto"
    /// Target ids hidden from the menu — terminals and IDEs that register as http handlers.
    var hidden: [String] = []
    /// Days of history kept besides today; 0 keeps only today. `nil` keeps everything.
    var historyRetentionDays: Int?
    init() {}

    /// Decoded key by key: a config written by an older version is missing the newer
    /// keys, and the synthesised initialiser would reject the whole file over that.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultBrowser = try c.decodeIfPresent(String.self, forKey: .defaultBrowser)
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays)
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: Paths.config),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Paths.config, options: .atomic)
    }
}

// MARK: - Targets

/// A place a link can be sent to: an app, optionally pinned to one Chromium profile.
struct Target {
    let appURL: URL
    let bundleID: String
    let appName: String
    let profileDir: String?
    let profileName: String?

    var id: String { profileDir.map { "\(bundleID)#\($0)" } ?? bundleID }
    var name: String { profileName.map { "\(appName) — \($0)" } ?? appName }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }

    func open(_ url: URL) {
        guard let profileDir else {
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
            return
        }
        // Chromium only honours --profile-directory from a command line, so go through `open`.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", "-a", appURL.path, "--args",
                             "--profile-directory=\(profileDir)", url.absoluteString]
        try? process.run()
    }

    // MARK: Discovery

    /// Real browsers, listed before other registered http handlers (terminals, IDEs…).
    static let knownBrowsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.kagimacOS.Kagi",
        "app.zen-browser.zen", "com.apple.SafariTechnologyPreview", "org.chromium.Chromium",
        "com.duckduckgo.macos.browser", "net.waterfox.waterfox"
    ]

    /// Other browser pickers: routing to them would just bounce the URL around.
    static let excluded: Set<String> = [
        "com.browserosaurus", "com.sindresorhus.Velja", "com.choosyosx.Choosy",
        "net.kassett.finicky", "com.lowtechguys.Bumpr", "com.apple.SafariLauncher"
    ]

    /// Chromium-family support directories, where profile names live in `Local State`.
    static let chromiumSupportDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi"
    ]

    /// Every app that can handle https, plus one entry per Chromium profile.
    static func all() -> [Target] {
        let probe = URL(string: "https://example.com")!
        let ownID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .compactMap { url -> Target? in
                guard let bundle = Bundle(url: url),
                      let id = bundle.bundleIdentifier,
                      id != ownID,
                      !excluded.contains(id),
                      seen.insert(id).inserted else { return nil }
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                return Target(appURL: url, bundleID: id, appName: name,
                              profileDir: nil, profileName: nil)
            }

        let expanded = apps.flatMap { app -> [Target] in
            let profiles = chromiumProfiles(for: app)
            return profiles.isEmpty ? [app] : [app] + profiles
        }

        return expanded.sorted { a, b in
            let aKnown = knownBrowsers.contains(a.bundleID), bKnown = knownBrowsers.contains(b.bundleID)
            if aKnown != bKnown { return aKnown }
            if a.bundleID != b.bundleID {
                return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
            }
            // Plain app entry first, then its profiles by name.
            if (a.profileDir == nil) != (b.profileDir == nil) { return a.profileDir == nil }
            return (a.profileName ?? "").localizedCaseInsensitiveCompare(b.profileName ?? "") == .orderedAscending
        }
    }

    private static func chromiumProfiles(for app: Target) -> [Target] {
        guard let subpath = chromiumSupportDirs[app.bundleID] else { return [] }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let localState = base.appendingPathComponent(subpath).appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localState),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any],
              cache.count > 1 else { return [] }   // a single profile needs no extra entry

        return cache.compactMap { dir, info in
            let name = (info as? [String: Any])?["name"] as? String ?? dir
            return Target(appURL: app.appURL, bundleID: app.bundleID, appName: app.appName,
                          profileDir: dir, profileName: name)
        }
        .sorted { ($0.profileName ?? "").localizedCaseInsensitiveCompare($1.profileName ?? "") == .orderedAscending }
    }
}

// MARK: - History

struct HistoryEntry: Codable {
    let time: String
    let url: String
    let sourceApp: String
    let sourceBundleID: String
    let browser: String
    let rule: String?

    var date: Date? { ISO8601DateFormatter().date(from: time) }
}

enum History {
    static func append(url: String, source: NSRunningApplication?, browser: String, rule: String?) {
        let entry = HistoryEntry(
            time: ISO8601DateFormatter().string(from: Date()),
            url: url,
            sourceApp: source?.localizedName ?? "unknown",
            sourceBundleID: source?.bundleIdentifier ?? "unknown",
            browser: browser,
            rule: rule
        )
        guard let data = try? JSONEncoder().encode(entry) else { return }
        var line = data
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: Paths.history) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: Paths.history, options: .atomic)
        }
    }

    /// Drops entries from before the start of the day `retentionDays` ago, and any line that cannot be read.
    static func prune(retentionDays: Int, file: URL = Paths.history,
                      now: Date = Date(), calendar: Calendar = .current) {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let cutoff = calendar.date(byAdding: .day, value: -max(retentionDays, 0),
                                         to: calendar.startOfDay(for: now)) else { return }
        let decoder = JSONDecoder()
        let lines = text.split(separator: "\n")
        let kept = lines.filter { line in
            guard let entry = try? decoder.decode(HistoryEntry.self, from: Data(line.utf8)),
                  let date = entry.date else { return false }
            return date >= cutoff
        }
        guard kept.count != lines.count else { return }
        let output = kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
        try? output.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Last `limit` entries, newest first.
    static func recent(limit: Int) -> [HistoryEntry] {
        guard let text = try? String(contentsOf: Paths.history, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        return text.split(separator: "\n")
            .suffix(limit)
            .reversed()
            .compactMap { try? dec.decode(HistoryEntry.self, from: Data($0.utf8)) }
    }
}
