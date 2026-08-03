import Foundation

@MainActor
final class NoteWorkspace: ObservableObject {
    @Published var document = NoteDocument.starter
    @Published var noteName = "名称未設定"
    @Published var folderURL: URL?
    @Published var isChoosingFolder = false
    @Published var errorMessage: String?
    @Published private(set) var hasUnsavedPackageChanges = true
    @Published private(set) var pendingUnsavedAction: PendingUnsavedAction?
    @Published private(set) var pendingOpenFolderURL: URL?
    @Published private(set) var recentNotes: [RecentNote]
    private var pendingFolderAction: FolderAction?
    private var actionAfterSuccessfulPackageSave: PendingUnsavedAction?
    private var persistenceTask: Task<Void, Never>?
    var terminationHandler: (() -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: "recentNotes"),
           let notes = try? JSONDecoder().decode([RecentNote].self, from: data) {
            recentNotes = notes
        } else {
            recentNotes = []
        }
        restoreLastPackageIfAvailable()
    }

    func requestNewNote() {
        guard requiresPackageSaveConfirmation else {
            createNewNote()
            return
        }
        pendingUnsavedAction = .newNote
    }

    private func createNewNote() {
        document = .starter
        noteName = document.name
        folderURL = nil
        hasUnsavedPackageChanges = true
        errorMessage = nil
        PackageBookmarkStore.clear()
        index()
    }

    func requestOpen() {
        guard !requiresOpenPackageSaveConfirmation else {
            pendingUnsavedAction = .openNote
            return
        }
        beginChoosingNoteToOpen()
    }

    private func beginChoosingNoteToOpen() {
        pendingFolderAction = .open
        isChoosingFolder = true
    }

    func requestTermination() {
        guard requiresPackageSaveConfirmation else {
            terminationHandler?()
            return
        }
        pendingUnsavedAction = .terminate
    }

    func saveBeforePendingAction() {
        guard let action = pendingUnsavedAction else { return }
        pendingUnsavedAction = nil
        actionAfterSuccessfulPackageSave = action
        requestSave()
    }

    func discardAndContinuePendingAction() {
        guard let action = pendingUnsavedAction else { return }
        pendingUnsavedAction = nil
        continueAfterUnsavedDecision(action)
    }

    func cancelPendingUnsavedAction() {
        pendingUnsavedAction = nil
        actionAfterSuccessfulPackageSave = nil
    }

    func requestSave() {
        if let folderURL, folderURL.lastPathComponent == noteName {
            save(toExistingFolder: folderURL)
        } else {
            requestSaveAs()
        }
    }

    func requestSaveAs() {
        pendingFolderAction = .saveParent
        isChoosingFolder = true
    }

    func handleSelectedFolder(_ folder: URL) {
        let action = pendingFolderAction
        pendingFolderAction = nil
        switch action {
        case .open:
            prepareToOpen(selectedFolder: folder)
        case .saveParent:
            save(selectedParent: folder)
        case nil:
            break
        }
    }

    func folderSelectionFailed(_ error: Error) {
        pendingFolderAction = nil
        actionAfterSuccessfulPackageSave = nil
        errorMessage = error.localizedDescription
    }

    func folderSelectionCancelled() {
        pendingFolderAction = nil
        actionAfterSuccessfulPackageSave = nil
    }

    func confirmPendingOpen() {
        guard let folder = pendingOpenFolderURL else { return }
        pendingOpenFolderURL = nil
        open(selectedFolder: folder)
    }

    func cancelPendingOpen() {
        pendingOpenFolderURL = nil
    }

    func open(selectedFolder: URL) {
        access(selectedFolder) {
            document = try NoteFolderStore.load(from: selectedFolder)
            noteName = selectedFolder.lastPathComponent
            document.name = noteName
            folderURL = selectedFolder
            hasUnsavedPackageChanges = false
            try PackageBookmarkStore.save(selectedFolder)
            errorMessage = nil
        }
        if errorMessage == nil {
            addRecent(selectedFolder)
        }
        index()
    }

    private func prepareToOpen(selectedFolder folder: URL) {
        let selectedName = folder.lastPathComponent
        if selectedName == noteName {
            open(selectedFolder: folder)
        } else {
            pendingOpenFolderURL = folder
        }
    }

    func openRecent(_ recentNote: RecentNote) {
        guard !requiresOpenPackageSaveConfirmation else {
            pendingUnsavedAction = .openRecent(recentNote)
            return
        }
        openRecentAfterConfirmation(recentNote)
    }

    private func openRecentAfterConfirmation(_ recentNote: RecentNote) {
        let folder = URL(filePath: recentNote.path, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            errorMessage = "Noteフォルダが見つかりません:\n\(folder.path)"
            removeRecent(recentNote)
            return
        }
        open(selectedFolder: folder)
    }

    func clearRecentNotes() {
        recentNotes = []
        persistRecentNotes()
    }

    func save(selectedParent: URL) {
        access(selectedParent) {
            document.name = noteName
            folderURL = try NoteFolderStore.save(
                document: document,
                noteName: noteName,
                parentFolder: selectedParent,
                sourceNoteFolder: folderURL
            )
            if let folderURL {
                try PackageBookmarkStore.save(folderURL)
            }
            errorMessage = nil
        }
        if errorMessage == nil, let folderURL {
            hasUnsavedPackageChanges = false
            addRecent(folderURL)
            finishSuccessfulPackageSave()
        } else {
            actionAfterSuccessfulPackageSave = nil
            index()
        }
    }

    func documentDidChange() {
        document.updatedAt = .now
        document.name = noteName
        hasUnsavedPackageChanges = true
        index()
    }

    func cardEditorDidSave() async {
        documentDidChange()
        if let folderURL, folderURL.lastPathComponent == noteName {
            save(toExistingFolder: folderURL)
        }
        await persistenceTask?.value
    }

    func noteNameDidChange() {
        guard document.name != noteName else { return }
        document.name = noteName
        document.updatedAt = .now
        hasUnsavedPackageChanges = true
        index()
    }

    private func save(toExistingFolder folder: URL) {
        let parent = folder.deletingLastPathComponent()
        access(folder) {
            document.name = noteName
            folderURL = try NoteFolderStore.save(
                document: document,
                noteName: noteName,
                parentFolder: parent,
                sourceNoteFolder: folder
            )
            if let folderURL {
                try PackageBookmarkStore.save(folderURL)
            }
            errorMessage = nil
        }
        if errorMessage == nil, let folderURL {
            hasUnsavedPackageChanges = false
            addRecent(folderURL)
            finishSuccessfulPackageSave()
        } else {
            actionAfterSuccessfulPackageSave = nil
            index()
        }
    }

    private func index() {
        let snapshot = document
        let name = noteName
        let url = folderURL
        let previousTask = persistenceTask
        persistenceTask = Task { [weak self] in
            await previousTask?.value
            do {
                try await AppDatabase.shared.index(
                    document: snapshot,
                    noteName: name,
                    folderURL: url
                )
            } catch {
                self?.errorMessage = "作業状態を自動保存できませんでした:\n\(error.localizedDescription)"
            }
        }
    }

    var requiresPackageSaveConfirmation: Bool {
        folderURL == nil || hasUnsavedPackageChanges
    }

    private var requiresOpenPackageSaveConfirmation: Bool {
        !document.cards.isEmpty && requiresPackageSaveConfirmation
    }

    private func finishSuccessfulPackageSave() {
        let action = actionAfterSuccessfulPackageSave
        actionAfterSuccessfulPackageSave = nil
        index()

        guard let action else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.persistenceTask?.value
            self.continueAfterUnsavedDecision(action)
        }
    }

    private func continueAfterUnsavedDecision(_ action: PendingUnsavedAction) {
        switch action {
        case .newNote:
            createNewNote()
        case .openNote:
            beginChoosingNoteToOpen()
        case .openRecent(let recentNote):
            openRecentAfterConfirmation(recentNote)
        case .terminate:
            terminationHandler?()
        }
    }

    private func access(_ url: URL, operation: () throws -> Void) {
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addRecent(_ folder: URL) {
        let standardizedPath = folder.standardizedFileURL.path
        recentNotes.removeAll { $0.path == standardizedPath }
        recentNotes.insert(
            RecentNote(name: folder.lastPathComponent, path: standardizedPath),
            at: 0
        )
        if recentNotes.count > 10 {
            recentNotes.removeLast(recentNotes.count - 10)
        }
        persistRecentNotes()
    }

    private func restoreLastPackageIfAvailable() {
        let folder: URL
        do {
            guard let resolved = try PackageBookmarkStore.resolve() else {
                index()
                return
            }
            folder = resolved
        } catch {
            PackageBookmarkStore.clear()
            errorMessage = "最後に開いたPackageへアクセスできませんでした:\n"
                + error.localizedDescription
            index()
            return
        }
        guard FileManager.default.fileExists(atPath: folder.path) else {
            PackageBookmarkStore.clear()
            index()
            return
        }
        open(selectedFolder: folder)
    }

    private func removeRecent(_ recentNote: RecentNote) {
        recentNotes.removeAll { $0.id == recentNote.id }
        persistRecentNotes()
    }

    private func persistRecentNotes() {
        if let data = try? JSONEncoder().encode(recentNotes) {
            UserDefaults.standard.set(data, forKey: "recentNotes")
        }
    }
}

private enum FolderAction {
    case open
    case saveParent
}

struct RecentNote: Identifiable, Codable, Hashable {
    var id: String { path }
    let name: String
    let path: String
}

enum PendingUnsavedAction {
    case newNote
    case openNote
    case openRecent(RecentNote)
    case terminate

    var discardButtonTitle: String {
        switch self {
        case .newNote: "保存せず新規作成"
        case .openNote, .openRecent(_): "保存せず開く"
        case .terminate: "保存せず終了"
        }
    }
}
