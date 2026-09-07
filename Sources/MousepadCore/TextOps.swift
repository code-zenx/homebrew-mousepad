import Foundation

/// One replacement the editor should apply, plus the selection to leave behind.
/// Ranges are UTF-16 (`NSRange`) so they plug straight into `NSTextView`.
public struct TextEdit: Equatable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    public func apply(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

public enum CaseKind: Sendable { case lower, upper, title, opposite }

/// Pure text operations behind the Edit menu. Input: text + selection. Output: a `TextEdit`.
public enum TextOps {
    private static func len(_ s: String) -> Int { (s as NSString).length }

    /// A selection that ends right after a newline would otherwise pull the next line in.
    private static func trimmed(_ sel: NSRange, _ s: NSString) -> NSRange {
        guard sel.length > 0, s.character(at: NSMaxRange(sel) - 1) == 10 else { return sel }
        return NSRange(location: sel.location, length: sel.length - 1)
    }

    private static func splitLines(_ s: NSString, _ sel: NSRange) -> (range: NSRange, lines: [String], trailingNewline: Bool) {
        let r = s.lineRange(for: trimmed(sel, s))
        var block = s.substring(with: r)
        let nl = block.hasSuffix("\n")
        if nl { block.removeLast() }
        return (r, block.components(separatedBy: "\n"), nl)
    }

    private static func linesEdit(_ s: NSString, _ sel: NSRange, _ f: (String) -> String) -> TextEdit {
        let (r, lines, nl) = splitLines(s, sel)
        let out = lines.map(f).joined(separator: "\n") + (nl ? "\n" : "")
        return TextEdit(range: r, replacement: out, selection: NSRange(location: r.location, length: len(out)))
    }

    /// Selected lines, or the whole text when nothing is selected.
    private static func scopedEdit(_ s: NSString, _ sel: NSRange, _ f: (String) -> String) -> TextEdit {
        let r = sel.length > 0 ? s.lineRange(for: trimmed(sel, s)) : NSRange(location: 0, length: s.length)
        let out = f(s.substring(with: r))
        let selection = sel.length > 0
            ? NSRange(location: r.location, length: len(out))
            : NSRange(location: min(sel.location, len(out)), length: 0)
        return TextEdit(range: r, replacement: out, selection: selection)
    }

    public static func indent(_ s: NSString, _ sel: NSRange, unit: String) -> TextEdit {
        linesEdit(s, sel) { $0.isEmpty ? $0 : unit + $0 }
    }

    public static func unindent(_ s: NSString, _ sel: NSRange, tabWidth: Int) -> TextEdit {
        linesEdit(s, sel) { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix { $0 == " " }.count
            return String(line.dropFirst(min(spaces, tabWidth)))
        }
    }

    public static func changeCase(_ s: NSString, _ sel: NSRange, _ kind: CaseKind) -> TextEdit? {
        guard sel.length > 0 else { return nil }
        let t = s.substring(with: sel)
        let out: String
        switch kind {
        case .lower: out = t.lowercased()
        case .upper: out = t.uppercased()
        case .title: out = t.capitalized
        case .opposite:
            out = t.map { c -> String in
                if c.isUppercase { return c.lowercased() }
                if c.isLowercase { return c.uppercased() }
                return String(c)
            }.joined()
        }
        return TextEdit(range: sel, replacement: out, selection: NSRange(location: sel.location, length: len(out)))
    }

    /// Column-aware: a tab expands to the next tab stop, not a fixed count.
    public static func tabsToSpaces(_ s: NSString, _ sel: NSRange, tabWidth: Int) -> TextEdit {
        scopedEdit(s, sel) { t in
            var out = ""
            var col = 0
            for c in t {
                if c == "\t" {
                    let n = tabWidth - col % tabWidth
                    out += String(repeating: " ", count: n)
                    col += n
                } else if c == "\n" {
                    out.append(c)
                    col = 0
                } else {
                    out.append(c)
                    col += 1
                }
            }
            return out
        }
    }

    // ponytail: leading indentation only. Mid-line space runs are usually alignment; leave them.
    public static func spacesToTabs(_ s: NSString, _ sel: NSRange, tabWidth: Int) -> TextEdit {
        scopedEdit(s, sel) { t in
            t.components(separatedBy: "\n").map { line in
                let n = line.prefix { $0 == " " }.count
                guard n >= tabWidth else { return line }
                return String(repeating: "\t", count: n / tabWidth)
                    + String(repeating: " ", count: n % tabWidth)
                    + line.dropFirst(n)
            }.joined(separator: "\n")
        }
    }

    public static func stripTrailingSpaces(_ s: NSString, _ sel: NSRange) -> TextEdit {
        scopedEdit(s, sel) { $0.replacingOccurrences(of: "(?m)[ \\t]+$", with: "", options: .regularExpression) }
    }

    /// Swap the selected lines with the line above or below. Selection follows the text.
    public static func moveLines(_ s: NSString, _ sel: NSRange, up: Bool) -> TextEdit? {
        let cur = s.lineRange(for: trimmed(sel, s))
        var curText = s.substring(with: cur)
        let curNL = curText.hasSuffix("\n")
        if curNL { curText.removeLast() }
        let delta = sel.location - cur.location

        if up {
            guard cur.location > 0 else { return nil }
            let prev = s.lineRange(for: NSRange(location: cur.location - 1, length: 0))
            var prevText = s.substring(with: prev)
            prevText.removeLast()   // always ends with "\n": a line follows it
            let out = curText + "\n" + prevText + (curNL ? "\n" : "")
            let whole = NSRange(location: prev.location, length: prev.length + cur.length)
            return TextEdit(range: whole, replacement: out,
                            selection: NSRange(location: prev.location + delta, length: sel.length))
        } else {
            let end = NSMaxRange(cur)
            guard curNL, end < s.length else { return nil }
            let next = s.lineRange(for: NSRange(location: end, length: 0))
            var nextText = s.substring(with: next)
            let nextNL = nextText.hasSuffix("\n")
            if nextNL { nextText.removeLast() }
            let out = nextText + "\n" + curText + (nextNL ? "\n" : "")
            let whole = NSRange(location: cur.location, length: cur.length + next.length)
            return TextEdit(range: whole, replacement: out,
                            selection: NSRange(location: cur.location + len(nextText) + 1 + delta, length: sel.length))
        }
    }

    /// Duplicate the selection after itself, or the current line below itself.
    public static func duplicate(_ s: NSString, _ sel: NSRange) -> TextEdit {
        if sel.length > 0 {
            let t = s.substring(with: sel)
            let at = NSMaxRange(sel)
            return TextEdit(range: NSRange(location: at, length: 0), replacement: t,
                            selection: NSRange(location: at, length: sel.length))
        }
        let r = s.lineRange(for: sel)
        var t = s.substring(with: r)
        let nl = t.hasSuffix("\n")
        if nl { t.removeLast() }
        let out = t + "\n" + t + (nl ? "\n" : "")
        return TextEdit(range: r, replacement: out,
                        selection: NSRange(location: r.location + len(t) + 1 + (sel.location - r.location), length: 0))
    }

    /// No selection: swap the two characters around the cursor.
    /// One-line selection: reverse the words. Multi-line selection: reverse the lines.
    public static func transpose(_ s: NSString, _ sel: NSRange) -> TextEdit? {
        if sel.length == 0 {
            let i = sel.location
            guard i >= 1, i < s.length else { return nil }
            let ra = s.rangeOfComposedCharacterSequence(at: i - 1)
            guard NSMaxRange(ra) < s.length else { return nil }
            let rb = s.rangeOfComposedCharacterSequence(at: NSMaxRange(ra))
            let a = s.substring(with: ra), b = s.substring(with: rb)
            if a == "\n" || b == "\n" { return nil }
            let whole = NSRange(location: ra.location, length: ra.length + rb.length)
            return TextEdit(range: whole, replacement: b + a, selection: NSRange(location: NSMaxRange(whole), length: 0))
        }
        let t = s.substring(with: sel)
        let out: String
        if t.contains("\n") {
            var body = t
            let nl = body.hasSuffix("\n")
            if nl { body.removeLast() }
            out = body.components(separatedBy: "\n").reversed().joined(separator: "\n") + (nl ? "\n" : "")
        } else {
            out = t.components(separatedBy: " ").reversed().joined(separator: " ")
        }
        return TextEdit(range: sel, replacement: out, selection: NSRange(location: sel.location, length: len(out)))
    }
}
