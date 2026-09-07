import AppKit

/// One scrolling form, three headings. Controls bind straight to UserDefaults: no Apply button.
final class PreferencesWindowController: NSWindowController {
    private var fontButton: NSButton!
    private var observer: Any?

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Preferences"
        super.init(window: w)
        build()
        w.center()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.fontButton.title = Self.fontTitle
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    private static var fontTitle: String {
        let f = Settings.font
        return "Font…   \(f.displayName ?? f.fontName) \(Int(f.pointSize))"
    }

    private func bind(_ c: NSControl, _ key: Settings.Key, _ binding: NSBindingName = .value) {
        c.bind(binding, to: NSUserDefaultsController.shared, withKeyPath: "values.\(key.rawValue)", options: nil)
    }

    private func check(_ title: String, _ key: Settings.Key) -> NSView {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        bind(b, key)
        return b
    }

    private func heading(_ t: String) -> NSView {
        let l = NSTextField(labelWithString: t.uppercased())
        l.font = Theme.uiFont
        l.textColor = .secondaryLabelColor
        return l
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let s = NSStackView(views: [NSTextField(labelWithString: title), control])
        s.orientation = .horizontal
        s.spacing = 8
        return s
    }

    private func intField(_ title: String, _ key: Settings.Key, min: Int, max: Int) -> NSView {
        let f = NSTextField()
        let fmt = NumberFormatter()
        fmt.minimum = NSNumber(value: min)
        fmt.maximum = NSNumber(value: max)
        f.formatter = fmt
        f.widthAnchor.constraint(equalToConstant: 60).isActive = true
        bind(f, key)
        return row(title, f)
    }

    private func build() {
        let scheme = NSPopUpButton()
        for t in Theme.all {
            scheme.addItem(withTitle: t.title)
            scheme.lastItem?.representedObject = t.name
        }
        scheme.selectItem(withTitle: Theme.named(Settings.string(.colorScheme)).title)
        scheme.target = self
        scheme.action = #selector(schemeChanged(_:))

        fontButton = NSButton(title: Self.fontTitle, target: self, action: #selector(pickFont(_:)))

        let views: [NSView] = [
            heading("View"),
            check("Line numbers", .showLineNumbers),
            check("Highlight current line", .highlightCurrentLine),
            check("Right margin", .showRightMargin),
            intField("Right margin column", .rightMarginColumn, min: 20, max: 400),
            check("Word wrap", .wordWrap),
            check("Block cursor", .blockCursor),
            check("Match brackets", .matchBrackets),
            row("Color scheme", scheme),
            fontButton,
            heading("Editor"),
            intField("Tab width", .tabWidth, min: 1, max: 32),
            check("Insert spaces instead of tabs", .insertSpaces),
            check("Auto indent", .autoIndent),
            check("Smart Home key", .smartHome),
            heading("Window"),
            check("Status bar", .statusBarVisible),
            check("Full path in title bar", .pathInTitle),
            check("Remember window frame", .rememberWindowFrame),
        ]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for v in views where v is NSTextField { stack.setCustomSpacing(4, after: v) }
        window?.contentView = stack
        window?.setContentSize(stack.fittingSize)
    }

    @objc private func schemeChanged(_ sender: NSPopUpButton) {
        Settings.set(sender.selectedItem?.representedObject as? String, .colorScheme)
    }

    @objc private func pickFont(_ sender: Any?) {
        NSFontManager.shared.setSelectedFont(Settings.font, isMultiple: false)
        NSFontManager.shared.orderFrontFontPanel(sender)
    }

    /// Font panel sends this up the responder chain while this window is key.
    @objc func changeFont(_ sender: Any?) {
        guard let fm = sender as? NSFontManager else { return }
        let f = fm.convert(Settings.font)
        Settings.set(f.fontName, .fontName)
        Settings.set(Int(f.pointSize), .fontSize)
    }
}
