import AppKit

@MainActor
final class macOSApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var workspace: NoteWorkspace?
    private weak var mainWindowCloseButton: NSButton?
    private var mayTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainMenuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
        scheduleMainMenuConfiguration()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleMainMenuConfiguration()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(workspace: NoteWorkspace) {
        guard self.workspace !== workspace else { return }
        self.workspace = workspace
        workspace.terminationHandler = { [weak self] in
            guard let self else { return }
            self.mayTerminate = true
            NSApplication.shared.terminate(nil)
        }
        scheduleMainMenuConfiguration()
    }

    func configureMainWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar?.showsBaselineSeparator = false

        guard let closeButton = window.standardWindowButton(.closeButton),
              mainWindowCloseButton !== closeButton else {
            return
        }

        mainWindowCloseButton = closeButton
        closeButton.target = self
        closeButton.action = #selector(requestMainWindowTermination(_:))
        scheduleMainMenuConfiguration()
    }

    private func scheduleMainMenuConfiguration() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.configureMainMenu()
        }
    }

    private func configureMainMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              mainMenu.items.count >= 2 else {
            return
        }

        while mainMenu.items.count > 2 {
            mainMenu.removeItem(at: mainMenu.items.count - 1)
        }

        guard let applicationMenu = mainMenu.items.first?.submenu,
              let aboutItem = applicationMenu.items.first(
                where: { $0.title == "TeXNoteについて" }
              ),
              let settingsItem = applicationMenu.items.first(
                where: { $0.title.hasPrefix("設定") }
              ),
              let quitItem = applicationMenu.items.first(
                where: { $0.title.hasSuffix("を終了") }
              ) else {
            return
        }

        applicationMenu.removeAllItems()
        applicationMenu.addItem(aboutItem)
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(quitItem)
    }

    @objc
    private func mainMenuDidAddItem(_ notification: Notification) {
        guard let changedMenu = notification.object as? NSMenu,
              changedMenu === NSApplication.shared.mainMenu else {
            return
        }
        scheduleMainMenuConfiguration()
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
