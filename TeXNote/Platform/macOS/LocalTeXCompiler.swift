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

        for (folderName, assets) in [("pics", pictures), ("files", files)] {
            let resourceDirectory = workDirectory.appending(
                path: folderName,
                directoryHint: .isDirectory
            )
            try manager.createDirectory(
                at: resourceDirectory,
                withIntermediateDirectories: true
            )
            for asset in assets {
                try asset.data.write(
                    to: resourceDirectory.appending(path: asset.fileName),
                    options: .atomic
                )
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
        return CompilationResult(pdfURL: pdfURL, log: combinedLog)
    }

    private func generateBoundingBoxes(
        for pictures: [CardAsset],
        in workDirectory: URL
    ) async throws -> String {
        let supportedExtensions = Set(["jpg", "jpeg", "png", "pdf"])
        let targets = pictures.filter {
            supportedExtensions.contains(
                URL(filePath: $0.fileName).pathExtension.lowercased()
            )
        }
        guard !targets.isEmpty else { return "" }

        let extractor = binaryDirectory.appending(path: "extractbb")
        guard FileManager.default.isExecutableFile(atPath: extractor.path) else {
            throw CompilationError.executableNotFound(extractor.path)
        }

        var log = ""
        for picture in targets {
            let result = try await run(
                executable: extractor,
                arguments: ["-x", "pics/\(picture.fileName)"],
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
            environment["PATH"] = existingPath.isEmpty
                ? binaryDirectory.path
                : "\(binaryDirectory.path):\(existingPath)"
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
