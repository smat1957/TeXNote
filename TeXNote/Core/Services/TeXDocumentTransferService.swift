import Foundation

enum TeXDocumentTransferError: LocalizedError {
    case unreadableSource
    case missingDocumentClass
    case missingDocumentEnvironment
    case multipleDocumentEnvironments
    case invalidCardTitle
    case noteMustBeSavedBeforeExporting
    case pdfNotGenerated
    case pdfOutdated
    case invalidExportDestination(String)
    case duplicateResourceName(String)
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSource:
            "TeX文書をUTF-8として読み込めませんでした。"
        case .missingDocumentClass:
            "TeX文書に\\documentclassがありません。"
        case .missingDocumentEnvironment:
            "TeX文書に\\begin{document}と\\end{document}がありません。"
        case .multipleDocumentEnvironments:
            "TeX文書に複数のdocument環境があるため、取り込めません。"
        case .invalidCardTitle:
            "Card名をTeX文書のファイル名として使用できません。"
        case .noteMustBeSavedBeforeExporting:
            "この記事をエクスポートする前に、NoteをPackageへ保存してください。"
        case .pdfNotGenerated:
            "PDFが生成されていません。先に版組してください。"
        case .pdfOutdated:
            "PDFが現在のTeXソースに対応していません。再度版組してください。"
        case .invalidExportDestination(let name):
            "保存先の「\(name)」をエクスポート用に使用できません。"
        case .duplicateResourceName(let name):
            "同名の画像またはファイルが複数登録されています:\n\(name)"
        case .missingResource(let path):
            "エクスポートに必要な画像またはファイルが見つかりません:\n\(path)"
        }
    }
}

enum TeXDocumentTransferService {
    struct ExportConflict: Error, Sendable {
        let itemNames: [String]
    }

    static func importedCard(from sourceURL: URL) throws -> TeXCard {
        guard let source = String(data: try Data(contentsOf: sourceURL), encoding: .utf8) else {
            throw TeXDocumentTransferError.unreadableSource
        }
        let parts = try parse(source)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        guard !title.isEmpty else {
            throw TeXDocumentTransferError.invalidCardTitle
        }
        return TeXCard(
            title: title,
            body: parts.body,
            documentClassLine: parts.documentClass,
            preamble: parts.preamble
        )
    }

