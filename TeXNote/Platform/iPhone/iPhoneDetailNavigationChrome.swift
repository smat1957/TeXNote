import SwiftUI

struct PlatformSidebarBottomBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct PlatformSidebarNavigationChromeModifier: ViewModifier {
    let showsReturnToDetail: Bool
    let returnToDetail: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsReturnToDetail {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Button("Noteへ戻る", systemImage: "chevron.right") {
                            returnToDetail()
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
        } else {
            content
        }
    }
}

struct PlatformAuthenticationSidebarToolbarModifier<Control: View>:
    ViewModifier {
    let control: Control

    init(@ViewBuilder control: () -> Control) {
        self.control = control()
    }

    func body(content: Content) -> some View {
        content
    }
}

struct PlatformDetailNavigationChromeModifier: ViewModifier {
    let dismissSidebar: () -> Void

    func body(content: Content) -> some View {
        content
    }
}

struct PlatformSidebarRevealControl: View {
    let action: () -> Void

    var body: some View {
        EmptyView()
    }
}
