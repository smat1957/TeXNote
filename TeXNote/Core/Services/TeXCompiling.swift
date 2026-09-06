import Foundation

struct CompilationResult: Sendable {
    let pdfData: Data
    let log: String
}

struct CardAsset: Codable, Sendable {
    /// ノートルートを基準にした、安全な相対パス。
    let relativePath: String
    let data: Data

    var fileName: String {
        URL(filePath: relativePath).lastPathComponent
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case fileName
        case data
    }

    init(relativePath: String, data: Data) {
        self.relativePath = relativePath
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try container.decodeIfPresent(
            String.self,
            forKey: .relativePath
        ) ?? container.decode(String.self, forKey: .fileName)
        data = try container.decode(Data.self, forKey: .data)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(data, forKey: .data)
    }
}

enum CompilationError: LocalizedError {
    case executableNotFound(String)
    case failed(exitCode: Int32, log: String)
    case pdfNotProduced(log: String)
    case invalidServerURL
    case authenticationRequired(String)
    case serverResponse(statusCode: Int, message: String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            "TeXエンジンが見つかりません: \(path)"
        case .failed(_, let log), .pdfNotProduced(let log):
            log.isEmpty ? "PDFを生成できませんでした。" : log
        case .invalidServerURL:
            "P0公開サーバーのURLが正しくありません。"
        case .authenticationRequired(let message):
            message
        case .serverResponse(let statusCode, let message):
            message.isEmpty
                ? "版組サーバーでエラーが発生しました（HTTP \(statusCode)）。"
                : message
        case .unavailable(let message):
            message
        }
    }
}

protocol TeXCompiling: Sendable {
    func compile(
        card: TeXCard,
        pictures: [CardAsset],
        files: [CardAsset]
    ) async throws -> CompilationResult
}
