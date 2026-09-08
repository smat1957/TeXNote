import Foundation

struct CardResourceTreeNode: Identifiable {
    let name: String
    let relativePath: String
    var asset: CardAsset?
    var children: [CardResourceTreeNode]

    var id: String { relativePath }
    var isDirectory: Bool { asset == nil }

    var outlineChildren: [CardResourceTreeNode]? {
        isDirectory ? children : nil
    }
}

enum CardResourceTree {
    static func root(
        for assets: [CardAsset],
        kind: CardResourceDirectory,
        card: TeXCard
    ) -> CardResourceTreeNode {
        var root = CardResourceTreeNode(
            name: kind.folderName,
            relativePath: "",
            asset: nil,
            children: []
        )
        for asset in assets {
            guard let storedPath = kind.storedRelativePath(
                for: asset.relativePath,
                card: card
            ) else { continue }
            let components = storedPath.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            insert(
                asset,
                components: ArraySlice(components),
                parentPath: "",
                into: &root
            )
        }
        sort(&root)
        return root
    }

    private static func insert(
        _ asset: CardAsset,
        components: ArraySlice<String>,
        parentPath: String,
        into parent: inout CardResourceTreeNode
    ) {
        guard let name = components.first else { return }
        let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        if components.count == 1 {
            parent.children.append(
                CardResourceTreeNode(
                    name: name,
                    relativePath: path,
                    asset: asset,
                    children: []
                )
            )
            return
        }

        let index: Int
        if let existing = parent.children.firstIndex(where: {
            $0.isDirectory && $0.name == name
        }) {
            index = existing
        } else {
            parent.children.append(
                CardResourceTreeNode(
                    name: name,
                    relativePath: path,
                    asset: nil,
                    children: []
                )
            )
            index = parent.children.index(before: parent.children.endIndex)
        }
        insert(
            asset,
            components: components.dropFirst(),
            parentPath: path,
            into: &parent.children[index]
        )
    }

    private static func sort(_ node: inout CardResourceTreeNode) {
        for index in node.children.indices {
            sort(&node.children[index])
        }
        node.children.sort {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
