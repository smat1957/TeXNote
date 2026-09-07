import AppKit
import SwiftUI

struct TeXSourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var showsLineNumbers: Bool
    var searchText: String
    var searchIsCaseSensitive: Bool
    var firstLineNumber: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = showsLineNumbers

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        scrollView.verticalRulerView = TeXLineNumberRulerView(
            textView: textView,
            scrollView: scrollView,
            firstLineNumber: firstLineNumber
        )
        context.coordinator.textView = textView
        context.coordinator.setText(text, selection: selection)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        scrollView.rulersVisible = showsLineNumbers
        if let ruler = scrollView.verticalRulerView as? TeXLineNumberRulerView {
            ruler.firstLineNumber = firstLineNumber
        }
        guard let textView = context.coordinator.textView else { return }
        guard !textView.hasMarkedText() else { return }
        if textView.string != text {
            context.coordinator.setText(text, selection: selection)
        } else if context.coordinator.searchConfigurationChanged {
            context.coordinator.refreshHighlighting(scrollToFirstMatch: true)
        } else if textView.selectedRange() != selection {
            let range = clamped(selection, length: textView.string.utf16.count)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }

    private func clamped(_ range: NSRange, length: Int) -> NSRange {
        NSRange(
            location: min(max(0, range.location), length),
            length: min(max(0, range.length), max(0, length - range.location))
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TeXSourceEditor
        weak var textView: NSTextView?
        private var isApplyingHighlight = false
        var lastSearchText = ""
        var lastSearchIsCaseSensitive = false

        var searchConfigurationChanged: Bool {
            lastSearchText != parent.searchText
                || lastSearchIsCaseSensitive != parent.searchIsCaseSensitive
        }

        init(parent: TeXSourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingHighlight,
                  let textView,
                  !textView.hasMarkedText() else {
                return
            }
            parent.text = textView.string
            parent.selection = textView.selectedRange()
            highlight(textView)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingHighlight,
                  let textView,
                  !textView.hasMarkedText() else {
                return
            }
            let newSelection = textView.selectedRange()
            if parent.selection != newSelection {
                parent.selection = newSelection
            }
        }

        func setText(_ text: String, selection: NSRange) {
            guard let textView else { return }
            isApplyingHighlight = true
            textView.string = text
            textView.setSelectedRange(clamp(selection, text.utf16.count))
            highlightAttributes(textView)
            textView.scrollRangeToVisible(textView.selectedRange())
            isApplyingHighlight = false
        }

        private func highlight(_ textView: NSTextView) {
            guard !textView.hasMarkedText() else { return }
            let selectedRange = textView.selectedRange()
            isApplyingHighlight = true
            highlightAttributes(textView)
            textView.setSelectedRange(clamp(selectedRange, textView.string.utf16.count))
            isApplyingHighlight = false
        }

        func refreshHighlighting(scrollToFirstMatch: Bool = false) {
            guard let textView else { return }
            highlight(textView)
            guard scrollToFirstMatch,
                  let textContainer = textView.textContainer,
                  let firstMatch = TeXSyntaxHighlighting.searchRanges(
                      in: textView.string,
                      query: parent.searchText,
                      caseSensitive: parent.searchIsCaseSensitive
                  ).first else { return }
            textView.layoutManager?.ensureLayout(for: textContainer)
            textView.scrollRangeToVisible(firstMatch)
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        private func highlightAttributes(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.textColor
            ], range: fullRange)
            for span in TeXSyntaxHighlighting.spans(in: textView.string) {
                storage.addAttribute(.foregroundColor, value: color(for: span.kind), range: span.range)
            }
            for range in TeXSyntaxHighlighting.searchRanges(
                in: textView.string,
                query: parent.searchText,
                caseSensitive: parent.searchIsCaseSensitive
            ) {
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.55),
                    range: range
                )
            }
            storage.endEditing()
            lastSearchText = parent.searchText
            lastSearchIsCaseSensitive = parent.searchIsCaseSensitive
        }

        private func color(for kind: TeXSyntaxKind) -> NSColor {
            switch kind {
            case .command: .systemBlue
            case .comment: .systemGreen
            case .math: .systemPurple
            case .environment: .systemOrange
            }
        }

        private func clamp(_ range: NSRange, _ length: Int) -> NSRange {
            let location = min(max(0, range.location), length)
            return NSRange(
                location: location,
                length: min(max(0, range.length), length - location)
            )
        }
    }
}

private final class TeXLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    var firstLineNumber: Int {
        didSet { needsDisplay = true }
    }

    init(
        textView: NSTextView,
        scrollView: NSScrollView,
        firstLineNumber: Int
    ) {
        self.textView = textView
        self.firstLineNumber = firstLineNumber
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 42
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func refresh() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let string = textView.string as NSString
        var glyphIndex = glyphRange.location

        while glyphIndex < NSMaxRange(glyphRange) {
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let isLogicalLineStart = characterIndex == 0
                || string.character(at: characterIndex - 1) == 10
            let relativeLineNumber = string.substring(to: characterIndex)
                .reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            var effectiveRange = NSRange()
            let fragment = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveRange
            )
            if isLogicalLineStart {
                let label = "\(firstLineNumber + relativeLineNumber - 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.smallSystemFontSize,
                        weight: .regular
                    ),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(
                        x: ruleThickness - size.width - 7,
                        y: fragment.minY + textView.textContainerInset.height
                            - visibleRect.minY
                    ),
                    withAttributes: attributes
                )
            }
            glyphIndex = NSMaxRange(effectiveRange)
        }
    }
}
