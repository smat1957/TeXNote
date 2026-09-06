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
    var pictureRelativePaths: [String]
    var fileRelativePaths: [String]
    var pdfData: Data? = nil
    var pdfNeedsSaving = false
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
        pictureRelativePaths: [String] = [],
        fileRelativePaths: [String] = [],
        pdfData: Data? = nil,
        pdfNeedsSaving: Bool = false,
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
            ?? "Cards/\(id.uuidString)/pics"
        self.filesRelativePath = filesRelativePath
            ?? "Cards/\(id.uuidString)/files"
        self.pictureRelativePaths = pictureRelativePaths
        self.fileRelativePaths = fileRelativePaths
        self.pdfData = pdfData
        self.pdfNeedsSaving = pdfNeedsSaving
        self.compiledSourceHash = compiledSourceHash
        self.lastTypesetAt = lastTypesetAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var completeSource: String {
        sourcePrefixThroughDocumentBegin
            + body
            + "\n\\end{document}"
    }

    var preambleFirstLineNumber: Int {
        logicalLineCount(in: documentClassLine) + 1
    }

    var bodyFirstLineNumber: Int {
        sourcePrefixThroughDocumentBegin.reduce(1) {
            $1 == "\n" ? $0 + 1 : $0
        }
    }

    private var sourcePrefixThroughDocumentBegin: String {
        documentClassLine
            + "\n"
            + preamble
            + "\n\n\\begin{document}\n"
    }

    private func logicalLineCount(in text: String) -> Int {
        text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
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
        case pictureRelativePaths
        case fileRelativePaths
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
        pictureRelativePaths = try container.decode(
            [String].self,
            forKey: .pictureRelativePaths
        )
        fileRelativePaths = try container.decode(
            [String].self,
            forKey: .fileRelativePaths
        )
        pdfData = nil
        pdfNeedsSaving = false
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
