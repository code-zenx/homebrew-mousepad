import AppKit

/// Line-number gutter. A plain view placed beside the scroll view, not an NSRulerView:
/// modern NSScrollView overlays rulers on the clip view, which hides column 0 of a
/// horizontally scrolling document. A sibling view has no such surprise.
final class LineNumberRuler: NSView {
    unowned let textView: EditorTextView
    var theme = Theme.terminal {
        didSet { needsDisplay = true }
    }
    var visible = true {
        didSet {
            isHidden = !visible
            invalidateIntrinsicContentSize()
        }
    }
    private var thickness: CGFloat = 40

    init(textView: EditorTextView) {
        self.textView = textView
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }   // same orientation as the text view

    override var intrinsicContentSize: NSSize {
        NSSize(width: visible ? thickness : 0, height: NSView.noIntrinsicMetric)
    }

    private var font: NSFont { textView.font ?? Settings.font }

    /// Call when the text changes. Widens the gutter as the line count grows.
    func updateThickness() {
        var n = 1
        for b in textView.string.utf8 where b == 10 { n += 1 }
        let digits = max(2, String(n).count)
        let w = ("0" as NSString).size(withAttributes: [.font: font]).width
        let t = ceil(CGFloat(digits) * w + 16)
        if abs(t - thickness) > 0.5 {
            thickness = t
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.panel.setFill()
        bounds.fill()
        theme.border.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        let ns = textView.string as NSString
        let visibleRect = textView.visibleRect
        let inset = textView.textContainerInset.height
        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let caretLine = lineNumber(at: textView.selectedRange().location, ns)

        var lineNo = lineNumber(at: charRange.location, ns)
        var lineStart = ns.lineRange(for: NSRange(location: charRange.location, length: 0)).location
        let end = NSMaxRange(charRange)
        while lineStart < ns.length, lineStart <= end {
            let lr = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let frag = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: lineStart), effectiveRange: nil)
            draw(lineNo, y: frag.minY + inset - visibleRect.minY, current: lineNo == caretLine)
            lineNo += 1
            if lr.length == 0 { break }
            lineStart = NSMaxRange(lr)
        }
        // The empty line after a trailing newline, or the only line of an empty document.
        let endsWithNewline = ns.length > 0 && ns.character(at: ns.length - 1) == 10
        if (ns.length == 0 || endsWithNewline) && lineStart >= ns.length {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 { draw(lineNo, y: extra.minY + inset - visibleRect.minY, current: lineNo == caretLine) }
        }
    }

    // ponytail: O(n) newline count per draw. Cache line starts if a 5 MB file ever scrolls slowly.
    private func lineNumber(at loc: Int, _ ns: NSString) -> Int {
        var n = 1
        for b in ns.substring(to: min(loc, ns.length)).utf8 where b == 10 { n += 1 }
        return n
    }

    private func draw(_ n: Int, y: CGFloat, current: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: current ? theme.accent : theme.muted]
        let s = "\(n)" as NSString
        let w = s.size(withAttributes: attrs).width
        s.draw(at: NSPoint(x: bounds.width - 8 - w, y: y), withAttributes: attrs)
    }
}
