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
    let kindleLocOffset: Int    // přesný LOC offset pro tuto kapitolu
}

// MARK: - LOC Segment
// Každý spine soubor má vlastní LOC rozsah vypočítaný z poměru znaků
struct LOCSegment {
    let charStart: Int
    let charEnd: Int
    let locStart: Int
    let locEnd: Int

    /// Přepočítá znaky na LOC v rámci segmentu (lineární interpolace)
    func locFromChars(_ chars: Int) -> Int {
        guard charEnd > charStart, locEnd > locStart else { return locStart }
        let ratio = Double(chars - charStart) / Double(charEnd - charStart)
        return locStart + Int(ratio * Double(locEnd - locStart))
    }

    /// Přepočítá LOC na znaky v rámci segmentu
    func charsFromLoc(_ loc: Int) -> Int {
        guard locEnd > locStart, charEnd > charStart else { return charStart }
        let ratio = Double(loc - locStart) / Double(locEnd - locStart)
        return charStart + Int(ratio * Double(charEnd - charStart))
    }
}

// MARK: - EPUB Manager
class EPUBManager: ObservableObject {

    @Published var bookTitle: String = ""
    @Published var chapters: [EPUBChapter] = []
    @Published var isLoaded: Bool = false
    @Published var errorMessage: String? = nil

    private(set) var fullText: String = ""

    // LOC segmenty pro přesné mapování
    private(set) var locSegments: [LOCSegment] = []

    // Globální LOC faktor jako fallback
    var locFactor: Int = 115

    // MARK: - Load

