import Foundation

enum macOSTypesettingMode: String, CaseIterable, Identifiable {
    case local
    case remote

    var id: Self { self }

    var title: String {
        switch self {
        case .local:
            "このMacで版組"
        case .remote:
            "P0公開サーバー経由"
        }
    }
}

enum TeXCompilerFactory {
    static let typesettingModeDefaultsKey = "macOSTypesettingMode"

    static func isAvailable(for engine: TeXEngine) -> Bool {
        switch typesettingMode {
        case .local:
            return isLocalCompilerAvailable(for: engine)
        case .remote:
            return RemoteTeXCompilerFactory.isAvailable(for: engine)
        }
    }

    static func make() -> any TeXCompiling {
        switch typesettingMode {
        case .local:
            return LocalTeXCompiler(binaryDirectory: binaryDirectory)
        case .remote:
            return RemoteTeXCompilerFactory.make()
        }
    }

    private static var typesettingMode: macOSTypesettingMode {
        let value = UserDefaults.standard.string(
            forKey: typesettingModeDefaultsKey
        )
        return macOSTypesettingMode(rawValue: value ?? "") ?? .local
    }

    private static func isLocalCompilerAvailable(for engine: TeXEngine) -> Bool {
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

    private static var binaryDirectory: URL {
        let path = UserDefaults.standard.string(forKey: "compilerPath")
            ?? "/Library/TeX/texbin"
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}
