import AppKit
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
                .background {
                    macOSMainWindowReader { window in
                        applicationDelegate.configureMainWindow(window)
                    }
                }
                .onAppear {
                    applicationDelegate.configure(workspace: workspace)
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                macOSAboutMenuCommand()
            }

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

        Window("TeXNoteについて", id: "about") {
            TeXNoteAboutView()
        }
        .windowResizability(.contentSize)
    }
}

private struct macOSMainWindowReader: NSViewRepresentable {
    let resolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> macOSMainWindowReaderView {
        let view = macOSMainWindowReaderView()
        view.resolve = resolve
        return view
    }

    func updateNSView(
        _ nsView: macOSMainWindowReaderView,
        context: Context
    ) {
        nsView.resolve = resolve
        nsView.resolveWindowIfAvailable()
    }
}

private final class macOSMainWindowReaderView: NSView {
    var resolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindowIfAvailable()
    }

    func resolveWindowIfAvailable() {
        guard let window else { return }
        resolve?(window)
    }
}
