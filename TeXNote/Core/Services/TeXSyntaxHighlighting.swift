import Foundation

enum TeXSyntaxKind: Sendable {
    case command
    case comment
    case math
    case environment
}

struct TeXSyntaxSpan: Sendable {
    let range: NSRange
    let kind: TeXSyntaxKind
}

struct TeXCompletion: Identifiable, Equatable, Sendable {
    let command: String
    let insertion: String
    let cursorBacktrack: Int

    var id: String { command }
}

enum TeXSyntaxHighlighting {
    private static let patterns: [(String, TeXSyntaxKind, NSRegularExpression.Options)] = [
        (#"\\[A-Za-z@]+|\\[^A-Za-z\s]"#, .command, []),
        (#"\\(?:begin|end)\{[^}\n]+\}"#, .environment, []),
        (#"(?s)\\\[.*?\\\]|\\\(.*?\\\)|(?<!\\)\$\$.*?(?<!\\)\$\$|(?<!\\)\$(?:\\.|[^$\n])*?(?<!\\)\$"#, .math, []),
        (#"(?m)(?<!\\)%.*$"#, .comment, [])
    ]

    private static let commands: [TeXCompletion] = [
        .init(command: #"\begin"#, insertion: #"\begin{}"#, cursorBacktrack: 1),
        .init(command: #"\end"#, insertion: #"\end{}"#, cursorBacktrack: 1),
        .init(command: #"\section"#, insertion: #"\section{}"#, cursorBacktrack: 1),
        .init(command: #"\subsection"#, insertion: #"\subsection{}"#, cursorBacktrack: 1),
        .init(command: #"\textbf"#, insertion: #"\textbf{}"#, cursorBacktrack: 1),
        .init(command: #"\textit"#, insertion: #"\textit{}"#, cursorBacktrack: 1),
        .init(command: #"\emph"#, insertion: #"\emph{}"#, cursorBacktrack: 1),
        .init(command: #"\item"#, insertion: #"\item "#, cursorBacktrack: 0),
        .init(command: #"\label"#, insertion: #"\label{}"#, cursorBacktrack: 1),
        .init(command: #"\ref"#, insertion: #"\ref{}"#, cursorBacktrack: 1),
        .init(command: #"\cite"#, insertion: #"\cite{}"#, cursorBacktrack: 1),
        .init(command: #"\includegraphics"#, insertion: #"\includegraphics{}"#, cursorBacktrack: 1),
        .init(command: #"\input"#, insertion: #"\input{}"#, cursorBacktrack: 1),
        .init(command: #"\usepackage"#, insertion: #"\usepackage{}"#, cursorBacktrack: 1),
        .init(command: #"\documentclass"#, insertion: #"\documentclass{}"#, cursorBacktrack: 1),
        .init(command: #"\frac"#, insertion: #"\frac{}{}"#, cursorBacktrack: 3),
        .init(command: #"\sqrt"#, insertion: #"\sqrt{}"#, cursorBacktrack: 1),
        .init(command: #"\mathrm"#, insertion: #"\mathrm{}"#, cursorBacktrack: 1),
        .init(command: #"\mathbf"#, insertion: #"\mathbf{}"#, cursorBacktrack: 1),
        .init(command: #"\left"#, insertion: #"\left"#, cursorBacktrack: 0),
        .init(command: #"\right"#, insertion: #"\right"#, cursorBacktrack: 0)
    ]

    static func spans(in text: String) -> [TeXSyntaxSpan] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var spans: [TeXSyntaxSpan] = []
        for (pattern, kind, options) in patterns {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: options
            ) else { continue }
            spans.append(contentsOf: expression.matches(in: text, range: range).map {
                TeXSyntaxSpan(range: $0.range, kind: kind)
            })
        }
        return spans
    }

    static func searchRanges(
        in text: String,
        query: String,
        caseSensitive: Bool = false
    ) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let needle = query
        var options: NSString.CompareOptions = [.diacriticInsensitive]
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        let source = text as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let match = source.range(
                of: needle,
                options: options,
                range: searchRange
            )
            guard match.location != NSNotFound else { break }
            ranges.append(match)
            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(
                location: nextLocation,
                length: source.length - nextLocation
            )
        }
        return ranges
    }

    static func nextSearchRange(
        in text: String,
        query: String,
        caseSensitive: Bool,
        after selection: NSRange
    ) -> NSRange? {
        let ranges = searchRanges(
            in: text,
            query: query,
            caseSensitive: caseSensitive
        )
        guard !ranges.isEmpty else { return nil }
        let nextLocation = NSMaxRange(selection)
        return ranges.first { $0.location >= nextLocation } ?? ranges.first
    }

    static func selectionRange(
        forDisplayedLine lineNumber: Int,
        in text: String,
        firstLineNumber: Int
    ) -> NSRange? {
        guard lineNumber >= firstLineNumber else { return nil }
        let targetIndex = lineNumber - firstLineNumber
        let units = Array(text.utf16)
        var currentIndex = 0
        var location = 0
        if targetIndex == 0 {
            return NSRange(location: 0, length: 0)
        }
        for (index, unit) in units.enumerated() where unit == 10 {
            currentIndex += 1
            location = index + 1
            if currentIndex == targetIndex {
                return NSRange(location: location, length: 0)
            }
        }
        return nil
    }

    static func completions(
        in text: String,
        cursorUTF16Offset: Int
    ) -> [TeXCompletion] {
        let nsText = text as NSString
        let cursor = min(max(0, cursorUTF16Offset), nsText.length)
        let beforeCursor = nsText.substring(to: cursor)
        guard let expression = try? NSRegularExpression(
            pattern: #"\\[A-Za-z@]*$"#
        ), let match = expression.firstMatch(
            in: beforeCursor,
            range: NSRange(location: 0, length: (beforeCursor as NSString).length)
        ) else { return [] }

        let prefix = (beforeCursor as NSString).substring(with: match.range)
        guard prefix.count >= 2 else { return [] }
        return commands.filter {
            $0.command.hasPrefix(prefix) && $0.command != prefix
        }.prefix(6).map { $0 }
    }

    static func applying(
        _ completion: TeXCompletion,
        to text: String,
        selection: NSRange
    ) -> (text: String, selection: NSRange) {
        let nsText = text as NSString
        let cursor = min(max(0, selection.location), nsText.length)
        let beforeCursor = nsText.substring(to: cursor) as NSString
        let expression = try? NSRegularExpression(pattern: #"\\[A-Za-z@]*$"#)
        let match = expression?.firstMatch(
            in: beforeCursor as String,
            range: NSRange(location: 0, length: beforeCursor.length)
        )
        let replacementRange = match?.range ?? NSRange(location: cursor, length: 0)
        let result = nsText.replacingCharacters(
            in: replacementRange,
            with: completion.insertion
        )
        let location = replacementRange.location
            + (completion.insertion as NSString).length
            - completion.cursorBacktrack
        return (result, NSRange(location: location, length: 0))
    }
}
