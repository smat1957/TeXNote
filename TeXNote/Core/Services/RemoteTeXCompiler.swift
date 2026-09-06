import Foundation

/// P0公開入口からP1認証サーバーを経由し、P2で版組する共有クライアントです。
///
/// ユーザーはP1やP2へ直接接続しません。P0の`POST /compile`へユーザーJWTを送り、
/// P0がP1へ、P1が内部トークンを付けてP2の`POST /v1/typeset`へ中継します。
actor RemoteTeXCompiler: TeXCompiling {
    private let serverURL: URL
    private let accessToken: String
    private let session: URLSession

    init(
        serverURL: URL,
        accessToken: String,
        session: URLSession = .shared
    ) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.session = session
    }

    func compile(
        card: TeXCard,
        pictures: [CardAsset],
        files: [CardAsset]
    ) async throws -> CompilationResult {
        let endpoint = try RemoteTeXCompilerFactory.endpoint(
            baseURL: serverURL,
            path: "compile"
        )
        var request = RemoteTeXCompilerFactory.authorizedRequest(
            url: endpoint,
            accessToken: accessToken
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(
            CompileRequest(
                engine: card.engine,
                source: card.completeSource,
                pictures: pictures,
                files: files
            )
        )

        let (data, response) = try await session.data(for: request)
        let httpResponse = try RemoteTeXCompilerFactory.httpResponse(response)
        try RemoteTeXCompilerFactory.validate(
            httpResponse: httpResponse,
            data: data
        )

        let result = try JSONDecoder().decode(CompileResponse.self, from: data)
        guard let pdfData = Data(base64Encoded: result.pdfBase64) else {
            throw CompilationError.pdfNotProduced(log: result.log)
        }

        return CompilationResult(pdfData: pdfData, log: result.log)
    }
}

enum RemoteTeXCompilerFactory {
    static let serverURLDefaultsKey = "typesettingServerURL"
    static let userEmailDefaultsKey = "typesettingUserEmail"
    static let defaultServerURL = "http://192.168.3.22:8080"

    private static let legacyP1ServerURLs: Set<String> = [
        "http://192.168.3.21",
        "http://192.168.3.21:8000",
        "http://192.168.3.22",
        "http://192.168.30.10",
        "http://192.168.30.10:8000"
    ]

    static func isAvailable(for engine: TeXEngine) -> Bool {
        configuration != nil
    }

    static func make() -> any TeXCompiling {
        guard let configuration else {
            return UnavailableRemoteTeXCompiler()
        }
        return RemoteTeXCompiler(
            serverURL: configuration.url,
            accessToken: configuration.accessToken
        )
    }

    /// P0経由でログインし、P0 URL・メールアドレス・ユーザーJWTを保存します。
    @discardableResult
    static func login(
        serverURL: String,
        email: String,
        password: String,
        session: URLSession = .shared
    ) async throws -> RemoteAccount {
        let normalizedURL = serverURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            throw CompilationError.authenticationRequired(
                "メールアドレスとパスワードを入力してください。"
            )
        }

        let baseURL = try validatedBaseURL(normalizedURL)
        let endpoint = try endpoint(baseURL: baseURL, path: "login")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            LoginRequest(
                email: normalizedEmail,
                password: password,
                service: "texnote"
            )
        )

        let (data, response) = try await session.data(for: request)
        let httpResponse = try httpResponse(response)
        try validate(
            httpResponse: httpResponse,
            data: data,
            invalidatesStoredSession: false
        )
        let loginResponse = try JSONDecoder().decode(
            LoginResponse.self,
            from: data
        )

        // 保存前にP0経由で/meを呼び、JWTが実際に有効か確認します。
        let account = try await validateSession(
            serverURL: baseURL,
            accessToken: loginResponse.accessToken,
            session: session,
            invalidatesStoredSession: false
        )

        try TypesettingServerTokenStore.save(loginResponse.accessToken)
        UserDefaults.standard.set(
            normalizedURL,
            forKey: serverURLDefaultsKey
        )
        UserDefaults.standard.set(
            normalizedEmail,
            forKey: userEmailDefaultsKey
        )
        return account
    }

    static func logout() {
        TypesettingServerTokenStore.delete()
    }

    static var savedServerURL: String {
        migratedStoredServerURL() ?? defaultServerURL
    }

    static var savedUserEmail: String {
        UserDefaults.standard.string(forKey: userEmailDefaultsKey) ?? ""
    }

    static func currentAccount(
        session: URLSession = .shared
    ) async throws -> RemoteAccount? {
        guard let configuration else { return nil }
        return try await validateSession(
            serverURL: configuration.url,
            accessToken: configuration.accessToken,
            session: session
        )
    }

    fileprivate static func endpoint(baseURL: URL, path: String) throws -> URL {
        let validatedURL = try validatedBaseURL(baseURL.absoluteString)
        return validatedURL.appending(path: path)
    }

    fileprivate static func authorizedRequest(
        url: URL,
        accessToken: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    fileprivate static func httpResponse(
        _ response: URLResponse
    ) throws -> HTTPURLResponse {
        guard let response = response as? HTTPURLResponse else {
            throw CompilationError.unavailable(
                "P0公開サーバーから有効な応答を受信できませんでした。"
            )
        }
        return response
    }

    fileprivate static func validate(
        httpResponse: HTTPURLResponse,
        data: Data,
        invalidatesStoredSession: Bool = true
    ) throws {
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = ServerErrorResponse.message(from: data)
            if httpResponse.statusCode == 401 {
                if invalidatesStoredSession {
                    TypesettingServerTokenStore.delete()
                }
                throw CompilationError.authenticationRequired(
                    invalidatesStoredSession
                        ? "ログインの有効期限が切れました。再ログインしてください。"
                        : (message.isEmpty ? "ログインに失敗しました。" : message)
                )
            }
            throw CompilationError.serverResponse(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
    }

    private static var configuration: (
        url: URL,
        accessToken: String
    )? {
        guard let value = migratedStoredServerURL(),
              let url = try? validatedBaseURL(value) else {
            return nil
        }
        let accessToken = TypesettingServerTokenStore.load()
        guard !accessToken.isEmpty else { return nil }
        return (url, accessToken)
    }

    private static func validatedBaseURL(_ value: String) throws -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            throw CompilationError.invalidServerURL
        }
        return url
    }

    private static func migratedStoredServerURL() -> String? {
        guard let storedURL = UserDefaults.standard.string(
            forKey: serverURLDefaultsKey
        ) else {
            return nil
        }
        let normalizedURL = storedURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard legacyP1ServerURLs.contains(normalizedURL) else {
            return storedURL
        }
        UserDefaults.standard.set(
            defaultServerURL,
            forKey: serverURLDefaultsKey
        )
        return defaultServerURL
    }

    private static func validateSession(
        serverURL: URL,
        accessToken: String,
        session: URLSession,
        invalidatesStoredSession: Bool = true
    ) async throws -> RemoteAccount {
        let endpoint = try endpoint(baseURL: serverURL, path: "me")
        let request = authorizedRequest(
            url: endpoint,
            accessToken: accessToken
        )
        let (data, response) = try await session.data(for: request)
        let httpResponse = try httpResponse(response)
        try validate(
            httpResponse: httpResponse,
            data: data,
            invalidatesStoredSession: invalidatesStoredSession
        )
        let account = try JSONDecoder().decode(RemoteAccount.self, from: data)
        guard account.service == "texnote" else {
            throw CompilationError.authenticationRequired(
                "TeXNote用ではないP0入口が指定されています。サーバーURLとポート番号を確認してください。"
            )
        }
        return account
    }
}

