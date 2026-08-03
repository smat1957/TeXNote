import SwiftUI

struct macOSAboutMenuCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("TeXNoteについて") {
            openWindow(id: "about")
        }
    }
}
