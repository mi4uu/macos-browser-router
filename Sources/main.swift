import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var config = Config.load()
    var targets: [Target] = []

    /// Frontmost app that is not us — the app a URL request most likely came from.
    var lastForeignApp: NSRunningApplication?
    var historyPruneTimer: Timer?

    static let retentionOptions: [(title: String, days: Int?)] = [
        ("Forever", nil),
        ("Today only", 0),
        ("Today and yesterday", 1),
        ("Last 7 days", 6)
    ]

    func schedulePruning() {
        historyPruneTimer?.invalidate()
        historyPruneTimer = nil
        guard let days = config.historyRetentionDays else { return }
        History.prune(retentionDays: days)
        guard let nextMidnight = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) else { return }
        let timer = Timer(fire: nextMidnight, interval: 0, repeats: false) { [weak self] _ in
            self?.schedulePruning()
        }
        RunLoop.main.add(timer, forMode: .common)
        historyPruneTimer = timer
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.language = config.language
        schedulePruning()
        Rules.createTemplateIfMissing()
        targets = Target.all()
        if config.defaultBrowser == nil { config.defaultBrowser = visibleTargets().first?.id; config.save() }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        lastForeignApp = NSWorkspace.shared.frontmostApplication

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusIcon()
    }

    @objc func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        lastForeignApp = app
    }

    // MARK: - Routing

    func application(_ application: NSApplication, open urls: [URL]) {
        let source = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier ? lastForeignApp : $0
        } ?? lastForeignApp

        for url in urls { route(url, from: source) }
    }

    func route(_ url: URL, from source: NSRunningApplication?) {
        if targets.isEmpty { targets = Target.all() }
        let hit = Rules.match(url: url, sourceName: source?.localizedName,
                              sourceBundleID: source?.bundleIdentifier, in: targets)
        guard let target = hit?.target ?? currentBrowser() else {
            NSSound.beep()
            return
        }
        target.open(url)
        History.append(url: url.absoluteString, source: source, browser: target.name,
                       rule: hit?.rule.pattern)
    }

    func visibleTargets() -> [Target] {
        let hidden = Set(config.hidden)
        let visible = targets.filter { !hidden.contains($0.id) }
        return visible.isEmpty ? targets : visible
    }

    func currentBrowser() -> Target? {
        // A cold start triggered by a URL calls this before applicationDidFinishLaunching,
        // so the list has to be able to populate itself here.
        if targets.isEmpty { targets = Target.all() }
        return targets.first { $0.id == config.defaultBrowser } ?? visibleTargets().first
    }

    // MARK: - Menu

    func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        if let browser = currentBrowser() {
            let icon = browser.icon
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.toolTip = L("Opens in: %@", browser.name)
        } else {
            button.title = "?"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        config = Config.load()
        L10n.language = config.language
        schedulePruning()
        targets = Target.all()
        menu.removeAllItems()

        let current = currentBrowser()
        let header = NSMenuItem(title: L("Default: %@", current?.name ?? L("none")), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for (i, browser) in visibleTargets().enumerated() {
            let item = NSMenuItem(title: browser.name, action: #selector(selectBrowser(_:)),
                                  keyEquivalent: i < 9 ? String(i + 1) : "")
            item.target = self
            item.representedObject = browser.id
            item.state = browser.id == current?.id ? .on : .off
            let icon = browser.icon
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let historyItem = NSMenuItem(title: L("History"), action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        let entries = History.recent(limit: 20)
        if entries.isEmpty {
            let empty = NSMenuItem(title: L("(empty)"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            for entry in entries {
                let time = entry.date.map { fmt.string(from: $0) } ?? "--:--"
                let parsed = URL(string: entry.url)
                let what = parsed?.host ?? parsed?.lastPathComponent ?? entry.url
                let mark = entry.rule.map { _ in "  ⚙" } ?? ""
                let item = NSMenuItem(title: "\(time)   \(entry.sourceApp) → \(what) → \(entry.browser)\(mark)",
                                      action: #selector(reopen(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.url
                item.toolTip = entry.rule.map { L("Rule: %@", $0) + "\n" + entry.url } ?? entry.url
                historyMenu.addItem(item)
            }
        }
        historyMenu.addItem(.separator())
        let reveal = NSMenuItem(title: L("Reveal history file…"), action: #selector(revealHistory), keyEquivalent: "")
        reveal.target = self
        historyMenu.addItem(reveal)

        let keepItem = NSMenuItem(title: L("Keep history"), action: nil, keyEquivalent: "")
        let keepMenu = NSMenu()
        for option in AppDelegate.retentionOptions {
            let item = NSMenuItem(title: L(option.title), action: #selector(selectRetention(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.days.map { NSNumber(value: $0) } ?? NSNull()
            item.state = config.historyRetentionDays == option.days ? .on : .off
            keepMenu.addItem(item)
        }
        keepItem.submenu = keepMenu
        historyMenu.addItem(keepItem)
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        let editItem = NSMenuItem(title: L("Edit list"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu()
        let hidden = Set(config.hidden)
        for target in targets {
            let item = NSMenuItem(title: target.name, action: #selector(toggleHidden(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = target.id
            item.state = hidden.contains(target.id) ? .off : .on
            let icon = target.icon
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            editMenu.addItem(item)
        }
        editMenu.addItem(.separator())
        let hint = NSMenuItem(title: L("Checked items appear in the menu"), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        editMenu.addItem(hint)
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let rulesItem = NSMenuItem(title: L("Rules"), action: nil, keyEquivalent: "")
        let rulesMenu = NSMenu()
        let rules = Rules.load()
        if rules.isEmpty {
            let empty = NSMenuItem(title: L("(no rules)"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            rulesMenu.addItem(empty)
        } else {
            for rule in rules {
                // Show what the rule actually resolves to, so a typo is visible here
                // rather than only in the history after a link went somewhere odd.
                let resolved = Rules.resolve(rule.target, in: targets)
                let suffix: String
                switch resolved?.name {
                case nil: suffix = "   ⚠ " + L("no such browser")
                case rule.target: suffix = ""
                case let actual?: suffix = "   (\(actual))"
                }
                let item = NSMenuItem(title: "\(rule.pattern)  →  \(rule.target)\(suffix)",
                                      action: nil, keyEquivalent: "")
                item.isEnabled = false
                rulesMenu.addItem(item)
            }
        }
        rulesMenu.addItem(.separator())
        let editRules = NSMenuItem(title: L("Edit rules…"), action: #selector(editRules), keyEquivalent: "")
        editRules.target = self
        rulesMenu.addItem(editRules)
        rulesItem.submenu = rulesMenu
        menu.addItem(rulesItem)

        menu.addItem(.separator())
        let makeDefault = NSMenuItem(title: L("Set Browser Router as default browser…"),
                                     action: #selector(becomeSystemDefault), keyEquivalent: "")
        makeDefault.target = self
        menu.addItem(makeDefault)

        let langItem = NSMenuItem(title: L("Language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for (code, name) in [("auto", L("Automatic (system)"))] + L10n.available {
            let item = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = config.language == code ? .on : .off
            langMenu.addItem(item)
            if code == "auto" { langMenu.addItem(.separator()) }
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        let login = NSMenuItem(title: L("Open at login"),
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: L("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc func selectBrowser(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        config.defaultBrowser = id
        config.save()
        refreshStatusIcon()
    }

    @objc func toggleHidden(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if let index = config.hidden.firstIndex(of: id) {
            config.hidden.remove(at: index)
        } else {
            config.hidden.append(id)
            // Never leave the current target hidden and unreachable.
            if config.defaultBrowser == id { config.defaultBrowser = visibleTargets().first?.id }
        }
        config.save()
        refreshStatusIcon()
    }

    @objc func selectRetention(_ sender: NSMenuItem) {
        config.historyRetentionDays = (sender.representedObject as? NSNumber)?.intValue
        config.save()
        schedulePruning()
    }

    @objc func reopen(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String, let url = URL(string: string) else { return }
        route(url, from: nil)
    }

    @objc func editRules() {
        Rules.createTemplateIfMissing()
        NSWorkspace.shared.open(Paths.rules)
    }

    @objc func revealHistory() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.history])
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        config.language = code
        config.save()
        L10n.language = code
        refreshStatusIcon()
    }

    @objc func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc func becomeSystemDefault() {
        let me = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: scheme) { _ in }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
