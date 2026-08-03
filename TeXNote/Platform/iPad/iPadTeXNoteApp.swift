import SwiftUI

@main
struct iPadTeXNoteApp: App {
    @StateObject private var workspace = NoteWorkspace()

    var body: some Scene {
        WindowGroup {
            iOSTeXNoteRootView(workspace: workspace)
        }
    }
}
