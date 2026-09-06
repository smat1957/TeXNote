import SwiftUI

/// iPad・iPhoneではPDF上のピンチ操作をCoreから受け取り、そのまま適用します。
extension View {
    func platformPDFInteractions<ZoomGesture: Gesture>(
        zoomGesture: ZoomGesture,
        magnify: @escaping (CGFloat) -> Void,
        zoomPercentage: Int,
        canZoomOut: Bool,
        canZoomIn: Bool,
        zoomOut: @escaping () -> Void,
        resetZoom: @escaping () -> Void,
        zoomIn: @escaping () -> Void
    ) -> some View {
        simultaneousGesture(zoomGesture)
    }
}
