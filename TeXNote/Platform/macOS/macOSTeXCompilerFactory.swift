import Foundation

enum TeXCompilerFactory {
    static func isAvailable(for engine: TeXEngine) -> Bool {
        let manager = FileManager.default
        let directory = binaryDirectory
        guard manager.isExecutableFile(
            atPath: directory.appending(path: engine.rawValue).path
        ) else {
            return false
        }
        guard engine.producesDVI else { return true }
        return manager.isExecutableFile(
            atPath: directory.appending(path: "dvipdfmx").path
        ) && manager.isExecutableFile(
            atPath: directory.appending(path: "extractbb").path
        )
    }

    static func make() -> any TeXCompiling {
        return LocalTeXCompiler(
            binaryDirectory: binaryDirectory
        )
    }

    private static var binaryDirectory: URL {
        let path = UserDefaults.standard.string(forKey: "compilerPath")
            ?? "/Library/TeX/texbin"
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
