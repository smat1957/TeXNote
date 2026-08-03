import SwiftUI

private struct macOSPDFZoomControlsModifier: ViewModifier {
    @State private var previousMagnification: CGFloat = 1
    let magnify: (CGFloat) -> Void
    let zoomPercentage: Int
    let canZoomOut: Bool
    let canZoomIn: Bool
    let zoomOut: () -> Void
    let resetZoom: () -> Void
    let zoomIn: () -> Void

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let incrementalMagnification =
                            value.magnification / previousMagnification
                        previousMagnification = value.magnification
                        magnify(incrementalMagnification)
                    }
                    .onEnded { _ in
                        previousMagnification = 1
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 2) {
                    Button(action: zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!canZoomOut)
                    .help("縮小（⌘−）")

                    Button(action: resetZoom) {
                        Text("\(zoomPercentage)%")
                            .monospacedDigit()
                            .frame(minWidth: 44)
                    }
                    .keyboardShortcut("0", modifiers: .command)
                    .help("表示倍率をリセット（⌘0）")

                    Button(action: zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!canZoomIn)
                    .help("拡大（⌘＋）")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .padding(16)
            }
    }
}

extension View {
    func macOSPDFZoomControls(
        magnify: @escaping (CGFloat) -> Void,
        zoomPercentage: Int,
        canZoomOut: Bool,
        canZoomIn: Bool,
        zoomOut: @escaping () -> Void,
        resetZoom: @escaping () -> Void,
        zoomIn: @escaping () -> Void
    ) -> some View {
        modifier(macOSPDFZoomControlsModifier(
            magnify: magnify,
            zoomPercentage: zoomPercentage,
            canZoomOut: canZoomOut,
            canZoomIn: canZoomIn,
            zoomOut: zoomOut,
            resetZoom: resetZoom,
            zoomIn: zoomIn
        ))
    }
}
