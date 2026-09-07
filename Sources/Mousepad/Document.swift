import AppKit
import MousepadCore
import UniformTypeIdentifiers

/// Remembers which charset opened a non-UTF-8 file so the next open is silent.
enum RecentCharsets {
    private static let key = "charsets"

    static func encoding(for url: URL?) -> String.Encoding? {
        guard let p = url?.path,
              let raw = UserDefaults.standard.dictionary(forKey: key)?[p] as? UInt else { return nil }
        return String.Encoding(rawValue: raw)
    }

    static func remember(_ e: String.Encoding, for url: URL?) {
        guard let p = url?.path else { return }
        var d = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        if e == .utf8 { d.removeValue(forKey: p) } else { d[p] = e.rawValue }
        UserDefaults.standard.set(d, forKey: key)
    }
}

/// One file. NSDocument does open/save/revert/recent/close-prompts; we do bytes <-> text.
final class Document: NSDocument {
    /// Source of truth until the window exists; after that the text view owns the text.
    var text = ""
    var meta = TextMeta()
    var languageID = Languages.plainText.id
    var userSetLanguage = false
    private var undecodable: Data?
    weak var wc: DocumentWindowController?

    var language: Language { Languages.language(id: languageID) ?? Languages.plainText }
    var currentText: String { wc?.textView.string ?? text }

    override class var autosavesInPlace: Bool { false }
    override class var readableTypes: [String] { ["public.plain-text", "public.text", "public.source-code", "public.data"] }
    override class var writableTypes: [String] { ["public.plain-text"] }
    override class func isNativeType(_ type: String) -> Bool { true }
    override var fileType: String? {
        get { "public.plain-text" }
        set {}
    }

    // MARK: - Window

    override func makeWindowControllers() {
        let c = DocumentWindowController(document: self)
        addWindowController(c)
        wc = c
        c.applyAll()
        c.loadTextFromDocument()
        if undecodable != nil { DispatchQueue.main.async { self.promptForEncoding() } }
    }

    // MARK: - Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        do {
            let r = try TextFile.decode(data, preferred: RecentCharsets.encoding(for: fileURL))
            text = r.text
            meta = r.meta
            undecodable = nil
        } catch {
            text = ""
            undecodable = data
        }
        if !userSetLanguage { guessLanguage() }
        wc?.loadTextFromDocument()   // revert path: the window already exists
    }

    override func data(ofType typeName: String) throws -> Data {
        try TextFile.encode(currentText, meta: meta)
    }

    override func writeSafely(to url: URL, ofType typeName: String, for op: NSDocument.SaveOperationType) throws {
        try super.writeSafely(to: url, ofType: typeName, for: op)
        RecentCharsets.remember(meta.encoding, for: url)
        if !userSetLanguage {
            guessLanguage(url: url)
            wc?.languageDidChange()
        }
    }

    override func prepareSavePanel(_ panel: NSSavePanel) -> Bool {
        panel.allowsOtherFileTypes = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.plainText]
        return true
    }

    // MARK: - Printing (light colors on paper, regardless of the screen theme)

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.textStorage?.setAttributedString(NSAttributedString(string: currentText, attributes: [
            .font: Settings.font, .foregroundColor: NSColor.black,
        ]))
        view.backgroundColor = .white
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()

        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = displayName
        return op
    }

    // MARK: - Language

    func guessLanguage(url: URL? = nil) {
        let first = currentText.prefix { $0 != "\n" }
        languageID = Languages.guess(filename: (url ?? fileURL)?.lastPathComponent, firstLine: String(first)).id
    }

    func setTemplate(text t: String, name: String) {
        text = t
        wc?.loadTextFromDocument()
        languageID = Languages.guess(filename: name, firstLine: String(t.prefix { $0 != "\n" })).id
        wc?.languageDidChange()
        updateChangeCount(.changeDone)
    }

    // MARK: - Document menu

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        languageID = id
        userSetLanguage = true
        wc?.languageDidChange()
    }

    @objc func setLineEnding(_ sender: NSMenuItem) {
        guard let e = LineEnding(rawValue: sender.tag), e != meta.lineEnding else { return }
        meta.lineEnding = e
        updateChangeCount(.changeDone)
        wc?.metaDidChange()
    }

    @objc func toggleBOM(_ sender: Any?) {
        meta.writeBOM.toggle()
        updateChangeCount(.changeDone)
        wc?.metaDidChange()
    }

    @objc func setEncoding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? UInt else { return }
        let e = String.Encoding(rawValue: raw)
        guard e != meta.encoding else { return }
        meta.encoding = e
        if !Encodings.isUnicode(e) { meta.writeBOM = false }
        updateChangeCount(.changeDone)
        wc?.metaDidChange()
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setLanguage(_:)):
            item.state = (item.representedObject as? String) == languageID ? .on : .off
        case #selector(setLineEnding(_:)):
            item.state = item.tag == meta.lineEnding.rawValue ? .on : .off
        case #selector(toggleBOM(_:)):
            item.state = meta.writeBOM ? .on : .off
            return Encodings.isUnicode(meta.encoding)
        case #selector(setEncoding(_:)):
            item.state = (item.representedObject as? UInt) == meta.encoding.rawValue ? .on : .off
        default:
            return super.validateUserInterfaceItem(item)
        }
        return true
    }

    // MARK: - "Not valid UTF-8": pick an encoding, with a live preview

    private var encodingPopup: NSPopUpButton?
    private var encodingPreview: NSTextField?

    func promptForEncoding(error: String? = nil) {
        guard let data = undecodable, let window = wc?.window else { return }
        let alert = NSAlert()
        alert.messageText = "Not valid \(Encodings.name(for: meta.encoding)) text"
        alert.informativeText = error ?? "Pick the encoding this file was saved with."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        for g in Encodings.groups {
            for e in Encodings.all where e.group == g {
                popup.addItem(withTitle: e.name)
                popup.lastItem?.representedObject = e.encoding.rawValue
            }
        }
        popup.target = self
        popup.action = #selector(encodingPopupChanged(_:))
        let preview = NSTextField(wrappingLabelWithString: "")
        preview.font = Theme.uiFont
        preview.frame = NSRect(x: 0, y: 0, width: 420, height: 110)
        let stack = NSStackView(views: [popup, preview])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 150)
        alert.accessoryView = stack
        encodingPopup = popup
        encodingPreview = preview
        popup.selectItem(withTitle: "ISO-8859-1 (Latin-1)")
        encodingPopupChanged(popup)

        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn,
                  let raw = popup.selectedItem?.representedObject as? UInt else { self.close(); return }
            let enc = String.Encoding(rawValue: raw)
            do {
                let r = try TextFile.decode(data, preferred: enc)
                self.text = r.text
                self.meta = r.meta
                self.undecodable = nil
                RecentCharsets.remember(enc, for: self.fileURL)
                if !self.userSetLanguage { self.guessLanguage() }
                self.wc?.loadTextFromDocument()
                self.wc?.languageDidChange()
            } catch {
                DispatchQueue.main.async { self.promptForEncoding(error: error.localizedDescription) }
            }
        }
    }

    @objc private func encodingPopupChanged(_ sender: NSPopUpButton) {
        guard let data = undecodable, let raw = sender.selectedItem?.representedObject as? UInt else { return }
        let enc = String.Encoding(rawValue: raw)
        let s = String(data: data.prefix(2000), encoding: enc) ?? String(data: data, encoding: enc)
        encodingPreview?.stringValue = s.map { String($0.prefix(400)) } ?? "— cannot decode with this encoding —"
        encodingPreview?.textColor = s == nil ? .systemRed : .labelColor
    }
}
