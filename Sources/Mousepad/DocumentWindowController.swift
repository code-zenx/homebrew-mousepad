import AppKit
import MousepadCore

/// One window: editor + line numbers + status bar. Applies theme and settings, drives highlighting.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSTextStorageDelegate {
    let textView: EditorTextView
    let scrollView = NSScrollView()
    let ruler: LineNumberRuler
    let statusBar = StatusBarView()
    private var statusHeight: NSLayoutConstraint!
    private let highlighter = Highlighter()
    private var bracketRanges: [NSRange] = []
    private var pendingHighlight: NSRange?
    private var defaultsObserver: Any?

    var doc: Document? { document as? Document }
    var theme: Theme { Theme.named(Settings.string(.colorScheme)) }

    init(document: Document) {
        // Explicit TextKit 1 stack: rulers and highlighting have ten years of examples for it.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), textContainer: container)
        ruler = LineNumberRuler(textView: textView)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)

        window.delegate = self
        window.tabbingMode = AppState.separateNextWindow ? .disallowed : .preferred
        AppState.separateNextWindow = false
        window.tabbingIdentifier = "mousepad"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 320, height: 200)
        window.center()
        if Settings.bool(.rememberWindowFrame) { window.setFrameAutosaveName("MousepadWindow") }

        buildViews()
        // applyAll() runs from Document.makeWindowControllers, once `document` is set.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
        NotificationCenter.default.removeObserver(self)
    }

    private func buildViews() {
        guard let window, let content = window.contentView else { return }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        ruler.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(ruler)
        content.addSubview(scrollView)
        content.addSubview(statusBar)
        statusHeight = statusBar.heightAnchor.constraint(equalToConstant: 24)
        let top = (window.contentLayoutGuide as! NSLayoutGuide).topAnchor   // below the title bar
        NSLayoutConstraint.activate([
            ruler.topAnchor.constraint(equalTo: top),
            ruler.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            ruler.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            scrollView.topAnchor.constraint(equalTo: top),
            scrollView.leadingAnchor.constraint(equalTo: ruler.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusHeight,
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
        textView.onOverwriteChanged = { [weak self] in self?.updateStatus() }

        statusBar.onClick = { [weak self] seg, view in self?.statusClicked(seg, view) }

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc private func scrolled() { ruler.needsDisplay = true }

    // MARK: - Document <-> view

    func loadTextFromDocument() {
        textView.textStorage?.setAttributedString(NSAttributedString(string: doc?.text ?? "", attributes: textView.typingAttributes))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(.zero)
        doc?.undoManager?.removeAllActions()
        highlightAll()
        ruler.updateThickness()
        ruler.needsDisplay = true
        updateStatus()
    }

    func languageDidChange() {
        highlightAll()
        updateStatus()
    }

    func metaDidChange() { updateStatus() }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        let path = (doc?.fileURL?.path as NSString?)?.abbreviatingWithTildeInPath ?? ""
        window?.subtitle = Settings.bool(.pathInTitle) ? path : ""
    }

    // MARK: - Theme and settings

    func applyAll() {
        let t = theme
        let font = Settings.font
        window?.appearance = NSAppearance(named: t.isLight ? .aqua : .darkAqua)
        window?.backgroundColor = t.bg
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

        statusBar.theme = t
        let sb = Settings.bool(.statusBarVisible)
        statusBar.isHidden = !sb
        statusHeight.constant = sb ? 24 : 0

        highlightAll()
        synchronizeWindowTitleWithDocumentName()
        updateStatus()
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
        // ponytail: whole-document rescan below 64 KB, else the touched paragraph only.
        let target = storage.length < 65_536
            ? NSRange(location: 0, length: storage.length)
            : (storage.string as NSString).paragraphRange(for: range)
        scheduleHighlight(target)
        ruler.updateThickness()
        ruler.needsDisplay = true
        updateStatus()
    }

    private func scheduleHighlight(_ r: NSRange) {
        pendingHighlight = pendingHighlight.map { NSUnionRange($0, r) } ?? r
        DispatchQueue.main.async { [weak self] in
            guard let self, let r = self.pendingHighlight else { return }
            self.pendingHighlight = nil
            self.highlight(range: r)
        }
    }

    func highlightAll() {
        guard let s = textView.textStorage else { return }
        highlight(range: NSRange(location: 0, length: s.length))
    }

    private func highlight(range: NSRange) {
        guard let storage = textView.textStorage, storage.length <= 2_000_000 else { return }
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

    // MARK: - Selection, status bar, brackets

    func textViewDidChangeSelection(_ n: Notification) {
        updateStatus()
        matchBrackets()
        textView.needsDisplay = true
        ruler.needsDisplay = true
    }

    func undoManager(for view: NSTextView) -> UndoManager? { doc?.undoManager }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { doc?.undoManager }

    func updateStatus() {
        let sel = textView.selectedRange()
        let (line, col) = lineAndColumn(textView.string as NSString, sel.location)
        statusBar.update(filetype: (doc?.language ?? Languages.plainText).name,
                         encoding: Encodings.name(for: (doc?.meta ?? TextMeta()).encoding) + ((doc?.meta ?? TextMeta()).writeBOM ? " BOM" : ""),
                         eol: (doc?.meta ?? TextMeta()).lineEnding.label,
                         tab: Settings.int(.tabWidth),
                         line: line, column: col, selection: sel.length,
                         overwrite: textView.overwrite)
    }

    // ponytail: O(n) per caret move. Fine below ~1 MB; cache line starts if it ever lags.
    private func lineAndColumn(_ ns: NSString, _ loc: Int) -> (Int, Int) {
        var line = 1
        for b in ns.substring(to: min(loc, ns.length)).utf8 where b == 10 { line += 1 }
        let lineStart = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0)).location
        return (line, loc - lineStart + 1)
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

    // MARK: - Status bar clicks

    private func statusClicked(_ seg: StatusBarView.Segment, _ view: NSView) {
        let menu: NSMenu
        switch seg {
        case .filetype: menu = MainMenu.popup(MainMenu.fillLanguages)
        case .encoding: menu = MainMenu.popup(MainMenu.fillEncodings)
        case .eol: menu = MainMenu.popup(MainMenu.fillLineEndings)
        case .tab: menu = MainMenu.popup(MainMenu.fillTabSizes)
        case .mode: textView.overwrite.toggle(); return
        case .position: goToLine(nil); return
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
    }

    // MARK: - Go to line

    @objc func goToLine(_ sender: Any?) {
        guard let window else { return }
        let a = NSAlert()
        a.messageText = "Go to Line"
        a.informativeText = "line, or line:column"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        let (line, col) = lineAndColumn(textView.string as NSString, textView.selectedRange().location)
        f.stringValue = "\(line):\(col)"
        a.accessoryView = f
        a.addButton(withTitle: "Go")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        a.beginSheetModal(for: window) { [self] r in
            guard r == .alertFirstButtonReturn else { return }
            let parts = f.stringValue.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 1 }
            guard let l = parts.first else { return }
            jump(line: l, column: parts.count > 1 ? parts[1] : 1)
        }
    }

    func jump(line: Int, column: Int) {
        let ns = textView.string as NSString
        var loc = 0
        var n = 1
        while n < line, loc < ns.length {
            if ns.character(at: loc) == 10 { n += 1 }
            loc += 1
        }
        let lr = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
        var lineLen = lr.length
        if lineLen > 0, ns.character(at: NSMaxRange(lr) - 1) == 10 { lineLen -= 1 }
        let target = lr.location + min(max(column - 1, 0), lineLen)
        textView.setSelectedRange(NSRange(location: target, length: 0))
        textView.scrollRangeToVisible(NSRange(location: target, length: 0))
        window?.makeFirstResponder(textView)
    }
}
