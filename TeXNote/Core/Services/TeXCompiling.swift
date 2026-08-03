import Foundation

struct CompilationResult: Sendable {
    let pdfURL: URL
    let log: String
}

struct CardAsset: Codable, Sendable {
    let fileName: String
    let data: Data
}

enum CompilationError: LocalizedError {
    case executableNotFound(String)
    case failed(exitCode: Int32, log: String)
    case pdfNotProduced(log: String)
    case invalidServerURL
    case serverResponse(statusCode: Int, message: String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            "TeXエンジンが見つかりません: \(path)"
        case .failed(_, let log), .pdfNotProduced(let log):
            log.isEmpty ? "PDFを生成できませんでした。" : log
        case .invalidServerURL:
            "版組サーバーのURLが正しくありません。"
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
