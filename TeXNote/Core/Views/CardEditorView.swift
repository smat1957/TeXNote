import SwiftUI
import UniformTypeIdentifiers

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var card: TeXCard
    let noteFolder: URL?
    let isNewCard: Bool
    let saved: () async -> Void
    let creationCommitted: () -> Void

    @State private var draft: TeXCard
    @State private var pictures: [CardAsset]
    @State private var files: [CardAsset]
    @State private var selectedTab: EditTab = .source
    @State private var isChoosingResources = false
    @State private var resourceKindToImport = CardResourceDirectory.pictures
    @State private var isCompiling = false
    @State private var isSaving = false
    @State private var hasSavedChangesInSession = false
    @State private var compilationLog = ""
    @State private var errorMessage: String?
    @State private var resourceError: String?
    @State private var pendingResourceDeletion: PendingResourceDeletion?

    init(
        card: Binding<TeXCard>,
        noteFolder: URL?,
        pictures: [CardAsset],
        files: [CardAsset],
        isNewCard: Bool,
        creationCommitted: @escaping () -> Void,
        saved: @escaping () async -> Void
    ) {
        _card = card
        self.noteFolder = noteFolder
        self.isNewCard = isNewCard
        _pictures = State(initialValue: pictures)
        _files = State(initialValue: files)
        self.saved = saved
        self.creationCommitted = creationCommitted
        _draft = State(initialValue: card.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("カード名")
                    .foregroundStyle(.secondary)

                TextField("カード名", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)

                Spacer()

                Button("保存", systemImage: "square.and.arrow.up") {
                    saveDraft()
                }
                .disabled(isBusy)

                Button {
                    typeset()
                } label: {
                    if isCompiling {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("版組", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(
                    isBusy || !TeXCompilerFactory.isAvailable(for: draft.engine)
                )

                Button("キャンセル") {
                    dismiss()
                }
            }
            .padding()

            Picker("編集項目", selection: $selectedTab) {
                ForEach(EditTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch selectedTab {
                case .source:
                    TextEditor(text: $draft.body)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                case .settings:
                    settings
                case .resources:
                    resources
                case .error:
                    errorLog
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                .background,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }
            .padding(20)
        }
        .background(Color.gray.opacity(0.10))
        .fileImporter(
            isPresented: $isChoosingResources,
            allowedContentTypes: allowedResourceTypes,
            allowsMultipleSelection: true
        ) { result in
            importSelectedResources(result)
        }
        .alert(
            "ファイルを操作できません",
            isPresented: Binding(
                get: { resourceError != nil },
                set: { if !$0 { resourceError = nil } }
            )
        ) {
            Button("OK") {
                resourceError = nil
            }
        } message: {
            Text(resourceError ?? "")
        }
        .confirmationDialog(
            "ファイルを削除しますか？",
            isPresented: Binding(
                get: { pendingResourceDeletion != nil },
                set: { if !$0 { pendingResourceDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let pendingResourceDeletion {
                    deleteResource(
                        pendingResourceDeletion.resource,
                        kind: pendingResourceDeletion.kind
                    )
                }
                pendingResourceDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingResourceDeletion = nil
            }
        } message: {
            if let pendingResourceDeletion {
                Text("\(pendingResourceDeletion.relativeName)をPackageから削除します。")
            }
        }
    }

    private var settings: some View {
        Form {
            Picker("版組エンジン", selection: $draft.engine) {
                ForEach(TeXEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }

            Section("documentclass") {
                TextField("documentclass", text: $draft.documentClassLine)
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Text("\\documentclass から閉じ波括弧までの1行を入力します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preamble") {
                TextEditor(text: $draft.preamble)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var resources: some View {
        Form {
            Section("画像") {
                HStack {
                    Button("画像を追加…", systemImage: "photo.badge.plus") {
                        beginImporting(.pictures)
                    }

                    Button("ファイルを追加…", systemImage: "doc.badge.plus") {
                        beginImporting(.files)
                    }
                }

                if pictures.isEmpty {
                    Text("画像はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pictures, id: \.fileName) { picture in
                        resourceRow(picture, kind: .pictures)
                    }
                }
            }

            Section("ファイル") {
                if files.isEmpty {
                    Text("ファイルはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files, id: \.fileName) { file in
                        resourceRow(file, kind: .files)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var errorLog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if compilationLog.isEmpty {
                    ContentUnavailableView(
                        "エラーはありません",
                        systemImage: "checkmark.circle"
                    )
                }

                if !compilationLog.isEmpty {
                    Text(compilationLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var isBusy: Bool {
        isSaving || isCompiling
    }

    private func hasChanges() -> Bool {
        draft.title != card.title
            || draft.body != card.body
            || draft.documentClassLine != card.documentClassLine
            || draft.preamble != card.preamble
            || draft.engine != card.engine
    }

    private func hasSourceChanges() -> Bool {
        draft.sourceHash != card.sourceHash
    }

    private func saveDraft() {
        guard !isBusy else { return }
        isSaving = true
        Task {
            hasSavedChangesInSession = true
            let changed = hasChanges()
            let canCommitCreation = !isNewCard || hasSourceChanges()
            if changed && canCommitCreation {
                await commitDraft()
            }
            if canCommitCreation {
                creationCommitted()
            }
            isSaving = false
        }
    }

    private func commitDraft(notifyWorkspace: Bool = true) async {
        draft.updatedAt = .now
        card = draft
        if notifyWorkspace {
            await saved()
        }
        draft = card
    }

    private func typeset() {
        guard TeXCompilerFactory.isAvailable(for: draft.engine), !isBusy else {
            return
        }
        isCompiling = true
        errorMessage = nil
        compilationLog = ""

        Task {
            let changed = hasChanges()
            guard changed || hasSavedChangesInSession || isNewCard else {
                isCompiling = false
                dismiss()
                return
            }
            if changed {
                await commitDraft(notifyWorkspace: !isNewCard)
            }
            let snapshot = changed ? card : draft
            let compiler = TeXCompilerFactory.make()
            do {
                let result = try await compiler.compile(
                    card: snapshot,
                    pictures: pictures,
                    files: files
                )
                var compiled = snapshot
                compiled.pdfRelativePath = "PDF/\(snapshot.id.uuidString).pdf"
                compiled.pdfData = try Data(contentsOf: result.pdfURL)
                compiled.compiledSourceHash = compiled.sourceHash
                compiled.lastTypesetAt = .now
                card = compiled
                draft = compiled
                compilationLog = result.log
                await saved()
                creationCommitted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                compilationLog = error.localizedDescription
                selectedTab = .error
            }
            isCompiling = false
        }
    }

    private func importSelectedResources(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let imported = try NoteFolderStore.importResources(
                from: urls,
                for: draft,
                kind: resourceKindToImport,
                into: noteFolder
            )
            switch resourceKindToImport {
            case .pictures:
                pictures = imported
            case .files:
                files = imported
            }
            Task {
                if !isNewCard {
                    await saved()
                }
            }
        } catch {
            resourceError = error.localizedDescription
        }
    }

    private var allowedResourceTypes: [UTType] {
        switch resourceKindToImport {
        case .pictures:
            [.image, .pdf]
        case .files:
            [.data]
        }
    }

    private func beginImporting(_ kind: CardResourceDirectory) {
        guard noteFolder != nil else {
            resourceError = NoteFolderError
                .noteMustBeSavedBeforeAddingResources
                .localizedDescription
            return
        }
        resourceKindToImport = kind
        isChoosingResources = true
    }

    private func resourceRow(
        _ resource: CardAsset,
        kind: CardResourceDirectory
    ) -> some View {
        let relativeName = "\(kind.folderName)/\(resource.fileName)"
        return HStack(spacing: 12) {
            Text(relativeName)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Spacer(minLength: 12)

            Button(role: .destructive) {
                pendingResourceDeletion = PendingResourceDeletion(
                    resource: resource,
                    kind: kind
                )
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("削除")
            .accessibilityLabel("\(relativeName)を削除")
        }
    }

    private func deleteResource(
        _ resource: CardAsset,
        kind: CardResourceDirectory
    ) {
        do {
            let remaining = try NoteFolderStore.deleteResource(
                named: resource.fileName,
                for: draft,
                kind: kind,
                from: noteFolder
            )
            switch kind {
            case .pictures:
                pictures = remaining
            case .files:
                files = remaining
            }
            Task {
                if !isNewCard {
                    await saved()
                }
            }
        } catch {
            resourceError = error.localizedDescription
        }
    }
}

private struct PendingResourceDeletion {
    let resource: CardAsset
    let kind: CardResourceDirectory

    var relativeName: String {
        "\(kind.folderName)/\(resource.fileName)"
    }
}

private enum EditTab: String, CaseIterable, Identifiable {
    case source = "TeXソース"
    case settings = "設定"
    case resources = "画像・ファイル"
    case error = "エラー"

    var id: Self { self }
}
