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

    func body(content: Content) -> some View {
        content
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    control
                }
            }
    }
}

struct PlatformDetailNavigationChromeModifier: ViewModifier {
    let dismissSidebar: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .simultaneousGesture(
                TapGesture()
                    .onEnded(dismissSidebar)
            )
    }
}

struct PlatformSidebarRevealControl: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.leading")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Card一覧を表示")
    }
}
