import AppKit

@MainActor
final class macOSApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var workspace: NoteWorkspace?
    private weak var mainWindowCloseButton: NSButton?
    private var mayTerminate = false

    func configure(workspace: NoteWorkspace) {
        guard self.workspace !== workspace else { return }
        self.workspace = workspace
        workspace.terminationHandler = { [weak self] in
            guard let self else { return }
            self.mayTerminate = true
            NSApplication.shared.terminate(nil)
        }
    }

    func configureMainWindow(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              mainWindowCloseButton !== closeButton else {
            return
        }

        mainWindowCloseButton = closeButton
        closeButton.target = self
        closeButton.action = #selector(requestMainWindowTermination(_:))
    }

    @objc
    private func requestMainWindowTermination(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if mayTerminate {
            mayTerminate = false
            return .terminateNow
        }

        guard let workspace, workspace.requiresPackageSaveConfirmation else {
            return .terminateNow
        }

        workspace.requestTermination()
        return .terminateCancel
    }
}
