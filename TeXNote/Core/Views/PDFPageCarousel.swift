import CoreGraphics
import PDFKit
import SwiftUI

struct PDFPageCarousel: View {
    private let data: Data
    private let pages: [RenderedPDFPage]
    private let canSelectNextCard: Bool
    private let canSelectPreviousCard: Bool
    private let nextCardAction: () -> Void
    private let previousCardAction: () -> Void
    @Binding private var position: PDFPagePosition

    @State private var currentPage = 0
    @State private var verticalPage: Int? = 0
    @State private var zoom: CGFloat = 1
    @State private var panOffset = CGSize.zero
    @GestureState private var gestureMagnification: CGFloat = 1
    @GestureState private var gestureTranslation = CGSize.zero

    private let minimumZoom: CGFloat = 1
    private let maximumZoom: CGFloat = 4

    private var displayedZoom: CGFloat {
        clampedZoom(zoom * gestureMagnification)
    }

    init(
        data: Data,
        position: Binding<PDFPagePosition>,
        canSelectNextCard: Bool,
        canSelectPreviousCard: Bool,
        nextCardAction: @escaping () -> Void,
        previousCardAction: @escaping () -> Void
    ) {
        self.data = data
        pages = PDFPageRenderer.render(data: data)
        _position = position
        self.canSelectNextCard = canSelectNextCard
        self.canSelectPreviousCard = canSelectPreviousCard
        self.nextCardAction = nextCardAction
        self.previousCardAction = previousCardAction
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if canSelectPreviousCard {
                        Color.clear
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .id(-1)
                    }

                    horizontalPages(in: geometry.size)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .id(0)

                    if canSelectNextCard {
                        Color.clear
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .id(1)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $verticalPage)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(displayedZoom > 1)
        }
        .onAppear {
            verticalPage = 0
            updatePosition()
        }
        .onChange(of: currentPage) {
            panOffset = .zero
            updatePosition()
        }
        .onChange(of: verticalPage) {
            navigateToVerticalPage()
        }
    }

    private func horizontalPages(in size: CGSize) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages) { page in
                    let pageSize = fittedPageSize(for: page, in: size)
                    AdaptivePDFPageImage(
                        data: data,
                        page: page,
                        zoom: displayedZoom
                    )
                        .frame(
                            width: pageSize.width,
                            height: pageSize.height
                        )
                        .background(.white)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                        .scaleEffect(displayedZoom)
                        .offset(panPosition(in: size))
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .id(page.index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollDisabled(displayedZoom > 1)
        .scrollPosition(id: Binding(
            get: { currentPage },
            set: { currentPage = $0 ?? 0 }
        ))
        .contentShape(Rectangle())
#if !os(macOS)
        .simultaneousGesture(zoomGesture)
#endif
        .simultaneousGesture(
            panGesture(in: size),
            including: zoom > 1 ? .all : .none
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                resetZoom()
            }
        )
#if os(macOS)
        .macOSPDFZoomControls(
            magnify: applyMagnification,
            zoomPercentage: Int((zoom * 100).rounded()),
            canZoomOut: zoom > minimumZoom,
            canZoomIn: zoom < maximumZoom,
            zoomOut: zoomOut,
            resetZoom: resetZoom,
            zoomIn: zoomIn
        )
#endif
    }

    private func fitWidth(in availableWidth: CGFloat) -> CGFloat {
        max(240, availableWidth - 48)
    }

    private func fittedPageSize(
        for page: RenderedPDFPage,
        in availableSize: CGSize
    ) -> CGSize {
        let maximumWidth = fitWidth(in: availableSize.width)
        let maximumHeight = max(1, availableSize.height - 32)
        let pageWidth = CGFloat(page.image.width)
        let pageHeight = CGFloat(page.image.height)
        guard pageWidth > 0, pageHeight > 0 else {
            return CGSize(width: maximumWidth, height: maximumHeight)
        }

        let scale = min(
            maximumWidth / pageWidth,
            maximumHeight / pageHeight
        )
        return CGSize(
            width: pageWidth * scale,
            height: pageHeight * scale
        )
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureMagnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                applyMagnification(value.magnification)
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($gestureTranslation) { value, state, _ in
                guard displayedZoom > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard displayedZoom > 1 else { return }
                let currentOffset = clampedPanOffset(panOffset, in: size)
                panOffset = clampedPanOffset(
                    CGSize(
                        width: currentOffset.width + value.translation.width,
                        height: currentOffset.height + value.translation.height
                    ),
                    in: size
                )
            }
    }

    private func panPosition(in size: CGSize) -> CGSize {
        clampedPanOffset(
            CGSize(
                width: panOffset.width + gestureTranslation.width,
                height: panOffset.height + gestureTranslation.height
            ),
            in: size
        )
    }

    private func clampedPanOffset(
        _ offset: CGSize,
        in size: CGSize?
    ) -> CGSize {
        guard let size else { return offset }
        let pageWidth = fitWidth(in: size.width)
        let pageHeight = max(1, size.height - 32)
        let maximumX = max(0, pageWidth * (displayedZoom - 1) / 2)
        let maximumY = max(0, pageHeight * (displayedZoom - 1) / 2)
        return CGSize(
            width: min(maximumX, max(-maximumX, offset.width)),
            height: min(maximumY, max(-maximumY, offset.height))
        )
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, value))
    }

    private func applyMagnification(_ magnification: CGFloat) {
        zoom = clampedZoom(zoom * magnification)
        if zoom <= 1 {
            panOffset = .zero
        } else {
            panOffset = clampedPanOffset(panOffset, in: nil)
        }
    }

    private func zoomIn() {
        changeZoom(by: 0.25)
    }

    private func zoomOut() {
        changeZoom(by: -0.25)
    }

    private func changeZoom(by amount: CGFloat) {
        zoom = clampedZoom(zoom + amount)
        if zoom <= 1 {
            panOffset = .zero
        }
    }

    private func resetZoom() {
        zoom = 1
        panOffset = .zero
    }

    private func updatePosition() {
        position = pages.isEmpty
            ? .empty
            : PDFPagePosition(current: currentPage + 1, total: pages.count)
    }

    private func navigateToVerticalPage() {
        guard let verticalPage, verticalPage != 0 else { return }
        if verticalPage > 0 {
            guard canSelectNextCard else {
                resetVerticalPage()
                return
            }
            nextCardAction()
        } else {
            guard canSelectPreviousCard else {
                resetVerticalPage()
                return
            }
            previousCardAction()
        }
        resetVerticalPage()
    }

    private func resetVerticalPage() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            verticalPage = 0
        }
    }
}

