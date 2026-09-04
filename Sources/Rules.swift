import Foundation

/// One line of `rules.txt`: `pattern -> target`.
///
/// A pattern containing `://` is matched against the URL, otherwise against the name
/// or bundle id of the app the link came from. `*` matches anything; matching is
/// case-insensitive and the first matching rule wins.
struct Rule {
    let pattern: String
    let target: String
    let line: Int

    var matchesURL: Bool { pattern.contains("://") }

    func matches(url: URL, sourceName: String?, sourceBundleID: String?) -> Bool {
        if matchesURL { return Rule.glob(pattern, url.absoluteString) }
        return Rule.glob(pattern, sourceName ?? "") || Rule.glob(pattern, sourceBundleID ?? "")
    }

    /// `*` is the only metacharacter; everything else is literal.
    static func glob(_ pattern: String, _ text: String) -> Bool {
        let escaped = pattern
            .split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
        guard let regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive])
        else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}

enum Rules {
    static let template = """
    # Browser Router rules — one per line, first match wins:
    #
    #     pattern -> browser
    #
    # A pattern with :// is matched against the URL, without it against the app the
    # link came from. * matches anything. The browser is a name from the menu.
    #
    # Examples:
    #     https://github.com/* -> Google Chrome — Work
    #     https://*.slack.com/* -> Safari
    #     Slack -> Google Chrome — Work
    #     Mail -> Safari
    #
    # Links that match nothing go to the browser ticked in the menu.

    """

    static func load() -> [Rule] {
        guard let text = try? String(contentsOf: Paths.rules, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .compactMap { index, raw -> Rule? in
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"),
                      let arrow = line.range(of: "->") else { return nil }
                let pattern = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
                let target = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !pattern.isEmpty, !target.isEmpty else { return nil }
                return Rule(pattern: pattern, target: target, line: index + 1)
            }
    }

    static func createTemplateIfMissing() {
        guard !FileManager.default.fileExists(atPath: Paths.rules.path) else { return }
        try? template.write(to: Paths.rules, atomically: true, encoding: .utf8)
    }

    /// The first rule matching this link, together with the target it names.
    static func match(url: URL, sourceName: String?, sourceBundleID: String?,
                      in targets: [Target]) -> (rule: Rule, target: Target)? {
        for rule in load() where rule.matches(url: url, sourceName: sourceName, sourceBundleID: sourceBundleID) {
            if let target = resolve(rule.target, in: targets) { return (rule, target) }
        }
        return nil
    }

    /// Rules name a target the way the menu shows it, but nobody should have to type
    /// `Google Chrome — Michał` exactly: `chrome work`, `Chrome-Work` and `chrom work`
    /// all have to land on the same entry.
    static func resolve(_ name: String, in targets: [Target]) -> Target? {
        let wanted = normalize(name)
        guard !wanted.isEmpty else { return nil }

        if let hit = targets.first(where: { normalize($0.id) == wanted })
            ?? targets.first(where: { normalize($0.name) == wanted })
            ?? targets.first(where: { normalize($0.appName) == wanted }) { return hit }

        // Every word of the rule appears in the target: "chrome work" → "Google Chrome — Work".
        let words = wanted.split(separator: " ").map(String.init)
        if let hit = targets.first(where: { target in
            let haystack = normalize(target.name)
            return words.allSatisfy { haystack.contains($0) }
        }) { return hit }

        if let hit = targets.first(where: { normalize($0.name).contains(wanted) }) { return hit }

        // Last resort: typo tolerance, best match wins and only if it is close enough.
        let scored = targets
            .map { ($0, similarity(wanted, normalize($0.name))) }
            .max { $0.1 < $1.1 }
        if let (target, score) = scored, score >= 0.7 { return target }
        return nil
    }

    /// Lowercased, without diacritics or punctuation, single-spaced. Latin-ASCII also
    /// handles letters folding alone will not touch, such as the ł in "Michał".
    static func normalize(_ text: String) -> String {
        let latin = text.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? text
        let folded = latin.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cleaned = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// 1.0 for identical strings, 0.0 for entirely different ones.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let distance = Double(levenshtein(Array(a), Array(b)))
        return 1 - distance / Double(max(a.count, b.count))
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : min(previous[j - 1], previous[j], current[j - 1]) + 1
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