    static func export(
        card: TeXCard,
        fileName: String,
        noteFolder: URL?,
        to destinationFolder: URL,
        replacingExistingItems: Bool
    ) throws {
        guard let noteFolder else {
            throw TeXDocumentTransferError.noteMustBeSavedBeforeExporting
        }
        let baseName = try validatedExportBaseName(fileName)
        let pdfData: Data
        switch card.pdfStatus {
        case .current:
            guard let currentPDFData = card.pdfData else {
                throw TeXDocumentTransferError.pdfNotGenerated
            }
            pdfData = currentPDFData
        case .outdated:
            throw TeXDocumentTransferError.pdfOutdated
        case .notTypeset:
            throw TeXDocumentTransferError.pdfNotGenerated
        }

        let sourceURL = destinationFolder.appending(path: "\(baseName).tex")
        let pdfURL = destinationFolder.appending(path: "\(baseName).pdf")
        let resources = try exportResources(for: card, from: noteFolder)
        let resourceFolders = ["pics", "files"].map {
            destinationFolder.appending(path: $0, directoryHint: .isDirectory)
        }
        var isDirectory: ObjCBool = false
        for fileURL in [sourceURL, pdfURL] {
            isDirectory = false
            if FileManager.default.fileExists(
                atPath: fileURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue {
                throw TeXDocumentTransferError.invalidExportDestination(
                    fileURL.lastPathComponent
                )
            }
        }
        for folder in resourceFolders {
            isDirectory = false
            if FileManager.default.fileExists(
                atPath: folder.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue {
                throw TeXDocumentTransferError.invalidExportDestination(
                    folder.lastPathComponent
                )
            }
        }
        let targets = [sourceURL, pdfURL] + resources.map { resource in
            destinationFolder
                .appending(path: resource.folderName, directoryHint: .isDirectory)
                .appending(path: resource.fileName)
        }
        let conflicts = targets.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        if !replacingExistingItems, !conflicts.isEmpty {
            throw ExportConflict(
                itemNames: conflicts.map {
                    $0.path.replacingOccurrences(
                        of: destinationFolder.path + "/",
                        with: ""
                    )
                }
            )
        }

        let writes = [
            AtomicFileWrite(
                url: sourceURL,
                data: Data(card.completeSource.utf8)
            ),
            AtomicFileWrite(
                url: pdfURL,
                data: pdfData
            )
        ] + resources.map { resource in
            let folder = destinationFolder.appending(
                path: resource.folderName,
                directoryHint: .isDirectory
            )
            return AtomicFileWrite(
                url: folder.appending(path: resource.fileName),
                data: resource.data
            )
        }
        try AtomicFileSetWriter.write(
            writes,
            creatingDirectories: [destinationFolder] + resourceFolders
        )
    }

    static func validatedExportBaseName(_ proposedName: String) throws -> String {
        let baseName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty,
              baseName != ".",
              baseName != "..",
              !baseName.contains("/"),
              !baseName.contains(":"),
              !baseName.contains("\0") else {
            throw TeXDocumentTransferError.invalidCardTitle
        }
        return baseName
    }

    private static func parse(_ source: String) throws -> ParsedSource {
        let searchable = sourceWithNonStructuralContentMasked(source)
        let wholeRange = NSRange(searchable.startIndex..., in: searchable)
        let documentClass = try firstMatch(
            #"(?<!\\)\\documentclass(?:\s*\[[^\]]*\])?\s*\{[^{}]+\}"#,
            in: searchable,
            requiredError: .missingDocumentClass
        )
        let begins = matches(
            #"(?<!\\)\\begin\s*\{document\}"#,
            in: searchable
        )
        let ends = matches(
            #"(?<!\\)\\end\s*\{document\}"#,
            in: searchable
        )
        guard begins.count == 1, ends.count == 1,
              begins[0].location > documentClass.location,
              ends[0].location >= NSMaxRange(begins[0]) else {
            if begins.count > 1 || ends.count > 1 {
                throw TeXDocumentTransferError.multipleDocumentEnvironments
            }
            throw TeXDocumentTransferError.missingDocumentEnvironment
        }
        guard NSMaxRange(ends[0]) <= wholeRange.length else {
            throw TeXDocumentTransferError.missingDocumentEnvironment
        }

        let original = source as NSString
        return ParsedSource(
            documentClass: original.substring(with: documentClass)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            preamble: original.substring(
                with: NSRange(
                    location: NSMaxRange(documentClass),
                    length: begins[0].location - NSMaxRange(documentClass)
                )
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            body: original.substring(
                with: NSRange(
                    location: NSMaxRange(begins[0]),
                    length: ends[0].location - NSMaxRange(begins[0])
                )
            ).trimmingCharacters(in: .newlines)
        )
    }

    private static func firstMatch(
        _ pattern: String,
        in source: String,
        requiredError: TeXDocumentTransferError
    ) throws -> NSRange {
        guard let match = matches(pattern, in: source).first else {
            throw requiredError
        }
        return match
    }

    private static func matches(_ pattern: String, in source: String) -> [NSRange] {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        return regex?.matches(in: source, range: range).map(\.range) ?? []
    }

    private static func sourceWithNonStructuralContentMasked(
        _ source: String
    ) -> String {
        var units = Array(source.utf16)
        maskComments(in: &units)

        let commentMaskedSource = String(decoding: units, as: UTF16.self)
        var verbatimEnvironmentNames: Set<String> = [
            "verbatim",
            "Verbatim",
            "lstlisting",
            "minted",
            "filecontents",
            "filecontents*"
        ]
        let definitionPattern = #"(?<!\\)\\DefineVerbatimEnvironment\s*\{([^{}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: definitionPattern) {
            let range = NSRange(
                commentMaskedSource.startIndex...,
                in: commentMaskedSource
            )
            for match in regex.matches(in: commentMaskedSource, range: range) {
                guard match.numberOfRanges > 1,
                      let nameRange = Range(
                        match.range(at: 1),
                        in: commentMaskedSource
                      ) else {
                    continue
                }
                verbatimEnvironmentNames.insert(
                    String(commentMaskedSource[nameRange])
                )
            }
        }

        for name in verbatimEnvironmentNames {
            maskEnvironment(named: name, in: &units)
        }
        maskInlineVerbCommands(in: &units)
        return String(decoding: units, as: UTF16.self)
    }

    private static func maskComments(in units: inout [UInt16]) {
        var index = 0
        var inComment = false
        while index < units.count {
            let unit = units[index]
            if unit == 10 || unit == 13 {
                inComment = false
                index += 1
                continue
            }
            if inComment {
                units[index] = 32
                index += 1
                continue
            }
            if unit == 37 {
                var slashCount = 0
                var previous = index
                while previous > 0, units[previous - 1] == 92 {
                    slashCount += 1
                    previous -= 1
                }
                if slashCount.isMultiple(of: 2) {
                    units[index] = 32
                    inComment = true
                }
            }
            index += 1
        }
    }

    private static func maskEnvironment(
        named name: String,
        in units: inout [UInt16]
    ) {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let beginPattern = #"(?m)^[\t ]*(?<!\\)\\begin\s*\{"#
            + escapedName
            + #"\}"#
        let endPattern = #"(?m)^[\t ]*(?<!\\)\\end\s*\{"#
            + escapedName
            + #"\}"#
        guard let beginRegex = try? NSRegularExpression(pattern: beginPattern),
              let endRegex = try? NSRegularExpression(pattern: endPattern) else {
            return
        }

        var searchLocation = 0
        while searchLocation < units.count {
            let source = String(decoding: units, as: UTF16.self)
            let remainingRange = NSRange(
                location: searchLocation,
                length: units.count - searchLocation
            )
            guard let begin = beginRegex.firstMatch(
                in: source,
                range: remainingRange
            ) else {
                return
            }
            let afterBegin = NSMaxRange(begin.range)
            guard let end = endRegex.firstMatch(
                in: source,
                range: NSRange(
                    location: afterBegin,
                    length: units.count - afterBegin
                )
            ) else {
                return
            }
            let maskedRange = NSRange(
                location: begin.range.location,
                length: NSMaxRange(end.range) - begin.range.location
            )
            mask(maskedRange, in: &units)
            searchLocation = NSMaxRange(maskedRange)
        }
    }

    private static func maskInlineVerbCommands(in units: inout [UInt16]) {
        let verb = Array("verb".utf16)
        var index = 0
        while index + verb.count + 1 < units.count {
            guard units[index] == 92,
                  (index == 0 || units[index - 1] != 92),
                  Array(units[(index + 1)...(index + verb.count)]) == verb else {
                index += 1
                continue
            }

            var delimiterIndex = index + verb.count + 1
            if units[delimiterIndex] == 42 {
                delimiterIndex += 1
            }
            guard delimiterIndex < units.count else { return }
            let delimiter = units[delimiterIndex]
            guard delimiter != 10,
                  delimiter != 13,
                  delimiter != 32,
                  delimiter != 9 else {
                index += 1
                continue
            }

            var endIndex = delimiterIndex + 1
            while endIndex < units.count,
                  units[endIndex] != delimiter,
                  units[endIndex] != 10,
                  units[endIndex] != 13 {
                endIndex += 1
            }
            guard endIndex < units.count, units[endIndex] == delimiter else {
                index += 1
                continue
            }
            mask(
                NSRange(location: index, length: endIndex - index + 1),
                in: &units
            )
            index = endIndex + 1
        }
    }

    private static func mask(_ range: NSRange, in units: inout [UInt16]) {
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= units.count else {
            return
        }
        for index in range.location..<NSMaxRange(range)
        where units[index] != 10 && units[index] != 13 {
            units[index] = 32
        }
    }

    private static func exportResources(
        for card: TeXCard,
        from noteFolder: URL
    ) throws -> [ExportResource] {
        var results: [ExportResource] = []
        var namesByFolder: [String: Set<String>] = [:]
        for (folderName, paths) in [
            ("pics", card.pictureRelativePaths),
            ("files", card.fileRelativePaths)
        ] {
            for path in paths.sorted() {
                let url = try NoteFolderStore.safeURL(for: path, in: noteFolder)
                let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values?.isRegularFile == true,
                      values?.isSymbolicLink != true,
                      let data = try? Data(contentsOf: url) else {
                    throw TeXDocumentTransferError.missingResource(path)
                }
                let fileName = url.lastPathComponent
                guard namesByFolder[folderName, default: []].insert(fileName).inserted else {
                    throw TeXDocumentTransferError.duplicateResourceName(
                        "\(folderName)/\(fileName)"
                    )
                }
                results.append(
                    ExportResource(
                        folderName: folderName,
                        fileName: fileName,
                        data: data
                    )
                )
            }
        }
        return results
    }
}

private struct ParsedSource {
    let documentClass: String
    let preamble: String
    let body: String
}

private struct ExportResource {
    let folderName: String
    let fileName: String
    let data: Data
}
