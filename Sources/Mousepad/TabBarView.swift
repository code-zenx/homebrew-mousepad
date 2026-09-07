import AppKit

/// 28 pt tab strip in the Mousepad look (05-ui-style.md §4): one per window, listing the
/// host's documents. Click selects, × or middle-click closes, + opens a new document.
final class TabBarView: NSView, NSViewToolTipOwner {
    static let height: CGFloat = 28
    private let pad: CGFloat = 8
    private let closeWidth: CGFloat = 16
    private let plusWidth: CGFloat = 28

    var theme = Theme.terminal { didSet { needsDisplay = true } }
    weak var host: DocumentWindowController?

    private var tabs: [(doc: Document, rect: NSRect)] = []
    private var plusRect = NSRect.zero
    private var hover: Int?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    override func layout() {
        super.layout()
        reload()
    }

    /// Rebuilds the strip from the host's documents. Cheap enough to call on every change.
    func reload() {
        let docs = host?.documents ?? []
        // ponytail: no scrolling. Tabs shrink to fit; add a scroller if someone opens 30 files.
        let cap = floor((bounds.width - plusWidth) / CGFloat(max(1, docs.count)))
        var x: CGFloat = 0
        tabs = docs.map { d in
            let width = max(48, min(title(for: d, active: false).size().width + pad * 2 + closeWidth, cap))
            defer { x += width }
            return (d, NSRect(x: x, y: 0, width: width, height: Self.height))
        }
        plusRect = NSRect(x: bounds.width - plusWidth, y: 0, width: plusWidth, height: Self.height)
        removeAllToolTips()
        for t in tabs { addToolTip(t.rect, owner: self, userData: nil) }
        needsDisplay = true
    }

    private func title(for doc: Document, active: Bool) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString()
        if doc.isDocumentEdited {
            s.append(NSAttributedString(string: "*", attributes: [.font: Theme.uiFont, .foregroundColor: theme.accent, .paragraphStyle: para]))
        }
        s.append(NSAttributedString(string: doc.displayName, attributes: [
            .font: Theme.uiFont, .foregroundColor: active ? theme.textBright : theme.muted, .paragraphStyle: para,
        ]))
        return s
    }

    private func closeRect(_ tab: NSRect) -> NSRect {
        NSRect(x: tab.maxX - closeWidth - 4, y: 0, width: closeWidth, height: Self.height)
    }

    private func drawCentered(_ text: String, in rect: NSRect, color: NSColor) {
        let s = NSAttributedString(string: text, attributes: [.font: Theme.uiFont, .foregroundColor: color])
        let size = s.size()
        s.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.panel.setFill()
        bounds.fill()
        theme.border.setFill()
        NSRect(x: 0, y: Self.height - 1, width: bounds.width, height: 1).fill()

        for (i, t) in tabs.enumerated() {
            let active = t.doc === host?.current
            if i == hover {
                theme.panelRaised.setFill()
                t.rect.fill()
            }
            let s = title(for: t.doc, active: active)
            let h = s.size().height
            s.draw(with: NSRect(x: t.rect.minX + pad, y: (Self.height - h) / 2, width: t.rect.width - pad * 2 - closeWidth, height: h),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            if i == hover { drawCentered("×", in: closeRect(t.rect), color: theme.muted) }
            theme.border.setFill()
            NSRect(x: t.rect.maxX - 1, y: 0, width: 1, height: Self.height).fill()
            if active {
                theme.accent.setFill()
                NSRect(x: t.rect.minX, y: Self.height - 2, width: t.rect.width - 1, height: 2).fill()
            }
        }

        theme.border.setFill()
        NSRect(x: plusRect.minX, y: 0, width: 1, height: Self.height).fill()
        drawCentered("+", in: plusRect, color: theme.muted)
    }

    // MARK: - Mouse

    private func tab(at p: NSPoint) -> (doc: Document, rect: NSRect)? { tabs.first { $0.rect.contains(p) } }

    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if plusRect.contains(p) { host?.newTab(nil); return }
        guard let t = tab(at: p) else { return }
        if closeRect(t.rect).contains(p) { host?.close(tab: t.doc) } else { host?.show(t.doc) }
    }

    override func otherMouseDown(with e: NSEvent) {
        guard e.buttonNumber == 2, let t = tab(at: convert(e.locationInWindow, from: nil)) else { return }
        host?.close(tab: t.doc)
    }

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let h = tabs.firstIndex { $0.rect.contains(p) }
        if h != hover { hover = h; needsDisplay = true }
    }

    override func mouseExited(with e: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        guard let doc = tab(at: point)?.doc else { return "" }
        return doc.fileURL?.path ?? doc.displayName
    }
}
