import AppKit
import MousepadCore

/// One window: tab bar + the current document's editor pane + status bar. Hosts any
/// number of Documents. The NSWindowController `document` is whichever tab is showing,
/// so the responder chain, window title and edited dot follow the active tab.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    /// Documents hold their host weakly; this keeps hosts alive until their window closes.
    static var all: [DocumentWindowController] = []
    /// Where the next opened document lands: the key window's host, else the newest one.
    static var front: DocumentWindowController? {
        (NSApp.keyWindow?.windowController as? DocumentWindowController) ?? all.last
    }

    private(set) var documents: [Document] = []
    private(set) var current: Document?
    let tabBar = TabBarView()
    let statusBar = StatusBarView()
    private let paneArea = NSView()
    private var statusHeight: NSLayoutConstraint!
    private var defaultsObserver: Any?
    private var closingAll = false

    var theme: Theme { Theme.named(Settings.string(.colorScheme)) }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)

        window.delegate = self
        window.tabbingMode = .disallowed   // tabs are ours (TabBarView), not AppKit's
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 320, height: 200)
        window.center()
        if Settings.bool(.rememberWindowFrame) { window.setFrameAutosaveName("MousepadWindow") }

        buildViews()
        applyAll()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }
        Self.all.append(self)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func buildViews() {
        guard let window, let content = window.contentView else { return }
        for v in [tabBar, paneArea, statusBar] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        statusHeight = statusBar.heightAnchor.constraint(equalToConstant: 24)
        let top = (window.contentLayoutGuide as! NSLayoutGuide).topAnchor   // below the title bar
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: top),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TabBarView.height),
            paneArea.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            paneArea.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            paneArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            paneArea.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusHeight,
        ])
        tabBar.host = self
        statusBar.onClick = { [weak self] seg, view in self?.statusClicked(seg, view) }
    }

    // MARK: - Tabs

    func add(_ doc: Document) {
        documents.append(doc)
        doc.wc = self
        let pane = doc.pane ?? EditorPane(doc: doc)
        let fresh = doc.pane == nil
        doc.pane = pane
        pane.onChange = { [weak self, weak doc] in
            if let self, doc === self.current { self.updateStatus() }
        }
        pane.apply(theme, font: Settings.font)
        if fresh { pane.loadTextFromDocument() }
        show(doc)
    }

    func show(_ doc: Document) {
        guard doc !== current, documents.contains(where: { $0 === doc }), let pane = doc.pane else { return }
        current?.pane?.view.removeFromSuperview()
        if let old = current, old.windowControllers.contains(self) { old.removeWindowController(self) }
        current = doc
        doc.addWindowController(self)   // window title, edited dot and responder chain now follow this doc

        pane.view.translatesAutoresizingMaskIntoConstraints = false
        paneArea.addSubview(pane.view)
        NSLayoutConstraint.activate([
            pane.view.topAnchor.constraint(equalTo: paneArea.topAnchor),
            pane.view.leadingAnchor.constraint(equalTo: paneArea.leadingAnchor),
            pane.view.trailingAnchor.constraint(equalTo: paneArea.trailingAnchor),
            pane.view.bottomAnchor.constraint(equalTo: paneArea.bottomAnchor),
        ])
        setDocumentEdited(doc.isDocumentEdited)
        synchronizeWindowTitleWithDocumentName()
        updateStatus()
        window?.makeFirstResponder(pane.textView)
    }

    /// Detaches a document from this window without closing it. `Document.close()` calls this;
    /// the window goes away with its last tab.
    func remove(_ doc: Document) {
        guard let i = documents.firstIndex(where: { $0 === doc }) else { return }
        documents.remove(at: i)
        doc.pane?.view.removeFromSuperview()
        if doc.windowControllers.contains(self) { doc.removeWindowController(self) }
        doc.wc = nil
        if current === doc {
            current = nil
            if documents.isEmpty { close() } else { show(documents[min(i, documents.count - 1)]) }
        }
        tabBar.reload()
    }

    @objc func newTab(_ sender: Any?) { NSDocumentController.shared.newDocument(sender) }

    @objc func closeTab(_ sender: Any?) {
        if let d = current { close(tab: d) }
    }

    func close(tab doc: Document) {
        closingAll = false
        show(doc)
        doc.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ doc: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard shouldClose else { closingAll = false; return }
        doc.close()
        if closingAll, !documents.isEmpty { window?.performClose(nil) }   // next tab, same prompt flow
    }

    /// Close box / Close Window: every tab gets its save prompt; the window closes with the last one.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let doc = documents.first else { return true }
        closingAll = true
        show(doc)
        doc.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
        return false
    }

    func windowWillClose(_ n: Notification) {
        // Deferred: `all` may be the last strong reference, and a close can start inside remove().
        DispatchQueue.main.async { Self.all.removeAll { $0 === self } }
    }

    @objc func selectTab(_ sender: NSMenuItem) {
        guard sender.tag < documents.count else { NSSound.beep(); return }
        show(documents[sender.tag])
    }

    @objc func nextTab(_ sender: Any?) { step(1) }
    @objc func previousTab(_ sender: Any?) { step(-1) }

    private func step(_ by: Int) {
        guard let c = current, let i = documents.firstIndex(where: { $0 === c }) else { return }
        show(documents[(i + by + documents.count) % documents.count])
    }

    @objc func moveTabToNewWindow(_ sender: Any?) {
        guard let doc = current, documents.count > 1 else { return }
        remove(doc)
        let host = DocumentWindowController()
        host.add(doc)
        host.showWindow(nil)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(selectTab(_:)): return item.tag < documents.count
        case #selector(nextTab(_:)), #selector(previousTab(_:)), #selector(moveTabToNewWindow(_:)): return documents.count > 1
        default: return true
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { current?.undoManager }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        let path = (current?.fileURL?.path as NSString?)?.abbreviatingWithTildeInPath ?? ""
        window?.subtitle = Settings.bool(.pathInTitle) ? path : ""
        tabBar.reload()
    }

    // MARK: - Theme and settings

    func applyAll() {
        let t = theme
        window?.appearance = NSAppearance(named: t.isLight ? .aqua : .darkAqua)
        window?.backgroundColor = t.bg
        tabBar.theme = t
        statusBar.theme = t
        let sb = Settings.bool(.statusBarVisible)
        statusBar.isHidden = !sb
        statusHeight.constant = sb ? 24 : 0
        for d in documents { d.pane?.apply(t, font: Settings.font) }
        synchronizeWindowTitleWithDocumentName()
        updateStatus()
    }

    // MARK: - Status bar

    func updateStatus() {
        guard let doc = current, let pane = doc.pane else { return }
        let sel = pane.textView.selectedRange()
        let (line, col) = pane.lineAndColumn(sel.location)
        statusBar.update(filetype: doc.language.name,
                         encoding: Encodings.name(for: doc.meta.encoding) + (doc.meta.writeBOM ? " BOM" : ""),
                         eol: doc.meta.lineEnding.label,
                         tab: Settings.int(.tabWidth),
                         line: line, column: col, selection: sel.length,
                         overwrite: pane.textView.overwrite)
    }

    private func statusClicked(_ seg: StatusBarView.Segment, _ view: NSView) {
        let menu: NSMenu
        switch seg {
        case .filetype: menu = MainMenu.popup(MainMenu.fillLanguages)
        case .encoding: menu = MainMenu.popup(MainMenu.fillEncodings)
        case .eol: menu = MainMenu.popup(MainMenu.fillLineEndings)
        case .tab: menu = MainMenu.popup(MainMenu.fillTabSizes)
        case .mode: current?.pane?.textView.overwrite.toggle(); return
        case .position: goToLine(nil); return
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
    }

    // MARK: - Go to line

    @objc func goToLine(_ sender: Any?) {
        guard let window, let pane = current?.pane else { return }
        let a = NSAlert()
        a.messageText = "Go to Line"
        a.informativeText = "line, or line:column"
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        let (line, col) = pane.lineAndColumn(pane.textView.selectedRange().location)
        f.stringValue = "\(line):\(col)"
        a.accessoryView = f
        a.addButton(withTitle: "Go")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        a.beginSheetModal(for: window) { r in
            guard r == .alertFirstButtonReturn else { return }
            let parts = f.stringValue.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 1 }
            guard let l = parts.first else { return }
            pane.jump(line: l, column: parts.count > 1 ? parts[1] : 1)
        }
    }
}
