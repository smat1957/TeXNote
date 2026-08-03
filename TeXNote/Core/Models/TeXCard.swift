import Foundation
import CryptoKit

struct TeXCard: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var documentClassLine: String
    var preamble: String
    var engine: TeXEngine
    var pdfRelativePath: String?
    var picturesRelativePath: String
    var filesRelativePath: String
    var pdfData: Data? = nil
    var compiledSourceHash: String?
    var lastTypesetAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "無題のカード",
        body: String = """
        ここに本文を書きます。

        \\[
          e^{i\\pi} + 1 = 0
        \\]
        """,
        documentClassLine: String = "\\documentclass{ltjsarticle}",
        preamble: String = "\\usepackage{amsmath}",
        engine: TeXEngine = .luaLaTeX,
        pdfRelativePath: String? = nil,
        picturesRelativePath: String? = nil,
        filesRelativePath: String? = nil,
        pdfData: Data? = nil,
        compiledSourceHash: String? = nil,
        lastTypesetAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.documentClassLine = documentClassLine
        self.preamble = preamble
        self.engine = engine
        self.pdfRelativePath = pdfRelativePath
        self.picturesRelativePath = picturesRelativePath
            ?? "\(id.uuidString)/pics"
        self.filesRelativePath = filesRelativePath
            ?? "\(id.uuidString)/files"
        self.pdfData = pdfData
        self.compiledSourceHash = compiledSourceHash
        self.lastTypesetAt = lastTypesetAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var completeSource: String {
        """
        \(documentClassLine)
        \(preamble)

        \\begin{document}
        \(body)
        \\end{document}
        """
    }

    var sourceHash: String {
        SHA256.hash(data: Data("\(engine.rawValue)\n\(completeSource)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var pdfStatus: PDFStatus {
        guard pdfData != nil else { return .notTypeset }
        return compiledSourceHash == sourceHash ? .current : .outdated
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case documentClassLine
        case preamble
        case engine
        case pdfRelativePath
        case picturesRelativePath
        case filesRelativePath
        case compiledSourceHash
        case lastTypesetAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        documentClassLine = try container.decode(String.self, forKey: .documentClassLine)
        preamble = try container.decode(String.self, forKey: .preamble)
        engine = try container.decode(TeXEngine.self, forKey: .engine)
        pdfRelativePath = try container.decodeIfPresent(String.self, forKey: .pdfRelativePath)
        picturesRelativePath = try container.decode(
            String.self,
            forKey: .picturesRelativePath
        )
        filesRelativePath = try container.decode(
            String.self,
            forKey: .filesRelativePath
        )
        pdfData = nil
        compiledSourceHash = try container.decodeIfPresent(
            String.self,
            forKey: .compiledSourceHash
        )
        lastTypesetAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastTypesetAt
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

enum PDFStatus {
    case current
    case outdated
    case notTypeset

    var label: String {
        switch self {
        case .current: "最新版"
        case .outdated: "ソース更新後"
        case .notTypeset: "未版組"
        }
    }
}

enum TeXEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case luaLaTeX = "lualatex"
    case xeLaTeX = "xelatex"
    case pdfLaTeX = "pdflatex"
    case upLaTeX = "uplatex"
    case pLaTeX = "platex"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .luaLaTeX: "LuaLaTeX"
        case .xeLaTeX: "XeLaTeX"
        case .pdfLaTeX: "pdfLaTeX"
        case .upLaTeX: "upLaTeX"
        case .pLaTeX: "pLaTeX"
        }
    }

    var producesDVI: Bool {
        self == .upLaTeX || self == .pLaTeX
    }
}
