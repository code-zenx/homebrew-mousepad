import AppKit

/// Dev aid: `MOUSEPAD_SMOKE=1 Mousepad a.txt b.txt c.txt` drives the tab flows that need a
/// live window (switch, edit, undo, new, close, move to new window) and exits 0/1.
/// Only clean documents get closed, so no sheet ever blocks the run.
enum Smoke {
    private static var failures = 0

    private static func check(_ ok: Bool, _ what: String) {
        if !ok { failures += 1 }
        FileHandle.standardError.write("\(ok ? "ok  " : "FAIL") \(what)\n".data(using: .utf8)!)
    }

    static func run() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { step1() }
    }

    private static func step1() {
        guard let host = DocumentWindowController.all.first else { return finish("no host window") }
        let docs = host.documents
        check(DocumentWindowController.all.count == 1, "three files, one window")
        check(docs.count == 3, "three tabs")
        guard docs.count == 3 else { return finish("cannot continue") }

        host.show(docs[0])
        check(host.current === docs[0] && host.document === docs[0], "show(tab) makes it current and the controller's document")
        check(host.window?.title.contains(docs[0].displayName) == true, "title follows the tab")
        check(host.window?.firstResponder === docs[0].pane?.textView, "editor of the shown tab is first responder")

        let before = docs[0].currentText
        docs[0].pane?.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        // NSDocument counts the change when the undo group closes, which a scripted run (no events) does lazily.
        let grouped = { docs[0].undoManager?.groupingLevel == 0 }
        waitFor(grouped) {
            check(docs[0].isDocumentEdited && host.window?.isDocumentEdited == true, "typing marks the tab and window edited")
            host.show(docs[1])
            check(host.window?.isDocumentEdited == false, "edited dot belongs to the tab, not the window")
            host.show(docs[0])
            docs[0].undoManager?.undo()
            waitFor(grouped) {
                check(!docs[0].isDocumentEdited && docs[0].currentText == before, "undo is per document")
                NSDocumentController.shared.newDocument(nil)
                check(host.documents.count == 4 && host.current?.fileURL == nil, "New opens a tab in the same window")
                host.closeTab(nil)
                after(0.1) { step2(host) }
            }
        }
    }

    private static func after(_ s: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f)
    }

    /// Undo groups close at the end of an event; a scripted run has none, so post one.
    private static func waitFor(_ cond: @escaping () -> Bool, tries: Int = 40, then f: @escaping () -> Void) {
        if cond() || tries == 0 { return after(0.05, f) }
        if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(e, atStart: false)
        }
        after(0.05) { waitFor(cond, tries: tries - 1, then: f) }
    }

    private static func step2(_ host: DocumentWindowController) {
        check(host.documents.count == 3 && NSDocumentController.shared.documents.count == 3, "closing a clean tab closes only that document")
        host.show(host.documents[2])
        host.moveTabToNewWindow(nil)
        let hosts = DocumentWindowController.all
        check(hosts.count == 2 && hosts[0].documents.count == 2 && hosts[1].documents.count == 1, "Move Tab to New Window")
        hosts[1].window?.performClose(nil)
        after(0.1) {
            check(DocumentWindowController.all.count == 1 && NSDocumentController.shared.documents.count == 2, "closing a window closes its documents")
            finish(nil)
        }
    }

    private static func finish(_ fatal: String?) {
        if let fatal { check(false, fatal) }
        FileHandle.standardError.write((failures == 0 ? "SMOKE OK\n" : "SMOKE FAILED (\(failures))\n").data(using: .utf8)!)
        exit(failures == 0 ? 0 : 1)
    }
}
