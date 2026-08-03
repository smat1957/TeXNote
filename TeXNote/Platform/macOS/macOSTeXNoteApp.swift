import SwiftUI

@main
struct macOSTeXNoteApp: App {
    @NSApplicationDelegateAdaptor(macOSApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var workspace = NoteWorkspace()

    var body: some Scene {
        WindowGroup {
            NoteContentView(workspace: workspace)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    applicationDelegate.configure(workspace: workspace)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新規") {
                    workspace.requestNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("開く…") {
                    workspace.requestOpen()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("最近使ったノート") {
                    if workspace.recentNotes.isEmpty {
                        Button("なし") {}
                            .disabled(true)
                    } else {
                        ForEach(workspace.recentNotes) { note in
                            Button(note.name) {
                                workspace.openRecent(note)
                            }
                        }

                        Divider()

                        Button("最近使ったノートを消去") {
                            workspace.clearRecentNotes()
                        }
                    }
                }
            }

            CommandGroup(replacing: .saveItem) {
                Button("保存") {
                    workspace.requestSave()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("名前をつけて保存…") {
                    workspace.requestSaveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            macOSSettingsView()
        }
    }
}
