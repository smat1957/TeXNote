import Foundation
import PDFKit

struct CardSearchResult: Identifiable {
    let cardID: UUID
    let title: String
    let excerpt: String

    var id: UUID { cardID }
}

enum CardSearchService {
    static func search(
        cards: [TeXCard],
        keyword: String,
        caseSensitive: Bool
    ) -> [CardSearchResult] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return cards.compactMap { card in
            let pdfText = card.pdfData.flatMap {
                PDFDocument(data: $0)?.string
            } ?? ""
            guard query.isEmpty
                    || contains(card.title, query, caseSensitive: caseSensitive)
                    || contains(pdfText, query, caseSensitive: caseSensitive) else {
                return nil
            }
            return CardSearchResult(
                cardID: card.id,
                title: card.title,
                excerpt: excerpt(
                    from: pdfText,
                    matching: query,
                    caseSensitive: caseSensitive
                )
            )
        }
    }

    private static func contains(
        _ text: String,
        _ query: String,
        caseSensitive: Bool
    ) -> Bool {
        text.range(
            of: query,
            options: caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private static func excerpt(
        from text: String,
        matching query: String,
        caseSensitive: Bool
    ) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "PDFテキストはありません" }

        let matchingIndex = lines.firstIndex {
            contains($0, query, caseSensitive: caseSensitive)
        } ?? 0
        let lower = max(0, matchingIndex - 1)
        let upper = min(lines.count, lower + 3)
        return lines[lower..<upper].joined(separator: "\n")
    }
}
