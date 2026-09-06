import SwiftUI
import UIKit

struct TeXSourceEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var showsLineNumbers: Bool
    var searchText: String
    var searchIsCaseSensitive: Bool
    var firstLineNumber: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = TeXLineNumberTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.adjustsFontForContentSizeCategory = true
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.keyboardDismissMode = .interactive
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.textContainer.heightTracksTextView = false
        textView.showsLineNumbers = showsLineNumbers
        textView.firstLineNumber = firstLineNumber
        context.coordinator.textView = textView
        context.coordinator.setText(text, selection: selection)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if let lineNumberTextView = textView as? TeXLineNumberTextView {
            lineNumberTextView.showsLineNumbers = showsLineNumbers
            lineNumberTextView.firstLineNumber = firstLineNumber
        }
        if textView.text != text {
            context.coordinator.setText(text, selection: selection)
        } else if context.coordinator.searchConfigurationChanged {
            context.coordinator.refreshHighlighting(scrollToFirstMatch: true)
        } else if textView.selectedRange != selection {
            let range = clamped(selection, length: textView.text.utf16.count)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(
            location: location,
            length: min(max(0, range.length), length - location)
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: TeXSourceEditor
        weak var textView: UITextView?
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

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            parent.text = textView.text
            parent.selection = textView.selectedRange
            highlight(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            if parent.selection != textView.selectedRange {
                parent.selection = textView.selectedRange
            }
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            var actions: [UIMenuElement] = []
            if range.length == 0 {
                actions.append(
                    UIAction(title: "選択") { [weak textView] _ in
                        textView?.select(nil)
                    }
                )
            } else {
                actions.append(
                    UIAction(title: "カット") { [weak textView] _ in
                        textView?.cut(nil)
                    }
                )
                actions.append(
                    UIAction(title: "コピー") { [weak textView] _ in
                        textView?.copy(nil)
                    }
                )
            }
            if textView.canPerformAction(
                #selector(UIResponderStandardEditActions.paste(_:)),
                withSender: nil
            ) {
                actions.append(
                    UIAction(title: "ペースト") { [weak textView] _ in
                        textView?.paste(nil)
                    }
                )
            }
            actions.append(
                UIAction(title: "すべて選択") { [weak textView] _ in
                    textView?.selectAll(nil)
                }
            )
            return UIMenu(children: actions)
        }

        func setText(_ text: String, selection: NSRange) {
            guard let textView else { return }
            isApplyingHighlight = true
            textView.text = text
            textView.selectedRange = clamp(selection, text.utf16.count)
            highlightAttributes(textView)
            textView.scrollRangeToVisible(textView.selectedRange)
            isApplyingHighlight = false
        }

        private func highlight(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            isApplyingHighlight = true
            highlightAttributes(textView)
            textView.selectedRange = clamp(selectedRange, textView.text.utf16.count)
            isApplyingHighlight = false
        }

        func refreshHighlighting(scrollToFirstMatch: Bool = false) {
            guard let textView else { return }
            highlight(textView)
            guard scrollToFirstMatch,
                  let firstMatch = TeXSyntaxHighlighting.searchRanges(
                      in: textView.text,
                      query: parent.searchText,
                      caseSensitive: parent.searchIsCaseSensitive
                  ).first else { return }
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            textView.scrollRangeToVisible(firstMatch)
        }

        private func highlightAttributes(_ textView: UITextView) {
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.label
            ], range: fullRange)
            for span in TeXSyntaxHighlighting.spans(in: textView.text) {
                storage.addAttribute(.foregroundColor, value: color(for: span.kind), range: span.range)
            }
            for range in TeXSyntaxHighlighting.searchRanges(
                in: textView.text,
                query: parent.searchText,
                caseSensitive: parent.searchIsCaseSensitive
            ) {
                storage.addAttribute(
                    .backgroundColor,
                    value: UIColor.systemYellow.withAlphaComponent(0.45),
                    range: range
                )
            }
            storage.endEditing()
            lastSearchText = parent.searchText
            lastSearchIsCaseSensitive = parent.searchIsCaseSensitive
        }

        private func color(for kind: TeXSyntaxKind) -> UIColor {
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

private final class TeXLineNumberTextView: UITextView {
    var firstLineNumber = 1 {
        didSet { setNeedsDisplay() }
    }

    var showsLineNumbers = false {
        didSet {
            textContainerInset = UIEdgeInsets(
                top: 8,
                left: showsLineNumbers ? 43 : 5,
                bottom: 8,
                right: 5
            )
            setNeedsDisplay()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let containerWidth = max(
            0,
            bounds.width - textContainerInset.left - textContainerInset.right
        )
        if textContainer.size.width != containerWidth
            || textContainer.size.height != CGFloat.greatestFiniteMagnitude {
            textContainer.size = CGSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        layoutManager.ensureLayout(for: textContainer)
        let laidOutHeight = layoutManager.usedRect(for: textContainer).maxY
            + textContainerInset.top
            + textContainerInset.bottom
        let requiredHeight = max(bounds.height, laidOutHeight)
        if abs(contentSize.height - requiredHeight) > 0.5 {
            contentSize = CGSize(width: bounds.width, height: requiredHeight)
        }

        if showsLineNumbers { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard showsLineNumbers else { return }

        let string = text as NSString
        let visibleTextContainerRect = bounds.offsetBy(
            dx: -textContainerInset.left,
            dy: -textContainerInset.top
        )
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleTextContainerRect,
            in: textContainer
        )
        var glyphIndex = visibleGlyphRange.location
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]

        while glyphIndex < NSMaxRange(visibleGlyphRange) {
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
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: CGPoint(
                        x: textContainerInset.left - size.width - 7,
                        y: fragment.minY + textContainerInset.top
                    ),
                    withAttributes: attributes
                )
            }
            glyphIndex = max(NSMaxRange(effectiveRange), glyphIndex + 1)
        }
    }
}
