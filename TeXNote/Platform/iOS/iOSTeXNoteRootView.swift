import SwiftUI

/// iPad版とiPhone版で共通する画面遷移だけを担当します。
/// 設定画面のUIは各プラットフォームから注入します。
struct iOSTeXNoteRootView<SettingsView: View>: View {
    @ObservedObject var workspace: NoteWorkspace
    @ObservedObject var authenticationSession: RemoteAuthenticationSession
    @State private var isShowingSettings = false
    private let showsAuthenticationInSidebar: Bool
    private let initialCompactColumn: NavigationSplitViewColumn
    private let extendsDetailIntoTopSafeArea: Bool
    private let detailTopSafeAreaInset: CGFloat
    private let settingsView: () -> SettingsView

    init(
        workspace: NoteWorkspace,
        authenticationSession: RemoteAuthenticationSession,
        showsAuthenticationInSidebar: Bool,
        initialCompactColumn: NavigationSplitViewColumn = .sidebar,
        extendsDetailIntoTopSafeArea: Bool = false,
        detailTopSafeAreaInset: CGFloat = 0,
        @ViewBuilder settingsView: @escaping () -> SettingsView
    ) {
        self.workspace = workspace
        self.authenticationSession = authenticationSession
        self.showsAuthenticationInSidebar = showsAuthenticationInSidebar
        self.initialCompactColumn = initialCompactColumn
        self.extendsDetailIntoTopSafeArea = extendsDetailIntoTopSafeArea
        self.detailTopSafeAreaInset = detailTopSafeAreaInset
        self.settingsView = settingsView
    }

    var body: some View {
        NoteContentView(
            workspace: workspace,
            authenticationSession: authenticationSession,
            settingsAction: {
                isShowingSettings = true
            },
            showsAuthenticationInSidebar: showsAuthenticationInSidebar,
            initialCompactColumn: initialCompactColumn,
            extendsDetailIntoTopSafeArea: extendsDetailIntoTopSafeArea,
            detailTopSafeAreaInset: detailTopSafeAreaInset
        )
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                settingsView()
            }
        }
    }
}
