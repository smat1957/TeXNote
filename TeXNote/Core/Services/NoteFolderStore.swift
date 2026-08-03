import Foundation

enum NoteFolderError: LocalizedError {
    case invalidName
    case missingJSON
    case unsupportedFormat(Int)
    case noteMustBeSavedBeforeAddingResources

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
    static func save(
        document: NoteDocument,
        noteName: String,
        parentFolder: URL,
        sourceNoteFolder: URL? = nil
    ) throws -> URL {
        let name = noteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":") else {
            throw NoteFolderError.invalidName
        }

        let manager = FileManager.default
        let noteFolder = parentFolder.appending(path: name, directoryHint: .isDirectory)
        let pdfFolder = noteFolder.appending(path: "PDF", directoryHint: .isDirectory)
        try manager.createDirectory(at: pdfFolder, withIntermediateDirectories: true)

        if let sourceNoteFolder,
           sourceNoteFolder.standardizedFileURL != noteFolder.standardizedFileURL {
            try copyCardResources(
                for: document.cards,
                from: sourceNoteFolder,
                to: noteFolder,
                manager: manager
            )
        }

        for card in document.cards {
            for kind in [CardResourceDirectory.pictures, .files] {
                try manager.createDirectory(
                    at: resourceFolder(for: card, kind: kind, in: noteFolder),
                    withIntermediateDirectories: true
                )
            }
        }

        var snapshot = document
        snapshot.formatVersion = 6
        snapshot.name = name

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(snapshot)
        try json.write(to: noteFolder.appending(path: "note.json"), options: .atomic)

        for card in document.cards {
            guard let relativePath = card.pdfRelativePath, let data = card.pdfData else { continue }
            let fileName = URL(filePath: relativePath).lastPathComponent
            try data.write(to: pdfFolder.appending(path: fileName), options: .atomic)
        }
        return noteFolder
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
        guard version == 6 else {
            throw NoteFolderError.unsupportedFormat(version)
        }
        var document = try decoder.decode(
            NoteDocument.self,
            from: data
        )
        for index in document.cards.indices {
            guard let path = document.cards[index].pdfRelativePath else { continue }
            let pdfURL = noteFolder.appending(path: path)
            document.cards[index].pdfData = try? Data(contentsOf: pdfURL)
        }
        return document
    }

    static func resourceFolder(
        for card: TeXCard,
        kind: CardResourceDirectory,
        in noteFolder: URL
    ) throws -> URL {
        let relativePath = kind.relativePath(for: card)
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !relativePath.hasPrefix("/"),
              !components.contains(".."),
              components.count == 2,
              components[0] == Substring(card.id.uuidString),
              components[1] == Substring(kind.folderName) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return noteFolder.appending(path: relativePath, directoryHint: .isDirectory)
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

        guard let folder = existingResourceFolder(
                  for: card,
                  kind: kind,
                  in: noteFolder
              ),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: folder,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return CardAsset(fileName: url.lastPathComponent, data: data)
            }
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

        let manager = FileManager.default
        let destinationFolder = try resourceFolder(
            for: card,
            kind: kind,
            in: noteFolder
        )
        try manager.createDirectory(
            at: destinationFolder,
            withIntermediateDirectories: true
        )

        for sourceURL in sourceURLs {
            let sourceAccessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if sourceAccessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = destinationFolder.appending(
                path: sourceURL.lastPathComponent
            )
            let data = try Data(contentsOf: sourceURL)
            try data.write(to: destinationURL, options: .atomic)
        }

        return loadResources(for: card, kind: kind, from: noteFolder)
    }

    @discardableResult
    static func deleteResource(
        named fileName: String,
        for card: TeXCard,
        kind: CardResourceDirectory,
        from noteFolder: URL?
    ) throws -> [CardAsset] {
        guard let noteFolder else {
            throw NoteFolderError.noteMustBeSavedBeforeAddingResources
        }
        guard !fileName.isEmpty,
              fileName == URL(filePath: fileName).lastPathComponent,
              fileName != ".",
              fileName != ".." else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let noteAccessGranted = noteFolder.startAccessingSecurityScopedResource()
        defer {
            if noteAccessGranted {
                noteFolder.stopAccessingSecurityScopedResource()
            }
        }

        let folder = try resourceFolder(for: card, kind: kind, in: noteFolder)
        let resourceURL = folder.appending(path: fileName)
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

        let cardFolder = noteFolder.appending(
            path: card.id.uuidString,
            directoryHint: .isDirectory
        )
        try? FileManager.default.removeItem(at: cardFolder)
    }

    private static func copyCardResources(
        for cards: [TeXCard],
        from sourceNoteFolder: URL,
        to destinationNoteFolder: URL,
        manager: FileManager
    ) throws {
        for card in cards {
            for kind in [CardResourceDirectory.pictures, .files] {
                guard let source = existingResourceFolder(
                    for: card,
                    kind: kind,
                    in: sourceNoteFolder
                ) else {
                    continue
                }

                let destination = try resourceFolder(
                    for: card,
                    kind: kind,
                    in: destinationNoteFolder
                )
                try manager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }
                try manager.copyItem(at: source, to: destination)
            }
        }
    }

    private static func existingResourceFolder(
        for card: TeXCard,
        kind: CardResourceDirectory,
        in noteFolder: URL
    ) -> URL? {
        let manager = FileManager.default
        if let current = try? resourceFolder(for: card, kind: kind, in: noteFolder),
           manager.fileExists(atPath: current.path) {
            return current
        }
        return nil
    }
}

private struct NoteFormatVersion: Decodable {
    let formatVersion: Int
}
