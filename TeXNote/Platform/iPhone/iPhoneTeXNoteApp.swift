import SwiftUI

@main
struct iPhoneTeXNoteApp: App {
    @StateObject private var workspace = NoteWorkspace()

    var body: some Scene {
        WindowGroup {
            iOSTeXNoteRootView(
                workspace: workspace,
                editsCardTitleOnPreview: true
            )
        }
    }
}