    func load(url: URL) {
        errorMessage = nil
        isLoaded = false
        chapters = []
        fullText = ""
        locSegments = []

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

        // Načti spine soubory a spočítej znaky
        var spineContents: [(path: String, plain: String, raw: String)] = []

        for spineItem in document.spine.items {
            guard let manifestItem = document.manifest.items[spineItem.idref] else { continue }
            let path = manifestItem.path
            guard !path.isEmpty else { continue }

            let chapterURL: URL
            if path.hasPrefix("/") {
                chapterURL = URL(fileURLWithPath: path)
            } else {
                chapterURL = document.contentDirectory.appendingPathComponent(path)
            }

            let raw = (try? String(contentsOf: chapterURL, encoding: .utf8)) ?? ""
            let plain = htmlToPlainText(raw)
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            spineContents.append((path: path, plain: plain, raw: raw))
        }

        // Celkový počet znaků
        let totalChars = spineContents.reduce(0) { $0 + $1.plain.count + 1 }

        // Spočítej LOC segmenty — každý soubor dostane LOC úměrný počtu znaků
        let totalLoc = totalChars / locFactor
        var charOffset = 0
        var locOffset = 0
        var segments: [LOCSegment] = []

        for item in spineContents {
            let itemChars = item.plain.count + 1
            let itemLoc = max(1, Int(Double(itemChars) / Double(totalChars) * Double(totalLoc)))
            segments.append(LOCSegment(
                charStart: charOffset,
                charEnd: charOffset + itemChars,
                locStart: locOffset,
                locEnd: locOffset + itemLoc
            ))
            charOffset += itemChars
            locOffset += itemLoc
        }
        locSegments = segments

        // Sestav kapitoly s přesnými LOC offsety
        var parsedChapters: [EPUBChapter] = []
        var globalOffset = 0
        var combinedText = ""

        for (index, item) in spineContents.enumerated() {
            let locOff = segments[safe: index]?.locStart ?? (globalOffset / locFactor)
            let title = inferTitle(html: item.raw, index: index + 1)

            let chapter = EPUBChapter(
                id: index,
                title: title,
                content: item.plain,
                rawHTML: item.raw,
                characterOffset: globalOffset,
                kindleLocOffset: locOff
            )
            parsedChapters.append(chapter)
            combinedText += item.plain + "\n"
            globalOffset += item.plain.count + 1
        }

        chapters = parsedChapters
        fullText = combinedText
        isLoaded = true

        print("EPUBManager: načteno \(chapters.count) kapitol, \(fullText.count) znaků, \(totalKindleLoc) LOC")
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

    // MARK: - Přesná LOC konverze přes segmenty

    /// Kindle LOC → absolutní pozice v textu
    func charsFromKindleLoc(_ loc: Int) -> Int {
        // Najdi segment který obsahuje tento LOC
        if let segment = locSegments.first(where: { $0.locStart <= loc && loc <= $0.locEnd }) {
            return min(segment.charsFromLoc(loc), max(0, fullText.count - 1))
        }
        // Fallback — globální faktor
        return min(loc * locFactor, max(0, fullText.count - 1))
    }

    /// Absolutní pozice v textu → Kindle LOC
    func kindleLocFromChars(_ chars: Int) -> Int {
        // Najdi segment který obsahuje tuto pozici
        if let segment = locSegments.first(where: { $0.charStart <= chars && chars <= $0.charEnd }) {
            return segment.locFromChars(chars)
        }
        // Fallback — globální faktor
        return chars / locFactor
    }

    /// Celkový počet Kindle LOC v knize
    var totalKindleLoc: Int {
        return locSegments.last?.locEnd ?? (fullText.count / locFactor)
    }

    /// Kalibruj LOC faktor — přepočítá segmenty s novým faktorem
    func calibratedLocFactor(kindleLoc: Int, charPosition: Int) -> Int {
        guard kindleLoc > 0 else { return locFactor }
        return charPosition / kindleLoc
    }

    /// Aplikuj nový globální LOC faktor a přepočítej segmenty
    func applyLocFactor(_ factor: Int) {
        locFactor = factor
        // Přepočítej segmenty s novým faktorem
        guard !locSegments.isEmpty else { return }
        let totalChars = fullText.count
        let totalLoc = totalChars / factor
        var updatedSegments: [LOCSegment] = []
        for seg in locSegments {
            let segChars = seg.charEnd - seg.charStart
            let segLoc = max(1, Int(Double(segChars) / Double(totalChars) * Double(totalLoc)))
            let prevEnd = updatedSegments.last?.locEnd ?? 0
            updatedSegments.append(LOCSegment(
                charStart: seg.charStart,
                charEnd: seg.charEnd,
                locStart: prevEnd,
                locEnd: prevEnd + segLoc
            ))
        }
        locSegments = updatedSegments
        print("EPUBManager: přepočítány segmenty s faktorem \(factor), celkem \(totalKindleLoc) LOC")
    }

    // MARK: - Page konverze (interní, pro zpětnou kompatibilitu)
    private let locsPerPage: Double = 16.6

    func charsFromPage(_ page: Int) -> Int {
        let loc = Int(Double(page) * locsPerPage)
        return charsFromKindleLoc(loc)
    }

    func pageFromChars(_ chars: Int) -> Int {
        let loc = kindleLocFromChars(chars)
        return max(1, Int(Double(loc) / locsPerPage))
    }

    var totalPages: Int {
        return max(1, Int(Double(totalKindleLoc) / locsPerPage))
    }

    // MARK: - HTML → plain text

    private func htmlToPlainText(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferTitle(html: String, index: Int) -> String {
        // Hledej standardní nadpisy h1-h3
        for tag in ["<h1", "<h2", "<h3"] {
            if let open = html.range(of: tag, options: .caseInsensitive),
               let tagEnd = html.range(of: ">", range: open.upperBound..<html.endIndex) {
                let closeTag = "</" + tag.dropFirst()
                if let close = html.range(of: closeTag, options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex) {
                    let content = String(html[tagEnd.upperBound..<close.lowerBound])
                    let stripped = content
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stripped.isEmpty && stripped.count < 100 && stripped.count > 2 {
                        return stripped
                    }
                }
            }
        }
        // Fallback — jednoduché pořadí
        return "Kapitola \(index)"
    }
}

// MARK: - Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