struct PDFPagePosition: Equatable {
    var current: Int
    var total: Int

    static let empty = PDFPagePosition(current: 0, total: 0)
}

private struct RenderedPDFPage: Identifiable {
    struct ID: Hashable {
        let documentFingerprint: Int
        let pageIndex: Int
    }

    let index: Int
    let image: CGImage
    let documentFingerprint: Int

    var id: ID { ID(documentFingerprint: documentFingerprint, pageIndex: index) }
}

private struct AdaptivePDFPageImage: View {
    private let data: Data
    private let page: RenderedPDFPage
    private let zoom: CGFloat
    @State private var image: CGImage

    init(data: Data, page: RenderedPDFPage, zoom: CGFloat) {
        self.data = data
        self.page = page
        self.zoom = zoom
        _image = State(initialValue: page.image)
    }

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .task(id: targetPixelHeight) {
                guard image.height != targetPixelHeight else { return }

                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let pdfData = data
                let pageIndex = page.index
                let pixelHeight = targetPixelHeight
                let renderedImage = await Task.detached(
                    priority: .userInitiated
                ) {
                    PDFPageRenderer.renderPage(
                        data: pdfData,
                        index: pageIndex,
                        pixelHeight: pixelHeight
                    )
                }.value

                guard !Task.isCancelled, let renderedImage else { return }
                image = renderedImage
            }
    }

    private var targetPixelHeight: Int {
        PDFPageRenderer.pixelHeight(for: zoom)
    }
}

private enum PDFPageRenderer {
    private static let basePixelHeight = 1800

    static func render(data: Data) -> [RenderedPDFPage] {
        guard let document = PDFDocument(data: data) else { return [] }
        let documentFingerprint = data.hashValue
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index),
                  let pdfPage = page.pageRef,
                  let image = render(
                    pdfPage: pdfPage,
                    pixelHeight: basePixelHeight
                  ) else { return nil }
            return RenderedPDFPage(
                index: index,
                image: image,
                documentFingerprint: documentFingerprint
            )
        }
    }

    static func renderPage(
        data: Data,
        index: Int,
        pixelHeight: Int
    ) -> CGImage? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: index),
              let pdfPage = page.pageRef else { return nil }
        return render(pdfPage: pdfPage, pixelHeight: pixelHeight)
    }

    static func pixelHeight(for zoom: CGFloat) -> Int {
        switch zoom {
        case ...1.25: basePixelHeight
        case ...1.75: 2700
        case ...2.25: 3600
        case ...2.75: 4500
        case ...3.25: 5400
        case ...3.75: 6300
        default: 7200
        }
    }

    private static func render(
        pdfPage: CGPDFPage,
        pixelHeight: Int
    ) -> CGImage? {
        let bounds = pdfPage.getBoxRect(.cropBox)
        let pixelWidth = max(
            1,
            Int(CGFloat(pixelHeight) * bounds.width / bounds.height)
        )
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(
            CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
        context.saveGState()
        context.scaleBy(
            x: CGFloat(pixelWidth) / bounds.width,
            y: CGFloat(pixelHeight) / bounds.height
        )
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(pdfPage)
        context.restoreGState()
        return context.makeImage()
    }
}