private actor UnavailableRemoteTeXCompiler: TeXCompiling {
    func compile(
        card: TeXCard,
        pictures: [CardAsset],
        files: [CardAsset]
    ) async throws -> CompilationResult {
        throw CompilationError.authenticationRequired(
            "P0公開サーバーへログインしてください。"
        )
    }
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
    let service: String
}

private struct LoginResponse: Decodable {
    let accessToken: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct RemoteAccount: Decodable, Equatable {
    let service: String
    let id: Int
    let email: String
    let plan: RemotePlan
    let status: String
    let used: Int
    let limit: Int
}

enum RemotePlan: String, Decodable {
    case free
    case standard
    case pro

    var displayName: String {
        switch self {
        case .free: "Free"
        case .standard: "Standard"
        case .pro: "Pro"
        }
    }
}

private struct CompileRequest: Encodable {
    let engine: TeXEngine
    let source: String
    let pictures: [CardAsset]
    let files: [CardAsset]
}

private struct CompileResponse: Decodable {
    let pdfBase64: String
    let log: String
}

private struct ServerErrorResponse: Decodable {
    let detail: Detail

    static func message(from data: Data) -> String {
        if let response = try? JSONDecoder().decode(Self.self, from: data) {
            return response.detail.message
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    enum Detail: Decodable {
        case text(String)
        case object(
            message: String,
            plan: String?,
            limit: Int?,
            used: Int?,
            p2Detail: String?
        )

        var message: String {
            switch self {
            case .text(let message):
                return Self.localized(message)
            case .object(
                let message,
                let plan,
                let limit,
                let used,
                let p2Detail
            ):
                if let p2Detail,
                   !p2Detail.trimmingCharacters(
                       in: .whitespacesAndNewlines
                   ).isEmpty {
                    return p2Detail
                }
                let localizedMessage = Self.localized(message)
                guard let plan, let limit, let used else {
                    return localizedMessage
                }
                return "\(localizedMessage)（plan: \(plan), \(used)/\(limit)）"
            }
        }

        private static func localized(_ message: String) -> String {
            switch message {
            case "Invalid email or password":
                "メールアドレスまたはパスワードが正しくありません。"
            case "Invalid token", "Invalid or expired token":
                "ログイン情報が無効、または有効期限切れです。"
            case "User not found":
                "ユーザーが見つかりません。"
            case "User is inactive":
                "このユーザーは利用停止中です。"
            case "Monthly compile limit exceeded":
                "月間コンパイル回数の上限に達しました。"
            default:
                message
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let message = try? container.decode(String.self) {
                self = .text(message)
                return
            }
            let object = try container.decode(Object.self)
            self = .object(
                message: object.message,
                plan: object.plan,
                limit: object.limit,
                used: object.used,
                p2Detail: object.p2Detail
            )
        }

        private struct Object: Decodable {
            let message: String
            let plan: String?
            let limit: Int?
            let used: Int?
            let p2Detail: String?

            private enum CodingKeys: String, CodingKey {
                case message
                case plan
                case limit
                case used
                case p2Detail = "p2_detail"
            }
        }
    }
}
