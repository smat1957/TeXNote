import Foundation

actor LocalTeXCompiler: TeXCompiling {
    private let binaryDirectory: URL

    init(binaryDirectory: URL) {
        self.binaryDirectory = binaryDirectory
    }

    func compile(
        card: TeXCard,
        pictures: [CardAsset],
        files: [CardAsset]
    ) async throws -> CompilationResult {
        let manager = FileManager.default
        let workDirectory = manager.temporaryDirectory
            .appending(path: "TeXNote", directoryHint: .isDirectory)
            .appending(path: card.id.uuidString, directoryHint: .isDirectory)
        try? manager.removeItem(at: workDirectory)
        try manager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: workDirectory)
        }

        for (kind, assets) in [
            (CardResourceDirectory.pictures, pictures),
            (CardResourceDirectory.files, files)
        ] {
            for asset in assets {
                let resourceURL = try NoteFolderStore.safeURL(
                    for: asset.relativePath,
                    in: workDirectory
                )
                try manager.createDirectory(
                    at: resourceURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try asset.data.write(to: resourceURL, options: .atomic)

                let legacyPath = kind.legacyRelativePath(
                    for: asset.relativePath,
                    card: card
                )
                guard legacyPath != asset.relativePath else { continue }
                let legacyURL = try NoteFolderStore.safeURL(
                    for: legacyPath,
                    in: workDirectory
                )
                try manager.createDirectory(
                    at: legacyURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try asset.data.write(to: legacyURL, options: .atomic)
            }
        }

        let sourceURL = workDirectory.appending(path: "main.tex")
        try card.completeSource.write(to: sourceURL, atomically: true, encoding: .utf8)

        let executable = binaryDirectory.appending(path: card.engine.rawValue)
        guard manager.isExecutableFile(atPath: executable.path) else {
            throw CompilationError.executableNotFound(executable.path)
        }

        var combinedLog = ""
        if card.engine.producesDVI {
            combinedLog += try await generateBoundingBoxes(
                for: pictures,
                card: card,
                in: workDirectory
            )
        }

        for _ in 0..<2 {
            let result = try await run(
                executable: executable,
                arguments: [
                    "-interaction=nonstopmode",
                    "-file-line-error",
                    "-halt-on-error",
                    "main.tex"
                ],
                directory: workDirectory
            )
            combinedLog += result.output
            if result.exitCode != 0 {
                throw CompilationError.failed(exitCode: result.exitCode, log: combinedLog)
            }
        }

        if card.engine.producesDVI {
            let converter = binaryDirectory.appending(path: "dvipdfmx")
            guard manager.isExecutableFile(atPath: converter.path) else {
                throw CompilationError.executableNotFound(converter.path)
            }
            let result = try await run(
                executable: converter,
                arguments: ["main.dvi"],
                directory: workDirectory
            )
            combinedLog += result.output
            if result.exitCode != 0 {
                throw CompilationError.failed(
                    exitCode: result.exitCode,
                    log: combinedLog
                )
            }
        }

        let pdfURL = workDirectory.appending(path: "main.pdf")
        guard manager.fileExists(atPath: pdfURL.path) else {
            throw CompilationError.pdfNotProduced(log: combinedLog)
        }
        return CompilationResult(
            pdfData: try Data(contentsOf: pdfURL),
            log: combinedLog
        )
    }

    private func generateBoundingBoxes(
        for pictures: [CardAsset],
        card: TeXCard,
        in workDirectory: URL
    ) async throws -> String {
        let supportedExtensions = Set(["jpg", "jpeg", "png", "pdf"])
        let targets = pictures.filter {
            supportedExtensions.contains(
                URL(filePath: $0.relativePath).pathExtension.lowercased()
            )
        }
        guard !targets.isEmpty else { return "" }

        let extractor = binaryDirectory.appending(path: "extractbb")
        guard FileManager.default.isExecutableFile(atPath: extractor.path) else {
            throw CompilationError.executableNotFound(extractor.path)
        }

        var log = ""
        for picture in targets {
            let picturePath = CardResourceDirectory.pictures.legacyRelativePath(
                for: picture.relativePath,
                card: card
            )
            let result = try await run(
                executable: extractor,
                arguments: ["-x", picturePath],
                directory: workDirectory
            )
            log += result.output
            if result.exitCode != 0 {
                throw CompilationError.failed(
                    exitCode: result.exitCode,
                    log: log
                )
            }
        }
        return log
    }

    private func run(
        executable: URL,
        arguments: [String],
        directory: URL
    ) async throws -> (exitCode: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            var environment = ProcessInfo.processInfo.environment
            let existingPath = environment["PATH"] ?? ""
            let ghostscriptDirectories = [
                URL(filePath: "/usr/local/bin", directoryHint: .isDirectory),
                URL(filePath: "/opt/homebrew/bin", directoryHint: .isDirectory)
            ].filter { directory in
                FileManager.default.isExecutableFile(
                    atPath: directory.appending(path: "gs").path
                )
            }
            let searchPath = [binaryDirectory.path]
                + ghostscriptDirectories.map(\.path)
                + (existingPath.isEmpty ? [] : [existingPath])
            environment["PATH"] = searchPath.joined(separator: ":")
            let cacheDirectory = directory.appending(path: ".tex-cache", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            environment["TEXMFCACHE"] = cacheDirectory.path
            environment["TEXMFVAR"] = cacheDirectory.path
            process.environment = environment
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                continuation.resume(returning: (process.terminationStatus, output))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
