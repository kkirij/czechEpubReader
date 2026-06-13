import Foundation

/// Ukládá poslední otevřenou knihu a pozici do UserDefaults.
/// URL knihy se ukládá jako security-scoped bookmark aby přístup fungoval i po restartu.
class BookmarkStore {

    static let shared = BookmarkStore()
    private init() {}

    private let keyBookmarkData = "lastBookBookmarkData"
    private let keyKindleLoc    = "lastKindleLoc"

    // MARK: - Uložení

    func save(url: URL, kindleLoc: Int) {
        // Ulož security-scoped bookmark
        do {
            let data = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: keyBookmarkData)
        } catch {
            print("BookmarkStore: nepodařilo se uložit bookmark: \(error)")
        }
        UserDefaults.standard.set(kindleLoc, forKey: keyKindleLoc)
    }

    func saveLocation(kindleLoc: Int) {
        UserDefaults.standard.set(kindleLoc, forKey: keyKindleLoc)
    }

    // MARK: - Načtení

    func loadURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: keyBookmarkData) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Bookmark je zastaralý — zkus ho obnovit
                if let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: keyBookmarkData)
                }
            }
            return url
        } catch {
            print("BookmarkStore: nepodařilo se obnovit URL: \(error)")
            return nil
        }
    }

    func loadKindleLoc() -> Int {
        return UserDefaults.standard.integer(forKey: keyKindleLoc)
    }

    // MARK: - Smazání

    func clear() {
        UserDefaults.standard.removeObject(forKey: keyBookmarkData)
        UserDefaults.standard.removeObject(forKey: keyKindleLoc)
    }
}
