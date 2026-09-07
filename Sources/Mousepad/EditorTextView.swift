import AppKit
import MousepadCore

enum ClipboardHistory {
    static var items: [String] = []

    static func record() {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 10 { items.removeLast(items.count - 10) }
    }
}

/// The editor. Drawing of the current line and right margin, smart keys, and the
/// Edit-menu operations (which delegate to `TextOps`).
final class EditorTextView: NSTextView {
    var theme = Theme.terminal
    var overwrite = false {
        didSet { onOverwriteChanged?(); needsDisplay = true }
    }
    var onOverwriteChanged: (() -> Void)?
    private var applyingEdit = false

    var ns: NSString { string as NSString }
    private var tabWidth: Int { max(1, Settings.int(.tabWidth)) }
    private var indentUnit: String { Settings.bool(.insertSpaces) ? String(repeating: " ", count: tabWidth) : "\t" }

    func charWidth(_ f: NSFont? = nil) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: f ?? font ?? Settings.font]).width
    }

    // MARK: - Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        if Settings.bool(.highlightCurrentLine), window?.firstResponder === self {
            var r = currentLineRect(lm)
            r.origin.x = 0
            r.size.width = bounds.width
            r.origin.y += textContainerInset.height
            if r.intersects(rect) {
                theme.currentLine.setFill()
                r.intersection(rect).fill()
            }
        }
        if Settings.bool(.showRightMargin) {
            let x = textContainerInset.width + tc.lineFragmentPadding + charWidth() * CGFloat(Settings.int(.rightMarginColumn))
            theme.border.setFill()
            NSRect(x: x, y: rect.minY, width: 1, height: rect.height).fill()
        }
    }

    private func currentLineRect(_ lm: NSLayoutManager) -> NSRect {
        let loc = selectedRange().location
        let n = ns.length
        if n == 0 || (loc >= n && ns.character(at: n - 1) == 10) { return lm.extraLineFragmentRect }
        let g = lm.glyphIndexForCharacter(at: min(loc, n - 1))
        return lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
    }

    private var blockCursor: Bool { Settings.bool(.blockCursor) || overwrite }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var r = rect
        var c = color
        if blockCursor {
            r.size.width = charWidth()
            c = color.withAlphaComponent(0.6)
        }
        super.drawInsertionPoint(in: r, color: c, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var r = rect
        if blockCursor { r.size.width += charWidth() }
        super.setNeedsDisplay(r, avoidAdditionalLayout: flag)
    }

    // MARK: - Keys

    override func keyDown(with e: NSEvent) {
        let shift = e.modifierFlags.contains(.shift)
        let cmd = e.modifierFlags.contains(.command)
        switch e.keyCode {
        case 115:   // Home
            if cmd { shift ? moveToBeginningOfDocumentAndModifySelection(nil) : moveToBeginningOfDocument(nil) }
            else { shift ? moveToBeginningOfLineAndModifySelection(nil) : moveToBeginningOfLine(nil) }
        case 119:   // End
            if cmd { shift ? moveToEndOfDocumentAndModifySelection(nil) : moveToEndOfDocument(nil) }
            else { shift ? moveToEndOfLineAndModifySelection(nil) : moveToEndOfLine(nil) }
        case 114:   // Insert / Help
            overwrite.toggle()
        default:
            super.keyDown(with: e)
        }
    }

    /// Home toggles between the first non-blank character and column 0.
    override func moveToBeginningOfLine(_ sender: Any?) {
        guard Settings.bool(.smartHome), let t = smartHomeTarget() else { super.moveToBeginningOfLine(sender); return }
        setSelectedRange(NSRange(location: t, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    private func smartHomeTarget() -> Int? {
        let loc = selectedRange().location
        let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
        var end = NSMaxRange(lr)
        if lr.length > 0, ns.character(at: end - 1) == 10 { end -= 1 }
        var first = lr.location
        while first < end, [32, 9].contains(ns.character(at: first)) { first += 1 }
        if first == lr.location { return nil }
        return loc == first ? lr.location : first
    }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0, ns.substring(with: sel).contains("\n") { indentSelection(sender); return }
        guard Settings.bool(.insertSpaces) else { super.insertTab(sender); return }
        let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let col = visualColumn(from: lineStart, to: sel.location)
        insertText(String(repeating: " ", count: tabWidth - col % tabWidth), replacementRange: sel)
    }

    override func insertBacktab(_ sender: Any?) { unindentSelection(sender) }

    override func insertNewline(_ sender: Any?) {
        guard Settings.bool(.autoIndent) else { super.insertNewline(sender); return }
        let sel = selectedRange()
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: sel.location, length: 0)))
        let ws = String(line.prefix { $0 == " " || $0 == "\t" })
        insertText("\n" + ws, replacementRange: sel)
    }

    private func visualColumn(from: Int, to: Int) -> Int {
        var c = 0
        var i = from
        while i < to {
            c += ns.character(at: i) == 9 ? tabWidth - c % tabWidth : 1
            i += 1
        }
        return c
    }

    /// Overwrite mode: a typed character replaces the one under the cursor.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if overwrite, !applyingEdit, !hasMarkedText() {
            let sel = selectedRange()
            let s = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
            if sel.length == 0, (s as NSString).length == 1, s != "\n",
               sel.location < ns.length, ns.character(at: sel.location) != 10 {
                super.insertText(string, replacementRange: NSRange(location: sel.location, length: 1))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: - Edit menu operations

    private func apply(_ e: TextEdit?) {
        guard let e else { NSSound.beep(); return }
        applyingEdit = true
        defer { applyingEdit = false }
        guard shouldChangeText(in: e.range, replacementString: e.replacement) else { return }
        textStorage?.replaceCharacters(in: e.range, with: NSAttributedString(string: e.replacement, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(e.selection)
        scrollRangeToVisible(e.selection)
    }

    @objc func indentSelection(_ s: Any?) { apply(TextOps.indent(ns, selectedRange(), unit: indentUnit)) }
    @objc func unindentSelection(_ s: Any?) { apply(TextOps.unindent(ns, selectedRange(), tabWidth: tabWidth)) }
    @objc func convertLower(_ s: Any?) { apply(TextOps.changeCase(ns, selectedRange(), .lower)) }
    @objc func convertUpper(_ s: Any?) { apply(TextOps.changeCase(ns, selectedRange(), .upper)) }
    @objc func convertTitle(_ s: Any?) { apply(TextOps.changeCase(ns, selectedRange(), .title)) }
    @objc func convertOpposite(_ s: Any?) { apply(TextOps.changeCase(ns, selectedRange(), .opposite)) }
    @objc func tabsToSpaces(_ s: Any?) { apply(TextOps.tabsToSpaces(ns, selectedRange(), tabWidth: tabWidth)) }
    @objc func spacesToTabs(_ s: Any?) { apply(TextOps.spacesToTabs(ns, selectedRange(), tabWidth: tabWidth)) }
    @objc func stripTrailingSpaces(_ s: Any?) { apply(TextOps.stripTrailingSpaces(ns, selectedRange())) }
    @objc func transposeSelection(_ s: Any?) { apply(TextOps.transpose(ns, selectedRange())) }
    @objc func moveLineUp(_ s: Any?) { apply(TextOps.moveLines(ns, selectedRange(), up: true)) }
    @objc func moveLineDown(_ s: Any?) { apply(TextOps.moveLines(ns, selectedRange(), up: false)) }
    @objc func duplicateLine(_ s: Any?) { apply(TextOps.duplicate(ns, selectedRange())) }

    private static let ownActions: Set<Selector> = [
        #selector(indentSelection(_:)), #selector(unindentSelection(_:)),
        #selector(convertLower(_:)), #selector(convertUpper(_:)), #selector(convertTitle(_:)), #selector(convertOpposite(_:)),
        #selector(tabsToSpaces(_:)), #selector(spacesToTabs(_:)), #selector(stripTrailingSpaces(_:)),
        #selector(transposeSelection(_:)), #selector(moveLineUp(_:)), #selector(moveLineDown(_:)),
        #selector(duplicateLine(_:)), #selector(pasteFromHistory(_:)),
    ]

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let a = item.action, Self.ownActions.contains(a) { return isEditable }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Clipboard history

    override func copy(_ sender: Any?) { super.copy(sender); ClipboardHistory.record() }
    override func cut(_ sender: Any?) { super.cut(sender); ClipboardHistory.record() }

    @objc func pasteFromHistory(_ sender: Any?) {
        guard !ClipboardHistory.items.isEmpty else { NSSound.beep(); return }
        let menu = NSMenu()
        for (i, s) in ClipboardHistory.items.enumerated() {
            let title = String(s.replacingOccurrences(of: "\n", with: "⏎").prefix(60))
            let item = NSMenuItem(title: "\(i + 1)  \(title)", action: #selector(pasteHistoryItem(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            item.keyEquivalentModifierMask = []
            item.target = self
            item.representedObject = s
            menu.addItem(item)
        }
        var p = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        if let lm = layoutManager, ns.length > 0 {
            let loc = min(selectedRange().location, ns.length - 1)
            let r = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: loc), effectiveRange: nil)
            p = NSPoint(x: r.minX + textContainerInset.width, y: r.maxY + textContainerInset.height)
        }
        menu.popUp(positioning: nil, at: p, in: self)
    }

    @objc private func pasteHistoryItem(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String else { return }
        insertText(s, replacementRange: selectedRange())
    }

    // MARK: - Misc

    override func menu(for event: NSEvent) -> NSMenu? { MainMenu.contextMenu() }

    /// Font panel changes become a setting so every window follows.
    override func changeFont(_ sender: Any?) {
        guard let fm = sender as? NSFontManager else { return }
        let f = fm.convert(Settings.font)
        Settings.set(f.fontName, .fontName)
        Settings.set(Int(f.pointSize), .fontSize)
    }
}
