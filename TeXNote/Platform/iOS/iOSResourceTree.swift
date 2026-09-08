import SwiftUI

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
