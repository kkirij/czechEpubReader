import Foundation

/// Ukládá poslední otevřenou knihu a pozici do UserDefaults.
class BookmarkStore {

    static let shared = BookmarkStore()
    private init() {}

    private let keyBookmarkData = "lastBookBookmarkData"
    private let keyKindleLoc    = "lastKindleLoc"
    private let keyBookPath     = "lastBookPath"      // záloha — plain cesta

    // MARK: - Uložení

    func save(url: URL, kindleLoc: Int) {
        // Ulož plain cestu jako zálohu
        UserDefaults.standard.set(url.path, forKey: keyBookPath)
        UserDefaults.standard.set(kindleLoc, forKey: keyKindleLoc)

        // Ulož security-scoped bookmark
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: keyBookmarkData)
            UserDefaults.standard.synchronize()
            print("BookmarkStore: uloženo — \(url.lastPathComponent) LOC \(kindleLoc)")
        } catch {
            print("BookmarkStore: nepodařilo se uložit bookmark: \(error)")
        }
    }

    func saveLocation(kindleLoc: Int) {
        UserDefaults.standard.set(kindleLoc, forKey: keyKindleLoc)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Načtení

    func loadURL() -> URL? {
        // Zkus nejdřív bookmark
        if let url = loadFromBookmark() {
            return url
        }
        // Fallback na plain cestu
        if let path = UserDefaults.standard.string(forKey: keyBookPath) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                print("BookmarkStore: načteno z plain cesty — \(url.lastPathComponent)")
                return url
            }
        }
        print("BookmarkStore: žádná uložená kniha nenalezena")
        return nil
    }

    private func loadFromBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: keyBookmarkData) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard FileManager.default.fileExists(atPath: url.path) else {
                print("BookmarkStore: soubor z bookmarku neexistuje")
                return nil
            }

            if isStale {
                print("BookmarkStore: bookmark je zastaralý, obnovovám")
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let fresh = try? url.bookmarkData(
                    options: [.minimalBookmark],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(fresh, forKey: keyBookmarkData)
                    UserDefaults.standard.synchronize()
                }
            }

            print("BookmarkStore: načteno z bookmarku — \(url.lastPathComponent)")
            return url
        } catch {
            print("BookmarkStore: chyba bookmarku: \(error)")
            return nil
        }
    }

    func loadKindleLoc() -> Int {
        let loc = UserDefaults.standard.integer(forKey: keyKindleLoc)
        print("BookmarkStore: načtena pozice LOC \(loc)")
        return loc
    }

    // MARK: - Smazání

    func clear() {
        UserDefaults.standard.removeObject(forKey: keyBookmarkData)
        UserDefaults.standard.removeObject(forKey: keyKindleLoc)
        UserDefaults.standard.removeObject(forKey: keyBookPath)
        UserDefaults.standard.synchronize()
    }
}
