import SwiftUI

struct CardDetailView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var pdfPosition = PDFPagePosition.empty
    @Binding var card: TeXCard
    let editsTitle: Bool
    let titleChanged: () -> Void
    let canSelectNextCard: Bool
    let canSelectPreviousCard: Bool
    let editAction: () -> Void
    let addRelatedAction: () -> Void
    let deleteAction: () -> Void
    let nextCardAction: () -> Void
    let previousCardAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            cardTitleBar

            Divider()

            if let data = card.pdfData {
                PDFPageCarousel(
                    data: data,
                    position: $pdfPosition,
                    canSelectNextCard: canSelectNextCard,
                    canSelectPreviousCard: canSelectPreviousCard,
                    nextCardAction: nextCardAction,
                    previousCardAction: previousCardAction
                )
                .background(Color.gray.opacity(0.30))
            } else {
                ContentUnavailableView {
                    Label("PDFなし", systemImage: "doc.badge.ellipsis")
                } description: {
                    Text("編集画面から保存・版組してください。")
                } actions: {
                    Button("編集して版組", action: editAction)
                }
            }
        }
    }

    private var cardTitleBar: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(spacing: 6) {
                    cardTitle
                    cardMetadataAndActions
                }
            } else {
                ZStack {
                    cardTitle
                    cardMetadataAndActions
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }

    private var cardTitle: some View {
        VStack(spacing: 2) {
            Group {
                if editsTitle {
                    TextField("Card名", text: $card.title)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            .quaternary,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .onChange(of: card.title) {
                            titleChanged()
                        }
                } else {
                    Text(card.title)
                        .lineLimit(1)
                }
            }
            .font(.headline)
            .frame(maxWidth: 320)
            HStack(spacing: 8) {
                Text(card.pdfStatus.label)
                    .foregroundStyle(statusColor)

                if pdfPosition.total > 0 {
                    Text("\(pdfPosition.current)／\(pdfPosition.total)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
    }

    private var cardMetadataAndActions: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lastTypesetDateText)
                Text("（\(formatted(card.createdAt))）")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("編集", systemImage: "pencil", action: editAction)
                .labelStyle(.iconOnly)

            Menu {
                Group {
                    Button(
                        "関連記事の追加",
                        systemImage: "link",
                        action: addRelatedAction
                    )

                    Divider()

                    Button(
                        "削除",
                        systemImage: "trash",
                        role: .destructive,
                        action: deleteAction
                    )
                }
                .labelStyle(.titleAndIcon)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Cardメニュー")
            }
        }
        .buttonStyle(.borderless)
    }

    private var lastTypesetDateText: String {
        guard let date = card.lastTypesetAt else { return "未版組" }
        return formatted(date)
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var statusColor: Color {
        switch card.pdfStatus {
        case .current: .green
        case .outdated: .orange
        case .notTypeset: .secondary
        }
    }
}
