import SwiftUI

enum PlatformNoteActionSymbols {
    static let latestCard = "clock.arrow.circlepath"
    static let menu = "ellipsis"
}

enum PlatformNoteActionChrome {
    static let usesGroupedChrome = true
}

struct PlatformNoteActionGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .buttonStyle(iPhoneNoteActionButtonStyle())
            .tint(.primary)
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.55), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}

struct PlatformNoteActionControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 42, height: 42)
            .contentShape(Circle())
    }
}

private struct iPhoneNoteActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.62 : 1)
            .background {
                Circle()
                    .fill(
                        configuration.isPressed
                            ? Color.primary.opacity(0.10)
                            : Color.clear
                    )
            }
            .animation(
                .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
    }
}
