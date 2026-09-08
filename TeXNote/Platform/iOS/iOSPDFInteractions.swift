import SwiftUI

/// iPad・iPhone固有のPDFピンチ操作とサイドバー表示フリックを適用します。
extension View {
    func platformPDFInteractions<ZoomGesture: Gesture>(
        zoomGesture: ZoomGesture,
        magnify: @escaping (CGFloat) -> Void,
        zoomPercentage: Int,
        canZoomOut: Bool,
        canZoomIn: Bool,
        zoomOut: @escaping () -> Void,
        resetZoom: @escaping () -> Void,
        zoomIn: @escaping () -> Void,
        canRevealSidebar: Bool,
        revealSidebar: @escaping () -> Void
    ) -> some View {
        simultaneousGesture(zoomGesture)
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard canRevealSidebar,
                              value.translation.width >= 60,
                              abs(value.translation.width)
                                > abs(value.translation.height) else { return }
                        revealSidebar()
                    },
                including: canRevealSidebar ? .all : .none
            )
    }
}
