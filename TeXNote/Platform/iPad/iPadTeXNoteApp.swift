import SwiftUI

@main
struct iPadTeXNoteApp: App {
    @StateObject private var workspace = NoteWorkspace()
    @StateObject private var authenticationSession =
        RemoteAuthenticationSession()

    var body: some Scene {
        WindowGroup {
            iOSTeXNoteRootView(
                workspace: workspace,
                authenticationSession: authenticationSession,
                showsAuthenticationInSidebar: true
            ) {
                iPadAuthenticationSettingsView(
                    authenticationSession: authenticationSession
                )
            }
        }
    }
}

private struct iPadAuthenticationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authenticationSession: RemoteAuthenticationSession
    @State private var serverURL = RemoteTeXCompilerFactory.savedServerURL
    @State private var email = RemoteTeXCompilerFactory.savedUserEmail
    @State private var password = ""
    @State private var statusMessage = ""
    @State private var isWorking = false

    var body: some View {
        Form {
            Section("P0公開サーバー") {
                TextField("サーバーURL", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                TextField("メールアドレス", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)

                SecureField("パスワード", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("例: http://192.168.20.10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await login() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Label("ログインして接続確認", systemImage: "person.badge.key")
                    }
                }
                .disabled(isWorking)

                Button("ログアウト", role: .destructive) {
                    authenticationSession.logout()
                    password = ""
                    statusMessage = "ログアウトしました。"
                }
                .disabled(isWorking)

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
        .navigationTitle("P0公開サーバー")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") { dismiss() }
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
