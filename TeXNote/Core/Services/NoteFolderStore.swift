import Foundation

enum NotePackageNaming {
    static let pathExtension = "texnote"

    static func folderName(for noteName: String) -> String {
        let suffix = ".\(pathExtension)"
        return noteName.lowercased().hasSuffix(suffix)
            ? noteName
            : noteName + suffix
    }

    static func noteName(for folderURL: URL) -> String {
        let folderName = folderURL.lastPathComponent
        return folderURL.pathExtension.lowercased() == pathExtension
            ? folderURL.deletingPathExtension().lastPathComponent
            : folderName
    }

    static func matches(folderURL: URL, noteName: String) -> Bool {
        self.noteName(for: folderURL) == noteName
    }
}

enum NoteFolderError: LocalizedError {
    case invalidName
    case missingJSON
    case unsupportedFormat(Int)
    case noteMustBeSavedBeforeAddingResources
    case duplicateResourceName(String)
    case missingResource(String)
    case missingPDF(String)
    case invalidStoredPath(String)
    case pdfWriteFailed(path: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "ノート名を入力してください。記号「/」と「:」は使用できません。"
        case .missingJSON:
            "選択したフォルダにnote.jsonがありません。"
        case .unsupportedFormat(let version):
            "このノートのJSON形式（バージョン\(version)）には対応していません。"
        case .noteMustBeSavedBeforeAddingResources:
            "画像またはファイルを追加する前に、ノートを保存してください。"
        case .duplicateResourceName(let name):
            "同名の画像またはファイルが複数選択されています:\n\(name)"
        case .missingResource(let path):
            "保存に必要な画像またはファイルが見つかりません:\n\(path)"
        case .missingPDF(let path):
            "保存に必要なPDFが見つかりません:\n\(path)"
        case .invalidStoredPath(let path):
            "format 8のCard PATHとして無効です:\n\(path)"
        case .pdfWriteFailed(let path, let underlying):
            "CardのPDFを保存できませんでした:\n\(path)\n\(underlying)"
        }
    }
}

enum CardResourceDirectory: Equatable {
    case pictures
    case files

    func relativePath(for card: TeXCard) -> String {
        switch self {
        case .pictures:
            card.picturesRelativePath
        case .files:
            card.filesRelativePath
        }
    }

    var folderName: String {
        switch self {
        case .pictures: "pics"
        case .files: "files"
        }
    }
}

enum NoteFolderStore {
    struct SaveResult: Sendable {
        let folderURL: URL
        let document: NoteDocument
    }

    static func save(
        document: NoteDocument,
        noteName: String,
        parentFolder: URL,
        sourceNoteFolder: URL? = nil,
        destinationFolderName: String? = nil
    ) throws -> SaveResult {
        let name = noteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":") else {
            throw NoteFolderError.invalidName
        }

