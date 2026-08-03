import SwiftUI
import UniformTypeIdentifiers

extension View {
    func noteWorkspacePresentation(
        workspace: NoteWorkspace,
        editingCardID: Binding<UUID?>,
        newCardID: Binding<UUID?>
    ) -> some View {
        modifier(
            NoteWorkspacePresentationModifier(
                workspace: workspace,
                editingCardID: editingCardID,
                newCardID: newCardID
            )
        )
    }
}

private struct NoteWorkspacePresentationModifier: ViewModifier {
    @ObservedObject var workspace: NoteWorkspace
    @Binding var editingCardID: UUID?
    @Binding var newCardID: UUID?

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            .sheet(
                isPresented: Binding(
                    get: { editingCardID != nil },
                    set: { if !$0 { editingCardID = nil } }
                ),
                onDismiss: discardUncommittedCard
            ) {
                if let cardID = editingCardID,
                   let index = workspace.document.cards.firstIndex(
                       where: { $0.id == cardID }
                   ) {
                    CardEditorView(
                        card: $workspace.document.cards[index],
                        noteFolder: workspace.folderURL,
                        pictures: NoteFolderStore.loadResources(
                            for: workspace.document.cards[index],
                            kind: .pictures,
                            from: workspace.folderURL
                        ),
                        files: NoteFolderStore.loadResources(
                            for: workspace.document.cards[index],
                            kind: .files,
                            from: workspace.folderURL
                        ),
                        isNewCard: newCardID == cardID,
                        creationCommitted: {
                            if newCardID == cardID {
                                newCardID = nil
                            }
                        }
                    ) {
                        await workspace.cardEditorDidSave()
                    }
                    .frame(
                        width: min(1_100, geometry.size.width),
                        height: min(760, geometry.size.height)
                    )
                }
            }
            .fileImporter(
                isPresented: $workspace.isChoosingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let folder = urls.first {
                        workspace.handleSelectedFolder(folder)
                    } else {
                        workspace.folderSelectionCancelled()
                    }
                case .failure(let error):
                    workspace.folderSelectionFailed(error)
                }
            }
            .alert(
                "TeXNote",
                isPresented: Binding(
                    get: { workspace.errorMessage != nil },
                    set: { if !$0 { workspace.errorMessage = nil } }
                )
            ) {
                Button("OK") { workspace.errorMessage = nil }
            } message: {
                Text(workspace.errorMessage ?? "")
            }
            .confirmationDialog(
                "Packageに保存されていない変更があります",
                isPresented: Binding(
                    get: { workspace.pendingUnsavedAction != nil },
                    set: { if !$0 { workspace.cancelPendingUnsavedAction() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Packageに保存…") {
                    workspace.saveBeforePendingAction()
                }
                if let action = workspace.pendingUnsavedAction {
                    Button(action.discardButtonTitle, role: .destructive) {
                        workspace.discardAndContinuePendingAction()
                    }
                }
                Button("キャンセル", role: .cancel) {
                    workspace.cancelPendingUnsavedAction()
                }
            } message: {
                Text(
                    "現在の変更はPortableなPackageに保存されていません。"
                    + "保存しない場合、アプリ終了後には復元できません。"
                )
            }
            .confirmationDialog(
                "選択したノートを開きますか？",
                isPresented: Binding(
                    get: { workspace.pendingOpenFolderURL != nil },
                    set: { if !$0 { workspace.cancelPendingOpen() } }
                ),
                titleVisibility: .visible
            ) {
                Button("ノート名を変更して開く") {
                    workspace.confirmPendingOpen()
                }
                Button("キャンセル", role: .cancel) {
                    workspace.cancelPendingOpen()
                }
            } message: {
                if let folder = workspace.pendingOpenFolderURL {
                    Text(
                        "現在のノートを「\(folder.lastPathComponent)」へ切り替え、"
                        + "ノート名をフォルダ名と同じにします。"
                    )
                }
            }
        }
    }

    private func discardUncommittedCard() {
        guard let cardID = newCardID else { return }
        if let card = workspace.document.cards.first(where: { $0.id == cardID }) {
            NoteFolderStore.discardResources(
                for: card,
                from: workspace.folderURL
            )
        }
        workspace.document.cards.removeAll { $0.id == cardID }
        newCardID = nil
    }
}
