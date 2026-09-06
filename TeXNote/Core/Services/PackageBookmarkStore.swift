import Foundation

enum iOSPackageBookmarkOptions {
    static let creation: URL.BookmarkCreationOptions = []
    static let resolution: URL.BookmarkResolutionOptions = []
}

enum PackageBookmarkStore {
    private static let bookmarkKey = "lastPackageBookmark"
    private static let relativePackageNameKey = "lastPackageRelativeName"
    private static let legacyPathKey = "lastPackagePath"

    static func save(_ packageURL: URL) throws {
        try saveBookmark(for: packageURL, relativePackageName: nil)
    }

    static func save(packageURL: URL, accessRootURL: URL) throws {
        let package = packageURL.standardizedFileURL
        let accessRoot = accessRootURL.standardizedFileURL
        guard package.deletingLastPathComponent().path == accessRoot.path else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try saveBookmark(
            for: accessRoot,
            relativePackageName: package.lastPathComponent
        )
    }

    private static func saveBookmark(
        for accessURL: URL,
        relativePackageName: String?
    ) throws {
        let data = try accessURL.bookmarkData(
            options: PlatformPackageBookmarkOptions.creation,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        if let relativePackageName {
            UserDefaults.standard.set(
                relativePackageName,
                forKey: relativePackageNameKey
            )
        } else {
            UserDefaults.standard.removeObject(forKey: relativePackageNameKey)
        }
        UserDefaults.standard.removeObject(forKey: legacyPathKey)
    }

    static func resolve() throws -> ResolvedPackageBookmark? {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: PlatformPackageBookmarkOptions.resolution,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let relativeName = UserDefaults.standard.string(
                forKey: relativePackageNameKey
            )
            if isStale {
                try saveBookmark(
                    for: url,
                    relativePackageName: relativeName
                )
            }
            guard let relativeName else {
                return ResolvedPackageBookmark(
                    packageURL: url,
                    accessRootURL: url
                )
            }
            guard !relativeName.isEmpty,
                  relativeName == URL(filePath: relativeName).lastPathComponent,
                  relativeName != ".",
                  relativeName != ".." else {
                clear()
                throw CocoaError(.fileReadInvalidFileName)
            }
            return ResolvedPackageBookmark(
                packageURL: url.appending(
                    path: relativeName,
                    directoryHint: .isDirectory
                ),
                accessRootURL: url
            )
        }

        guard let path = UserDefaults.standard.string(
            forKey: legacyPathKey
        ) else {
            return nil
        }
        let url = URL(filePath: path, directoryHint: .isDirectory)
        return ResolvedPackageBookmark(
            packageURL: url,
            accessRootURL: url
        )
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: relativePackageNameKey)
        UserDefaults.standard.removeObject(forKey: legacyPathKey)
    }
}

struct ResolvedPackageBookmark {
    let packageURL: URL
    let accessRootURL: URL
}
