import SwiftUI
import UniformTypeIdentifiers

struct PlatformTeXDocumentPickerModifier: ViewModifier {
    @ObservedObject var workspace: NoteWorkspace

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $workspace.isFileSelectionPresented,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                workspace.handleFileSelection(result)
            }
    }

    private var allowedContentTypes: [UTType] {
        switch workspace.fileSelectionRequest {
        case .teXDocument:
            [UTType(filenameExtension: "tex") ?? .plainText]
        case .packageFolder, .teXExportFolder, nil:
            [.folder]
        }
    }
}

private enum PlatformResourceSelection: Equatable {
    case files
    case folder
}

struct PlatformResourceImportControls: View {
    let prepare: () -> Bool
    let completed: (Result<[URL], Error>, CardResourceDirectory) -> Void

    @State private var isPresented = false
    @State private var kind: CardResourceDirectory = .pictures
    @State private var selection: PlatformResourceSelection = .files

    var body: some View {
        HStack(spacing: 12) {
            resourceMenu(
                title: "画像を追加",
                fileTitle: "画像を選択…",
                systemImage: "photo.badge.plus",
                kind: .pictures
            )
            resourceMenu(
                title: "ファイルを追加",
                fileTitle: "ファイルを選択…",
                systemImage: "doc.badge.plus",
                kind: .files
            )
        }
        .buttonStyle(.bordered)
        .fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: selection == .files,
            onCompletion: { completed($0, kind) }
        )
    }

    private var allowedContentTypes: [UTType] {
        switch (kind, selection) {
        case (.pictures, .files): [.image, .pdf]
        case (.files, .files): [.data, .item]
        case (_, .folder): [.folder]
        }
    }

    private func resourceMenu(
        title: String,
        fileTitle: String,
        systemImage: String,
        kind: CardResourceDirectory
    ) -> some View {
        Menu {
            Button(
                fileTitle,
                systemImage: kind == .pictures ? "photo" : "doc"
            ) {
                present(kind: kind, selection: .files)
            }
            Button("フォルダを選択…", systemImage: "folder") {
                present(kind: kind, selection: .folder)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func present(
        kind: CardResourceDirectory,
        selection: PlatformResourceSelection
    ) {
        guard prepare() else { return }
        self.kind = kind
        self.selection = selection
        isPresented = true
    }
}

struct PlatformResourceTree: View {
    let root: CardResourceTreeNode
    let delete: (CardAsset) -> Void
    let renameDirectory: (String, String) -> Void

    @State private var editingPath: String?
    @State private var editedName = ""

    var body: some View {
        OutlineGroup([root], children: \.outlineChildren) { node in
            row(for: node)
        }
    }

    @ViewBuilder
    private func row(for node: CardResourceTreeNode) -> some View {
        if let asset = node.asset {
            HStack(spacing: 12) {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                Text(node.name)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer(minLength: 12)
                Button(role: .destructive) {
                    delete(asset)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("削除")
                .accessibilityLabel("\(node.name)を削除")
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                if editingPath == node.relativePath {
                    TextField("フォルダ名", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { finishRenaming(node) }
                    Button {
                        finishRenaming(node)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    Button {
                        editingPath = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(node.name)
                        .fontWeight(node.relativePath.isEmpty ? .semibold : .regular)
                    Spacer(minLength: 12)
                    if !node.relativePath.isEmpty {
                        Button {
                            editedName = node.name
                            editingPath = node.relativePath
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        .help("名前を変更")
                        .accessibilityLabel("\(node.name)の名前を変更")
                    }
                }
            }
        }
    }

    private func finishRenaming(_ node: CardResourceTreeNode) {
        renameDirectory(node.relativePath, editedName)
        editingPath = nil
    }
}
