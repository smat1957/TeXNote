import Foundation

enum iOSPackageBookmarkOptions {
    static let creation: URL.BookmarkCreationOptions = []
    static let resolution: URL.BookmarkResolutionOptions = []
}

enum PackageBookmarkStore {
    private static let bookmarkKey = "lastPackageBookmark"
    private static let legacyPathKey = "lastPackagePath"

    static func save(_ packageURL: URL) throws {
        let data = try packageURL.bookmarkData(
            options: PlatformPackageBookmarkOptions.creation,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: legacyPathKey)
    }

    static func resolve() throws -> URL? {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: PlatformPackageBookmarkOptions.resolution,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                try save(url)
            }
            return url
        }

        guard let path = UserDefaults.standard.string(
            forKey: legacyPathKey
        ) else {
            return nil
        }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: legacyPathKey)
    }
}
