import SwiftUI
import UIKit
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

struct PlatformResourceImportControls: View {
    let prepare: () -> Bool
    let completed: (Result<[URL], Error>, CardResourceDirectory) -> Void

    @State private var isFilePickerPresented = false
    @State private var isFolderPickerPresented = false
    @State private var kind: CardResourceDirectory = .pictures

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
            isPresented: $isFilePickerPresented,
            allowedContentTypes: fileContentTypes,
            allowsMultipleSelection: true,
            onCompletion: { completed($0, kind) }
        )
        .sheet(isPresented: $isFolderPickerPresented) {
            PlatformFolderPicker { result in
                isFolderPickerPresented = false
                if let result {
                    completed(result, kind)
                }
            }
        }
    }

    private var fileContentTypes: [UTType] {
        switch kind {
        case .pictures: [.image, .pdf]
        case .files: [.data, .item]
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
                presentFiles(kind: kind)
            }
            Button("フォルダを選択…", systemImage: "folder") {
                presentFolder(kind: kind)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func presentFiles(kind: CardResourceDirectory) {
        guard prepare() else { return }
        self.kind = kind
        isFilePickerPresented = true
    }

    private func presentFolder(kind: CardResourceDirectory) {
        guard prepare() else { return }
        self.kind = kind
        isFolderPickerPresented = true
    }
}

private struct PlatformFolderPicker: UIViewControllerRepresentable {
    let finished: (Result<[URL], Error>?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(finished: finished)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (Result<[URL], Error>?) -> Void

        init(finished: @escaping (Result<[URL], Error>?) -> Void) {
            self.finished = finished
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            finished(.success(urls))
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            finished(nil)
        }
    }
}
