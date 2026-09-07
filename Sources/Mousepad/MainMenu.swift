import AppKit
import MousepadCore

/// The whole menu bar, built in code. Items target `nil` so the responder chain
/// (text view -> window -> window controller -> document -> app delegate) picks the handler.
enum MainMenu {
    @discardableResult
    static func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                     _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0, rep: Any? = nil,
                     target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.tag = tag
        i.representedObject = rep
        i.target = target
        menu.addItem(i)
        return i
    }

    static func submenu(_ menu: NSMenu, _ title: String) -> NSMenu {
        let m = NSMenu(title: title)
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = m
        menu.addItem(i)
        return m
    }

    static func sep(_ m: NSMenu) { m.addItem(.separator()) }

    private static func toggle(_ menu: NSMenu, _ title: String, _ key: Settings.Key) {
        item(menu, title, #selector(AppDelegate.toggleSetting(_:)), rep: key)
    }

    private static func fkey(_ k: Int) -> String { String(Character(UnicodeScalar(UInt16(k))!)) }

    private static func finder(_ menu: NSMenu, _ title: String, _ action: NSTextFinder.Action, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) {
        item(menu, title, #selector(NSResponder.performTextFinderAction(_:)), key, mods, tag: action.rawValue)
    }

    static func build(templatesDelegate: NSMenuDelegate) -> NSMenu {
        let main = NSMenu()

        let app = submenu(main, "Mousepad")
        item(app, "About Mousepad", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        sep(app)
        item(app, "Preferences…", #selector(AppDelegate.showPreferences(_:)), ",")
        sep(app)
        NSApp.servicesMenu = submenu(app, "Services")
        sep(app)
        item(app, "Hide Mousepad", #selector(NSApplication.hide(_:)), "h")
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        sep(app)
        item(app, "Quit Mousepad", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(main, "File")
        item(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        item(file, "New Window", #selector(AppDelegate.newWindow(_:)), "n", [.command, .shift])
        submenu(file, "New From Template").delegate = templatesDelegate
        sep(file)
        item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = submenu(file, "Open Recent")
        // AppKit recognises the Open Recent menu by this item and fills it in.
        item(recent, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
        sep(file)
        item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        item(file, "Save", #selector(NSDocument.save(_:)), "s")
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        item(file, "Save All", #selector(AppDelegate.saveAll(_:)))
        item(file, "Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
        sep(file)
        item(file, "Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        item(file, "Print…", #selector(NSDocument.printDocument(_:)), "p")

        let edit = submenu(main, "Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        sep(edit)
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(submenu(edit, "Paste Special"), "Paste from History…", #selector(EditorTextView.pasteFromHistory(_:)), "v", [.command, .shift])
        item(edit, "Delete", #selector(NSText.delete(_:)))
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        sep(edit)
        fillConvert(submenu(edit, "Convert"))
        let move = submenu(edit, "Move Line")
        item(move, "Up", #selector(EditorTextView.moveLineUp(_:)), fkey(NSUpArrowFunctionKey), [.command, .control])
        item(move, "Down", #selector(EditorTextView.moveLineDown(_:)), fkey(NSDownArrowFunctionKey), [.command, .control])
        item(edit, "Duplicate Line / Selection", #selector(EditorTextView.duplicateLine(_:)), "d")
        item(edit, "Indent", #selector(EditorTextView.indentSelection(_:)), "]")
        item(edit, "Unindent", #selector(EditorTextView.unindentSelection(_:)), "[")

        let search = submenu(main, "Search")
        finder(search, "Find…", .showFindInterface, "f")
        finder(search, "Find Next", .nextMatch, "g")
        finder(search, "Find Previous", .previousMatch, "g", [.command, .shift])
        finder(search, "Find and Replace…", .showReplaceInterface, "r")
        finder(search, "Use Selection for Find", .setSearchString, "e")
        finder(search, "Hide Find Bar", .hideFindInterface, "")
        sep(search)
        item(search, "Go to Line…", #selector(DocumentWindowController.goToLine(_:)), "l")

        let view = submenu(main, "View")
        let fontMenu = submenu(view, "Font")
        item(fontMenu, "Show Fonts…", #selector(NSFontManager.orderFrontFontPanel(_:)), "t", target: NSFontManager.shared)
        item(fontMenu, "Bigger", #selector(AppDelegate.fontBigger(_:)), "=")
        item(fontMenu, "Smaller", #selector(AppDelegate.fontSmaller(_:)), "-")
        let scheme = submenu(view, "Color Scheme")
        for t in Theme.all { item(scheme, t.title, #selector(AppDelegate.setColorScheme(_:)), rep: t.name) }
        sep(view)
        toggle(view, "Line Numbers", .showLineNumbers)
        toggle(view, "Highlight Current Line", .highlightCurrentLine)
        toggle(view, "Right Margin", .showRightMargin)
        toggle(view, "Word Wrap", .wordWrap)
        toggle(view, "Block Cursor", .blockCursor)
        sep(view)
        toggle(view, "Status Bar", .statusBarVisible)
        sep(view)
        item(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let document = submenu(main, "Document")
        toggle(document, "Auto Indent", .autoIndent)
        fillTabSizes(submenu(document, "Tab Size"))
        toggle(document, "Insert Spaces", .insertSpaces)
        sep(document)
        fillLanguages(submenu(document, "Filetype"))
        fillEncodings(submenu(document, "Encoding"))
        fillLineEndings(submenu(document, "Line Ending"))
        item(document, "Write Unicode BOM", #selector(Document.toggleBOM(_:)))

        let windowMenu = submenu(main, "Window")
        item(windowMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(windowMenu, "Zoom", #selector(NSWindow.performZoom(_:)))
        sep(windowMenu)
        item(windowMenu, "Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "[", [.command, .shift])
        item(windowMenu, "Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "]", [.command, .shift])
        let goTab = submenu(windowMenu, "Go to Tab")
        for n in 1...9 { item(goTab, "Tab \(n)", #selector(AppDelegate.selectTab(_:)), "\(n)", tag: n - 1) }
        item(windowMenu, "Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:)))
        item(windowMenu, "Merge All Windows", #selector(NSWindow.mergeAllWindows(_:)))
        item(windowMenu, "Show Tab Bar", #selector(NSWindow.toggleTabBar(_:)))
        sep(windowMenu)
        item(windowMenu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = windowMenu

        let help = submenu(main, "Help")
        item(help, "Mousepad Help", #selector(AppDelegate.showHelp(_:)), "?")
        NSApp.helpMenu = help

        return main
    }

    // MARK: - Reusable submenus (also used as popups from the status bar)

    static func fillConvert(_ m: NSMenu) {
        item(m, "To Lowercase", #selector(EditorTextView.convertLower(_:)))
        item(m, "To Uppercase", #selector(EditorTextView.convertUpper(_:)))
        item(m, "To Title Case", #selector(EditorTextView.convertTitle(_:)))
        item(m, "To Opposite Case", #selector(EditorTextView.convertOpposite(_:)))
        sep(m)
        item(m, "Tabs to Spaces", #selector(EditorTextView.tabsToSpaces(_:)))
        item(m, "Spaces to Tabs", #selector(EditorTextView.spacesToTabs(_:)))
        sep(m)
        item(m, "Strip Trailing Spaces", #selector(EditorTextView.stripTrailingSpaces(_:)))
        sep(m)
        item(m, "Transpose", #selector(EditorTextView.transposeSelection(_:)), "t", [.control])
    }

    static func fillLanguages(_ m: NSMenu) {
        item(m, Languages.plainText.name, #selector(Document.setLanguage(_:)), rep: Languages.plainText.id)
        sep(m)
        for section in Languages.sections {
            let sub = submenu(m, section)
            for l in Languages.all where l.section == section {
                item(sub, l.name, #selector(Document.setLanguage(_:)), rep: l.id)
            }
        }
    }

    static func fillEncodings(_ m: NSMenu) {
        for g in Encodings.groups {
            let sub = submenu(m, g)
            for e in Encodings.all where e.group == g {
                item(sub, e.name, #selector(Document.setEncoding(_:)), rep: e.encoding.rawValue)
            }
        }
    }

    static func fillLineEndings(_ m: NSMenu) {
        for e in LineEnding.allCases { item(m, e.menuTitle, #selector(Document.setLineEnding(_:)), tag: e.rawValue) }
    }

    static func fillTabSizes(_ m: NSMenu) {
        for n in Settings.tabSizes { item(m, "\(n)", #selector(AppDelegate.setTabSize(_:)), tag: n) }
        item(m, "Other…", #selector(AppDelegate.setTabSize(_:)), tag: 0)
    }

    static func popup(_ fill: (NSMenu) -> Void) -> NSMenu { let m = NSMenu(); fill(m); return m }

    static func contextMenu() -> NSMenu {
        let m = NSMenu()
        item(m, "Undo", Selector(("undo:")))
        item(m, "Redo", Selector(("redo:")))
        sep(m)
        item(m, "Cut", #selector(NSText.cut(_:)))
        item(m, "Copy", #selector(NSText.copy(_:)))
        item(m, "Paste", #selector(NSText.paste(_:)))
        item(m, "Paste from History…", #selector(EditorTextView.pasteFromHistory(_:)))
        item(m, "Delete", #selector(NSText.delete(_:)))
        item(m, "Select All", #selector(NSText.selectAll(_:)))
        sep(m)
        fillConvert(submenu(m, "Convert"))
        let move = submenu(m, "Move Line")
        item(move, "Up", #selector(EditorTextView.moveLineUp(_:)))
        item(move, "Down", #selector(EditorTextView.moveLineDown(_:)))
        item(m, "Duplicate Line / Selection", #selector(EditorTextView.duplicateLine(_:)))
        item(m, "Indent", #selector(EditorTextView.indentSelection(_:)))
        item(m, "Unindent", #selector(EditorTextView.unindentSelection(_:)))
        return m
    }
}
