import Foundation

/// Linux版組サービスとの通信を担当する共有クライアントです。
///
/// API:
/// POST <serverURL>/v1/typeset
/// Request JSON: TypesettingRequest
/// Success JSON: TypesettingResponse
actor RemoteTeXCompiler: TeXCompiling {
    private let serverURL: URL
    private let apiToken: String
    private let session: URLSession

    init(serverURL: URL, apiToken: String, session: URLSession = .shared) {
        self.serverURL = serverURL
        self.apiToken = apiToken
        self.session = session
    }

    func compile(
        card: TeXCard,
        pictures: [CardAsset],
        files: [CardAsset]
    ) async throws -> CompilationResult {
        let endpoint = serverURL.appending(path: "v1/typeset")
        guard let scheme = endpoint.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw CompilationError.invalidServerURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(apiToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.timeoutInterval = 120
        request.httpBody = try JSONEncoder().encode(
            TypesettingRequest(
                cardID: card.id,
                engine: card.engine,
                source: card.completeSource,
                pictures: pictures,
                files: files
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompilationError.unavailable(
                "版組サーバーから有効な応答を受信できませんでした。"
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(
                TypesettingErrorResponse.self,
                from: data
            ).message) ?? String(data: data, encoding: .utf8) ?? ""
            throw CompilationError.serverResponse(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        let result = try JSONDecoder().decode(TypesettingResponse.self, from: data)
        guard let pdfData = Data(base64Encoded: result.pdfBase64) else {
            throw CompilationError.pdfNotProduced(log: result.log)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "\(card.id.uuidString).pdf")
        try pdfData.write(to: outputURL, options: .atomic)
        return CompilationResult(pdfURL: outputURL, log: result.log)
    }
}

enum RemoteTeXCompilerFactory {
    static func isAvailable(for engine: TeXEngine) -> Bool {
        configuration != nil
    }

    static func make() -> any TeXCompiling {
        guard let configuration else {
            return UnavailableRemoteTeXCompiler()
        }
        return RemoteTeXCompiler(
            serverURL: configuration.url,
            apiToken: configuration.token
        )
    }

    private static var configuration: (url: URL, token: String)? {
        guard let value = UserDefaults.standard.string(
                  forKey: "typesettingServerURL"
              ),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        let token = TypesettingServerTokenStore.load()
        guard !token.isEmpty else { return nil }
        return (url, token)
    }
}

private actor UnavailableRemoteTeXCompiler: TeXCompiling {
    func compile(
        card: TeXCard,
        pictures: [CardAsset],
        files: [CardAsset]
    ) async throws -> CompilationResult {
        throw CompilationError.unavailable(
            "版組サーバーのURLまたはAPIトークンが設定されていません。"
        )
    }
}

private struct TypesettingRequest: Encodable {
    let cardID: UUID
    let engine: TeXEngine
    let source: String
    let pictures: [CardAsset]
    let files: [CardAsset]
}

private struct TypesettingResponse: Decodable {
    let pdfBase64: String
    let log: String
}

private struct TypesettingErrorResponse: Decodable {
    let message: String
}

