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
