import SwiftUI
import UIKit

struct TeXSourceEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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
        context.coordinator.textView = textView
        context.coordinator.setText(text, selection: selection)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            context.coordinator.setText(text, selection: selection)
        } else if textView.selectedRange != selection {
            textView.selectedRange = clamped(selection, length: textView.text.utf16.count)
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
        private var isApplyingHighlight = false

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

        func setText(_ text: String, selection: NSRange) {
            guard let textView else { return }
            isApplyingHighlight = true
            textView.text = text
            textView.selectedRange = clamp(selection, text.utf16.count)
            highlightAttributes(textView)
            isApplyingHighlight = false
        }

        private func highlight(_ textView: UITextView) {
            let selectedRange = textView.selectedRange
            isApplyingHighlight = true
            highlightAttributes(textView)
            textView.selectedRange = clamp(selectedRange, textView.text.utf16.count)
            isApplyingHighlight = false
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
            storage.endEditing()
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
