import Foundation

/// Preprocessing textu před TTS syntézou.
/// Upravuje text aby zněl přirozeněji při čtení.
struct TTSPreprocessor {

    static func process(_ text: String) -> String {
        var t = text

        // 1. Rozviň zkratky na plná slova
        t = expandAbbreviations(t)

        // 2. Čísla na slova (základní)
        t = expandNumbers(t)

        // 3. Odstraň nebo nahraď problematické znaky
        t = cleanSymbols(t)

        // 4. Normalizuj mezery a interpunkci
        t = normalizeWhitespace(t)

        return t
    }

    // MARK: - Zkratky

    private static func expandAbbreviations(_ text: String) -> String {
        var t = text

        let abbreviations: [(String, String)] = [
            // Tituly
            ("Dr\\.", "doktor"),
            ("Mgr\\.", "magistr"),
            ("Ing\\.", "inženýr"),
            ("Prof\\.", "profesor"),
            ("MUDr\\.", "mudr"),
            ("JUDr\\.", "judr"),
            ("PhDr\\.", "phdr"),
            ("Bc\\.", "bakalář"),
            ("RNDr\\.", "rndr"),
            ("MVDr\\.", "mvdr"),
            ("Th\\.D\\.", "thd"),
            ("Ph\\.D\\.", "phd"),
            ("CSc\\.", "kandidát věd"),
            ("DrSc\\.", "doktor věd"),

            // Obecné zkratky
            ("atd\\.", "a tak dále"),
            ("apod\\.", "a podobně"),
            ("např\\.", "například"),
            ("tj\\.", "to jest"),
            ("tzn\\.", "to znamená"),
            ("tzv\\.", "takzvaný"),
            ("mj\\.", "mimo jiné"),
            ("cca\\.", "přibližně"),
            ("cca", "přibližně"),
            ("č\\.", "číslo"),
            ("str\\.", "strana"),
            ("obr\\.", "obrázek"),
            ("tab\\.", "tabulka"),
            ("kap\\.", "kapitola"),
            ("odd\\.", "oddíl"),
            ("s\\.", "strana"),
            ("r\\.", "roku"),
            ("sv\\.", "světec"),
            ("p\\.", "pan"),
            ("pí\\.", "paní"),
            ("sl\\.", "slečna"),
            ("Bc", "bakalář"),
            ("ul\\.", "ulice"),
            ("nám\\.", "náměstí"),

            // Měrné jednotky
            ("km/h", "kilometrů za hodinu"),
            ("m/s", "metrů za sekundu"),
            ("km", "kilometrů"),
            ("kg", "kilogramů"),
            ("mg", "miligramů"),
            ("ml", "mililitrů"),
            ("°C", "stupňů celsia"),
            ("°F", "stupňů fahrenheita"),
            ("kW", "kilowattů"),
            ("MW", "megawattů"),
            ("GB", "gigabajtů"),
            ("MB", "megabajtů"),
            ("TB", "terabajtů"),
        ]

        for (abbr, expansion) in abbreviations {
            if let regex = try? NSRegularExpression(pattern: "\\b\(abbr)", options: []) {
                t = regex.stringByReplacingMatches(
                    in: t,
                    range: NSRange(t.startIndex..., in: t),
                    withTemplate: expansion
                )
            }
        }
        return t
    }

    // MARK: - Čísla

    private static func expandNumbers(_ text: String) -> String {
        var t = text

        // Roky (1900-2099) — "v roce 1995" → přečte jako "tisíc devět set devadesát pět"
        // Piper/espeak tohle zvládne sám, jen pomůžeme s kontextem

        // Čísla s tečkou jako oddělovačem tisíců: 1.000 → 1000
        if let regex = try? NSRegularExpression(pattern: "(\\d)\\.(\\d{3})(?!\\d)", options: []) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: "$1$2"
            )
        }

        // Čísla s mezerou jako oddělovačem tisíců: 1 000 → 1000
        if let regex = try? NSRegularExpression(pattern: "(\\d) (\\d{3})(?!\\d)", options: []) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: "$1$2"
            )
        }

        // Ordinal čísla: 1. → první (jen na začátku výčtu)
        // Necháme espeak ať to zvládne sám

        return t
    }

    // MARK: - Symboly

    private static func cleanSymbols(_ text: String) -> String {
        var t = text

        let replacements: [(String, String)] = [
            // Závorky — přidej pauzu
            ("(", ", "),
            (")", ", "),

            // Pomlčky — přidej pauzu
            (" – ", ", "),
            (" — ", ", "),
            (" - ", ", "),

            // Lomítko
            ("/", " nebo "),

            // Procenta — espeak zvládne, ale jistota
            ("%", " procent"),

            // Znaky které způsobují problémy
            ("…", "."),
            ("„", ""),
            ("\"", ""),
            ("«", ""),
            ("»", ""),
            ("\u{00AD}", ""),  // soft hyphen
            ("\u{200B}", ""),  // zero width space
            ("\u{FEFF}", ""),  // BOM

            // Hvězdičky (markdown bold/italic)
            ("**", ""),
            ("*", ""),
            ("__", ""),
            ("_", " "),

            // URL — přeskoč
            // (řeší se níže regexem)
        ]

        for (symbol, replacement) in replacements {
            t = t.replacingOccurrences(of: symbol, with: replacement)
        }

        // Odstraň URL
        if let regex = try? NSRegularExpression(pattern: "https?://[^\\s]+", options: .caseInsensitive) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: "odkaz"
            )
        }

        // Odstraň HTML entity které proklouzly
        if let regex = try? NSRegularExpression(pattern: "&[a-z]+;", options: []) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: ""
            )
        }

        return t
    }

    // MARK: - Whitespace

    private static func normalizeWhitespace(_ text: String) -> String {
        var t = text

        // Více mezer → jedna
        if let regex = try? NSRegularExpression(pattern: "\\s{2,}", options: []) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: " "
            )
        }

        // Více teček → jedna
        if let regex = try? NSRegularExpression(pattern: "\\.{2,}", options: []) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: "."
            )
        }

        // Více čárek → jedna
        if let regex = try? NSRegularExpression(pattern: ",{2,}", options: []) {
            t = regex.stringByReplacingMatches(
                in: t,
                range: NSRange(t.startIndex..., in: t),
                withTemplate: ","
            )
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
