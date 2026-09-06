import SwiftUI

extension View {
    func noteWorkspacePresentation(
        workspace: NoteWorkspace,
        editingCardID: Binding<UUID?>,
        newCardID: Binding<UUID?>,
        showsCardTitleField: Bool = true
    ) -> some View {
        modifier(
            NoteWorkspacePresentationModifier(
                workspace: workspace,
                editingCardID: editingCardID,
                newCardID: newCardID,
                showsCardTitleField: showsCardTitleField
            )
        )
    }
}

private struct NoteWorkspacePresentationModifier: ViewModifier {
    @ObservedObject var workspace: NoteWorkspace
    @Binding var editingCardID: UUID?
    @Binding var newCardID: UUID?
    let showsCardTitleField: Bool

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .modifier(PlatformTeXDocumentPickerModifier(workspace: workspace))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .overlay {
                    if let message = workspace.fileOperationMessage {
                        ZStack {
                            Color.black.opacity(0.18)
                                .ignoresSafeArea()
                            VStack(spacing: 16) {
                                ProgressView()
                                    .controlSize(.large)
                                Text(message)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(28)
                            .background(
                                .regularMaterial,
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                        }
                        .zIndex(10)
                    }
                }
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
                        showsCardTitleField: showsCardTitleField,
                        creationCommitted: {
                            if newCardID == cardID {
                                newCardID = nil
                            }
                        }
                    ) {
                        await workspace.cardEditorDidSave()
                    }
                    .frame(
                        width: min(1_200, geometry.size.width),
                        height: geometry.size.height
                    )
                }
            }
            .alert(
                "Note名を入力",
                isPresented: $workspace.isNamingSaveAs
            ) {
                TextField("Note名", text: $workspace.saveAsNameDraft)
                Button("次へ") {
                    workspace.confirmSaveAsName()
                }
                .disabled(!workspace.isSaveAsNameValid)
                Button("キャンセル", role: .cancel) {
                    workspace.cancelSaveAsName()
                }
            } message: {
                Text(
                    "保存するPackageの名前を入力してください。"
                        + "記号「/」と「:」は使用できません。"
                )
            }
            .alert(
                "TeX文書のファイル名を入力",
                isPresented: Binding(
                    get: { workspace.pendingExportFileNameFolderURL != nil },
                    set: {
                        if !$0,
                           workspace.pendingExportFileNameFolderURL != nil {
                            workspace.cancelExportFileName()
                        }
                    }
                )
            ) {
                TextField("ファイル名", text: $workspace.exportFileNameDraft)
                Button("エクスポート") {
                    workspace.confirmExportFileName()
                }
                .disabled(!workspace.isExportFileNameValid)
                Button("キャンセル", role: .cancel) {
                    workspace.cancelExportFileName()
                }
            } message: {
                Text(
                    "拡張子「.tex」を除いたファイル名を入力してください。"
                        + "記号「/」と「:」は使用できません。"
                )
            }
            .alert(
                "TeXNote",
                isPresented: Binding(
                    get: {
                        workspace.errorMessage != nil
                            || workspace.fileOperationCompletionMessage != nil
                    },
                    set: {
                        if !$0 {
                            workspace.errorMessage = nil
                            workspace.fileOperationCompletionMessage = nil
                        }
                    }
                )
            ) {
                Button("OK") {
                    workspace.errorMessage = nil
                    workspace.fileOperationCompletionMessage = nil
                }
            } message: {
                Text(
                    workspace.errorMessage
                        ?? workspace.fileOperationCompletionMessage
                        ?? ""
                )
            }
            .alert(
                workspace.pendingUnsavedAction?.confirmationTitle ?? "",
                isPresented: Binding(
                    get: { workspace.pendingUnsavedAction != nil },
                    set: { if !$0 { workspace.cancelPendingUnsavedAction() } }
                )
            ) {
                if workspace.requiresPackageSaveConfirmation {
                    Button("Packageに保存…") {
                        workspace.saveBeforePendingAction()
                    }
                }
                if let action = workspace.pendingUnsavedAction {
                    Button(
                        action.destructiveButtonTitle,
                        role: .destructive
                    ) {
                        workspace.discardAndContinuePendingAction()
                    }
                }
                Button("キャンセル", role: .cancel) {
                    workspace.cancelPendingUnsavedAction()
                }
            } message: {
                Text(workspace.pendingUnsavedAction?.confirmationMessage ?? "")
            }
            .alert(
                "選択したノートを開きますか？",
                isPresented: Binding(
                    get: { workspace.pendingOpenFolderURL != nil },
                    set: { if !$0 { workspace.cancelPendingOpen() } }
                )
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
            .confirmationDialog(
                "同じ名前のNoteがあります",
                isPresented: Binding(
                    get: {
                        workspace.pendingOverwriteSaveParentURL != nil
                    },
                    set: {
                        if !$0 {
                            workspace.cancelOverwriteSave()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("上書き保存", role: .destructive) {
                    workspace.confirmOverwriteSave()
                }
                Button("キャンセル", role: .cancel) {
                    workspace.cancelOverwriteSave()
                }
            } message: {
                Text(
                    "選択したフォルダ内の「\(workspace.overwriteSaveName)」を"
                    + "上書きしてもよいですか？"
                )
            }
            .confirmationDialog(
                "同じ名前の書き出し項目があります",
                isPresented: Binding(
                    get: { workspace.pendingOverwriteExportFolderURL != nil },
                    set: { if !$0 { workspace.cancelOverwriteExport() } }
                ),
                titleVisibility: .visible
            ) {
                Button("上書き", role: .destructive) {
                    workspace.confirmOverwriteExport()
                }
                Button("キャンセル", role: .cancel) {
                    workspace.cancelOverwriteExport()
                }
            } message: {
                Text(
                    workspace.exportConflictNames.joined(separator: "、")
                        + "を上書きしてもよいですか？"
                )
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
