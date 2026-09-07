import Foundation

public struct Token: Equatable {
    public let range: NSRange
    public let kind: TokenKind
}

/// Regex-based tokenizer. Rules run in order; the caller paints tokens in that order so later rules win.
// ponytail: no incremental state. Block comments that span the highlighted range go stale in
// paragraph-only mode. Upgrade path: tree-sitter via Neon.
public final class Highlighter {
    private var cache: [String: NSRegularExpression] = [:]

    public init() {}

    public func tokens(in text: String, range: NSRange? = nil, language: Language) -> [Token] {
        let full = NSRange(location: 0, length: (text as NSString).length)
        let r = range ?? full
        var out: [Token] = []
        for rule in language.rules {
            let re = regex(rule.pattern)
            re.enumerateMatches(in: text, options: [], range: r) { m, _, _ in
                if let m { out.append(Token(range: m.range, kind: rule.kind)) }
            }
        }
        return out
    }

    private func regex(_ pattern: String) -> NSRegularExpression {
        if let r = cache[pattern] { return r }
        // Patterns are compile-time constants covered by tests; a bad one is a programmer error.
        let r = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        cache[pattern] = r
        return r
    }
}
