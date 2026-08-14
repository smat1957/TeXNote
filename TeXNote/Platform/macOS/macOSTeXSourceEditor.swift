import AppKit
import SwiftUI

struct TeXSourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

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
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.setText(text, selection: selection)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            context.coordinator.setText(text, selection: selection)
        } else if textView.selectedRange() != selection {
            textView.setSelectedRange(clamped(selection, length: textView.string.utf16.count))
        }
    }

    private func clamped(_ range: NSRange, length: Int) -> NSRange {
        NSRange(
            location: min(max(0, range.location), length),
            length: min(max(0, range.length), max(0, length - range.location))
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TeXSourceEditor
        weak var textView: NSTextView?
        private var isApplyingHighlight = false

        init(parent: TeXSourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingHighlight, let textView else { return }
            parent.text = textView.string
            parent.selection = textView.selectedRange()
            highlight(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingHighlight, let textView else { return }
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
            isApplyingHighlight = false
        }

        private func highlight(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            isApplyingHighlight = true
            highlightAttributes(textView)
            textView.setSelectedRange(clamp(selectedRange, textView.string.utf16.count))
            isApplyingHighlight = false
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
            storage.endEditing()
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
