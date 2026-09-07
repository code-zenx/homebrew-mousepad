import AppKit

/// Makes the document machinery work with or without an Info.plist (i.e. from `swift run`).
final class DocumentController: NSDocumentController {
    override var defaultType: String? { "public.plain-text" }

    override func documentClass(forType typeName: String) -> AnyClass? { Document.self }

    override func typeForContents(of url: URL) throws -> String { "public.plain-text" }

    override func displayName(forType typeName: String) -> String { "Text Document" }

    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = []          // any file; TextFile decides if it is text
        openPanel.treatsFilePackagesAsDirectories = true
        super.beginOpenPanel(openPanel, forTypes: nil, completionHandler: completionHandler)
    }
}
