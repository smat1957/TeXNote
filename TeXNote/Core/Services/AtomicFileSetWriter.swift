import Foundation

struct AtomicFileWrite: Sendable {
    let url: URL
    let data: Data
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

        let backups = try uniqueWrites.map { write in
            let path = write.url.standardizedFileURL.path
            if manager.fileExists(atPath: path) {
                return Backup(
                    url: write.url,
                    data: try Data(contentsOf: write.url)
                )
            }
            return Backup(url: write.url, data: nil)
        }
        let removalBackups = try filesToRemove.map { url in
            Backup(url: url, data: try Data(contentsOf: url))
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
                try write.data.write(to: write.url, options: .atomic)
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
                try? backup.data?.write(to: backup.url, options: .atomic)
            }
            for backup in backups.prefix(completedWriteCount).reversed() {
                if let data = backup.data {
                    try? data.write(to: backup.url, options: .atomic)
                } else {
                    try? manager.removeItem(at: backup.url)
                }
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
        return writes
    }

    private struct Backup {
        let url: URL
        let data: Data?
    }
}
