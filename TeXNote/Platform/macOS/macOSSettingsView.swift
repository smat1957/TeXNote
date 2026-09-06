import SwiftUI

struct macOSSettingsView: View {
    @ObservedObject var authenticationSession: RemoteAuthenticationSession
    @AppStorage(TeXCompilerFactory.typesettingModeDefaultsKey)
    private var typesettingMode = macOSTypesettingMode.local.rawValue
    @AppStorage("compilerPath")
    private var compilerPath = "/Library/TeX/texbin"

    @State private var serverURL = RemoteTeXCompilerFactory.savedServerURL
    @State private var email = RemoteTeXCompilerFactory.savedUserEmail
    @State private var password = ""
    @State private var statusMessage = ""
    @State private var isWorking = false

    var body: some View {
        Form {
            Picker("版組方法", selection: $typesettingMode) {
                ForEach(macOSTypesettingMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            if typesettingMode == macOSTypesettingMode.local.rawValue {
                Section("ローカルTeX") {
                    TextField("TeXバイナリのフォルダ", text: $compilerPath)
                    Text("通常のMacTeXでは /Library/TeX/texbin を使用します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                remoteAuthenticationSection
            }
        }
        .padding()
        .frame(width: 560)
    }

    private var remoteAuthenticationSection: some View {
        Section("P0公開サーバー") {
            TextField("サーバーURL", text: $serverURL)

            TextField("メールアドレス", text: $email)

            SecureField("パスワード", text: $password)

            Text("例: http://192.168.20.10")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("ログインして接続確認") {
                    Task { await login() }
                }
                .disabled(isWorking)

                Button("ログアウト", role: .destructive) {
                    authenticationSession.logout()
                    password = ""
                    statusMessage = "ログアウトしました。"
                }
                .disabled(isWorking)

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(
                        statusMessage.hasPrefix("接続成功")
                            ? Color.green
                            : Color.red
                    )
            }
        }
    }

    @MainActor
    private func login() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await authenticationSession.login(
                serverURL: serverURL,
                email: email,
                password: password
            )
            password = ""
            statusMessage = "接続成功：P0経由で版組できます。"
        } catch {
            statusMessage = "接続失敗：\(error.localizedDescription)"
        }
    }
}
