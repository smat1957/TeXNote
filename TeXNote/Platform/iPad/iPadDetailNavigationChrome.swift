import SwiftUI

struct PlatformSidebarNavigationChromeModifier: ViewModifier {
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
