import AppKit

@MainActor
final class macOSApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var workspace: NoteWorkspace?
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
