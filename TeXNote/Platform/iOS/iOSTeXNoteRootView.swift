import SwiftUI

struct iOSTeXNoteRootView: View {
    @ObservedObject var workspace: NoteWorkspace
    let editsCardTitleOnPreview: Bool
    @State private var isShowingSettings = false

    init(
        workspace: NoteWorkspace,
        editsCardTitleOnPreview: Bool = false
    ) {
        self.workspace = workspace
        self.editsCardTitleOnPreview = editsCardTitleOnPreview
    }

    var body: some View {
        NoteContentView(
            workspace: workspace,
            editsCardTitleOnPreview: editsCardTitleOnPreview,
            settingsAction: {
                isShowingSettings = true
            }
        )
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                RemoteTypesettingSettingsView()
            }
        }
    }
}

private struct RemoteTypesettingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = UserDefaults.standard.string(
        forKey: "typesettingServerURL"
    ) ?? "http://192.168.3.11:8000"
    @State private var apiToken = TypesettingServerTokenStore.load()
    @State private var statusMessage = ""
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("版組サーバー") {
                TextField("サーバーURL", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                SecureField("APIトークン", text: $apiToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("例: http://192.168.3.11:8000")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Label("保存して接続テスト", systemImage: "network")
                    }
                }
                .disabled(isTesting)

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
        .navigationTitle("版組サーバー")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") { dismiss() }
            }
        }
    }

    @MainActor
    private func saveAndTest() async {
        isTesting = true
        defer { isTesting = false }

        let normalizedURL = serverURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedToken = apiToken.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let baseURL = URL(string: normalizedURL),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !normalizedToken.isEmpty else {
            statusMessage = "URLとAPIトークンを確認してください。"
            return
        }

        do {
            try TypesettingServerTokenStore.save(normalizedToken)
            UserDefaults.standard.set(
                normalizedURL,
                forKey: "typesettingServerURL"
            )

            var request = URLRequest(
                url: baseURL.appending(path: "v1/auth-check")
            )
            request.timeoutInterval = 10
            request.setValue(
                "Bearer \(normalizedToken)",
                forHTTPHeaderField: "Authorization"
            )
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                statusMessage = "接続失敗：URLまたはトークンを確認してください。"
                return
            }
            statusMessage = "接続成功：版組サーバーを利用できます。"
        } catch {
            statusMessage = "接続失敗：\(error.localizedDescription)"
        }
    }
}
