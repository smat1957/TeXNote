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
