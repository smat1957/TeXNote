import SwiftUI

enum PlatformNoteActionSymbols {
    static let latestCard = "house"
    static let menu = "ellipsis.circle"
}

enum PlatformNoteActionChrome {
    static let usesGroupedChrome = false
}

struct PlatformNoteActionGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
    }
}

struct PlatformNoteActionControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
