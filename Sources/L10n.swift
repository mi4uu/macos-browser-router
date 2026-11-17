import Foundation

/// Menu strings. English is the source language: keys are the English text, so only
/// translations need a table. `language` is "auto" (follow macOS) or a language code.
enum L10n {
    static var language = "auto"

    static var resolved: String {
        if language != "auto" { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = String(preferred.prefix(2))
        return tables[code] != nil ? code : "en"
    }

    /// Language code → display name, in the order they appear in the menu.
    static let available: [(code: String, name: String)] = [
        ("en", "English"),
        ("pl", "Polski")
    ]

    static let tables: [String: [String: String]] = [
        "pl": [
            "Default: %@": "Domyślna: %@",
            "none": "brak",
            "Opens in: %@": "Otwiera w: %@",
            "History": "Historia",
            "(empty)": "(pusto)",
            "Reveal history file…": "Pokaż plik historii…",
            "Keep history": "Przechowuj historię",
            "Forever": "Bez limitu",
            "Today only": "Tylko dzisiaj",
            "Today and yesterday": "Dzisiaj i wczoraj",
            "Last 7 days": "Ostatnie 7 dni",
            "Edit list": "Edytuj listę",
            "Checked items appear in the menu": "Zaznaczone są widoczne w menu",
            "Rules": "Reguły",
            "(no rules)": "(brak reguł)",
            "Edit rules…": "Edytuj reguły…",
            "no such browser": "nie ma takiej przeglądarki",
            "Rule: %@": "Reguła: %@",
            "Language": "Język",
            "Automatic (system)": "Automatycznie (systemowy)",
            "Set Browser Router as default browser…": "Ustaw Browser Router jako domyślną przeglądarkę…",
            "Open at login": "Uruchamiaj przy starcie systemu",
            "Quit": "Zakończ"
        ]
    ]
}

/// Translate `text`, falling back to the English original.
func L(_ text: String) -> String {
    tableForCurrentLanguage()?[text] ?? text
}

/// Translate and interpolate a single `%@` placeholder.
func L(_ text: String, _ argument: String) -> String {
    String(format: L(text), argument)
}

private func tableForCurrentLanguage() -> [String: String]? {
    L10n.tables[L10n.resolved]
}
