import SwiftUI

struct CardSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let cards: [TeXCard]
    let selection: (UUID) -> Void

    @State private var keyword = ""
    @State private var isCaseSensitive = false

    private var results: [CardSearchResult] {
        CardSearchService.search(
            cards: cards,
            keyword: keyword,
            caseSensitive: isCaseSensitive
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("検索キーワード", text: $keyword)
                        .textFieldStyle(.roundedBorder)

                    Button("Aa") {
                        isCaseSensitive.toggle()
                    }
                    .buttonStyle(.bordered)
                    .tint(isCaseSensitive ? .accentColor : .gray)
                    .help(
                        isCaseSensitive
                            ? "大文字と小文字を区別する"
                            : "大文字と小文字を区別しない"
                    )

                    Button("クリア", systemImage: "xmark.circle.fill") {
                        keyword = ""
                    }
                    .labelStyle(.iconOnly)
                    .disabled(keyword.isEmpty)

                    Text("\(results.count)件")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 48, alignment: .trailing)
                }
                .padding()

                Divider()

                if results.isEmpty {
                    ContentUnavailableView.search(text: keyword)
                } else {
                    List(results) { result in
                        Button {
                            selection(result.cardID)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.title)
                                    .font(.headline)
                                Text(result.excerpt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("検索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .frame(idealWidth: 620, minHeight: 420)
    }
}
