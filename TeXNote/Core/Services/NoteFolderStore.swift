import Foundation
import UniformTypeIdentifiers

enum NotePackageNaming {
    static let pathExtension = "texnote"

    static func folderName(for noteName: String) -> String {
        noteName
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
    case invalidResourceFolderName(String)
    case resourceFolderAlreadyExists(String)
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
        case .invalidResourceFolderName(let name):
            "フォルダ名として使用できません:\n\(name)"
        case .resourceFolderAlreadyExists(let name):
            "同名のフォルダが既にあります:\n\(name)"
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

    func storedRelativePath(
        for resourcePath: String,
        card: TeXCard
    ) -> String? {
        let prefix = relativePath(for: card) + "/"
        guard resourcePath.hasPrefix(prefix) else { return nil }
        return String(resourcePath.dropFirst(prefix.count))
    }

    func legacyRelativePath(
        for resourcePath: String,
        card: TeXCard
    ) -> String {
        let storedPath = storedRelativePath(
            for: resourcePath,
            card: card
        ) ?? URL(filePath: resourcePath).lastPathComponent
        return "\(folderName)/\(storedPath)"
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
                let resourceFiles = try resourceFilesForSaving(
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
                for resourceFile in resourceFiles {
                    let destinationPath =
                        "\(folderPath)/\(resourceFile.relativePath)"
                    let destinationURL = try packageDestinationURL(
                        for: destinationPath,
                        in: noteFolder
                    )
                    directories.append(destinationURL.deletingLastPathComponent())
                    writes.append(
                        AtomicFileWrite(
                            url: destinationURL,
                            copying: resourceFile.url
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
                let pdfURL = try packageDestinationURL(
                    for: pdfPath,
                    in: noteFolder
                )
                if sourceCard.pdfNeedsSaving {
                    guard let currentData = sourceCard.pdfData else {
                        throw NoteFolderError.missingPDF(oldPDFPath)
                    }
                    writes.append(
                        AtomicFileWrite(url: pdfURL, data: currentData)
                    )
                } else {
                    let sourcePDF = try safeURL(
                        for: oldPDFPath,
                        in: sourceFolder
                    )
                    guard let values = try? sourcePDF.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                    ), values.isRegularFile == true,
                       values.isSymbolicLink != true else {
                        throw NoteFolderError.missingPDF(oldPDFPath)
                    }
                    writes.append(
                        AtomicFileWrite(url: pdfURL, copying: sourcePDF)
                    )
                }
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
        let directoriesToRemove = existingItems.directories.filter { directory in
            let path = directory.standardizedFileURL.path
            return !desiredDirectoryPaths.contains(path)
                && !desiredFilePaths.contains(where: { $0.hasPrefix(path + "/") })
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
        var destinationDirectories = [destinationFolder]
        for sourceURL in sourceURLs {
            for selectedFile in try selectedFiles(
                at: sourceURL,
                kind: kind
            ) {
                let relativePath = destinationFolderPath
                    + "/\(selectedFile.relativePath)"
                guard selectedRelativePaths.insert(relativePath).inserted else {
                    throw NoteFolderError.duplicateResourceName(
                        selectedFile.relativePath
                    )
                }
                let destinationURL = try packageDestinationURL(
                    for: relativePath,
                    in: noteFolder
                )
                destinationDirectories.append(
                    destinationURL.deletingLastPathComponent()
                )
                writes.append(
                    AtomicFileWrite(
                        url: destinationURL,
                        data: selectedFile.data
                    )
                )
                if knownRelativePaths.insert(relativePath).inserted {
                    mergedRelativePaths.append(relativePath)
                }
            }
        }

        try AtomicFileSetWriter.write(
            writes,
            creatingDirectories: destinationDirectories
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

    @discardableResult
    static func renameResourceDirectory(
        at storedRelativePath: String,
        to proposedName: String,
        for card: TeXCard,
        kind: CardResourceDirectory,
        in noteFolder: URL?
    ) throws -> [CardAsset] {
        guard let noteFolder else {
            throw NoteFolderError.noteMustBeSavedBeforeAddingResources
        }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains(":"),
              !name.contains("\0") else {
            throw NoteFolderError.invalidResourceFolderName(proposedName)
        }
        try validateRelativeResourcePath(storedRelativePath)

        let oldPath = kind.relativePath(for: card) + "/" + storedRelativePath
        let storedComponents = storedRelativePath.split(separator: "/")
        let parentStoredPath = storedComponents.dropLast().joined(separator: "/")
        let newStoredPath = parentStoredPath.isEmpty
            ? name
            : parentStoredPath + "/" + name
        try validateRelativeResourcePath(newStoredPath)
        if newStoredPath == storedRelativePath {
            return loadResources(for: card, kind: kind, from: noteFolder)
        }

        let newPath = kind.relativePath(for: card) + "/" + newStoredPath
        let granted = noteFolder.startAccessingSecurityScopedResource()
        defer {
            if granted {
                noteFolder.stopAccessingSecurityScopedResource()
            }
        }
        let oldURL = try safeURL(
            for: oldPath,
            in: noteFolder,
            directoryHint: .isDirectory
        )
        let values = try oldURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw NoteFolderError.missingResource(oldPath)
        }
        let newURL = try packageDestinationURL(
            for: newPath,
            in: noteFolder,
            directoryHint: .isDirectory
        )
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw NoteFolderError.resourceFolderAlreadyExists(newStoredPath)
        }

        try FileManager.default.moveItem(at: oldURL, to: newURL)
        let oldPrefix = oldPath + "/"
        let newPrefix = newPath + "/"
        let renamedPaths = resourcePaths(for: card, kind: kind).map { path in
            path.hasPrefix(oldPrefix)
                ? newPrefix + path.dropFirst(oldPrefix.count)
                : path
        }
        return loadResources(at: renamedPaths, from: noteFolder)
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

    private static func resourceFilesForSaving(
        for card: TeXCard,
        kind: CardResourceDirectory,
        from noteFolder: URL
    ) throws -> [ResourceFile] {
        let paths = resourcePaths(for: card, kind: kind)
        var seenRelativePaths: Set<String> = []
        return try paths.sorted().map { relativePath in
            guard let storedRelativePath = kind.storedRelativePath(
                for: relativePath,
                card: card
            ) else {
                throw NoteFolderError.missingResource(relativePath)
            }
            try validateRelativeResourcePath(storedRelativePath)
            let url = try safeURL(for: relativePath, in: noteFolder)
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            ), values.isRegularFile == true,
               values.isSymbolicLink != true else {
                throw NoteFolderError.missingResource(relativePath)
            }
            guard seenRelativePaths.insert(storedRelativePath).inserted else {
                throw NoteFolderError.invalidStoredPath(relativePath)
            }
            return ResourceFile(
                url: url,
                relativePath: storedRelativePath
            )
        }
    }

    private struct ResourceFile {
        let url: URL
        let relativePath: String
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

    private struct SelectedFile {
        let relativePath: String
        let data: Data
    }

    private static func selectedFiles(
        at sourceURL: URL,
        kind: CardResourceDirectory
    ) throws -> [SelectedFile] {
        let granted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try sourceURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        guard values.isDirectory == true else {
            return [SelectedFile(
                relativePath: sourceURL.lastPathComponent,
                data: try Data(contentsOf: sourceURL)
            )]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .contentTypeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var files: [SelectedFile] = []
        for case let fileURL as URL in enumerator {
            let fileValues = try fileURL.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .contentTypeKey
                ]
            )
            if fileValues.isSymbolicLink == true {
                if fileValues.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard fileValues.isRegularFile == true else { continue }
            if kind == .pictures {
                guard let contentType = fileValues.contentType,
                      contentType.conforms(to: .image)
                        || contentType.conforms(to: .pdf) else {
                    continue
                }
            }

            let childComponents = fileURL.pathComponents.dropFirst(
                sourceURL.pathComponents.count
            )
            let relativePath = (
                [sourceURL.lastPathComponent] + Array(childComponents)
            ).joined(separator: "/")
            try validateRelativeResourcePath(relativePath)
            files.append(
                SelectedFile(
                    relativePath: relativePath,
                    data: try Data(contentsOf: fileURL)
                )
            )
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func validateRelativeResourcePath(_ path: String) throws {
        _ = try containedPackageURL(
            for: path,
            in: URL(filePath: "/"),
            directoryHint: .notDirectory
        )
    }
}

private struct ManagedItems {
    let files: [URL]
    let directories: [URL]
}

private struct NoteFormatVersion: Decodable {
    let formatVersion: Int
}
