import Foundation

struct EditorSearchStatus {
    let ranges: [NSRange]
    let currentIndex: Int?

    var matchCount: Int { ranges.count }
    var displayedIndex: Int { currentIndex.map { $0 + 1 } ?? 0 }
}

struct EditorReplacementResult {
    let text: String
    let selection: NSRange
    let replacementCount: Int
}

enum EditorSearchService {
    static func status(
        in text: String,
        query: String,
        caseSensitive: Bool,
        selection: NSRange
    ) -> EditorSearchStatus {
        let ranges = TeXSyntaxHighlighting.searchRanges(
            in: text,
            query: query,
            caseSensitive: caseSensitive
        )
        return EditorSearchStatus(
            ranges: ranges,
            currentIndex: ranges.firstIndex(of: selection)
        )
    }

    static func replacingCurrent(
        in text: String,
        query: String,
        replacement: String,
        caseSensitive: Bool,
        selection: NSRange
    ) -> EditorReplacementResult? {
        let status = status(
            in: text,
            query: query,
            caseSensitive: caseSensitive,
            selection: selection
        )
        guard status.currentIndex != nil else { return nil }

        let source = text as NSString
        let updatedText = source.replacingCharacters(
            in: selection,
            with: replacement
        )
        let replacementEnd = selection.location + (replacement as NSString).length
        let updatedRanges = TeXSyntaxHighlighting.searchRanges(
            in: updatedText,
            query: query,
            caseSensitive: caseSensitive
        )
        let nextSelection = updatedRanges.first {
            $0.location >= replacementEnd
        } ?? updatedRanges.first ?? NSRange(location: replacementEnd, length: 0)

        return EditorReplacementResult(
            text: updatedText,
            selection: nextSelection,
            replacementCount: 1
        )
    }

    static func replacingAll(
        in text: String,
        query: String,
        replacement: String,
        caseSensitive: Bool
    ) -> EditorReplacementResult? {
        let ranges = TeXSyntaxHighlighting.searchRanges(
            in: text,
            query: query,
            caseSensitive: caseSensitive
        )
        guard !ranges.isEmpty else { return nil }

        let result = NSMutableString(string: text)
        for range in ranges.reversed() {
            result.replaceCharacters(in: range, with: replacement)
        }
        let updatedText = result as String
        let updatedRanges = TeXSyntaxHighlighting.searchRanges(
            in: updatedText,
            query: query,
            caseSensitive: caseSensitive
        )
        let selection = updatedRanges.first
            ?? NSRange(location: min(ranges[0].location, result.length), length: 0)

        return EditorReplacementResult(
            text: updatedText,
            selection: selection,
            replacementCount: ranges.count
        )
    }
}
