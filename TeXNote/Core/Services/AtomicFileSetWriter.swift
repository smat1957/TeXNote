import Foundation

struct AtomicFileWrite: Sendable {
    let url: URL
    let source: Source

    enum Source: Sendable {
        case data(Data)
        case file(URL)
    }

    init(url: URL, data: Data) {
        self.url = url
        source = .data(data)
    }

    init(url: URL, copying sourceURL: URL) {
        self.url = url
        source = .file(sourceURL)
    }

    var isNoOpFileCopy: Bool {
        guard case .file(let sourceURL) = source else { return false }
        return sourceURL.standardizedFileURL == url.standardizedFileURL
    }
}

enum AtomicFileSetWriter {
    static func write(
        _ writes: [AtomicFileWrite],
        creatingDirectories directories: [URL],
        removingFiles filesToRemove: [URL] = [],
        removingDirectories directoriesToRemove: [URL] = []
    ) throws {
        let manager = FileManager.default
        let uniqueWrites = try validatedOperations(
            writes,
            removingFiles: filesToRemove,
            removingDirectories: directoriesToRemove
        )
        var directoriesByPath: [String: URL] = [:]
        for directory in directories {
            var candidate = directory.standardizedFileURL
            while !manager.fileExists(atPath: candidate.path) {
                directoriesByPath[candidate.path] = candidate
                let parent = candidate.deletingLastPathComponent()
                guard parent.path != candidate.path else { break }
                candidate = parent
            }
            directoriesByPath[directory.standardizedFileURL.path] =
                directory.standardizedFileURL
        }
        let uniqueDirectories = directoriesByPath.values.sorted {
            $0.path.count < $1.path.count
        }

        let backupFolder = manager.temporaryDirectory.appending(
            path: "TeXNote-AtomicBackup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try manager.createDirectory(
            at: backupFolder,
            withIntermediateDirectories: false
        )
        defer { try? manager.removeItem(at: backupFolder) }

        let backups = try uniqueWrites.enumerated().map { index, write in
            try backup(
                write.url,
                index: index,
                in: backupFolder,
                manager: manager
            )
        }
        let removalBackups = try filesToRemove.enumerated().map { index, url in
            try backup(
                url,
                index: uniqueWrites.count + index,
                in: backupFolder,
                manager: manager
            )
        }

        var createdDirectories: [URL] = []
        var completedWriteCount = 0
        var completedRemovalCount = 0
        var removedDirectories: [URL] = []
        do {
            for directory in uniqueDirectories {
                var isDirectory: ObjCBool = false
                if manager.fileExists(
                    atPath: directory.path,
                    isDirectory: &isDirectory
                ) {
                    guard isDirectory.boolValue else {
                        throw CocoaError(.fileWriteFileExists)
                    }
                } else {
                    try manager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: false
                    )
                    createdDirectories.append(directory)
                }
            }

            for write in uniqueWrites {
                try perform(write, manager: manager)
                completedWriteCount += 1
            }
            for url in filesToRemove {
                try manager.removeItem(at: url)
                completedRemovalCount += 1
            }
            for directory in directoriesToRemove.sorted(
                by: { $0.path.count > $1.path.count }
            ) {
                try manager.removeItem(at: directory)
                removedDirectories.append(directory)
            }
        } catch {
            for directory in removedDirectories.reversed() {
                try? manager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            for backup in removalBackups.prefix(completedRemovalCount).reversed() {
                restore(backup, manager: manager)
            }
            for backup in backups.prefix(completedWriteCount).reversed() {
                restore(backup, manager: manager)
            }
            for directory in createdDirectories.reversed() {
                let contents = try? manager.contentsOfDirectory(
                    atPath: directory.path
                )
                if contents?.isEmpty == true {
                    try? manager.removeItem(at: directory)
                }
            }
            throw error
        }
    }

    private static func validatedOperations(
        _ writes: [AtomicFileWrite],
        removingFiles: [URL],
        removingDirectories: [URL]
    ) throws -> [AtomicFileWrite] {
        var paths: Set<String> = []
        for write in writes {
            guard paths.insert(write.url.standardizedFileURL.path).inserted else {
                throw CocoaError(.fileWriteFileExists)
            }
        }
        for url in removingFiles + removingDirectories {
            guard paths.insert(url.standardizedFileURL.path).inserted else {
                throw CocoaError(.fileWriteFileExists)
            }
        }
        return writes.filter { !$0.isNoOpFileCopy }
    }

    private struct Backup {
        let url: URL
        let backupURL: URL?
    }

    private static func backup(
        _ url: URL,
        index: Int,
        in backupFolder: URL,
        manager: FileManager
    ) throws -> Backup {
        guard manager.fileExists(atPath: url.path) else {
            return Backup(url: url, backupURL: nil)
        }
        let backupURL = backupFolder.appending(path: String(index))
        try streamCopy(from: url, to: backupURL, manager: manager)
        return Backup(url: url, backupURL: backupURL)
    }

    private static func perform(
        _ write: AtomicFileWrite,
        manager: FileManager
    ) throws {
        switch write.source {
        case .data(let data):
            try data.write(to: write.url, options: .atomic)
        case .file(let sourceURL):
            let temporaryURL = write.url.deletingLastPathComponent().appending(
                path: ".texnote-copy-\(UUID().uuidString)"
            )
            defer { try? manager.removeItem(at: temporaryURL) }
            try streamCopy(
                from: sourceURL,
                to: temporaryURL,
                manager: manager
            )
            if manager.fileExists(atPath: write.url.path) {
                _ = try manager.replaceItemAt(
                    write.url,
                    withItemAt: temporaryURL
                )
            } else {
                try manager.moveItem(at: temporaryURL, to: write.url)
            }
        }
    }

    private static func restore(_ backup: Backup, manager: FileManager) {
        try? manager.removeItem(at: backup.url)
        guard let backupURL = backup.backupURL else { return }
        try? streamCopy(
            from: backupURL,
            to: backup.url,
            manager: manager
        )
    }

    private static func streamCopy(
        from sourceURL: URL,
        to destinationURL: URL,
        manager: FileManager
    ) throws {
        guard !manager.fileExists(atPath: destinationURL.path),
              manager.createFile(
                  atPath: destinationURL.path,
                  contents: nil
              ) else {
            throw CocoaError(.fileWriteFileExists)
        }

        let source = try FileHandle(forReadingFrom: sourceURL)
        let destination = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? source.close()
            try? destination.close()
        }

        let bufferSize = 1024 * 1024
        while let data = try source.read(upToCount: bufferSize), !data.isEmpty {
            try destination.write(contentsOf: data)
        }
        try destination.synchronize()
    }
}
