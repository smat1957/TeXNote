import SwiftUI
import UniformTypeIdentifiers

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var card: TeXCard
    let noteFolder: URL?
    let isNewCard: Bool
    let showsCardTitleField: Bool
    let saved: () async -> Void
    let creationCommitted: () -> Void

    @State private var draft: TeXCard
    @State private var pictures: [CardAsset]
    @State private var files: [CardAsset]
    @State private var selectedTab: EditTab = .source
    @State private var isCompiling = false
    @State private var isSaving = false
    @State private var hasSavedChangesInSession = false
    @State private var compilationLog = ""
    @State private var errorMessage: String?
    @State private var resourceError: String?
    @State private var pendingResourceDeletion: PendingResourceDeletion?
    @AppStorage("showsEditorLineNumbers") private var showsLineNumbers = false
    @State private var searchText = ""
    @State private var searchIsCaseSensitive = false
    @State private var lineNumberText = ""
    @State private var navigationMessage: String?
    @State private var bodySelection = NSRange(location: 0, length: 0)
    @State private var preambleSelection = NSRange(location: 0, length: 0)

    init(
        card: Binding<TeXCard>,
        noteFolder: URL?,
        pictures: [CardAsset],
        files: [CardAsset],
        isNewCard: Bool,
        showsCardTitleField: Bool = true,
        creationCommitted: @escaping () -> Void,
        saved: @escaping () async -> Void
    ) {
        _card = card
        self.noteFolder = noteFolder
        self.isNewCard = isNewCard
        self.showsCardTitleField = showsCardTitleField
        _pictures = State(initialValue: pictures)
        _files = State(initialValue: files)
        self.saved = saved
        self.creationCommitted = creationCommitted
        _draft = State(initialValue: card.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            .padding()

            Picker("編集項目", selection: $selectedTab) {
                ForEach(EditTab.allCases) { tab in
                    Text(
                        horizontalSizeClass == .compact
                            ? tab.compactTitle
                            : tab.rawValue
                    )
                    .tag(tab)
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
                    TeXCodeEditor(
                        text: $draft.body,
                        selection: $bodySelection,
                        placeholder: "TeX本文を入力します",
                        showsLineNumbers: showsLineNumbers,
                        searchText: searchText,
                        searchIsCaseSensitive: searchIsCaseSensitive,
                        firstLineNumber: draft.bodyFirstLineNumber
                    )
                    .padding(8)
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
            .padding(12)
        }
        .background(Color.gray.opacity(0.10))
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("保存しています…")
                    }
                    .padding(24)
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
            }
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
        .alert(
            "指定した行へ移動できません",
            isPresented: Binding(
                get: { navigationMessage != nil },
                set: { if !$0 { navigationMessage = nil } }
            )
        ) {
            Button("OK") {
                navigationMessage = nil
            }
        } message: {
            Text(navigationMessage ?? "")
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

    @ViewBuilder
    private var editorHeader: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 12) {
                if showsCardTitleField {
                    cardTitleField
                }
                HStack(spacing: 18) {
                    compactSaveButton
                    compactTypesetButton
                    compactCancelButton
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    compactLineNumberButton
                    lineNumberField
                        .padding(.leading, 12)
                    searchField
                        .frame(maxWidth: .infinity)
                    caseSensitivityButton
                    nextSearchButton
                }
            }
        } else {
            HStack {
                if showsCardTitleField {
                    cardTitleField
                }
                lineNumberToggle
                lineNumberField
                    .padding(.leading, 24)
                searchField
                    .frame(width: 170)
                caseSensitivityButton
                nextSearchButton
                Spacer()
                saveButton
                typesetButton
                cancelButton
            }
        }
    }

    private var cardTitleField: some View {
        HStack {
            Text("カード名")
                .foregroundStyle(.secondary)
            TextField("カード名", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 160, maxWidth: 360)
        }
    }

    private var lineNumberToggle: some View {
        Toggle("行番号", isOn: $showsLineNumbers)
            .toggleStyle(.switch)
            .font(.callout)
            .controlSize(.small)
            .fixedSize()
    }

    private var compactLineNumberButton: some View {
        Button {
            showsLineNumbers.toggle()
        } label: {
            Image(systemName: "list.number")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(showsLineNumbers ? Color.accentColor : Color.secondary)
        .accessibilityLabel("行番号")
        .accessibilityValue(showsLineNumbers ? "表示" : "非表示")
    }

    private var compactSaveButton: some View {
        Button {
            saveDraft()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .disabled(isBusy)
        .accessibilityLabel("保存")
    }

    private var compactTypesetButton: some View {
        Button {
            typeset()
        } label: {
            Group {
                if isCompiling {
                    ProgressView()
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(
            isBusy || !TeXCompilerFactory.isAvailable(for: draft.engine)
        )
        .accessibilityLabel("版組")
    }

    private var compactCancelButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .accessibilityLabel("キャンセル")
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("文字列検索", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Text("\(searchMatchCount)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Button("検索をクリア", systemImage: "xmark.circle.fill") {
                    searchText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private var lineNumberField: some View {
        TextField("行", text: $lineNumberText)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .controlSize(.small)
            .multilineTextAlignment(.trailing)
            .frame(width: 54)
            .onSubmit {
                navigateToDisplayedLine()
            }
            .onChange(of: lineNumberText) {
                let digits = lineNumberText.filter(\.isNumber)
                if digits != lineNumberText {
                    lineNumberText = digits
                }
            }
            .accessibilityLabel("移動する行番号")
    }

    private var caseSensitivityButton: some View {
        Button {
            searchIsCaseSensitive.toggle()
        } label: {
            Text(searchIsCaseSensitive ? "Aa" : "aa")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(minWidth: 24, minHeight: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(searchIsCaseSensitive ? Color.accentColor : Color.secondary)
        .accessibilityLabel("大文字と小文字を区別")
        .accessibilityValue(searchIsCaseSensitive ? "オン" : "オフ")
    }

    private var nextSearchButton: some View {
        Button {
            selectNextSearchMatch()
        } label: {
            Image(systemName: "chevron.down")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(searchText.isEmpty || searchMatchCount == 0)
        .accessibilityLabel("次を検索")
    }

    private var saveButton: some View {
        Button("保存", systemImage: "square.and.arrow.up") {
            saveDraft()
        }
        .fixedSize()
        .disabled(isBusy)
    }

    private var typesetButton: some View {
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
        .fixedSize()
        .keyboardShortcut("r", modifiers: .command)
        .disabled(
            isBusy || !TeXCompilerFactory.isAvailable(for: draft.engine)
        )
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .accessibilityLabel("キャンセル")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("版組エンジン")
                Spacer()
                Picker("版組エンジン", selection: $draft.engine) {
                    ForEach(TeXEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            GroupBox("documentclass") {
                VStack(alignment: .leading, spacing: 6) {
                TextField("documentclass", text: $draft.documentClassLine)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                Text("\\documentclass から閉じ波括弧までの1行を入力します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Preamble") {
                VStack(alignment: .leading, spacing: 6) {
                    TeXCodeEditor(
                        text: $draft.preamble,
                        selection: $preambleSelection,
                        placeholder: "\\usepackage などを入力します",
                        showsLineNumbers: showsLineNumbers,
                        searchText: searchText,
                        searchIsCaseSensitive: searchIsCaseSensitive,
                        firstLineNumber: draft.preambleFirstLineNumber
                    )
                    .frame(minHeight: 220, maxHeight: .infinity)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var resources: some View {
        Form {
            HStack {
                ResourceImportButton(
                    title: "画像を追加…",
                    systemImage: "photo.badge.plus",
                    allowedContentTypes: [.image, .pdf]
                ) {
                    prepareResourceImport()
                } completed: { result in
                    importSelectedResources(result, kind: .pictures)
                }

                ResourceImportButton(
                    title: "ファイルを追加…",
                    systemImage: "doc.badge.plus",
                    allowedContentTypes: [.data, .item]
                ) {
                    prepareResourceImport()
                } completed: { result in
                    importSelectedResources(result, kind: .files)
                }
            }

            Section("画像") {
                if pictures.isEmpty {
                    Text("画像はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pictures, id: \.relativePath) { picture in
                        resourceRow(picture, kind: .pictures)
                    }
                }
            }
            Section("ファイル") {
                if files.isEmpty {
                    Text("ファイルはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files, id: \.relativePath) { file in
                        resourceRow(file, kind: .files)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var searchMatchCount: Int {
        let target: String
        switch selectedTab {
        case .source: target = draft.body
        case .settings: target = draft.preamble
        case .resources, .error: target = ""
        }
        return TeXSyntaxHighlighting.searchRanges(
            in: target,
            query: searchText,
            caseSensitive: searchIsCaseSensitive
        ).count
    }

    private func navigateToDisplayedLine() {
        guard let lineNumber = Int(lineNumberText), lineNumber > 0 else {
            navigationMessage = "1以上の行番号を入力してください。"
            return
        }

        let documentClassLastLine = logicalLineCount(
            in: draft.documentClassLine
        )
        if lineNumber <= documentClassLastLine {
            selectedTab = .settings
            navigationMessage = "この行はdocumentclass欄です。"
            return
        }

        if let selection = TeXSyntaxHighlighting.selectionRange(
            forDisplayedLine: lineNumber,
            in: draft.preamble,
            firstLineNumber: draft.preambleFirstLineNumber
        ) {
            selectedTab = .settings
            preambleSelection = selection
            return
        }

        if let selection = TeXSyntaxHighlighting.selectionRange(
            forDisplayedLine: lineNumber,
            in: draft.body,
            firstLineNumber: draft.bodyFirstLineNumber
        ) {
            selectedTab = .source
            bodySelection = selection
            return
        }

        let completeSourceLastLine = logicalLineCount(in: draft.completeSource)
        if lineNumber <= completeSourceLastLine {
            navigationMessage = "この行はTeXNoteが生成する構造行で、直接編集できません。"
        } else {
            navigationMessage = "この文書は\(completeSourceLastLine)行までです。"
        }
    }

    private func selectNextSearchMatch() {
        switch selectedTab {
        case .source:
            bodySelection = TeXSyntaxHighlighting.nextSearchRange(
                in: draft.body,
                query: searchText,
                caseSensitive: searchIsCaseSensitive,
                after: bodySelection
            ) ?? bodySelection
        case .settings:
            preambleSelection = TeXSyntaxHighlighting.nextSearchRange(
                in: draft.preamble,
                query: searchText,
                caseSensitive: searchIsCaseSensitive,
                after: preambleSelection
            ) ?? preambleSelection
        case .resources, .error:
            break
        }
    }

    private func logicalLineCount(in text: String) -> Int {
        text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
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
            guard changed || hasSavedChangesInSession || isNewCard
                    || draft.pdfData == nil else {
                isCompiling = false
                dismiss()
                return
            }
            if changed {
                await commitDraft(notifyWorkspace: false)
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
                compiled.pdfRelativePath = "Cards/\(snapshot.id.uuidString)/output.pdf"
                compiled.pdfData = result.pdfData
                compiled.pdfNeedsSaving = true
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

    private func importSelectedResources(
        _ result: Result<[URL], Error>,
        kind: CardResourceDirectory
    ) {
        do {
            let urls = try result.get()
            let imported = try NoteFolderStore.importResources(
                from: urls,
                for: draft,
                kind: kind,
                into: noteFolder
            )
            switch kind {
            case .pictures:
                pictures = imported
                draft.pictureRelativePaths = imported.map(\.relativePath)
            case .files:
                files = imported
                draft.fileRelativePaths = imported.map(\.relativePath)
            }
            Task {
                await commitDraft()
                creationCommitted()
            }
        } catch {
            resourceError = error.localizedDescription
        }
    }

    private func prepareResourceImport() -> Bool {
        guard noteFolder != nil else {
            resourceError = NoteFolderError
                .noteMustBeSavedBeforeAddingResources
                .localizedDescription
            return false
        }
        return true
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
                at: resource.relativePath,
                for: draft,
                kind: kind,
                from: noteFolder
            )
            switch kind {
            case .pictures:
                pictures = remaining
                draft.pictureRelativePaths = remaining.map(\.relativePath)
            case .files:
                files = remaining
                draft.fileRelativePaths = remaining.map(\.relativePath)
            }
            Task {
                await commitDraft()
                creationCommitted()
            }
        } catch {
            resourceError = error.localizedDescription
        }
    }
}

private struct ResourceImportButton: View {
    let title: String
    let systemImage: String
    let allowedContentTypes: [UTType]
    let prepare: () -> Bool
    let completed: (Result<[URL], Error>) -> Void

    @State private var isPresented = false

    var body: some View {
        Button(title, systemImage: systemImage) {
            guard prepare() else { return }
            isPresented = true
        }
        .buttonStyle(.borderless)
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: completed
        )
    }
}

private struct PendingResourceDeletion {
    let resource: CardAsset
    let kind: CardResourceDirectory

    var relativeName: String {
        resource.relativePath
    }
}

private enum EditTab: String, CaseIterable, Identifiable {
    case source = "TeXソース"
    case settings = "設定"
    case resources = "画像・ファイル"
    case error = "エラー"

    var id: Self { self }

    var compactTitle: String {
        switch self {
        case .source: "ソース"
        case .settings: "設定"
        case .resources: "添付"
        case .error: "エラー"
        }
    }
}
