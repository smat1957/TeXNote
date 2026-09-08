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
        textView.textColor = .label
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
        context.coordinator.startObservingKeyboard()
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
        } else {
            if context.coordinator.searchConfigurationChanged {
                context.coordinator.refreshHighlighting()
            }
            if textView.selectedRange != selection {
                let range = clamped(selection, length: textView.text.utf16.count)
                textView.selectedRange = range
                textView.scrollRangeToVisible(range)
            }
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
        private var contentOffsetBeforeKeyboard: CGPoint?
        var lastSearchText = ""
        var lastSearchIsCaseSensitive = false

        var searchConfigurationChanged: Bool {
            lastSearchText != parent.searchText
                || lastSearchIsCaseSensitive != parent.searchIsCaseSensitive
        }

        init(parent: TeXSourceEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func startObservingKeyboard() {
            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(keyboardWillShow(_:)),
                name: UIResponder.keyboardWillShowNotification,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(keyboardDidShow(_:)),
                name: UIResponder.keyboardDidShowNotification,
                object: nil
            )
        }

        @objc private func keyboardWillShow(_ notification: Notification) {
            guard let textView, textView.isFirstResponder else { return }
            contentOffsetBeforeKeyboard = textView.contentOffset
        }

        @objc private func keyboardDidShow(_ notification: Notification) {
            restoreViewportAfterKeyboardAppears()
        }

        private func restoreViewportAfterKeyboardAppears() {
            guard let textView,
                  textView.isFirstResponder,
                  let contentOffsetBeforeKeyboard else { return }
            self.contentOffsetBeforeKeyboard = nil
            textView.layoutIfNeeded()
            textView.setContentOffset(contentOffsetBeforeKeyboard, animated: false)

            guard let position = textView.position(
                from: textView.beginningOfDocument,
                offset: textView.selectedRange.location
            ) else { return }
            let caretRect = textView.caretRect(for: position)
            let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
                .insetBy(dx: 0, dy: 8)
            if !visibleRect.intersects(caretRect) {
                textView.scrollRangeToVisible(textView.selectedRange)
            }
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
            isApplyingHighlight = true
            highlightAttributes(textView)
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
            if let layoutManager = textView.textLayoutManager,
               let contentManager = layoutManager.textContentManager {
                layoutManager.invalidateRenderingAttributes(
                    for: contentManager.documentRange
                )
                for span in TeXSyntaxHighlighting.spans(in: textView.text) {
                    guard let range = textRange(for: span.range, in: contentManager) else {
                        continue
                    }
                    layoutManager.setRenderingAttributes(
                        [.foregroundColor: color(for: span.kind)],
                        for: range
                    )
                }
                for searchRange in TeXSyntaxHighlighting.searchRanges(
                    in: textView.text,
                    query: parent.searchText,
                    caseSensitive: parent.searchIsCaseSensitive
                ) {
                    guard let range = textRange(for: searchRange, in: contentManager) else {
                        continue
                    }
                    layoutManager.setRenderingAttributes(
                        [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.45)],
                        for: range
                    )
                }
            }
            textView.typingAttributes = [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            lastSearchText = parent.searchText
            lastSearchIsCaseSensitive = parent.searchIsCaseSensitive
        }

        private func textRange(
            for range: NSRange,
            in contentManager: NSTextContentManager
        ) -> NSTextRange? {
            let documentStart = contentManager.documentRange.location
            guard let start = contentManager.location(
                documentStart,
                offsetBy: range.location
            ), let end = contentManager.location(
                start,
                offsetBy: range.length
            ) else {
                return nil
            }
            return NSTextRange(location: start, end: end)
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
        lineNumberView.isHidden = true
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
        guard !isHidden, bounds.width > 0, let textView else { return }

        let string = textView.text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ]

        var lineIndex = 0
        var characterOffset = 0
        while characterOffset <= string.length {
            guard let position = textView.position(
                from: textView.beginningOfDocument,
                offset: characterOffset
            ) else { break }
            let caretRect = textView.caretRect(for: position)
            let caretInGutter = textView.convert(caretRect, to: self)
            if caretInGutter.maxY >= bounds.minY {
                if caretInGutter.minY > bounds.maxY { break }
                let label = "\(firstLineNumber + lineIndex)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: CGPoint(
                        x: bounds.width - size.width - 7,
                        y: caretInGutter.minY
                    ),
                    withAttributes: attributes
                )
            }

            let searchRange = NSRange(
                location: characterOffset,
                length: string.length - characterOffset
            )
            let newlineRange = string.range(of: "\n", range: searchRange)
            if newlineRange.location == NSNotFound { break }
            characterOffset = NSMaxRange(newlineRange)
            lineIndex += 1
        }
    }
}
