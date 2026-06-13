import Foundation
import Combine
import UIKit
import EPUBKit

// MARK: - EPUB Chapter Model
struct EPUBChapter: Identifiable {
    let id: Int
    let title: String
    let content: String
    let rawHTML: String
    let characterOffset: Int
}

// MARK: - EPUB Manager
class EPUBManager: ObservableObject {

    @Published var bookTitle: String = ""
    @Published var chapters: [EPUBChapter] = []
    @Published var isLoaded: Bool = false
    @Published var errorMessage: String? = nil

    private(set) var fullText: String = ""

    // MARK: - Load

    func load(url: URL) {
        errorMessage = nil
        isLoaded = false
        chapters = []
        fullText = ""

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Nelze přistoupit k souboru (chybí oprávnění)."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let document = EPUBDocument(url: url) else {
            errorMessage = "Nepodařilo se načíst EPUB soubor."
            return
        }

        bookTitle = document.title ?? url.deletingPathExtension().lastPathComponent

        var parsedChapters: [EPUBChapter] = []
        var globalOffset = 0
        var combinedText = ""

        let spine = document.spine
        let manifest = document.manifest

        for (index, spineItem) in spine.items.enumerated() {
            guard let manifestItem = manifest.items[spineItem.idref] else { continue }

            // EPUBKit ukládá path jako String (relativní vůči adresáři EPUB)
            let path = manifestItem.path
            guard !path.isEmpty else { continue }

            // Sestavení absolutní URL — EPUBKit rozbaluje EPUB do temp adresáře
            // document.contentDirectory obsahuje cestu k rozbalenému obsahu
            let chapterURL: URL
            if path.hasPrefix("/") {
                chapterURL = URL(fileURLWithPath: path)
            } else {
                chapterURL = document.contentDirectory.appendingPathComponent(path)
            }

            let raw: String
            do {
                raw = try String(contentsOf: chapterURL, encoding: .utf8)
            } catch {
                raw = ""
            }

            let plain = htmlToPlainText(raw)
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let title = inferTitle(html: raw, index: index + 1)

            let chapter = EPUBChapter(
                id: index,
                title: title,
                content: plain,
                rawHTML: raw,
                characterOffset: globalOffset
            )
            parsedChapters.append(chapter)

            combinedText += plain + "\n"
            globalOffset += plain.count + 1
        }

        chapters = parsedChapters
        fullText = combinedText
        isLoaded = true
    }

    // MARK: - Helpers

    func text(from position: Int) -> String {
        guard position >= 0, position < fullText.count else { return fullText }
        let startIndex = fullText.index(fullText.startIndex, offsetBy: position)
        return String(fullText[startIndex...])
    }

    func chapter(at position: Int) -> EPUBChapter? {
        chapters.last(where: { $0.characterOffset <= position })
    }

    // MARK: - Kindle LOC konverze
    //
    // Kindle LOC konstanta: 1 LOC ≈ 128 bytů (původní Kindle)
    // Moderní Kindle může používat jiné hodnoty.
    // Pokud se pozice neshoduje, uprav tuto konstantu.
    var locFactor: Int = 115

    /// Kindle LOC → absolutní pozice v textu (počet znaků)
    func charsFromKindleLoc(_ loc: Int) -> Int {
        let pos = loc * locFactor
        return min(pos, max(0, fullText.count - 1))
    }

    /// Absolutní pozice v textu → Kindle LOC
    func kindleLocFromChars(_ chars: Int) -> Int {
        return chars / locFactor
    }

    /// Celkový počet Kindle LOC v knize
    var totalKindleLoc: Int {
        return fullText.count / locFactor
    }

    /// Vypočítá LOC faktor porovnáním s known Kindle hodnotou.
    /// Zavolej s LOC a odpovídající pozicí v textu pro kalibraci.
    func calibratedLocFactor(kindleLoc: Int, charPosition: Int) -> Int {
        guard kindleLoc > 0 else { return locFactor }
        return charPosition / kindleLoc
    }



    private func htmlToPlainText(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        // Fallback — odstranění HTML tagů regexem
        return html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferTitle(html: String, index: Int) -> String {
        for tag in ["<title>", "<h1>", "<h2>"] {
            let closeTag = tag.replacingOccurrences(of: "<", with: "</")
            if let open = html.range(of: tag, options: .caseInsensitive),
               let close = html.range(of: closeTag, options: [.caseInsensitive, .backwards]) {
                let content = String(html[open.upperBound..<close.lowerBound])
                let stripped = content
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty { return stripped }
            }
        }
        return "Kapitola \(index)"
    }
}
