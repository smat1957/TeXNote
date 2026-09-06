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

    func makeUIView(context: Context) -> TeXEditorContainerView {
        let container = TeXEditorContainerView()
        let textView = container.textView
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
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        container.showsLineNumbers = showsLineNumbers
        container.firstLineNumber = firstLineNumber
        context.coordinator.textView = textView
        context.coordinator.container = container
        context.coordinator.setText(text, selection: selection)
        return container
    }

    func updateUIView(_ container: TeXEditorContainerView, context: Context) {
        context.coordinator.parent = self
        let textView = container.textView
        container.showsLineNumbers = showsLineNumbers
        container.firstLineNumber = firstLineNumber
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
        weak var container: TeXEditorContainerView?
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
            container?.refreshLineNumbers()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            if parent.selection != textView.selectedRange {
                parent.selection = textView.selectedRange
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            container?.refreshLineNumbers()
        }

        func setText(_ text: String, selection: NSRange) {
            guard let textView else { return }
            isApplyingHighlight = true
            textView.text = text
            textView.selectedRange = clamp(selection, text.utf16.count)
            highlightAttributes(textView)
            textView.scrollRangeToVisible(textView.selectedRange)
            isApplyingHighlight = false
            container?.refreshLineNumbers()
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
            textView.typingAttributes = [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.label
            ]
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

/// 標準の編集操作を保つため、行番号をUITextViewの外側に配置する。
final class TeXEditorContainerView: UIView {
    let textView = UITextView()
    private lazy var lineNumberView = TeXLineNumberView(textView: textView)

    var firstLineNumber = 1 {
        didSet {
            guard firstLineNumber != oldValue else { return }
            lineNumberView.firstLineNumber = firstLineNumber
        }
    }

    var showsLineNumbers = false {
        didSet {
            guard showsLineNumbers != oldValue else { return }
            lineNumberView.isHidden = !showsLineNumbers
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(lineNumberView)
        addSubview(textView)
        lineNumberView.isUserInteractionEnabled = false
        lineNumberView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let lineNumberWidth: CGFloat = showsLineNumbers ? 42 : 0
        lineNumberView.frame = CGRect(
            x: 0,
            y: 0,
            width: lineNumberWidth,
            height: bounds.height
        )
        textView.frame = CGRect(
            x: lineNumberWidth,
            y: 0,
            width: max(0, bounds.width - lineNumberWidth),
            height: bounds.height
        )
        refreshLineNumbers()
    }

    func refreshLineNumbers() {
        guard showsLineNumbers else { return }
        lineNumberView.setNeedsDisplay()
    }
}

/// UITextViewへ入力イベントを追加せず、現在の表示範囲の行番号だけを描画する。
private final class TeXLineNumberView: UIView {
    private weak var textView: UITextView?
    var firstLineNumber = 1 {
        didSet { setNeedsDisplay() }
    }

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let textView else { return }

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        layoutManager.ensureLayout(for: textContainer)
        let string = textView.text as NSString
        let visibleTextContainerRect = textView.bounds.offsetBy(
            dx: -textView.textContainerInset.left,
            dy: -textView.textContainerInset.top
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
                        x: bounds.width - size.width - 7,
                        y: fragment.minY
                            + textView.textContainerInset.top
                            - textView.contentOffset.y
                    ),
                    withAttributes: attributes
                )
            }
            glyphIndex = max(NSMaxRange(effectiveRange), glyphIndex + 1)
        }
    }
}
