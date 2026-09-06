import Foundation

@MainActor
final class NoteWorkspace: ObservableObject {
    @Published var document = NoteDocument.starter
    @Published var noteName = "名称未設定"
    @Published var folderURL: URL?
    @Published var isFileSelectionPresented = false
    @Published private(set) var fileSelectionRequest: FileSelectionRequest?
    @Published var isNamingSaveAs = false
    @Published var saveAsNameDraft = ""
    @Published var errorMessage: String?
    @Published private(set) var fileOperationMessage: String?
    @Published var fileOperationCompletionMessage: String?
    @Published private(set) var hasUnsavedPackageChanges = true
    @Published private(set) var pendingUnsavedAction: PendingUnsavedAction?
    @Published private(set) var pendingOpenFolderURL: URL?
    @Published private(set) var pendingOverwriteSaveParentURL: URL?
    @Published private(set) var pendingOverwriteExportFolderURL: URL?
    @Published private(set) var pendingExportFileNameFolderURL: URL?
    @Published var exportFileNameDraft = ""
    @Published private(set) var exportConflictNames: [String] = []
    @Published private(set) var importedCardID: UUID?
    @Published private(set) var recentNotes: [RecentNote]
    private var pendingFolderAction: FolderAction?
    private var pendingSaveAsName: String?
    private var pendingImportInsertionCardID: UUID?
    private var pendingExportCardID: UUID?
    private var pendingExportFileName: String?
    private var packageAccessRootURL: URL?
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
        pendingUnsavedAction = .newNote
    }

    private func createNewNote() {
        document = .starter
        noteName = document.name
        folderURL = nil
        packageAccessRootURL = nil
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
        presentFileSelection(.packageFolder)
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
        if let folderURL,
           NotePackageNaming.matches(folderURL: folderURL, noteName: noteName) {
            fileOperationMessage = "保存しています…"
            Task { [weak self] in
                guard let self else { return }
                await Task.yield()
                self.errorMessage = nil
                await self.save(toExistingFolder: folderURL)
                self.fileOperationMessage = nil
                if self.errorMessage == nil {
                    self.fileOperationCompletionMessage = "保存が完了しました。"
                }
            }
        } else {
            requestSaveAs()
        }
    }

    func requestSaveAs() {
        saveAsNameDraft = noteName
        isNamingSaveAs = true
    }

    func requestTeXDocumentImport(insertingAfter cardID: UUID?) {
        pendingImportInsertionCardID = cardID
        presentFileSelection(.teXDocument)
    }

    func handleSelectedTeXDocument(_ sourceURL: URL) {
        let insertionCardID = pendingImportInsertionCardID
        pendingImportInsertionCardID = nil
        fileOperationCompletionMessage = nil
        fileOperationMessage = "TeX文書を取り込んでいます…"
        Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            do {
                let card = try await Self.performFileIO(accessing: [sourceURL]) {
                    try TeXDocumentTransferService.importedCard(from: sourceURL)
                }
                let insertionIndex = insertionCardID.flatMap { cardID in
                    self.document.cards.firstIndex(where: { $0.id == cardID })
                }.map { $0 + 1 } ?? self.document.cards.endIndex
                self.document.cards.insert(card, at: insertionIndex)
                self.documentDidChange()
                self.importedCardID = card.id
                self.errorMessage = nil
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.fileOperationMessage = nil
        }
    }

    func consumeImportedCardID() {
        importedCardID = nil
    }

    func requestCardExport(cardID: UUID) {
        guard folderURL != nil else {
            errorMessage = TeXDocumentTransferError
                .noteMustBeSavedBeforeExporting.localizedDescription
            return
        }
        pendingExportCardID = cardID
        pendingExportFileName = nil
        pendingExportFileNameFolderURL = nil
        presentFileSelection(.teXExportFolder)
    }

    func handleSelectedTeXExportFolder(_ destinationFolder: URL) {
        guard let cardID = pendingExportCardID,
              let card = document.cards.first(where: { $0.id == cardID }) else {
            pendingExportCardID = nil
            return
        }
        do {
            pendingExportFileName = try TeXDocumentTransferService
                .validatedExportBaseName(card.title)
            beginCardExport(to: destinationFolder, replacingExistingItems: false)
        } catch TeXDocumentTransferError.invalidCardTitle {
            exportFileNameDraft = card.title
            pendingExportFileNameFolderURL = destinationFolder
        } catch {
            pendingExportCardID = nil
            errorMessage = error.localizedDescription
        }
    }

    var isExportFileNameValid: Bool {
        (try? TeXDocumentTransferService.validatedExportBaseName(
            exportFileNameDraft
        )) != nil
    }

    func confirmExportFileName() {
        guard let folder = pendingExportFileNameFolderURL else { return }
        do {
            pendingExportFileName = try TeXDocumentTransferService
                .validatedExportBaseName(exportFileNameDraft)
            pendingExportFileNameFolderURL = nil
            beginCardExport(to: folder, replacingExistingItems: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelExportFileName() {
        pendingExportFileNameFolderURL = nil
        pendingExportFileName = nil
        pendingExportCardID = nil
    }

    func confirmOverwriteExport() {
        guard let folder = pendingOverwriteExportFolderURL else { return }
        pendingOverwriteExportFolderURL = nil
        exportConflictNames = []
        beginCardExport(to: folder, replacingExistingItems: true)
    }

    func cancelOverwriteExport() {
        pendingOverwriteExportFolderURL = nil
        exportConflictNames = []
        pendingExportCardID = nil
        pendingExportFileName = nil
    }

    private func beginCardExport(
        to destinationFolder: URL,
        replacingExistingItems: Bool
    ) {
        guard let cardID = pendingExportCardID,
              let card = document.cards.first(where: { $0.id == cardID }),
              let exportFileName = pendingExportFileName else {
            pendingExportCardID = nil
            pendingExportFileName = nil
            return
        }
        let sourceFolder = folderURL
        fileOperationCompletionMessage = nil
        fileOperationMessage = "記事をエクスポートしています…"
        Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            do {
                try await Self.performFileIO(
                    accessing: [sourceFolder, destinationFolder].compactMap { $0 }
                ) {
                    try TeXDocumentTransferService.export(
                        card: card,
                        fileName: exportFileName,
                        noteFolder: sourceFolder,
                        to: destinationFolder,
                        replacingExistingItems: replacingExistingItems
                    )
                }
                self.pendingExportCardID = nil
                self.pendingExportFileName = nil
                self.errorMessage = nil
                self.fileOperationCompletionMessage = "記事をエクスポートしました。"
            } catch let conflict as TeXDocumentTransferService.ExportConflict {
                self.pendingOverwriteExportFolderURL = destinationFolder
                self.exportConflictNames = conflict.itemNames
            } catch {
                self.pendingExportCardID = nil
                self.pendingExportFileName = nil
                self.errorMessage = error.localizedDescription
            }
            self.fileOperationMessage = nil
        }
    }

    func confirmSaveAsName() {
        let name = saveAsNameDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard Self.isValidNoteName(name) else {
            return
        }
        pendingSaveAsName = name
        isNamingSaveAs = false
        pendingFolderAction = .saveParent
        presentFileSelection(.packageFolder)
    }

    func cancelSaveAsName() {
        isNamingSaveAs = false
        pendingSaveAsName = nil
        actionAfterSuccessfulPackageSave = nil
    }

    var isSaveAsNameValid: Bool {
        Self.isValidNoteName(
            saveAsNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var overwriteSaveName: String {
        pendingSaveAsName ?? noteName
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

    func folderSelectionCancelled() {
        pendingFolderAction = nil
        pendingSaveAsName = nil
        actionAfterSuccessfulPackageSave = nil
    }

    func handleFileSelection(_ result: Result<[URL], Error>) {
        let request = fileSelectionRequest
        fileSelectionRequest = nil
        isFileSelectionPresented = false

        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                cancelFileSelection(request)
                return
            }
            switch request {
            case .packageFolder:
                handleSelectedFolder(url)
            case .teXDocument:
                handleSelectedTeXDocument(url)
            case .teXExportFolder:
                handleSelectedTeXExportFolder(url)
            case nil:
                break
            }
        case .failure(let error):
            cancelFileSelection(request)
            if (error as? CocoaError)?.code != .userCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func presentFileSelection(_ request: FileSelectionRequest) {
        fileSelectionRequest = request
        isFileSelectionPresented = true
    }

    private func cancelFileSelection(_ request: FileSelectionRequest?) {
        switch request {
        case .packageFolder:
            folderSelectionCancelled()
        case .teXDocument:
            pendingImportInsertionCardID = nil
        case .teXExportFolder:
            pendingExportCardID = nil
            pendingExportFileName = nil
        case nil:
            break
        }
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
        beginOpen(selectedFolder: selectedFolder, accessRootURL: selectedFolder)
    }

    private func beginOpen(selectedFolder: URL, accessRootURL: URL) {
        fileOperationMessage = "「\(selectedFolder.lastPathComponent)」を開いています…"
        Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            await self.openNow(
                selectedFolder: selectedFolder,
                accessRootURL: accessRootURL
            )
            self.fileOperationMessage = nil
        }
    }

    private func openNow(selectedFolder: URL, accessRootURL: URL) async {
        do {
            let loadedDocument = try await Self.performFileIO(
                accessing: [accessRootURL, selectedFolder]
            ) {
                let loadedDocument = try NoteFolderStore.load(
                    from: selectedFolder
                )
                if accessRootURL.standardizedFileURL
                    == selectedFolder.standardizedFileURL {
                    try PackageBookmarkStore.save(selectedFolder)
                } else {
                    try PackageBookmarkStore.save(
                        packageURL: selectedFolder,
                        accessRootURL: accessRootURL
                    )
                }
                return loadedDocument
            }
            document = loadedDocument
            noteName = NotePackageNaming.noteName(for: selectedFolder)
            document.name = noteName
            folderURL = selectedFolder
            packageAccessRootURL = accessRootURL
            hasUnsavedPackageChanges = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        if errorMessage == nil {
            addRecent(selectedFolder)
        }
        index()
    }

    private func prepareToOpen(selectedFolder folder: URL) {
        if document.cards.isEmpty {
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
        let name = pendingSaveAsName ?? noteName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard Self.isValidNoteName(name) else {
            pendingSaveAsName = nil
            actionAfterSuccessfulPackageSave = nil
            errorMessage = NoteFolderError.invalidName.localizedDescription
            return
        }
        let destinationFolderName = NotePackageNaming.folderName(for: name)
        let targetFolder = selectedParent.appending(
            path: destinationFolderName,
            directoryHint: .isDirectory
        )
        let accessGranted = selectedParent.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                selectedParent.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: targetFolder.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            pendingOverwriteSaveParentURL = selectedParent
            return
        }
        beginSave(selectedParent: selectedParent, name: name)
    }

    func confirmOverwriteSave() {
        guard let selectedParent = pendingOverwriteSaveParentURL else { return }
        let name = pendingSaveAsName ?? noteName
        pendingOverwriteSaveParentURL = nil
        beginSave(selectedParent: selectedParent, name: name)
    }

    func cancelOverwriteSave() {
        pendingOverwriteSaveParentURL = nil
        pendingSaveAsName = nil
        actionAfterSuccessfulPackageSave = nil
    }

    private func beginSave(selectedParent: URL, name: String) {
        fileOperationCompletionMessage = nil
        fileOperationMessage = "名前をつけて保存しています…"
        Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            self.errorMessage = nil
            await self.saveNow(selectedParent: selectedParent, name: name)
            self.fileOperationMessage = nil
            if self.errorMessage == nil {
                self.fileOperationCompletionMessage = "保存が完了しました。"
            }
        }
    }

    private func saveNow(selectedParent: URL, name: String) async {
        let snapshot = document
        let sourceFolder = folderURL
        let accessURLs = [
            selectedParent,
            packageAccessRootURL,
            sourceFolder
        ].compactMap { $0 }
        do {
            let result = try await Self.performFileIO(accessing: accessURLs) {
                let saved = try NoteFolderStore.save(
                    document: snapshot,
                    noteName: name,
                    parentFolder: selectedParent,
                    sourceNoteFolder: sourceFolder,
                    destinationFolderName: NotePackageNaming.folderName(for: name)
                )
                try PackageBookmarkStore.save(
                    packageURL: saved.folderURL,
                    accessRootURL: selectedParent
                )
                return SavedPackageResult(
                    folderURL: saved.folderURL,
                    document: saved.document
                )
            }
            folderURL = result.folderURL
            document = result.document
            noteName = name
            pendingSaveAsName = nil
            errorMessage = nil
        } catch {
            pendingSaveAsName = nil
            errorMessage = error.localizedDescription
        }
        if errorMessage == nil, let folderURL {
            packageAccessRootURL = selectedParent
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
        document.updatedAt = .now
        document.name = noteName
        hasUnsavedPackageChanges = true
        if let folderURL,
           NotePackageNaming.matches(folderURL: folderURL, noteName: noteName) {
            await save(toExistingFolder: folderURL)
        } else {
            index()
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

    private func save(toExistingFolder folder: URL) async {
        let name = noteName
        var preparedDocument = document
        preparedDocument.name = name
        let snapshot = preparedDocument
        do {
            let result = try await Self.performFileIO(
                accessing: [packageAccessRootURL, folder].compactMap { $0 }
            ) {
                let saved = try NoteFolderStore.save(
                    document: snapshot,
                    noteName: name,
                    parentFolder: folder.deletingLastPathComponent(),
                    sourceNoteFolder: folder,
                    destinationFolderName: folder.lastPathComponent
                )
                return SavedPackageResult(
                    folderURL: saved.folderURL,
                    document: saved.document
                )
            }
            document = result.document
            folderURL = result.folderURL
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
                self?.errorMessage = "作業状態を自動保存できませんでした:\n"
                    + error.localizedDescription
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
        access([url], operation: operation)
    }

    private static func isValidNoteName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains(":")
    }

    private func access(_ urls: [URL], operation: () throws -> Void) {
        var accessedURLs: [URL] = []
        var seenPaths: Set<String> = []
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                continue
            }
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }
        defer {
            for url in accessedURLs.reversed() {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated private static func performFileIO<Result: Sendable>(
        accessing urls: [URL],
        operation: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            var accessedURLs: [URL] = []
            var seenPaths: Set<String> = []
            for url in urls {
                let standardizedURL = url.standardizedFileURL
                guard seenPaths.insert(standardizedURL.path).inserted else {
                    continue
                }
                if url.startAccessingSecurityScopedResource() {
                    accessedURLs.append(url)
                }
            }
            defer {
                for url in accessedURLs.reversed() {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try operation()
        }.value
    }

    private func addRecent(_ folder: URL) {
        let standardizedPath = folder.standardizedFileURL.path
        recentNotes.removeAll { $0.path == standardizedPath }
        recentNotes.insert(
            RecentNote(
                name: NotePackageNaming.noteName(for: folder),
                path: standardizedPath
            ),
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
            folder = resolved.packageURL
            packageAccessRootURL = resolved.accessRootURL
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
        beginOpen(
            selectedFolder: folder,
            accessRootURL: packageAccessRootURL ?? folder
        )
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

private struct SavedPackageResult: Sendable {
    let folderURL: URL
    let document: NoteDocument
}

private enum FolderAction {
    case open
    case saveParent
}

enum FileSelectionRequest {
    case packageFolder
    case teXDocument
    case teXExportFolder
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

    var confirmationTitle: String {
        switch self {
        case .newNote:
            "新しいNoteを作成しますか？"
        case .openNote, .openRecent(_), .terminate:
            "Packageに保存されていない変更があります"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .newNote:
            "現在のNoteを閉じ、Cardがない真っ新な状態にします。"
        case .openNote, .openRecent(_), .terminate:
            "現在の変更はPortableなPackageに保存されていません。"
                + "保存しない場合、アプリ終了後には復元できません。"
        }
    }

    var destructiveButtonTitle: String {
        switch self {
        case .newNote:
            "新しいNoteにする"
        case .openNote, .openRecent(_), .terminate:
            discardButtonTitle
        }
    }
}