        let manager = FileManager.default
        let noteFolder = parentFolder.appending(
            path: destinationFolderName ?? name,
            directoryHint: .isDirectory
        )
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: noteFolder.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            throw CocoaError(.fileWriteFileExists)
        }
        var snapshot = document
        snapshot.formatVersion = 8
        snapshot.name = name
        let sourceFolder = sourceNoteFolder ?? noteFolder
        let cardsFolder = noteFolder.appending(
            path: "Cards",
            directoryHint: .isDirectory
        )
        var directories = [noteFolder, cardsFolder]
        var writes: [AtomicFileWrite] = []

        for index in snapshot.cards.indices {
            let sourceCard = document.cards[index]
            let cardFolder = cardsFolder.appending(
                path: sourceCard.id.uuidString,
                directoryHint: .isDirectory
            )
            directories.append(cardFolder)
            for kind in [CardResourceDirectory.pictures, .files] {
                let folderPath = canonicalResourceFolderPath(
                    for: sourceCard,
                    kind: kind
                )
                let assets = try resourcesForSaving(
                    for: sourceCard,
                    kind: kind,
                    from: sourceFolder
                )
                let destinationFolder = try packageDestinationURL(
                    for: folderPath,
                    in: noteFolder,
                    directoryHint: .isDirectory
                )
                directories.append(destinationFolder)
                var savedPaths: [String] = []
                for asset in assets {
                    let destinationPath = "\(folderPath)/\(asset.fileName)"
                    let destinationURL = try packageDestinationURL(
                        for: destinationPath,
                        in: noteFolder
                    )
                    writes.append(
                        AtomicFileWrite(
                            url: destinationURL,
                            data: asset.data
                        )
                    )
                    savedPaths.append(destinationPath)
                }
                switch kind {
                case .pictures:
                    snapshot.cards[index].picturesRelativePath = folderPath
                    snapshot.cards[index].pictureRelativePaths = savedPaths
                case .files:
                    snapshot.cards[index].filesRelativePath = folderPath
                    snapshot.cards[index].fileRelativePaths = savedPaths
                }
            }

            if let oldPDFPath = sourceCard.pdfRelativePath {
                let pdfPath = canonicalPDFRelativePath(for: sourceCard)
                let data: Data
                if let currentData = sourceCard.pdfData {
                    data = currentData
                } else {
                    let sourcePDF = try safeURL(
                        for: oldPDFPath,
                        in: sourceFolder
                    )
                    guard let storedData = try? Data(contentsOf: sourcePDF) else {
                        throw NoteFolderError.missingPDF(oldPDFPath)
                    }
                    data = storedData
                }
                let pdfURL = try packageDestinationURL(
                    for: pdfPath,
                    in: noteFolder
                )
                writes.append(AtomicFileWrite(url: pdfURL, data: data))
                snapshot.cards[index].pdfRelativePath = pdfPath
            }
            snapshot.cards[index].pdfNeedsSaving = false
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(snapshot)
        writes.append(
            AtomicFileWrite(
                url: noteFolder.appending(path: "note.json"),
                data: json
            )
        )

        let existingItems = try managedItems(in: cardsFolder)
        let desiredFilePaths = Set(
            writes.map { $0.url.standardizedFileURL.path }
        )
        let desiredDirectoryPaths = Set(
            directories.map { $0.standardizedFileURL.path }
        )
        let filesToRemove = existingItems.files.filter {
            !desiredFilePaths.contains($0.standardizedFileURL.path)
        }
        let directoriesToRemove = existingItems.directories.filter {
            !desiredDirectoryPaths.contains($0.standardizedFileURL.path)
        }
        try AtomicFileSetWriter.write(
            writes,
            creatingDirectories: directories,
            removingFiles: filesToRemove,
            removingDirectories: directoriesToRemove
        )
        return SaveResult(folderURL: noteFolder, document: snapshot)
    }

    static func load(from noteFolder: URL) throws -> NoteDocument {
        let jsonURL = noteFolder.appending(path: "note.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw NoteFolderError.missingJSON
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: jsonURL)
        let version = try JSONDecoder().decode(
            NoteFormatVersion.self,
            from: data
        ).formatVersion
        guard version == 8 else {
            throw NoteFolderError.unsupportedFormat(version)
        }
        var document = try decoder.decode(
            NoteDocument.self,
            from: data
        )
        for index in document.cards.indices {
            try validateCanonicalPaths(for: document.cards[index])
            let card = document.cards[index]
            guard let relativePath = card.pdfRelativePath else { continue }
            let pdfURL = try safeURL(for: relativePath, in: noteFolder)
            document.cards[index].pdfData = try Data(contentsOf: pdfURL)
        }
        return document
    }

    static func resourceFolder(
        for card: TeXCard,
        kind: CardResourceDirectory,
        in noteFolder: URL
    ) throws -> URL {
        try safeURL(
            for: kind.relativePath(for: card),
            in: noteFolder,
            directoryHint: .isDirectory
        )
    }

    static func loadResources(
        for card: TeXCard,
        kind: CardResourceDirectory,
        from noteFolder: URL?
    ) -> [CardAsset] {
        guard let noteFolder else { return [] }
        let granted = noteFolder.startAccessingSecurityScopedResource()
        defer {
            if granted {
                noteFolder.stopAccessingSecurityScopedResource()
            }
        }

        return loadResources(
            at: resourcePaths(for: card, kind: kind),
            from: noteFolder
        )
    }

    @discardableResult
    static func importResources(
        from sourceURLs: [URL],
        for card: TeXCard,
        kind: CardResourceDirectory,
        into noteFolder: URL?
    ) throws -> [CardAsset] {
        guard let noteFolder else {
            throw NoteFolderError.noteMustBeSavedBeforeAddingResources
        }

        let noteAccessGranted = noteFolder.startAccessingSecurityScopedResource()
        defer {
            if noteAccessGranted {
                noteFolder.stopAccessingSecurityScopedResource()
            }
        }

        let destinationFolderPath = kind.relativePath(for: card)
        let destinationFolder = try packageDestinationURL(
            for: destinationFolderPath,
            in: noteFolder,
            directoryHint: .isDirectory
        )

        var mergedRelativePaths = resourcePaths(for: card, kind: kind)
        var knownRelativePaths = Set(mergedRelativePaths)
        var selectedRelativePaths: Set<String> = []
        var writes: [AtomicFileWrite] = []
        for sourceURL in sourceURLs {
            let relativePath = destinationFolderPath
                + "/\(sourceURL.lastPathComponent)"
            guard selectedRelativePaths.insert(relativePath).inserted else {
                throw NoteFolderError.duplicateResourceName(
                    sourceURL.lastPathComponent
                )
            }
            let destinationURL = try packageDestinationURL(
                for: relativePath,
                in: noteFolder
            )
            writes.append(
                AtomicFileWrite(
                    url: destinationURL,
                    data: try securityScopedData(from: sourceURL)
                )
            )
            if knownRelativePaths.insert(relativePath).inserted {
                mergedRelativePaths.append(relativePath)
            }
        }

        try AtomicFileSetWriter.write(
            writes,
            creatingDirectories: [destinationFolder]
        )

        return loadResources(at: mergedRelativePaths, from: noteFolder)
    }

    @discardableResult
    static func deleteResource(
        at relativePath: String,
        for card: TeXCard,
        kind: CardResourceDirectory,
        from noteFolder: URL?
    ) throws -> [CardAsset] {
        guard let noteFolder else {
            throw NoteFolderError.noteMustBeSavedBeforeAddingResources
        }
        let noteAccessGranted = noteFolder.startAccessingSecurityScopedResource()
        defer {
            if noteAccessGranted {
                noteFolder.stopAccessingSecurityScopedResource()
            }
        }

        let folder = try resourceFolder(for: card, kind: kind, in: noteFolder)
        let resourceURL = try safeURL(for: relativePath, in: noteFolder)
        let folderPath = folder.standardizedFileURL.path
        guard resourceURL.deletingLastPathComponent().standardizedFileURL.path == folderPath
                || resourceURL.standardizedFileURL.path.hasPrefix(folderPath + "/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        if FileManager.default.fileExists(atPath: resourceURL.path) {
            try FileManager.default.removeItem(at: resourceURL)
        }
        return loadResources(for: card, kind: kind, from: noteFolder)
    }

    static func discardResources(for card: TeXCard, from noteFolder: URL?) {
        guard let noteFolder else { return }
        let granted = noteFolder.startAccessingSecurityScopedResource()
        defer {
            if granted {
                noteFolder.stopAccessingSecurityScopedResource()
            }
        }

        for kind in [CardResourceDirectory.pictures, .files] {
            for relativePath in resourcePaths(for: card, kind: kind) {
                guard let url = try? safeURL(
                    for: relativePath,
                    in: noteFolder
                ) else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func safeURL(
        for relativePath: String,
        in root: URL,
        directoryHint: URL.DirectoryHint = .notDirectory
    ) throws -> URL {
        let candidate = try containedPackageURL(
            for: relativePath,
            in: root,
            directoryHint: directoryHint
        )
        let standardizedRoot = root.standardizedFileURL
        let components = relativePath.split(separator: "/")
        var inspectedURL = standardizedRoot
        for component in components {
            inspectedURL.append(path: String(component))
            guard FileManager.default.fileExists(atPath: inspectedURL.path) else {
                continue
            }
            let values = try inspectedURL.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw CocoaError(.fileReadInvalidFileName)
            }
        }
        return candidate
    }

    private static func packageDestinationURL(
        for relativePath: String,
        in root: URL,
        directoryHint: URL.DirectoryHint = .notDirectory
    ) throws -> URL {
        // 保存先はTeXNoteが管理する相対パスから生成する。File Provider上の
        // 未作成項目には、作成前のresourceValues検査を行わない。
        try containedPackageURL(
            for: relativePath,
            in: root,
            directoryHint: directoryHint
        )
    }

    private static func containedPackageURL(
        for relativePath: String,
        in root: URL,
        directoryHint: URL.DirectoryHint
    ) throws -> URL {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("~"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0"),
              components.allSatisfy(
                  { !$0.isEmpty && $0 != "." && $0 != ".." }
              ),
              components.map(String.init).joined(separator: "/")
                == relativePath else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let candidate = root
            .appending(path: relativePath, directoryHint: directoryHint)
            .standardizedFileURL
        return candidate
    }

    private static func canonicalPDFRelativePath(for card: TeXCard) -> String {
        "Cards/\(card.id.uuidString)/output.pdf"
    }

    private static func canonicalResourceFolderPath(
        for card: TeXCard,
        kind: CardResourceDirectory
    ) -> String {
        "Cards/\(card.id.uuidString)/\(kind.folderName)"
    }

    private static func resourcesForSaving(
        for card: TeXCard,
        kind: CardResourceDirectory,
        from noteFolder: URL
    ) throws -> [CardAsset] {
        let paths = resourcePaths(for: card, kind: kind)
        let sourceFolderPath = kind.relativePath(for: card)
        var seenFileNames: Set<String> = []
        return try paths.sorted().map { relativePath in
            guard relativePath.hasPrefix(sourceFolderPath + "/") else {
                throw NoteFolderError.missingResource(relativePath)
            }
            let url = try safeURL(for: relativePath, in: noteFolder)
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            ), values.isRegularFile == true,
               values.isSymbolicLink != true,
               let data = try? Data(contentsOf: url) else {
                throw NoteFolderError.missingResource(relativePath)
            }
            let asset = CardAsset(relativePath: relativePath, data: data)
            guard seenFileNames.insert(asset.fileName).inserted else {
                throw NoteFolderError.invalidStoredPath(relativePath)
            }
            return asset
        }
    }

    private static func validateCanonicalPaths(for card: TeXCard) throws {
        let picturePaths = card.pictureRelativePaths
        let filePaths = card.fileRelativePaths
        let picturesFolder = canonicalResourceFolderPath(
            for: card,
            kind: .pictures
        )
        let filesFolder = canonicalResourceFolderPath(
            for: card,
            kind: .files
        )
        guard card.picturesRelativePath == picturesFolder,
              card.filesRelativePath == filesFolder,
              picturePaths.allSatisfy(
                  { $0.hasPrefix(picturesFolder + "/") }
              ),
              filePaths.allSatisfy(
                  { $0.hasPrefix(filesFolder + "/") }
              ),
              card.pdfRelativePath == nil
                || card.pdfRelativePath == canonicalPDFRelativePath(for: card) else {
            throw NoteFolderError.invalidStoredPath(card.id.uuidString)
        }
    }

    private static func resourcePaths(
        for card: TeXCard,
        kind: CardResourceDirectory
    ) -> [String] {
        switch kind {
        case .pictures: card.pictureRelativePaths
        case .files: card.fileRelativePaths
        }
    }

    private static func loadResources(
        at relativePaths: [String],
        from noteFolder: URL
    ) -> [CardAsset] {
        relativePaths
            .sorted()
            .compactMap { relativePath in
                guard let url = try? safeURL(for: relativePath, in: noteFolder),
                      let values = try? url.resourceValues(
                          forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                      ),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return CardAsset(relativePath: relativePath, data: data)
            }
    }

    private static func managedItems(in cardsFolder: URL) throws -> ManagedItems {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(
            atPath: cardsFolder.path,
            isDirectory: &isDirectory
        ) else {
            return ManagedItems(files: [], directories: [])
        }
        guard isDirectory.boolValue else {
            throw CocoaError(.fileWriteFileExists)
        }

        var files: [URL] = []
        var directories: [URL] = []
        func collect(from folder: URL) throws {
            let children = try manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: []
            )
            for child in children {
                let values = try child.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey
                    ]
                )
                guard values.isSymbolicLink != true else {
                    throw CocoaError(.fileReadInvalidFileName)
                }
                if values.isDirectory == true {
                    directories.append(child)
                    try collect(from: child)
                } else if values.isRegularFile == true {
                    files.append(child)
                } else {
                    throw CocoaError(.fileReadUnknown)
                }
            }
        }
        try collect(from: cardsFolder)
        return ManagedItems(files: files, directories: directories)
    }

    private static func securityScopedData(from url: URL) throws -> Data {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }
}

private struct ManagedItems {
    let files: [URL]
    let directories: [URL]
}

private struct NoteFormatVersion: Decodable {
    let formatVersion: Int
}
