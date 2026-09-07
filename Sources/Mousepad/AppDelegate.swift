import AppKit
import MousepadCore

enum AppState {
    /// Set by "New Window" so the next window opens standalone instead of as a tab.
    static var separateNextWindow = false
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var prefs: PreferencesWindowController?

    func applicationWillFinishLaunching(_ n: Notification) {
        Settings.registerDefaults()
        NSApp.mainMenu = MainMenu.build(templatesDelegate: self)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        if let path = ProcessInfo.processInfo.environment["MOUSEPAD_SNAPSHOT"] { snapshot(to: path) }
    }

    /// Dev aid: `MOUSEPAD_SNAPSHOT=/tmp/x.png Mousepad.app/Contents/MacOS/Mousepad file.txt`
    /// writes the front window's content to a PNG and quits. No screen-recording permission needed.
    private func snapshot(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let docWindows = NSApp.windows.filter { $0.windowController is DocumentWindowController }
            guard let w = docWindows.first, let v = w.contentView else {
                FileHandle.standardError.write("snapshot: no document window (\(NSApp.windows.count) windows)\n".data(using: .utf8)!)
                NSApp.terminate(nil)
                return
            }
            w.makeKeyAndOrderFront(nil)
            w.displayIfNeeded()
            // PDF, not a bitmap cache: layer-backed scroll views come out blank from cacheDisplay.
            let wc = w.windowController as! DocumentWindowController
            try? v.dataWithPDF(inside: v.bounds).write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write("snapshot: wrote \(path) text=\(wc.textView.string.count) chars gutter=\(wc.ruler.frame) clip=\(wc.scrollView.contentView.frame) clipBounds=\(wc.scrollView.contentView.bounds.origin)\n".data(using: .utf8)!)
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Explicit file handling: works from Finder, `open -a`, and a bare command line alike.
    func application(_ app: NSApplication, openFiles filenames: [String]) {
        for f in filenames where FileManager.default.fileExists(atPath: f) {   // skips `-key value` defaults args
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: f), display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        app.reply(toOpenOrPrint: .success)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        (try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)) != nil
    }

    // MARK: - Actions reachable from the menu

    @objc func showPreferences(_ sender: Any?) {
        if prefs == nil { prefs = PreferencesWindowController() }
        prefs?.showWindow(sender)
        prefs?.window?.makeKeyAndOrderFront(sender)
    }

    @objc func newWindow(_ sender: Any?) {
        AppState.separateNextWindow = true
        NSDocumentController.shared.newDocument(sender)
    }

    @objc func saveAll(_ sender: Any?) {
        for d in NSDocumentController.shared.documents where d.isDocumentEdited { d.save(sender) }
    }

    @objc func toggleSetting(_ sender: NSMenuItem) {
        guard let k = sender.representedObject as? Settings.Key else { return }
        Settings.toggle(k)
    }

    @objc func setColorScheme(_ sender: NSMenuItem) {
        Settings.set(sender.representedObject as? String, .colorScheme)
    }

    @objc func setTabSize(_ sender: NSMenuItem) {
        if sender.tag > 0 { Settings.set(sender.tag, .tabWidth); return }
        let a = NSAlert()
        a.messageText = "Tab Size"
        a.informativeText = "Width in characters (1–32)."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        f.integerValue = Settings.int(.tabWidth)
        a.accessoryView = f
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        if a.runModal() == .alertFirstButtonReturn, (1...32).contains(f.integerValue) {
            Settings.set(f.integerValue, .tabWidth)
        }
    }

    @objc func fontBigger(_ sender: Any?) { Settings.set(min(72, Settings.int(.fontSize) + 1), .fontSize) }
    @objc func fontSmaller(_ sender: Any?) { Settings.set(max(6, Settings.int(.fontSize) - 1), .fontSize) }

    @objc func selectTab(_ sender: NSMenuItem) {
        guard let w = NSApp.keyWindow, let tabs = w.tabbedWindows, sender.tag < tabs.count else { NSSound.beep(); return }
        tabs[sender.tag].makeKeyAndOrderFront(nil)
    }

    @objc func showHelp(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://docs.xfce.org/apps/mousepad/start")!)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleSetting(_:)):
            if let k = item.representedObject as? Settings.Key { item.state = Settings.bool(k) ? .on : .off }
        case #selector(setColorScheme(_:)):
            item.state = (item.representedObject as? String) == Settings.string(.colorScheme) ? .on : .off
        case #selector(setTabSize(_:)):
            item.state = item.tag == Settings.int(.tabWidth) ? .on : .off
        case #selector(selectTab(_:)):
            return (NSApp.keyWindow?.tabbedWindows?.count ?? 0) > item.tag
        default:
            break
        }
        return true
    }

    // MARK: - New From Template (~/Templates, subfolders become submenus)

    static var templatesDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Templates")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu, dir: Self.templatesDir)
        if menu.items.isEmpty {
            let i = NSMenuItem(title: "No templates in ~/Templates", action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
    }

    private func fill(_ menu: NSMenu, dir: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        let sorted = items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for url in sorted {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let sub = NSMenu(title: url.lastPathComponent)
                fill(sub, dir: url)
                if sub.items.isEmpty { continue }
                let i = NSMenuItem(title: url.lastPathComponent, action: nil, keyEquivalent: "")
                i.submenu = sub
                menu.addItem(i)
            } else {
                let i = NSMenuItem(title: url.lastPathComponent, action: #selector(newFromTemplate(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = url
                menu.addItem(i)
            }
        }
    }

    @objc func newFromTemplate(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let data = try? Data(contentsOf: url),
              let decoded = try? TextFile.decode(data),
              let doc = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) as? Document
        else { NSSound.beep(); return }
        doc.setTemplate(text: decoded.text, name: url.lastPathComponent)
    }
}
