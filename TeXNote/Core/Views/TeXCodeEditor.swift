import SwiftUI

struct TeXCodeEditor: View {
    @Binding var text: String
    @Binding var selection: NSRange
    let placeholder: String
    var showsLineNumbers = false
    var searchText = ""
    var searchIsCaseSensitive = false
    var firstLineNumber = 1

    private var completions: [TeXCompletion] {
        TeXSyntaxHighlighting.completions(
            in: text,
            cursorUTF16Offset: selection.location
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TeXSourceEditor(
                    text: $text,
                    selection: $selection,
                    showsLineNumbers: showsLineNumbers,
                    searchText: searchText,
                    searchIsCaseSensitive: searchIsCaseSensitive,
                    firstLineNumber: firstLineNumber
                )

                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, showsLineNumbers ? 48 : 10)
                        .padding(.trailing, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }

            if !completions.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Label("入力候補", systemImage: "text.cursor")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(completions) { completion in
                            Button(completion.command) {
                                apply(completion)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(.bar)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private func apply(_ completion: TeXCompletion) {
        let result = TeXSyntaxHighlighting.applying(
            completion,
            to: text,
            selection: selection
        )
        text = result.text
        selection = result.selection
    }
}
