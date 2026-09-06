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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        VStack(spacing: 0) {
            HStack {
                control
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)

            Divider()

            content
        }
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
