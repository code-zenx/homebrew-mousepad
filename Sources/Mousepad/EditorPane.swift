import AppKit
import MousepadCore

/// One document's editor: text view + line-number gutter in a container view, plus the
/// highlighting and bracket matching that belong to that text. Owned by the Document and
/// installed into whichever window is showing it, so switching tabs swaps panes.
final class EditorPane: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    let view = NSView()
    let textView: EditorTextView
    let scrollView = NSScrollView()
    let ruler: LineNumberRuler
    let lines: LineIndex
    weak var doc: Document?
    /// Text, selection or mode changed; the host refreshes the status bar.
    var onChange: (() -> Void)?

    private var theme = Theme.terminal
    private let highlighter = Highlighter()
    private var bracketRanges: [NSRange] = []
    private var highlightPending = false

    init(doc: Document) {
        self.doc = doc
        // Explicit TextKit 1 stack: rulers and highlighting have ten years of examples for it.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true   // lay out what is on screen; a 20 MB file must not wait for every glyph
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), textContainer: container)
        let index = LineIndex()
        lines = index
        ruler = LineNumberRuler(textView: textView, lines: index)
        super.init()
        buildViews()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        ruler.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ruler)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            ruler.topAnchor.constraint(equalTo: view.topAnchor),
            ruler.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ruler.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: ruler.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.documentView = textView

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.onOverwriteChanged = { [weak self] in self?.onChange?() }

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc private func scrolled() {
        ruler.needsDisplay = true
        if (textView.textStorage?.length ?? 0) >= Self.wholeDocumentLimit { scheduleHighlight() }   // new screens came into view
    }

    // MARK: - Document <-> view

    func loadTextFromDocument() {
        textView.textStorage?.setAttributedString(NSAttributedString(string: doc?.text ?? "", attributes: textView.typingAttributes))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(.zero)
        doc?.undoManager?.removeAllActions()
        rehighlight()
        ruler.updateThickness()
        ruler.needsDisplay = true
        onChange?()
    }

    // MARK: - Theme and settings

    func apply(_ t: Theme, font: NSFont) {
        theme = t
        scrollView.backgroundColor = t.bg
        textView.theme = t
        textView.backgroundColor = t.bg
        textView.insertionPointColor = t.accent
        textView.selectedTextAttributes = [.backgroundColor: t.accentDim]
        textView.textColor = t.text
        textView.font = font

        let para = NSMutableParagraphStyle()
        para.tabStops = []
        para.defaultTabInterval = textView.charWidth(font) * CGFloat(max(1, Settings.int(.tabWidth)))
        textView.defaultParagraphStyle = para
        textView.typingAttributes = [.font: font, .foregroundColor: t.text, .paragraphStyle: para]
        if let s = textView.textStorage, s.length > 0 {
            s.addAttributes([.font: font, .paragraphStyle: para], range: NSRange(location: 0, length: s.length))
        }

        ruler.theme = t
        ruler.updateThickness()
        ruler.visible = Settings.bool(.showLineNumbers)
        setWordWrap(Settings.bool(.wordWrap))
        rehighlight()
        textView.needsDisplay = true
    }

    private func setWordWrap(_ wrap: Bool) {
        guard let tc = textView.textContainer else { return }
        if wrap {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            tc.widthTracksTextView = true
            tc.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
            textView.frame.size.width = scrollView.contentSize.width
            scrollView.hasHorizontalScroller = false
        } else {
            tc.widthTracksTextView = false
            tc.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = []
            scrollView.hasHorizontalScroller = true
        }
    }

    // MARK: - Highlighting

    func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
        guard mask.contains(.editedCharacters) else { return }
        lines.rebuild(storage.string as NSString)
        scheduleHighlight()
        ruler.updateThickness()
        ruler.needsDisplay = true
        onChange?()
    }

    /// Below this many UTF-16 units the whole document is rescanned on every edit, which keeps
    /// block comments right. Above it only the screens around the visible one are highlighted.
    static let wholeDocumentLimit = 65_536

    // ponytail: for big files a block comment opened off-screen goes stale until it scrolls into
    // the window. Upgrade path: tree-sitter via Neon.
    private func highlightTarget() -> NSRange {
        guard let storage = textView.textStorage, let lm = textView.layoutManager, let tc = textView.textContainer else { return NSRange(location: 0, length: 0) }
        if storage.length < Self.wholeDocumentLimit { return NSRange(location: 0, length: storage.length) }
        var r = textView.visibleRect
        r.origin.y -= r.height
        r.size.height *= 3
        let glyphs = lm.glyphRange(forBoundingRect: r, in: tc)
        return (storage.string as NSString).paragraphRange(for: lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
    }

    /// Coalesces to one pass per run-loop turn; the target is computed then, once layout is settled.
    private func scheduleHighlight() {
        guard !highlightPending else { return }
        highlightPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.highlightPending = false
            self.highlight(range: self.highlightTarget())
        }
    }

    func rehighlight() { highlight(range: highlightTarget()) }

    private func highlight(range: NSRange) {
        guard let storage = textView.textStorage else { return }
        let r = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard r.length > 0 else { return }
        let t = theme
        let tokens = highlighter.tokens(in: storage.string, range: r, language: (doc?.language ?? Languages.plainText))
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: t.text, range: r)
        for tok in tokens {
            if let c = t.tokens[tok.kind] { storage.addAttribute(.foregroundColor, value: c, range: tok.range) }
        }
        storage.endEditing()
    }

    // MARK: - Selection, brackets

    func textViewDidChangeSelection(_ n: Notification) {
        matchBrackets()
        textView.needsDisplay = true
        ruler.needsDisplay = true
        onChange?()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { doc?.undoManager }

    func lineAndColumn(_ loc: Int) -> (Int, Int) {
        let line = lines.line(at: loc)
        return (line, loc - lines.start(ofLine: line) + 1)
    }

    private func matchBrackets() {
        guard let lm = textView.layoutManager else { return }
        for r in bracketRanges {
            lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: r)
            lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: r)
        }
        bracketRanges = []
        guard Settings.bool(.matchBrackets) else { return }
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        guard sel.length == 0, ns.length > 0 else { return }
        // ( ) [ ] { }
        let pairs: [unichar: (other: unichar, forward: Bool)] = [40: (41, true), 91: (93, true), 123: (125, true),
                                                                 41: (40, false), 93: (91, false), 125: (123, false)]
        var idx = -1
        if sel.location > 0, pairs[ns.character(at: sel.location - 1)] != nil { idx = sel.location - 1 }
        else if sel.location < ns.length, pairs[ns.character(at: sel.location)] != nil { idx = sel.location }
        guard idx >= 0, let pair = pairs[ns.character(at: idx)] else { return }
        let me = ns.character(at: idx)
        var depth = 0
        var i = idx
        var steps = 0
        while i >= 0, i < ns.length, steps < 200_000 {
            let c = ns.character(at: i)
            if c == me { depth += 1 } else if c == pair.other { depth -= 1; if depth == 0 { break } }
            i += pair.forward ? 1 : -1
            steps += 1
        }
        guard depth == 0, i >= 0, i < ns.length else { return }
        for r in [NSRange(location: idx, length: 1), NSRange(location: i, length: 1)] {
            lm.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: theme.accent], forCharacterRange: r)
            bracketRanges.append(r)
        }
    }

    // MARK: - Go to line

    func jump(line: Int, column: Int) {
        let ns = textView.string as NSString
        let lr = ns.lineRange(for: NSRange(location: min(lines.start(ofLine: line), ns.length), length: 0))
        var lineLen = lr.length
        if lineLen > 0, ns.character(at: NSMaxRange(lr) - 1) == 10 { lineLen -= 1 }
        let target = lr.location + min(max(column - 1, 0), lineLen)
        textView.setSelectedRange(NSRange(location: target, length: 0))
        textView.scrollRangeToVisible(NSRange(location: target, length: 0))
        textView.window?.makeFirstResponder(textView)
    }
}
